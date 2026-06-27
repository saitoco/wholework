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

## spec retrospective

### Minor observations

- Issue body の L0 comment (Issue Retrospective by saito/MEMBER at 2026-06-27T14:09:17Z) に AC 変更点 (BRE fix, bats test AC 追加, section_contains AC 追加) が記録されており、issue body はすでに更新済みの状態で spec phase を開始できた。/issue retro → /spec 開始前に AC が反映されているのは理想的なフロー

### Judgment rationale

- 抑制条件を `matches_expected:true` 単独に緩和する判断: `commits_found:true` の AND 条件は commit の直接確認に限定されているが、reconciler の `matches_expected:true` は phase label fallback を含む上位判断を表す。AND 条件の削除は reconcile-first authority の徹底であり、false negative リスクはない (`matches_expected:true` が誤って返される場合は reconciler のバグであり anomaly detector の責務外)

### Uncertainty resolution

- `section_contains "modules/orchestration-fallbacks.md" "## code-patch-silent-no-op"` の section 境界: orchestration-fallbacks.md が `---` 区切りであることを確認済み。Exception Condition サブセクション追加後に "matches_expected" がセクション内に含まれることを確認

## Code Retrospective

### Deviations from Design
- なし。Spec の実装ステップをそのまま実施した。

### Design Gaps/Ambiguities
- Spec Notes に記載の通り、既存テスト (line 228: `matches_expected:true` AND `commits_found:true`) は AND 条件削除後も PASS することを確認済み。追加確認は不要だった。

### Rework
- なし。

## Consumed Comments

No new comments since last phase.

## review retrospective

### Spec vs. implementation divergence patterns

- なし。PR diff は Spec の実装ステップと完全に一致。AND 条件削除、新テスト追加、Exception Condition 追加の 3 点が Spec 通りに実装されており divergence なし。

### Recurring issues

- なし。今回は同種 issue が複数発生した形跡なし。

### Acceptance criteria verification difficulty

- すべて PASS。`command "bats tests/detect-wrapper-anomaly.bats"` は safe mode で CI reference fallback を使用: CI "Run bats tests" ジョブは FAILURE だが、失敗は `tests/append-loop-state-heartbeat.bats` (tests 11-15) の pre-existing 問題で detect-wrapper-anomaly.bats とは無関係。`ok 192 silent no-op: suppressed when reconcile confirms matches_expected true (async external commit)` が CI ログで PASS を確認できた。pre-existing CI 失敗への改善提案は /verify での集約対象とする。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- CI failing (ci_failing) を non-interactive auto-resolve で継続。失敗は pre-existing の `tests/append-loop-state-heartbeat.bats` に起因 (review フェーズ確認済み)、本 PR に無関係
- squash merge + delete-branch 完了 (2026-06-27T14:43:16Z)
- BASE_BRANCH=main のため `closes #771` が自動 close される

### Deferred Items

- `tests/append-loop-state-heartbeat.bats` の pre-existing CI 失敗を /verify フェーズで改善提案として集約予定

### Notes for Next Phase

- post-merge AC は manual observation のみ: 次回 async external commit recognition による phase/verify 遷移発生時に silent-no-op anomaly entry が log に記録されないことを観察する
- verify command は全 pre-merge AC PASS 済み (review フェーズ確認) — verify フェーズは post-merge observation のみ残存

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Issue Background が #746 観測事例を具体的に引用 (session-id + report § 番号) しており、根本原因 (reconciler signal 未参照) と修正方針 (reconcile-first authority 徹底) が初期から明確だった。

#### spec
- AND 条件削除の判断根拠 (`matches_expected:true` が phase label fallback を含む上位判断) が retrospective に明記され、後の review/verify でも参照可能な SSoT を成立させた。

#### code
- Spec 通り 3 ファイル変更で完了、rework なし。

#### review
- pre-existing CI failure (`tests/append-loop-state-heartbeat.bats`) を本 PR 無関係と特定して continue 判断。merge phase まで継承され phase handoff で `/verify` に集約予定として deferred。

#### merge
- CI failing を non-interactive auto-resolve で継続 — 改善 Issue 起票が前提の運用パターン。pre-existing failure の扱いについて運用合意がある。

#### verify
- 全 5 pre-merge AC + 1 post-merge manual AC PASS。
- **新規発見: #772 path migration 起因の regression**: `tests/append-loop-state-heartbeat.bats` (test 6-9) が `docs/reports/loop-state-...` の旧 path を参照したまま残されており、#772 で `docs/sessions/_daily/loop-state-...` に移行された script との不整合で全 4 テストが失敗。merge 時点では本 PR と無関係と判定して proceed したが、根本原因は #772 のスコープ漏れ (`scripts/append-loop-state-heartbeat.sh` の path は更新したが、対応する test の path は未更新)。
- post-merge manual AC は source code + bats test 25,26 (async external commit suppress assertion) で in-session 判定可能。

### Improvement Proposals

1. **#772 follow-up: tests/append-loop-state-heartbeat.bats の path 同期** — #772 で migration 対象ファイルとして `scripts/append-loop-state-heartbeat.sh` の path を更新したが、対応する bats test (`tests/append-loop-state-heartbeat.bats` line 69, 82, 95, 115, 126) は旧 path `docs/reports/loop-state-...` を参照したままで test 6-9 が失敗状態。修正は test ファイルの path replace のみ (`s|docs/reports/loop-state-|docs/sessions/_daily/loop-state-|g`)。**直接 Issue 化対象** (regression fix なので follow-up としてではなく独立 fix Issue)。
2. **migration Issue における関連 tests の網羅性チェック**: #772 の Spec で `Changed Files` リストに対応する test ファイルが含まれていなかった。SKILL.md / script / test の三層を同期して洗い出す Spec template ガイダンスの追加候補 (本 batch session で #778 として既起票の "verify command 対称性" と同根の論点 — symbolic naming で対象範囲を機械的に検出する仕組みの整備)。
