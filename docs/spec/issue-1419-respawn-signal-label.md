# Issue #1419: detect-unrecorded-kills: 出力ラベルを respawn signal に改め kill との等値誤読を防ぐ

## Issue Retrospective

### スコープ決定 (ユーザー確認)

出力の変更範囲について 3 案を提示し、**「`kill:` ラベルのみ改称」** が選択された。`## Burst:` ヘッダの改称は「バースト」も kill を含意するため一貫性の観点では望ましいが、既存テスト 3 箇所 (135 / 149 / 337 行) の修正を伴うため分離した。

`orchestration-recoveries.md` の `cause` 自動突合 (出力に `cause:` 列を追加) も提示したが、**含めない**が選択された。Markdown パースの実装とテスト追加で Size が上がるため、必要になった時点で別途起票する。Related 欄に将来候補として記録済み。

### AC の修正 (verify command 監査の結果)

初版の AC を `skill-dev-verify-audit.md` Pattern 2 (常時 PASS) で監査したところ、**2 件の欠陥が見つかったため本文を修正した**:

1. **`grep "respawn:"` は常時 PASS だった** — docstring に "respawn signal" が既に 10 箇所存在するため、変更前から PASS してしまい検証信号にならない。出力 f-string 固有の形である `, respawn: ` (変更前 0 箇所) に差し替えた
2. **`rubric` を機械的検証に置き換えた** — 「`kill:` ラベルが残っていない」を当初 `rubric` で書いていたが、`file_not_contains "..." ", kill: "` (変更前 1 箇所) で決定的に検証できるため置換した。内部変数 `kill_ts` は `, kill: ` にマッチしないため、スコープ外の変数名を誤検出しない

### bats AC の実効性に関する注記

`command "bats tests/detect-unrecorded-kills.bats"` を AC に含めたが、**#1412 (OPEN) が指摘する通り、同ファイルのアサーション 26 件はすべて裸の `[[ "$output" == ... ]]` 形式**で、bash 3.2 では `set -e` に反応せず FAIL を検出できない。

この AC を落とすことも検討したが、#1412 の着地後に実効性が回復すること、および回帰の有無を人が読む手がかりにはなることから、**補助的検証と明示したうえで残した**。変更の正しさの主たる根拠は上記 2 つの静的検証に置いている。Background と Related に依存関係を記録した。

### Size / Type 判定の根拠

- **Size XS**: 変更対象は `scripts/detect-unrecorded-kills.sh` 1 ファイル。出力文字列の変更のみでロジック分岐の追加はないため Axis 2 の増加要因に該当せず、テストファイルを変更しないため CI Dependency Minimum Override (Size M 下限) にも該当しない
- **Type Task**: 検出器は docstring 通りに動作しており機能欠陥ではない。出力ラベルの語彙選択の問題であり maintenance に相当する
- **Theme observability**: 「detection without persistence, logging gaps」— 検出結果の解釈可能性は observability の範疇

## Consumed Comments
No new comments since last phase.
