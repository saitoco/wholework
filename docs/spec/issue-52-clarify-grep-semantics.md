# Issue #52: docs: verify-executor.md で grep と file_not_contains のセマンティクスを明確化

## Overview

`modules/verify-executor.md` の verify command 変換表 line 46（`grep` コマンド行）に、セマンティクスの明示と `file_not_contains` への誘導を 1 行で追記する。verify command を書くユーザーが `grep` の exit code 感覚で「マッチしなければ PASS」と誤解するケースを防ぐ。

## Changed Files

- `modules/verify-executor.md`: line 46 を `Regex match using Grep` から `Regex match using Grep. **PASS when match is found**. To assert absence (no match), use \`file_not_contains\` instead` に変更

## Implementation Steps

1. `modules/verify-executor.md` line 46 の `grep` 行 Processing セルを Edit ツールで更新（→ 受け入れ条件 1, 2, 3）
   - 旧: `| \`grep "pattern" "path"\` | Regex match using Grep |`
   - 新: `| \`grep "pattern" "path"\` | Regex match using Grep. **PASS when match is found**. To assert absence (no match), use \`file_not_contains\` instead |`

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/verify-executor.md" "PASS when match is found" --> `modules/verify-executor.md` の `grep` 行に「PASS when match is found」のセマンティクス明示が追加されている
- <!-- verify: file_contains "modules/verify-executor.md" "To assert absence" --> `modules/verify-executor.md` の `grep` 行に「To assert absence」と代替コマンドへの誘導が追加されている
- <!-- verify: file_contains "modules/verify-executor.md" "Regex match using Grep." --> `modules/verify-executor.md` の `grep` 行末尾が新形式（"Grep." ピリオド + 追加説明）になっている

### Post-merge

- 将来の Issue 作成時にネガティブ表現（「X が残っていない」「X が削除されている」）に対して誤って `grep` を使うケースが発生しないかを観察 <!-- verify-type: opportunistic -->

## Notes

- 表セル内追記スタイルを採用（別セクション追加はしない）。XS スコープを維持するため
- 3 つの pre-merge 受け入れ条件のうち、3 番目は新形式の末尾ピリオド `"Regex match using Grep."` を一意マーカーとして利用する。旧形式は `"Regex match using Grep |"`（末尾パイプ）なので、ピリオドの存在で新形式を検証できる
- 表のフォーマット（パイプ区切り）を崩さないため、追記内容は 1 行に収める
- Issue body 元の 3 番目の受け入れ条件 `file_not_contains` 版は backslash escape の問題があったため、`/spec` フェーズで上記の `file_contains "Regex match using Grep."` 版に修正済み
