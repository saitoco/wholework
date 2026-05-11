# Issue #444: audit: /audit stats Step 1 の timelineItems 取得を gh-graphql.sh named query 経由に修正

## Overview

`/audit stats` の Step 1 で使用している `gh issue view {number} --json timelineItems` は
`gh` CLI の `issue view --json` が `timelineItems` フィールドをサポートしていないためエラーになる。
既存の `scripts/gh-graphql.sh` に `get-issue-timeline` という named query を追加し、
`skills/audit/SKILL.md` Step 1 をその helper 呼び出しに書き換えることで再現可能にする。

## Reproduction Steps

1. `/audit stats` を実行する
2. Step 1 で `gh issue view {number} --json timelineItems` が実行される
3. `gh` CLI が "Unknown JSON field: timelineItems" エラーを返す
4. `/audit stats` が中断する

## Root Cause

`gh issue view --json` がサポートするフィールドは `assignees / author / body / closed / ...`
など固定セットであり `timelineItems` は含まれない。
`timelineItems` の取得には GraphQL API (`gh api graphql`) が必要。
`gh-graphql.sh` は named query パターン (`--query <name>`) で GraphQL を抽象化しているが、
`get-issue-timeline` query が未定義だった。

## Changed Files

- `scripts/gh-graphql.sh`: `get-issue-timeline` named query を `get_named_query()` に追加 — bash 3.2+ compatible
- `skills/audit/SKILL.md`: Step 1 の `gh issue view --json timelineItems` を `gh-graphql.sh --query get-issue-timeline` 呼び出しに書き換え
- `tests/gh-graphql.bats`: `get-issue-timeline` の test case を追加

## Implementation Steps

1. `scripts/gh-graphql.sh` の `get_named_query()` 関数内、`get-blocked-by)` ケースと `*)` ワイルドカード（L64）の間に `get-issue-timeline)` ケースを追加する。クエリは Issue 本文の参考実装を minified した形式で記述し、`$owner`/`$repo` 変数を含める（既存 query 同様に auto-resolve される）。(→ 受け入れ基準 1, 2)

   ```
   get-issue-timeline)
       printf '%s' 'query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){number timelineItems(itemTypes:[LABELED_EVENT,UNLABELED_EVENT,REOPENED_EVENT],first:100){nodes{__typename ... on LabeledEvent{label{name}createdAt} ... on UnlabeledEvent{label{name}createdAt} ... on ReopenedEvent{createdAt}}}}}}'
       ;;
   ```

