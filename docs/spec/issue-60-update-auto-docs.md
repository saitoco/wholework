# Issue #60: docs: auto の説明が古い

## Overview

`docs/tech.md`・`docs/product.md` の `/auto` 関連記述が旧仕様（`code→review→merge→verify` のみ）を前提としており、現行実装と乖離している。以下の現行機能を Steering Documents に反映する:

- `phase/*` ラベル未設定の Issue に対して issue triage / refinement から自動開始
- `phase/ready` 未設定の場合は `/spec` を自動実行してから code 以降に進む
- `--batch N` で XS/S Issue をバックログから一括処理
- XL Issue に対して sub-issue 依存グラフを読み取り、独立な sub-issue を並列実行（worktree 分離）
- `--base {branch}` でリリースブランチを起点にした実行

`docs/workflow.md` は既に最新仕様を反映しているため変更不要。

## Changed Files

- `docs/tech.md`: Architecture Decisions の `/auto` skill bullet を現行仕様に更新（`--batch`・sub-issue 並列実行・issue 自動開始・spec 自動実行を追記）
- `docs/product.md`:
  - Future Direction: `/auto` hybrid approach の記述に XL 並列実行・`--batch`・issue 自動開始を追記
  - Terms table: `` `--auto` mode `` エントリを `` `/auto` `` に改名し、定義を現行仕様に更新

## Implementation Steps

1. `docs/tech.md` の `/auto` skill bullet（line 40）を更新: `code→review→merge→verify` のみの記述を、issue 自動開始・spec 自動実行・`--batch`・XL sub-issue 並列実行・`--base` を含む現行仕様に書き換える (→ 受け入れ基準 1, 2)
2. `docs/product.md` の Future Direction: `/auto` hybrid approach（line ~86）に XL 並列実行・`--batch`・issue 自動開始の記述を追記する (→ 受け入れ基準 3, 5)
3. `docs/product.md` の Terms table: `` `--auto` mode `` エントリを `` `/auto` `` に改名し、定義を現行仕様（issue triage 自動開始・spec 自動実行・`--batch`・XL sub-issue 並列実行を含む）に更新する (→ 受け入れ基準 3, 4, 5)

## Verification

### Pre-merge

- <!-- verify: file_contains "docs/tech.md" "--batch" --> `docs/tech.md` Architecture Decisions の `/auto` 記述に `--batch` が含まれる
- <!-- verify: file_contains "docs/tech.md" "sub-issue" --> `docs/tech.md` Architecture Decisions の `/auto` 記述に XL sub-issue 並列実行が言及される
- <!-- verify: file_contains "docs/product.md" "--batch" --> `docs/product.md` の `/auto` 関連記述に `--batch` が含まれる
- <!-- verify: file_not_contains "docs/product.md" "`--auto` mode" --> `docs/product.md` Terms table から旧 `` `--auto` mode `` エントリが削除されている
- <!-- verify: file_contains "docs/product.md" "issue triage" --> `docs/product.md` の `/auto` 記述に issue triage または issue refinement 自動開始の言及がある

### Post-merge

- 更新後のドキュメントを通読し、`/auto` の現行機能（issue 自動開始 / spec 自動実行 / code / review / merge / verify / `--batch` / XL sub-issue 並列実行 / `--base`）がいずれかの Steering / Project Document に反映されていることを目視確認する

## Notes

- Issue 本文の Auto-Resolved Ambiguity Points より: Terms table の `` `--auto` mode `` エントリ改名は `/auto` へ（他の Terms エントリが skill/機能名ベースのため統一）
- `docs/workflow.md` line 46 は既に `--batch`・XL・spec 自動実行・issue 自動開始を含む最新記述のため変更不要
- `README.md` line 9 の高レベル概要記述は既に正確のため変更不要
