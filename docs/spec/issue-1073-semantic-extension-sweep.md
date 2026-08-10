# Issue #1073: spec: タグ・enum の意味論拡張時に消費箇所を横断洗い出しする手順を追加

## Overview

`/spec` の Step 10 に、タグ・enum 値の**意味論を拡張する** (文字列は変えずに受理条件を広げる) Issue 向けの消費箇所横断洗い出し手順「Tag/enum semantic extension consumer sweep」を追加する。既存の Rename-type Issue grep check (文字列そのものの置換が対象) や Steering Docs sync candidate check (`docs/` 配下の参照同期のみが対象) とは対象範囲が異なることを手順内に明示し、(a) 洗い出しに使った grep パターン・対象ディレクトリを Spec に記録すること、(b) `(exhaustive)` 等の網羅宣言を含む成果物についてはその宣言の一致を検証する AC 例を示すこと、の 2 点を手順に含める。

あわせて、`/issue` フェーズ完了後に投稿された AC audit コメントが指摘した AC2 の常時 PASS verify command (`file_contains "skills/spec/SKILL.md" "semantic"` — "semantic" は本 Issue の実装前から L445/L770 に既存) を、新設セクション見出しに固有の複合語 `"Tag/enum semantic extension"` へ修正済み (Comment Consumption Procedure により Issue body へ反映済み。詳細は Consumed Comments 参照)。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 に "Tag/enum semantic extension consumer sweep" セクションを追加 (挿入位置: "Rename-type Issue grep check" ブロック末尾の "Section number cross-references" 行の直後、"**`.claude/` files and `git add -f`:**" 見出しの直前) — bash 3.2+ compatible (guidance text only, no new bash/script code)
- `tests/spec.bats`: 新規作成。新設セクションの見出し・grep パターン記録・差分説明の各要素を content-assertion で検証する (`tests/issue.bats` と同じ setup パターンを踏襲)

## Implementation Steps

1. `skills/spec/SKILL.md` Step 10 内、"Section number cross-references" 行の直後・"**`.claude/` files and `git add -f`:**" の直前に、以下のブロックを挿入する (→ acceptance criteria AC1, AC2, AC3):

```
**Tag/enum semantic extension consumer sweep (regardless of SPEC_DEPTH; only when applicable):**

When the Issue extends the accepted semantics or applicability scope of an existing tag/enum value (e.g., a `<!-- xxx-type: yyy -->` marker, a label value, a structured field constant) while the literal value string itself stays unchanged — for example, a tag previously valid only post-merge becoming also valid pre-merge — enumerate every consuming file and re-validate its assumptions:

1. Identify the target tag/enum value string from the Issue body (e.g., `verify-type: manual`).
2. Run `grep -rn '<value>' skills/ modules/ scripts/` from the repository root to enumerate every file that reads, branches on, or aggregates the value. Record the exact grep pattern and target directories used in the Spec's Changed Files or Notes section.
3. For each hit, read the surrounding logic and judge whether its assumption about the value still holds under the extended semantics. Add files needing updates to the Changed Files list with the specific change required.
4. If the resulting enumeration is presented as `(exhaustive)` in a Changed Files or Notes list, add a verify command that checks the enumeration matches the grep results, e.g.: `<!-- verify: rubric "modules/X.md の caller 一覧が、grep -rn 'PATTERN' skills/ modules/ scripts/ の結果と一致している" -->`.

**Differs from adjacent checks:**
- **Rename-type Issue grep check**: fires on literal string replacement — the string itself changes. This check fires when the string is unchanged but the conditions under which it is valid widen.
- **Steering Docs sync candidate check**: targets `docs/` reference sync only. This check targets consuming *logic* in `skills/`/`modules/`/`scripts/` that branches on the value's meaning.
- **Symbol impact discovery**: targets deletion/migration/rename, where the old symbol disappears. This check targets a symbol that remains present but whose consumers' assumptions must be re-validated.

**Skip** if the Issue does not extend an existing tag/enum's semantics.

*Example: Issue #1059 extended `<!-- verify-type: manual -->` from "post-merge only" to "pre-merge and post-merge", but the Spec's Changed Files were limited to `skills/issue`/`skills/review`/`skills/verify`; consumers in `skills/audit/SKILL.md` (Manual Waiting Count) and `skills/auto/SKILL.md` (Pending manual confirmation) surfaced only at `/review` time (#1090, #1092).*
```

2. `tests/spec.bats` を新規作成し、以下の内容を実装する (`tests/issue.bats` と同じ content-assertion パターン) (→ acceptance criteria AC4):

