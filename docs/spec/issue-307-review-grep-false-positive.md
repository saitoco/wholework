# Issue #307: review: LLM チェックをシェルスクリプトに移譲する際の grep パターン false positive チェックリストを追加

## Overview

`/review` の `review-bug` エージェントに、LLM 実行チェックをシェルスクリプト（grep/awk パターン）に移譲する際の false positive リスクを検出するチェック項目を追加する。

背景：Issue #303 の実装で conflict marker チェックを LLM からシェルスクリプトに移譲した際、`grep -rn '<<<<<<' .` がテストフィクスチャ（`.bats` の `echo '<<<<<<'`）やドキュメント内コードフェンスに false positive を起こした。LLM は暗黙的にこれらをフィルタリングできるが、シェルスクリプトはできない。この種の実装パターンを `/review` で検出できるよう `agents/review-bug.md` に検出ロジックを追加する。

## Changed Files

- `agents/review-bug.md`: `### 1. Bug/Logic Error Detection` セクションに **LLM-to-Shell Pattern Migration Risks** 検出カテゴリを追加

## Implementation Steps

1. `agents/review-bug.md` の `### 2. False Positive Filtering` 見出しの直前に、以下の新しい検出カテゴリを追加する (→ AC1)

   追加テキスト（英語）：

   ```
   **LLM-to-Shell Pattern Migration Risks:**
   When the PR replaces an LLM-executed check with a grep/awk/sed shell script pattern (e.g., migrating conflict marker detection from LLM to `grep -rn '<<<<<<' .`):
   - Check if the pattern may match false positives in test fixture files (e.g., `.bats` files containing `echo '<<<<<<'` as test data)
   - Check if the pattern may match documentation examples in code fences or backtick-enclosed content (e.g., SKILL.md or module files that demonstrate the pattern)
   - Check if an exclusion mechanism (`grep -v`, `--exclude`, path scoping, etc.) is absent for known false positive sources
   - Report at SHOULD level if false positive sources exist and no exclusions are present
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "Either skills/review/SKILL.md or agents/review-bug.md contains an explicit check or instruction to detect false positive risks when grep/awk shell script patterns replace LLM-executed checks" --> `skills/review/SKILL.md` または `agents/review-bug.md` に、LLM チェックをシェルスクリプト（grep/awk パターン）に移譲する際の false positive リスクをチェックするための記述が追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 既存 bats テストが引き続き CI で PASS する

### Post-merge

- 実際に LLM 側チェックをシェルスクリプトに移譲する実装 Issue で `/review` を実行した際、新規チェックリスト項目が review 結果に反映されることを確認

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
