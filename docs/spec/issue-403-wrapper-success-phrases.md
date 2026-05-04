# Issue #403: detect-wrapper-anomaly: silent-no-op 成功フレーズパターンを英語フレーズで拡充

## Overview

`scripts/detect-wrapper-anomaly.sh` の silent-no-op 検出パターン（Issue #369 追加）は現在、成功フレーズとして `完了しました` と `commit and push` の2パターンのみを用いている。LLM が生成する成功フレーズはバリエーションがあり検出漏れが発生しうるため、英語成功フレーズ `successfully committed`・`pushed to`・`changes have been committed` を追加してパターンを拡充する。フレーズチェック廃止（コミット有無のみ判定）は exit=0 + コミットなしの正当ケース（冪等実行、条件スキップ等）が誤検知されるリスクがあるため不採用。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: silent-no-op 成功フレーズ grep パターンに英語フレーズ3種を追加 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: 英語成功フレーズ `successfully committed` を使う silent-no-op 検出テストケースを追加

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の行 `grep -qiE "完了しました|commit and push"` を `grep -qiE "完了しました|commit and push|successfully committed|pushed to|changes have been committed"` に変更 (→ AC1, AC2)
2. `tests/detect-wrapper-anomaly.bats` に新テストケース `"silent no-op: detects exit_code=0 with English success phrase 'successfully committed'"` を追加。既存の silent-no-op テストと同じ git モック構成を使い、ログに `"Successfully committed all changes."` を書き込んで検出確認 (→ AC3)

## Verification

### Pre-merge

- <!-- verify: grep "successfully committed" "scripts/detect-wrapper-anomaly.sh" --> `scripts/detect-wrapper-anomaly.sh` の silent-no-op 成功フレーズパターンに英語フレーズ `successfully committed` が追加されている
- <!-- verify: grep "pushed to\|changes have been committed" "scripts/detect-wrapper-anomaly.sh" --> 英語成功フレーズ `pushed to` または `changes have been committed` が追加されている
- <!-- verify: grep "successfully committed" "tests/detect-wrapper-anomaly.bats" --> `tests/detect-wrapper-anomaly.bats` に `successfully committed` フレーズを使った silent-no-op 検出テストケースが追加されている

### Post-merge

- 英語成功フレーズ（例: `"successfully committed"` を含むログ）で silent-no-op が検出されることを確認

## Notes

- `detect-wrapper-anomaly.sh` は `--log <path>` で渡された特定のログファイルのみをスキャンするため、bats テストファイル自体に `successfully committed` が含まれても自己参照誤検知は発生しない
- 現行パターン `grep -qiE "..."` は `-i` フラグで大文字小文字を区別しないため、`Successfully committed` 等も一致する

## Code Retrospective

### Deviations from Design
- なし。Spec の実装ステップ通りに実装完了。

### Design Gaps/Ambiguities
- なし。

### Rework
- なし。

## review retrospective

### Spec vs. implementation divergence patterns
- なし。実装は Spec の Implementation Steps に完全に準拠しており、3フレーズの追加とテストケースがすべて期待通り実装されていた。

### Recurring issues
- verify コマンド構文の問題（ripgrep 非互換の `\|` 表記）が AC2 で検出された。verify-executor は ripgrep を使用するが、AC 作成時に `\|` を alternation として記述したため、実際の検証で FAIL/UNCERTAIN になる可能性がある。verify コマンドを書く際は bare `|` を使うよう、Issue テンプレートまたはドキュメントにガイドラインを追記することで再発防止が期待できる。
- pre-existing な Forbidden Expressions 違反（main の別 Spec ファイル）が pull_request CI で検出され、ブロッカーとなった。main ブランチの健全性チェックを定期的に行うか、push イベント CI と pull_request イベント CI の結果を明確に区別する仕組みが有効かもしれない。

### Acceptance criteria verification difficulty
- AC2 の verify コマンド `grep "pushed to\|changes have been committed"` が ripgrep 非互換のため、verify-executor での自動検証が FAIL/UNCERTAIN になる可能性があった。実際には `pushed to` と `changes have been committed` をそれぞれ個別の Grep 呼び出しで確認した。verify コマンドは bare `|` を使用する（例: `grep "pushed to|changes have been committed"`）ことで verify-executor との互換性が保たれる。
