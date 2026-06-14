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

## issue retrospective

### 曖昧ポイントの自動解決（non-interactive mode）

`/issue 590 --non-interactive` で以下の 3 つの曖昧ポイントを自動解決した。

**1. "Failed" 判定基準（HIGH IMPACT）**

Issue 提案の出力フォーマットに Failed カテゴリがあったが、Wholework の既存ラベル体系に "failed" ラベルが存在しないことが判明。`stale-verify` ラベル（「phase/verify で 60 日以上停滞」）が意味的に最も近傍。

**決定**: Failed → Stale に改名し、`stale-verify` ラベル保持を判定基準とする。ステータス分類基準テーブルを Issue body に追加。

**2. `get-sub-issue-graph.sh` 拡張 vs 新スクリプト（MEDIUM IMPACT）**

既存 `get-sub-issue-graph.sh` は OPEN sub-issue のみを返す `/auto` コア依存スクリプト。`/audit progress` に必要な「全 sub-issue（CLOSED 含む）+ labels + timestamps」には対応不可。

**決定**: `scripts/get-sub-issue-progress.sh` を新規作成する。既存スクリプトは変更なし。

**3. 24h アクティビティの `linked:#N` フィルタ（MEDIUM IMPACT）**

`gh issue list --search "linked:#<parent>"` は GitHub 標準検索では機能しない（`linked:` 修飾子は公式サポート外）。

**決定**: GraphQL で全 sub-issue の `updatedAt` を取得し、シェル側で 24h フィルタリングを行う。

## spec retrospective

### Minor observations

- `tests/` のファイルカウント（structure.md: 63、実際: 64）に既存ドリフトがあった。本 Issue での追加後に 65 になるため、ドリフト修正も兼ねて更新する
- `get-sub-issues-all` query の設計は `get-sub-issues` を参照して一貫性を保てた

### Judgment rationale

- SPEC_DEPTH=light（Size M）のため実装ステップを 5 ステップに制約。`gh-graphql.sh` 更新と `get-sub-issue-progress.sh` 作成を別ステップとしたのは依存関係（1→2）が明確なため
- Status の優先順位（Done > Blocked > Stale > In progress > Pending）は Issue body の分類基準テーブルから自明に導出できたが、重複ケースの扱いが未定義だったため Spec の Notes で明示

### Uncertainty resolution

- `docs/structure.md` のテスト数カウントが実際と乖離していることをファイルカウントで確認。Spec Notes に記録して `/code` フェーズで対応させる

## Code Retrospective

### Deviations from Design
- Spec の実装ステップは「1 → 2 → 3 (並行) → 4 → 5」を想定していたが、実際には 1・3・5 を並行コミット、2・4 を順次コミットした。機能的な差異はない

### Design Gaps/Ambiguities
- `jq` の `reduce`/`error` を使わない単純なパイプで構築できた (`get-sub-issue-progress.sh` は `get-sub-issue-graph.sh` より大幅にシンプル)
- `audit-progress.bats` のテストケースを 4 件（Spec の想定 3 件より 1 件多い no-arg エラーケースを追加）にすることで、引数検証も網羅した

### Rework
- なし（設計どおりに 1 パスで実装完了）

## review retrospective

### Spec vs. implementation divergence patterns
- 実装は Spec の全 6 要素（fetch/status/phase/time/activity/blocked）を忠実に実装。divergence なし
- SKILL.md の `description:` フィールドが新サブコマンド追加時に更新されなかった（他の全サブコマンドは記載済み）。フロントマター更新を実装チェックリストに含めるべき構造的パターン

### Recurring issues
- SKILL.md の出力テンプレート（Step 4）と定義（Step 3）の整合性に軽微な gap（"no phase" カウントの出力先未定義）。LLM instructions では Step 3 と Step 4 を cross-check する観点が弱い傾向がある

### Acceptance criteria verification difficulty
- 全 8 AC に verify command が設定済みで UNCERTAIN なし。`command "bats..."` は CI reference fallback (SUCCESS) で PASS 確認
- rubric AC のセマンティック判定は diff と SKILL.md の照合で問題なく実施できた

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #621 を `--squash --delete-branch` でマージ（conflicts なし、CI SUCCESS、approved 状態）
- Phase Handoff は review → merge で引き継ぎ。verify フェーズに渡す

### Deferred Items
- post-merge AC（実 XL Issue での `/audit progress <parent>` 実行確認）は verify フェーズで対応

### Notes for Next Phase
- 全 pre-merge AC: 8/8 PASS 確認済み
- squash コミットは main に着地済み。verify では実 XL Issue 番号でコマンド実行して出力を目視確認すること
- `get-sub-issue-progress.sh` は GraphQL mock ありのテスト環境でのみ検証済み。実環境でのレート制限・応答時間も確認対象

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 8 件すべて grep / file_exists / file_contains / rubric / command の自動 verify command 付き、verify を完全自動化
- 24h アクティビティ検出を `linked:#N` から GraphQL `updatedAt` に変更した issue refinement 判断が機能

#### code
- 新規 `scripts/get-sub-issue-progress.sh` 作成と SKILL.md / workflow.md / ja workflow.md の3箇所への記述追加が漏れなく完了
- bats 3 テスト（empty/mixed/all-done）で代表的な状態をカバー

#### review/merge
- review-light で問題なし、clean な squash merge

#### verify
- pre-merge AC 8 件全 PASS
- post-merge AC 1 件は observation event=auto-run → 実 XL Issue 発生時に観察

### Improvement Proposals
- N/A

