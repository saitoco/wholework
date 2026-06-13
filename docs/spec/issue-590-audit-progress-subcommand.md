# Issue #590: audit: /audit progress <XL-parent> Subcommand — XL Sub-issue Progress Snapshot

## Overview

Add a `progress <XL-parent-issue-number>` subcommand to `/audit` that aggregates and displays sub-issue status under a specified XL parent issue in one command. Users get an immediate snapshot of "what's done / what's stuck / how much is left" without repeatedly running `gh issue list` and inspecting each sub-issue manually.

Status is classified from GitHub labels and issue state: Done (CLOSED), In progress (OPEN + active phase label), Blocked (OPEN + OPEN blocker via `blockedBy`), Stale (OPEN + `stale-verify` label), Pending (default). Output also shows phase distribution, time estimates (median completion time from CLOSED sub-issues + remaining estimate), and recent 24h activity (from GraphQL `updatedAt`, filtered in shell).

The subcommand is standalone — it is not included in the no-argument `/audit` run, because it requires a specific XL parent issue number.

## Changed Files

- `skills/audit/SKILL.md`: add `progress` routing to Command Routing; add `## progress Subcommand` section; add `get-sub-issue-progress.sh` to `allowed-tools`
- `scripts/gh-graphql.sh`: add `get-sub-issues-all` named query — fetches all sub-issues (OPEN + CLOSED) with `number`, `title`, `state`, `createdAt`, `closedAt`, `updatedAt`, `labels`, `blockedBy`; bash 3.2+ compatible
- `scripts/get-sub-issue-progress.sh`: new script — accepts `<parent-issue-number>`, calls `get-sub-issues-all` query, outputs JSON with parent info and all sub-issues; bash 3.2+ compatible
- `tests/audit-progress.bats`: new bats test file — minimum 3 test cases (empty XL, mixed states, all done) using WHOLEWORK_SCRIPT_DIR mock
- `docs/workflow.md`: update `/audit` section to include `/audit progress <XL-parent-issue-number>` description
- `docs/ja/workflow.md`: update `/audit` section with Japanese translation of progress description
- `docs/structure.md`: update scripts count (51 → 52), add `get-sub-issue-progress.sh` entry under Key Files → Scripts; update tests count (63 → 65, fixing pre-existing drift 63→64 + new file)

## Implementation Steps

1. Add `get-sub-issues-all` named query to `scripts/gh-graphql.sh` — insert case block after `get-sub-issues)` block; query fetches all sub-issues including CLOSED: `number`, `title`, `state`, `createdAt`, `closedAt`, `updatedAt`, `labels(first:20){nodes{name}}`, `blockedBy(first:20){nodes{number state}}`; also fetches parent issue `title`; use `first:100` limit; bash 3.2+ compatible (prerequisite for step 2)

2. Create `scripts/get-sub-issue-progress.sh` (after 1) — validate numeric argument, call `"$SCRIPT_DIR/gh-graphql.sh" --query get-sub-issues-all -F "num=$PARENT_NUMBER"`, extract and output JSON `{"parent":{"number":N,"title":"..."},"sub_issues":[...]}` via jq; bash 3.2+ compatible (→ AC: file_exists "scripts/get-sub-issue-progress.sh")

3. Update `skills/audit/SKILL.md` (parallel with 1, 2):
   - Add `${CLAUDE_PLUGIN_ROOT}/scripts/get-sub-issue-progress.sh:*` to `allowed-tools` frontmatter
   - Add to Command Routing before "For any other ARGUMENTS": `If ARGUMENTS is progress or starts with progress (e.g. progress <issue-number>): execute "progress Subcommand" section and exit`
   - Add `## progress Subcommand` section specifying all 6 elements: (1) data fetch via `get-sub-issue-progress.sh <parent>`; (2) status breakdown — Done (CLOSED) / In progress (OPEN + phase/code or phase/review or phase/verify or phase/spec) / Blocked (OPEN + OPEN blocker in blockedBy) / Stale (OPEN + stale-verify label) / Pending (default); priority order Done > Blocked > Stale > In progress > Pending for overlaps; (3) phase distribution table for in-progress + blocked sub-issues; (4) time estimate — median of (closedAt - createdAt) for CLOSED sub-issues; remaining estimate = pending_count / max(in_progress_count, 1) × median; (5) 24h activity — fetch `updatedAt` from GraphQL output, filter in shell for issues updated within 24h; (6) blocked relationships — for each Blocked issue, show which OPEN `blockedBy` issues block it
   - Document output format including `Sub-issues:`, `Status breakdown:`, `Phase distribution:`, `Time estimates:`, and `Recent activity:` sections matching the Issue body format
   (→ AC: grep, rubric, file_contains)