```bash
#!/usr/bin/env bats
# Content-assertion tests for /spec skill's tag/enum semantic extension consumer sweep
# (added for #1073). Guards the new Step 10 procedure against accidental removal or drift.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SKILL_FILE="$PROJECT_ROOT/skills/spec/SKILL.md"
}

@test "spec skill documents tag/enum semantic extension consumer sweep" {
    grep -q 'Tag/enum semantic extension consumer sweep' "$SKILL_FILE"
}

@test "spec skill records grep pattern and target directories for the sweep" {
    grep -q "grep -rn '<value>' skills/ modules/ scripts/" "$SKILL_FILE"
}

@test "spec skill shows exhaustive-declaration verification AC example" {
    grep -q 'caller 一覧が' "$SKILL_FILE"
}

@test "spec skill differentiates the sweep from Rename-type and Steering Docs sync checks" {
    grep -q 'the string is unchanged but the conditions under which it is valid widen' "$SKILL_FILE"
}
```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md に、タグ・enum 値の意味論を拡張する Issue において、その値を grep で全消費箇所に展開し影響評価を Changed Files または Notes に記録する手順が追加されている。発火条件 (どのような Issue で実行するか) が明示されている。手順には (a) 洗い出しに使った検索条件 (grep パターンと対象ディレクトリ) を Spec に記録すること、(b) `(exhaustive)` 等の網羅宣言を含む成果物に対して宣言の一致を検証する AC 例を示すこと、の 2 点が含まれている" --> `/spec` に意味論拡張時の消費箇所洗い出し手順が追加されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "Tag/enum semantic extension" --> 追加された手順の記述に意味論拡張 (semantic) に関する説明が含まれている (rubric の補助的機械チェック。検索文字列は新設セクション見出しに固有の複合語)
- <!-- verify: rubric "追加された手順が、既存の Rename-type Issue grep check や Steering Docs sync candidate check と役割が重複しないよう、両者との差分が明示されている" --> 既存の grep check 系手順との差分が明示されている
- <!-- verify: command "bats tests/spec.bats" --> `tests/spec.bats` が PASS する (現時点で存在しないため実装時に新規作成するテストファイル。既存の関連テストは `tests/run-spec.bats` / `tests/spec-verification-hints.bats`)

### Post-merge

- タグ・enum の意味論を拡張する Issue を 1 件 `/spec` に通し、Changed Files または Notes に消費箇所の影響評価 (検索条件を含む) が記録されることを確認する

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective: 非対話モードでの `/issue` 実施内容の記録 (AC1 ルーブリックへの検索条件記録・網羅宣言検証の統合、`tests/spec.bats` 不存在の注記追加等) / https://github.com/saitoco/wholework/issues/1073#issuecomment-5241999844
- saito / MEMBER / first-class / `/issue` Step 15 AC audit: AC2 の verify command `file_contains "skills/spec/SKILL.md" "semantic"` が Pattern 2 (常時 PASS) である指摘。"semantic" は本 Issue 実装前から L445/L770 に既存するため判別不能。修復案 (a) (新設セクション見出しに固有の複合語へ変更) を採用し、Issue body の AC2 を `"Tag/enum semantic extension"` へ修正 (本フェーズで対応済み、Issue body "## Spec Auto-Resolve Log" 参照) / https://github.com/saitoco/wholework/issues/1073#issuecomment-5242053346

## Notes

- Size S → patch route (`always-pr` 未設定のため `ALWAYS_PR=false`)。単一 skill ファイル + 新規テストファイルの変更に留め、新規 module/script は追加しない (#804 「Symbol impact discovery」追加時の前例に倣う: modules/ 化は本 Issue のスコープでは over-engineering と判断)
- 挿入位置は行番号ではなく前後のアンカーテキスト (直前直後の見出し・文言) で指定する。Issue body の Background に記載の行番号 (L288-297 等) と現在の `skills/spec/SKILL.md` の実際の行番号 (L281 等) には若干のズレがあるが、記述内容・対象範囲は一致することを確認済み (`/issue` フェーズでも同様に確認済み) — 本 Spec のアンカーテキスト指定への影響なし
- Steering Docs sync candidate check: 新設予定のセクション見出し文字列 "Tag/enum semantic extension consumer sweep" で `docs/ tests/ scripts/` を検索した結果、既存の同期対象なし (新設セクションのため無風)。兄弟手順追加の前例 (#804 Symbol impact discovery 等) でも `skills/spec/SKILL.md` 単体以外への同期は発生していない
- `docs/ja/` 翻訳同期チェック: 変更対象がいずれも `docs/` 配下ではなく `skills/`・`tests/` のため非該当
- `modules/skill-dev-doc-impact.md` の Change Type (Skill 追加/変更/削除、Module 追加/変更/削除、Script 追加/変更/削除) と照合した結果いずれにも該当しない (`/spec` 自身の内部手順追加であり、スキル一覧・外部インターフェースに変化がないため) — README.md / docs/workflow.md / CLAUDE.md の同期は不要と判断
- Rename-type Issue grep check: Issue title/body に "rename" 系の文字列を含まないため非該当

## Code Retrospective

N/A — Implementation Steps のアンカーテキスト指定・挿入ブロック・`tests/spec.bats` の内容とも Spec 記載どおりに反映され、逸脱・設計ギャップ・手戻りはなし。Pre-merge verify command 4 件・`bats --jobs 18 tests/` フルスイート (1695 tests) とも初回実行で PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps をそのまま実装 (アンカーテキスト "Section number cross-references" 直後 / "`.claude/` files and `git add -f`" 直前への挿入、`tests/issue.bats` と同一パターンの `tests/spec.bats` 新規作成) — 設計判断は `/spec` フェーズで完了済みのため、`/code` では逸脱なし
- 既存テストが `skills/spec/SKILL.md` の複数箇所を参照していたため behavioral change 判定が成立し、`bats --jobs 18 tests/` でフルスイートを実行 (narrow scope ではなく全 1695 tests を対象)

### Deferred Items
- Post-merge AC (`verify-type: manual`): 意味論拡張 Issue を実際に 1 件 `/spec` へ通し、Changed Files/Notes に検索条件を含む影響評価が記録されることの確認は post-merge 観測待ち
- None (other than above)

### Notes for Next Phase
- `/verify` は post-merge AC の実地確認 (意味論拡張 Issue を 1 件 `/spec` に通す) を行う際、本 Issue 自身を対象候補にしないこと (本 Issue は「手順追加」であり「既存タグ/enum の意味論拡張」ではない)
- Pre-merge verify command 4 件は本フェーズで PASS 済み・チェックボックス更新済み。再検証は不要
