# Issue #144: spec: 外部 GitHub Action 参照スニペットに必須入力の検証ステップを追加

## Overview

`/spec` で `.github/workflows/*.yml` を含む変更を扱う場合に、参照する外部 GitHub Action の `action.yml` を確認して `required: true` の入力がスニペットに反映されているか検証するガイドラインを、`skills/spec/SKILL.md` の Step 10 SHOULD constraints 表に1行追加する。

背景: Issue #73（DCO導入）の verify レトロスペクティブにて、`tim-actions/dco@master` の必須入力 `commits: required: true` が欠落し、Spec のスニペット通りに実装しても CI FAIL が発生した。

## Changed Files

- `skills/spec/SKILL.md`: SHOULD constraints 表に External GitHub Action required inputs 行を追加

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 10「SHOULD constraints」表末尾（`| GitHub Actions workflow CI verify | ...` 行の直後）に以下の行を追加する (→ 受け入れ条件 1, 2):

   ```
   | External GitHub Action required inputs | When `.github/workflows/*.yml` is in the changed files and references an external Action, check the Action's `action.yml` (via WebFetch or repository reference) and verify all `required: true` inputs are included in the snippet | #144 |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "action.yml" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` の Step 10「SHOULD constraints」表に `action.yml` 参照ガイドライン行が追加されている
- <!-- verify: grep "required.*true" "skills/spec/SKILL.md" --> 同ガイドライン行の Content 列に `required: true` の入力欠落を防ぐ rationale テキストが記載されている

### Post-merge

- `.github/workflows/*.yml` の作成・変更を含む Issue に対して `/spec` を実行すると、実装ステップまたは Spec の Notes に `action.yml` 参照と `required: true` 入力の確認が提案されることを確認

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design
- なし。Spec の実装ステップ通りに `skills/spec/SKILL.md` の Step 10 SHOULD constraints 表末尾（`| GitHub Actions workflow CI verify | ...` 行の直後）に1行追加した。

### Design Gaps/Ambiguities
- なし。Spec の記述（追加する行の内容含む）が明確で、実装に迷いは生じなかった。

### Rework
- なし。
