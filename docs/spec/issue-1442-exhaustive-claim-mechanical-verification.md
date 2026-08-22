# Issue #1442: spec: skill-dev-constraints.md に exhaustive claim の機械的裏取りルールを追加

## Issue Retrospective

### Refinement Summary

- あいまい性検出: Size XS (検出上限 3件) で走査し、本質的なあいまい性は検出されませんでした。Background/Purpose/Proposal は具体的な1行のテーブル追加提案であり、AC も具体的な文字列一致条件で構成されています。
- Background の事実確認 (advisory): `skills/spec/skill-dev-constraints.md` に既存の "Example/exhaustive markers" 行はあるが、exhaustive claim の機械的裏取り制約は未収録という記述を `grep -n "Example/exhaustive\|exhaustive" skills/spec/skill-dev-constraints.md` で確認し、事実と一致することを確認しました。
- AC verify command 修正: 下記 Consumed Comments のトリアージ監査コメントの指摘を反映し、AC2 の verify command を `github_check "gh pr checks" "Run bats tests"` から patch route 用の `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` に修正しました (Size XS は `.wholework.yml` に `always-pr: true` が未設定のため patch route で処理され、対応する PR が存在しないため `gh pr checks` は恒久的に FAIL する)。
- `### Post-merge` セクションが本文に存在しなかったため、`なし` として追加し Standard Format に揃えました。

### Consumed Comments

- saito / MEMBER / first-class / Triage AC audit — AC2 の verify command が patch route (Size XS) と `gh pr checks` の不整合を指摘 / https://github.com/saitoco/wholework/issues/1442#issuecomment-5380797091