4. Create `tests/audit-progress.bats` (after 2) — set `WHOLEWORK_SCRIPT_DIR` to mock dir containing `gh-graphql.sh` mock that echoes `$MOCK_GRAPHQL_RESPONSE`; test cases: (a) `error: no arguments` — exits non-zero; (b) `success: empty XL returns empty sub_issues array` — mock returns zero nodes; (c) `success: mixed states — CLOSED, OPEN+phase/code, OPEN+stale-verify, OPEN+blockedBy` — script exits 0 and output includes sub-issue data; (d) `success: all done — all CLOSED` — script exits 0 (→ AC: command "bats tests/audit-progress.bats")

5. Update `docs/workflow.md` — in `/audit` section, append to the paragraph mentioning subcommands: `/audit progress <XL-parent-issue-number>` shows sub-issue progress snapshot (status breakdown, phase distribution, time estimate, recent 24h activity) for the specified XL parent; update `docs/ja/workflow.md` with equivalent Japanese text; update `docs/structure.md` script and test counts (→ AC: grep "/audit progress" workflow.md, grep "/audit progress" ja/workflow.md)

## Verification

### Pre-merge

- <!-- verify: grep "progress.*XL-parent|progress <XL-parent" "skills/audit/SKILL.md" --> SKILL.md に新サブコマンド `progress <XL-parent>` が追加されている
- <!-- verify: grep "Sub-issues:|Status breakdown|Time estimates" "skills/audit/SKILL.md" --> 出力フォーマットが文書化されている
- <!-- verify: rubric "skills/audit/SKILL.md /audit progress implementation specifies: sub-issue data fetch via get-sub-issue-progress.sh (new script for all sub-issues including CLOSED), status breakdown (done/in-progress/blocked/stale/pending), phase distribution, time estimate (median + remaining), recent 24h activity using GraphQL updatedAt, and blocked relationships from blockedBy" --> 仕様 6 要素（fetch/status/phase/time/activity/blocked）が rubric 基準を満たす
- <!-- verify: file_contains "skills/audit/SKILL.md" "get-sub-issue-progress.sh" --> SKILL.md が `get-sub-issue-progress.sh` を参照している（rubric 補足）
- <!-- verify: file_exists "scripts/get-sub-issue-progress.sh" --> 新スクリプト `scripts/get-sub-issue-progress.sh` が作成されている
- <!-- verify: command "bats tests/audit-progress.bats" --> bats テストが green（最低 3 ケース: empty XL / mixed states / all done）
- <!-- verify: grep "/audit progress" "docs/workflow.md" --> `docs/workflow.md` に `/audit progress <XL-parent>` の説明が追加されている
- <!-- verify: grep "/audit progress" "docs/ja/workflow.md" --> `docs/ja/workflow.md` に `/audit progress <XL-parent>` の説明が追加されている

### Post-merge

- 実 XL Issue で `/audit progress <parent>` を実行し、進捗監視が `gh issue list` 目視より明らかに効率的であることを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- `get-sub-issue-graph.sh` は `/auto` の core パスで OPEN 専用として使用されているため、本 Issue では変更しない（Issue body で明示）
- `get-sub-issues-all` named query は `first:100` を使用（XL の現実的な sub-issue 上界）
- Status 重複時の優先順位: Done > Blocked > Stale > In progress > Pending（例: OPEN + phase/code + OPEN blocker → Blocked）
- `progress` サブコマンドは引数なし `/audit` 実行には含めない（特定 XL を指定する必要があるため）
- `docs/structure.md` の tests カウントは 63 と記載されているが実際は 64 ファイル（既存ドリフト）。本 Issue で `audit-progress.bats` 追加後は 65 になるため、ドリフト修正も兼ねて 63→65 に更新する
