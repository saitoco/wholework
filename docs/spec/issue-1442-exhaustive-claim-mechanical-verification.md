# Issue #1442: spec: skill-dev-constraints.md に exhaustive claim の機械的裏取りルールを追加

## Issue Retrospective

### Refinement Summary

- あいまい性検出: Size XS (検出上限 3件) で走査し、本質的なあいまい性は検出されませんでした。Background/Purpose/Proposal は具体的な1行のテーブル追加提案であり、AC も具体的な文字列一致条件で構成されています。
- Background の事実確認 (advisory): `skills/spec/skill-dev-constraints.md` に既存の "Example/exhaustive markers" 行はあるが、exhaustive claim の機械的裏取り制約は未収録という記述を `grep -n "Example/exhaustive\|exhaustive" skills/spec/skill-dev-constraints.md` で確認し、事実と一致することを確認しました。
- AC verify command 修正: 下記 Consumed Comments のトリアージ監査コメントの指摘を反映し、AC2 の verify command を `github_check "gh pr checks" "Run bats tests"` から patch route 用の `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` に修正しました (Size XS は `.wholework.yml` に `always-pr: true` が未設定のため patch route で処理され、対応する PR が存在しないため `gh pr checks` は恒久的に FAIL する)。
- `### Post-merge` セクションが本文に存在しなかったため、`なし` として追加し Standard Format に揃えました。

### Consumed Comments

- saito / MEMBER / first-class / Triage AC audit — AC2 の verify command が patch route (Size XS) と `gh pr checks` の不整合を指摘 / https://github.com/saitoco/wholework/issues/1442#issuecomment-5380797091

## Consumed Comments
No new comments since last phase.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec なし (XS patch route)。

#### design
- N/A (XS patch route)。

#### code
- 特記事項なし。commit 1件のみで完了。

#### review
- N/A (XS patch route、review フェーズなし)。

#### merge
- N/A (XS patch route、merge フェーズなし)。

#### verify
- AC2 の verify command `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` は、CI が in_progress の間は `.conclusion` が空文字列を返し、`verify-executor.md` の `github_check` 変換表が期待する「出力に `in_progress` を含む → PENDING」の文字列一致に該当しない (該当するのは `gh pr checks` の出力形式のみ)。今回は `.status` フィールドを別途確認して in_progress と判定し、CI 完了を待ってから再実行して PASS を確認した。この Issue と同時期に処理された他の retro/verify Issue (#1438-#1441) も同じ Triage AC audit テンプレート由来で同型の verify command を持つ可能性が高く、同じ摩擦が再発しうる。

### Retry Count

(N/A — auto-retry は発火していない)

### Improvement Proposals
- `github_check` の `gh run list --json conclusion` 形式の verify command は、CI 実行中に FAIL 誤判定または人手介在を招く可能性がある。`verify-executor.md` の `github_check` 処理で `gh run list` 系コマンドの `.conclusion` が空/null のケースを "in_progress" 相当として PENDING 扱いする補助ロジックを追加するか、テンプレート側で `--json conclusion,status --jq 'if .[0].status != "completed" then "in_progress" else .[0].conclusion end'` のような形に統一することを検討する。
