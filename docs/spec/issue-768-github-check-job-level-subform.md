# Issue #768: verify-executor: github_check に job-level conclusion 参照 sub-form を追加

## Overview

`/verify` の `github_check` verify command が workflow 全体の conclusion を参照する形式のため、無関係 job (`Forbidden Expressions check` 等) の失敗で AC が literal FAIL になる false positive が #733・#738 で連続発生した。

`github_check` の sub-form として、特定 job の conclusion を参照できる **job-level variant** を `modules/verify-executor.md` に追加し、`modules/verify-patterns.md` §7 に使用ガイダンスも追加する。

新コマンド (`github_check_job`) ではなく、既存 `github_check` の **lateral extension** として `gh run view ... --json jobs --jq '.jobs[] | select(.name=="<job>").conclusion'` 形式を採用する (downstream skill 変更不要)。

## Changed Files

- `modules/verify-executor.md`: `github_check` の safe mode allowlist に `gh run view` を追加。翻訳テーブルの後に `### github_check: Job-Level Conclusion Sub-Form` セクションを追加 — 使用例、適用条件、workflow-level との比較表を記載
- `modules/verify-patterns.md`: §7 (GitHub Actions Workflow Changes) の Usage criteria table の後に job-level sub-form の使用ガイダンスを追加

## Implementation Steps

1. `modules/verify-executor.md` の `github_check` エントリ (line 84) の safe mode allowlist 記述に `gh run view` を追加する (→ AC1)
2. `modules/verify-executor.md` の翻訳テーブル直後 (rubric エントリの後、`### grep Verify Command: ERE vs BRE Reference` セクションの前) に `### github_check: Job-Level Conclusion Sub-Form` セクションを新規追加する。以下の内容を含める (→ AC1, AC2, AC3):
   - **使用形式**: `github_check "gh run view $(gh run list --workflow=<file>.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"<job_name>\").conclusion'" "success"`
   - **適用条件**: multi-job CI workflow で特定 job の合否のみを検証したい場合。pre-existing failure を持つ無関係 job (e.g., `Forbidden Expressions check`) が workflow-level 判定を false FAIL にするケース
   - **workflow-level との比較表**: スコープ・false-positive リスク
3. `modules/verify-patterns.md` §7 の Usage criteria table 後に job-level sub-form の説明を追加する (→ AC4, AC5):
   - job-level form の使用例と「無関係 job の失敗で本 AC が FAIL にならない」旨の説明
   - 既存 Usage criteria table に job-level row を追加

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md に job-level conclusion 参照を可能にする github_check sub-form のドキュメントが追加されている。使用例 (multi-job CI workflow での特定 job 指定) と適用条件が明記される" --> verify-executor.md に job-level sub-form 追加
- <!-- verify: file_contains "modules/verify-executor.md" "job-level" --> verify-executor.md に "job-level" キーワードが追加されている
- <!-- verify: grep "job-level|github_check_job|jobs\[\]" "modules/verify-executor.md" --> verify-executor.md に job-level 参照キーワードが追加されている
- <!-- verify: rubric "modules/verify-patterns.md の Section 7 (GitHub Actions Workflow Changes) に job-level job conclusion 参照 sub-form の使用ガイダンスが追加されている (Cross-Reference 整合性)" --> verify-patterns.md §7 にも job-level 記載追加
- <!-- verify: section_contains "modules/verify-patterns.md" "### 7." "job-level" --> verify-patterns.md §7 に "job-level" キーワードが追加されている

### Post-merge

- 次回 patch route Issue または PR Issue の AC で job-level form が使用され、無関係 job 失敗で AC が FAIL にならないことを観察 <!-- verify-type: manual -->

## Notes

- **Auto-resolved: Sub-form syntax 選択**: `github_check_job` (新コマンド) ではなく `github_check` lateral extension を採用。侵襲性が低く、`verify-executor.md` 翻訳テーブル・SKILL.md の supported commands 表への追加が不要
- **Auto-resolved: Cross-Reference 先**: `verify-patterns.md §7` を選択。既に `gh pr checks` false positive 問題と `gh run list` スコープ設計を扱うセクションとして文脈が最適
- `gh run view` の safe mode allowlist 追加: 既存 `gh run list` が safe mode では UNCERTAIN (allowlist 外) なのに対し、job-level sub-form はより精度が高いため safe mode でも動作させることを推奨する。`gh run view` は read-only 操作のため allowlist 追加が妥当
- verify-executor.md の既存パターン: `github_check "gh pr checks"` は safe mode allowlist に含まれるが workflow-level の `gh run list` 形式は allowlist 外 (full mode のみ)

## Consumed Comments

- saito (MEMBER / first-class / 2026-06-27T10:50:20Z): Issue Retrospective — Sub-form syntax 選択 (lateral extension を推奨)、AC2 の BRE metachar 修正 (`\|` → `|` in ERE)、rubric ACs に補助 file_contains/section_contains を追加、AC3 cross-reference 先を `verify-patterns.md §7` に特定

## Code Retrospective

### Deviations from Design

- None — Implementation Steps 1〜3 を Spec 通り実装。verify-executor.md の新セクション位置 (rubric 行の後・grep ERE BRE セクション前) も Spec 通り。

### Design Gaps/Ambiguities

- verify-patterns.md の Usage criteria table への行追加と、その後の説明段落の順序は Spec では「Usage criteria table 後に追加」とのみ指定されていたが、行追加 (table 内) と説明段落 (table 外) の両方を含む形で実装した。意図通りと判断。

### Rework

- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `github_check` の lateral extension として `gh run view` を safe mode allowlist に追加し、job-level sub-form を実装。`github_check_job` 新コマンドの追加は侵襲性が高いため採用しなかった。
- verify-patterns.md §7 の Usage criteria table に新行を追加し、続けて "Job-level conclusion sub-form" の説明段落も追加した (Spec の指示通り)。

### Deferred Items
- None — 実装スコープは Spec 通りに完了。

### Notes for Next Phase
- 全 pre-merge AC (file_contains/grep/section_contains) を code phase で確認済み PASS。rubric ACs は /verify で再評価される。
- `gh run view` は safe mode allowlist 追加済みのため、/verify での確認はシンプルな grep/section_contains チェックで完了できる見込み。