2. `skills/audit/SKILL.md` の stats サブコマンド Step 1 "Fetch timeline items" セクションにある
   コードブロック（`gh issue view {number} --json timelineItems`）を
   `gh-graphql.sh --query get-issue-timeline` 呼び出しに置き換える。(→ 受け入れ基準 3, 4)

   置換前:
   ```bash
   gh issue view {number} --json timelineItems
   ```

   置換後:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query get-issue-timeline -F num={number} \
       --jq '.data.repository.issue'
   ```

3. `tests/gh-graphql.bats` に `get-issue-timeline` の正常系テストを追加する。
   既存テスト（`get-sub-issues`, `get-blocked-by`）の直後に挿入。
   `api_call` に `timelineItems` が含まれることを確認する。(→ 受け入れ基準 5, 6, 7)

   ```bash
   @test "success: --query get-issue-timeline resolves named query" {
       run bash "$SCRIPT" --query get-issue-timeline -F num=444
       [ "$status" -eq 0 ]
       grep -q "api graphql" "$GH_CALL_LOG"
       local api_call
       api_call=$(grep "api graphql" "$GH_CALL_LOG")
       [[ "$api_call" == *"timelineItems"* ]]
   }
   ```

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/gh-graphql.sh" "get-issue-timeline" --> `scripts/gh-graphql.sh` の named query dictionary に `get-issue-timeline` が追加される
- <!-- verify: file_contains "scripts/gh-graphql.sh" "timelineItems" --> `get-issue-timeline` クエリ本体に `timelineItems` フィールドが含まれる
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "gh issue view {number} --json timelineItems" --> `skills/audit/SKILL.md` から壊れた `gh issue view --json timelineItems` 記述が削除される
- <!-- verify: section_contains "skills/audit/SKILL.md" "### Step 1: Data Collection" "get-issue-timeline" --> `skills/audit/SKILL.md` Step 1 が `gh-graphql.sh --query get-issue-timeline` を使う形に書き換えられる
- <!-- verify: file_exists "tests/gh-graphql.bats" --> `tests/gh-graphql.bats` が存在する（既存テストファイル）
- <!-- verify: command "bats tests/gh-graphql.bats" --> `bats tests/gh-graphql.bats` が PASS する（新 query のテストケース追加後）
- <!-- verify: command "bash -n scripts/gh-graphql.sh" --> `gh-graphql.sh` の bash 構文チェックが通る

### Post-merge

- `/audit stats` を再実行し、SKILL.md の手順だけで全工程が完走することを確認する

## Notes

- GraphQL クエリ文字列は `!` を含むが、`get_named_query()` 内の `printf '%s' '...'` (single-quote) 内なので zsh history expansion の問題なし
- `--jq '.data.repository.issue'` で `number` + `timelineItems` を含む Issue オブジェクト全体を返す。呼び出し側で `.timelineItems.nodes` を参照する
- `timelineItems` の `first: 100` 上限は Issue 本文に Out of Scope として明記済み（pagination 対応は別 Issue）
- bats テストは `gh api graphql` を mock しているので実際のクエリ内容（`timelineItems` キーワード）は `api_call` ログ文字列から確認する

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ基準 7 条件すべてに `<!-- verify: ... -->` ヒントが付与されており、検証可能性が高い。曖昧な条件なし。
- `section_contains` ヒントのセクション名（`### Step 1: Data Collection`）が実ファイルの見出しと完全一致しており、UNCERTAIN を踏まずに PASS できた。

#### design
- 実装手順が Spec の Implementation Steps と完全一致。クエリ文字列・変数名・返却フィールドすべて仕様通り。設計偏差なし。

#### code
- 実装コミットは 1 件（b97886d）。fixup/amend なし、rework なし。Spec 処方通りのクリーンな実装。

#### review
- PR #448 でレビューが実施され、全 4 観点（Spec 整合・エッジケース・セキュリティ・ドキュメント）で問題なし。CI 全ジョブ SUCCESS。レビューコメント指摘なし。

#### merge
- PR #448 が単一コミットでクリーンにマージ。コンフリクトなし。

#### verify
- 初回実行で全 7 条件 PASS。CI 参照なしで `bats tests/gh-graphql.bats`（command ヒント）も直接実行で PASS（テスト22件すべて成功）。
- Post-merge 手動条件（`/audit stats` 再実行確認）が未チェック。`phase/verify` で残留。

### Improvement Proposals
- N/A

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- `section_contains` ヒントの verify executor 実装（awk ベース）が Section 境界を正確に特定できているか、初回確認時にコマンドが誤っていた（awk の終了条件が `^### ` で同一見出し行を除外できていなかった）。verify-executor 実装上は問題ないが、ローカル確認スクリプトの書き方に注意が必要

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

Nothing to note. 実装は Spec と完全一致。クエリの変数名（`$owner/$repo/$num`）、返却フィールド（`number + timelineItems`）、イベント種別（`LABELED_EVENT/UNLABELED_EVENT/REOPENED_EVENT`）すべて仕様通り。

### Recurring Issues

Nothing to note. レビュー観点（Spec 整合・エッジケース・セキュリティ・ドキュメント）で問題は検出されなかった。

### Acceptance Criteria Verification Difficulty

Nothing to note. 7 条件すべて PASS。`command` 型ヒント（bats テスト・bash 構文チェック）は safe モードで CI 参照フォールバックにより解決。verify command の品質は良好。
