# Issue #164: spec: patch route 非互換 verify command の自動検出

## Overview

patch route（Size XS/S、PR なし）の Issue で `/spec` が `github_check "gh pr checks"` 形式の verify command を生成してしまう問題を自動検出・修正する。Issue #161 の実装時に `/code` フェーズで手動修正が必要だった経緯に基づく対応。

`/spec` SKILL.md Step 10 と `/code` SKILL.md Step 10 それぞれに「Patch route verify command check」段落を追加し、patch route で `github_check "gh pr checks"` が検出された場合に `github_check "gh run list"` 形式へ自動修正する。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の「Verification conditions vs. Issue body acceptance criteria consistency check」段落の直後に「Patch route verify command check」段落を追加
- `skills/code/SKILL.md`: Step 10 冒頭（「Resolving `{{base_url}}`」段落の直前）に「Patch route verify command check」段落を追加

## Implementation Steps

1. `skills/spec/SKILL.md` Step 10 に patch route チェックを追加する（→ 受入条件 1, 2）

   挿入箇所: 「Verification conditions vs. Issue body acceptance criteria consistency check」段落の末尾（`rm -f .tmp/issue-body-$NUMBER.md` を含む行）の直後、「Changed-file modification types」段落の直前。

   追加内容:

   ```
   **Patch route verify command check:**

   After `## Verification > Pre-merge` is finalized and the Issue body is updated, if Size is `XS` or `S` (patch route — no PR exists), scan `## Verification > Pre-merge` in the Spec for `github_check "gh pr checks"` entries.
   - If found: output "Warning: patch route — `github_check "gh pr checks"` is incompatible (no PR exists in patch route). Auto-fixing to `github_check "gh run list"` form." and replace each with `github_check "gh run list --limit=1 --json conclusion --jq '.[0].conclusion'"` (add `--workflow=<filename>` if there are multiple workflow files under `.github/workflows/`). Update Spec file using Edit tool. Also update Issue body via `gh-issue-edit.sh`.
   ```

2. `skills/code/SKILL.md` Step 10 に patch route チェックを追加する（after 1）（→ 受入条件 3）

   挿入箇所: 「### Step 10: Verify Command Consistency」見出しの直後、「**Resolving `{{base_url}}` to localhost**」段落の直前。

   追加内容:

   ```
   **Patch route verify command check:**

   If patch route (Size is `XS`/`S` or `--patch` flag), before running verify-executor, scan the Issue body's `## Acceptance Criteria > Pre-merge` for `github_check "gh pr checks"` entries.
   - If found: output "Warning: patch route — `github_check "gh pr checks"` is incompatible. Auto-fixing to `github_check "gh run list"` form." and replace each with `github_check "gh run list"` form (add `--workflow=<filename>` if there are multiple workflow files under `.github/workflows/`). Update Issue body via `gh-issue-edit.sh`. Also update Spec verify commands (`$SPEC_PATH/issue-$NUMBER-*.md`) with the same fix.
   ```

## Verification

### Pre-merge

- <!-- verify: grep "gh pr checks\|patch route" "skills/spec/SKILL.md" --> `/spec` SKILL.md に patch route 互換性チェックが記載されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "### Step 10: Create Spec" "Patch route verify command" --> Step 10 内に新しい「Patch route verify command check」段落が存在する
- <!-- verify: grep "gh pr checks" "skills/code/SKILL.md" --> `/code` SKILL.md に patch route チェックが追加されている

### Post-merge

- `/spec` で次の patch route Issue（Size XS/S）を実行した際に `gh pr checks` が自動修正されることを動作確認

## Notes

- 挿入テキストに半角 `!` が含まれないことを確認済み（validate-skill-syntax.py MUST 制約準拠）
- `gh run list` の `--workflow` オプション省略形を提供するが、プロジェクトに複数 CI ワークフローがある場合は LLM が判断して `--workflow=<filename>` を付与する設計にした
- 受入条件 2・3 は Issue body に verify command がなかったため、Spec で追加設計し Issue body を更新（verify command sync rule 準拠）

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
