# Issue #112: spec/code: Guide appropriate verify command for patch route `github_check "gh pr checks"` usage

## Overview

Issue #92 の `/verify` 実行時に判明した問題への対処。パッチルート（mainへの直接コミット）で実装されたIssueの受け入れ条件に `github_check "gh pr checks"` が使用されていたが、パッチルートではPRが存在しないためこのコマンドは実行できない。今回はCI run一覧から代替検証できたが、verifyコマンドとしての正確性に欠けていた。

以下の3ファイルを変更することで対処する：
1. `modules/verify-classifier.md` にパッチルート向けCI検証コマンド推奨形式を追記
2. `skills/spec/SKILL.md` Step 10 SHOULD制約テーブルにパッチルートCIverify行を追加
3. `skills/verify/SKILL.md` Step 5 先頭にパッチルート検知ロジックを追加

スコープ外: `skills/code/SKILL.md` および `skills/issue/spec-test-guidelines.md` への変更（受け入れ条件に含まれないため）。

## Changed Files

- `modules/verify-classifier.md`: Processing Steps 末尾に "### Patch Route CI Verification Note" サブセクションを追加
- `skills/spec/SKILL.md`: Step 10 の SHOULD 制約テーブルに "Patch route CI verify" 行を追加
- `skills/verify/SKILL.md`: Step 5 先頭（"Verification priority:" の前）にパッチルート検知ブロックを追加

## Implementation Steps

1. `modules/verify-classifier.md` の `## Processing Steps` 末尾（`## Output` の直前）に `### Patch Route CI Verification Note` サブセクションを追加する。内容: パッチルートIssueでは `github_check "gh pr checks"` は PR が存在しないため使用不可。代わりに `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` 形式を推奨 (→ 受け入れ条件1)

2. `skills/spec/SKILL.md` の SHOULD 制約テーブル末尾行（`| Post-merge skill name alignment | ...` の直後）に行を追加する。内容: `| Patch route CI verify | For patch route Issues (SPEC_DEPTH=light), use \`github_check "gh run list"\` instead of \`github_check "gh pr checks"\` (no PR in patch route). See \`${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md\` | #112 |` (→ 受け入れ条件2)

3. `skills/verify/SKILL.md` の `### Step 5: Verify Each Condition` 直後（"Verification priority:" の前）にパッチルート検知ブロックを追加する。条件: Step 2 でPR未検出（PR_NUMBER が空）かつ受け入れ条件に `github_check "gh pr checks"` が含まれる → 対象条件を UNCERTAIN として「PRが存在しないためCI run参照を推奨。`github_check "gh run list"` 形式を使用すること。`modules/verify-classifier.md` 参照」と案内 (→ 受け入れ条件3)

## Verification

### Pre-merge
- <!-- verify: grep "gh run list\|run list\|パッチルート" "modules/verify-classifier.md" --> `modules/verify-classifier.md` にパッチルートでのCI検証コマンドの推奨形式が記載されている
- <!-- verify: grep "gh run list\|run list" "skills/spec/SKILL.md" --> `/spec` SKILL.mdがパッチルートでのverifyコマンド推奨形式を案内している（または`modules/verify-classifier.md`を参照している）

### Post-merge
- パッチルートで実装されたIssueの受け入れ条件に `github_check "gh pr checks"` が含まれる場合、`/verify` 実行時に「PRが存在しないためCI run参照を推奨」と案内される

## Notes

- `skills/code/SKILL.md` も「spec/code」とIssueタイトルに含まれるが、受け入れ条件に含まれないためスコープ外とした。必要に応じてフォローアップIssueで対応する
- `skills/issue/spec-test-guidelines.md` には `github_check "gh pr checks"` の推奨例が掲載されているが、こちらもスコープ外（bats検証ガイドラインの更新は別途検討）
- Issue body の受け入れ条件3はverify commandなし（手動確認）のため、Post-mergeに配置。Issue body全3件に対しPre-merge verify commandは2件（count mismatch: 3 vs 2）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件3（`/verify`実行時の案内）にverifyコマンドが付与されておらず、post-merge・ヒントなしとして処理された。Specも「count mismatch: 3 vs 2」と自己注記しており、条件3のverifyコマンドとして `grep "gh pr checks" "skills/verify/SKILL.md"` を追加できた可能性がある。今回はAI判断でPASSできたが、verifyコマンドがあればより確実な自動検証が可能だった。

#### design
- 変更対象ファイル3本（`verify-classifier.md`, `skills/spec/SKILL.md`, `skills/verify/SKILL.md`）のスコープが明確かつ適切。スコープ外（`skills/code/SKILL.md`, `spec-test-guidelines.md`）についてもSpec Notesで明記されており、設計判断の透明性が高い。

#### code
- 実装は1コミット（5925a36）で完了、リワークなし。設計通り3ファイルへの変更が適用された。

#### review
- パッチルート（直接コミット）のため、PRレビューなし。

#### merge
- パッチルート（mainへの直接コミット）。コンフリクトなし。

#### verify
- 条件1,2はverifyコマンドによる自動検証でPASS。条件3はAI判断（`skills/verify/SKILL.md` Step 5の実装確認）でPASS。
- 今後、同種のIssueではpost-merge条件にも `grep` 等のverifyコマンドを付与することで、完全自動化できる。

### Improvement Proposals
- 受け入れ条件の記述ガイドラインとして、「post-merge条件にもverify commandを付与する」推奨を `spec-test-guidelines.md` や Spec フォーマットに追加することを検討する（今Issueはスコープ外と判断したが、継続的な改善として有効）。
