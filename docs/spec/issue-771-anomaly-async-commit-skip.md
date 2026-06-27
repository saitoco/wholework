# Issue #771: detect-wrapper-anomaly: silent-no-op detector に async external commit recognition の例外条件を追加

## Overview

`scripts/detect-wrapper-anomaly.sh` の silent-no-op 判定が、reconciler が `matches_expected: true` を返した正常完了ケースでも firing する false positive が発生している。具体的には、前 Issue で既実装済みの場合に `/code` skill が新規 commit を生成せず phase/verify に直接遷移する async external commit recognition パターンで、reconciler 側は正常認識 (`matches_expected: true`) しているにもかかわらず anomaly detector 側が commit 不在のみを判定材料として silent-no-op エントリを記録してしまう。

`reconcile-phase-state.sh --check-completion` が返す `"matches_expected":true` を anomaly detector の抑制条件として組み込み、false firing を排除する。

## Reproduction Steps

1. Issue A を実装済みの状態で、別 Issue B の `/code` phase が「Issue A の実装は Issue B の PR で既実装済み」を検知する
2. `/code` skill が新規 commit を生成せず phase/verify に直接遷移する (async external commit recognition)
3. `reconcile-phase-state.sh --check-completion` は `"matches_expected":true,"actual":{"commits_found":false}` を返す
4. `detect-wrapper-anomaly.sh` が `[silent-no-op]` anomaly entry を記録する (false positive)

## Root Cause

`detect-wrapper-anomaly.sh` の silent-no-op 抑制条件 (lines 98-99) が AND 条件:

```bash
if grep -q '"matches_expected":true' "$LOG_FILE" && grep -q '"commits_found":true' "$LOG_FILE"; then
    : # reconcile confirmed commits — suppress silent-no-op detection
```

reconciler が async external commit recognition で completion を確認した場合、`"matches_expected":true` を返すが `"commits_found":false` のため AND 条件が失敗し、抑制が働かない。

修正: 抑制条件を `"matches_expected":true` のみに変更する (reconcile-first authority を commits_found への依存から解放)。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: 抑制条件を `grep -q '"matches_expected":true'` のみに変更し、`"commits_found":true` の AND 条件を削除。コメントを「reconcile-first authority: matches_expected:true skips silent-no-op (covers async external commit recognition)」に更新 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: `@test "silent no-op: suppressed when reconcile confirms matches_expected true (async external commit)"` を追加 (log に `matches_expected:true` + `commits_found:false` の reconciler 出力が含まれる場合に抑制を確認)
- `modules/orchestration-fallbacks.md`: `## code-patch-silent-no-op` セクションに Exception Condition サブセクションを追加し、`matches_expected:true` の場合に `detect-wrapper-anomaly.sh` が silent-no-op エントリを skip することを明記

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の silent-no-op 抑制条件を修正: lines 98-99 の AND 条件 (`&& grep -q '"commits_found":true' "$LOG_FILE"`) を削除し、コメントを更新する (→ AC1, AC2)

2. `tests/detect-wrapper-anomaly.bats` に新テスト追加: async external commit ケース (`matches_expected:true`, `commits_found:false` を含む log) で anomaly entry が出力されないことを確認する。log に `commit and push complete.` (success phrase) を含めることで既存の success-phrase detection が走る条件を再現し、抑制が機能することを確認する (→ AC3)

3. `modules/orchestration-fallbacks.md` の `## code-patch-silent-no-op` セクションに Exception Condition サブセクションを追加: reconciler が `"matches_expected":true` を返した場合に `detect-wrapper-anomaly.sh` が silent-no-op エントリを skip することと、async external commit recognition パターン (`#async-external-commit`) との関連を明記する (→ AC4, AC5)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh の silent-no-op detector が reconcile-phase-state.sh --check-completion の matches_expected: true の場合に anomaly entry を skip する判定ロジックを持つ" --> async commit recognition signal を anomaly 判定に組み込む
- <!-- verify: grep "matches_expected|reconcile" "scripts/detect-wrapper-anomaly.sh" --> detect-wrapper-anomaly.sh が reconciler signal を参照
- <!-- verify: command "bats tests/detect-wrapper-anomaly.bats" --> detect-wrapper-anomaly.bats が全テスト PASS (async external commit false-positive ケース含む)
- <!-- verify: rubric "modules/orchestration-fallbacks.md の code-patch-silent-no-op または async-external-commit セクションに silent-no-op detection の matches_expected: true 例外条件が明記されている" --> 例外条件が SSoT に明文化されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## code-patch-silent-no-op" "matches_expected" --> orchestration-fallbacks.md の code-patch-silent-no-op セクションに matches_expected 例外条件が記載されている

### Post-merge

- 次回 async external commit recognition による phase/verify 遷移発生時に silent-no-op anomaly entry が log に記録されないことを観察 <!-- verify-type: manual -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: BRE metachar 修正・bats test AC 追加・section_contains AC 追加の auto-resolve ログ / https://github.com/saitoco/wholework/issues/771#issuecomment-4818288194

## Notes

- 既存テスト "silent no-op: suppressed when reconcile confirms matches_expected true and commits_found true" (line 228) は AND 条件が消えた後も `matches_expected:true` を含むため引き続き PASS する
- `grep "matches_expected|reconcile" "scripts/detect-wrapper-anomaly.sh"` は ERE alternation (ripgrep 対応)。修正後スクリプトは `grep -q '"matches_expected":true'` (条件部) と `# reconcile-first authority` (コメント部) に両語を含むため PASS する
- `section_contains` の section 境界: `## code-patch-silent-no-op` は `---` までを対象セクションとする。修正後に追加する Exception Condition サブセクションが "matches_expected" を含む
- docs/ja/ には modules/ ミラーなし、翻訳更新不要
