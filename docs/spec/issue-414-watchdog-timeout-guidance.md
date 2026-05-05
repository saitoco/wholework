# Issue #414: docs: watchdog-timeout-seconds の運用ガイダンスを customization.md に追加

## Overview

`docs/guide/customization.md` の `watchdog-timeout-seconds` 関連記述に、Claude モデルの長い思考時間（Opus / xhigh effort、Size L+ Issue）によって 1800 秒を超える silent 期間が発生しうるという運用ガイダンスを追加する。YAML 例コメントと Available Keys テーブルの両方に追記する。

Issue #385 の `/auto` 実行中に `run-code.sh` の `claude` プロセスが watchdog によって kill された経験を踏まえた改善。README.md への追記は本 Issue のスコープ外（既存リンクで到達可能）。

## Changed Files

- `docs/guide/customization.md`: YAML 例コメントと Available Keys テーブルの `watchdog-timeout-seconds` 記述を拡充（"thinking" の追加）
- `docs/ja/guide/customization.md`: 上記に対応する日本語ミラーを更新

## Implementation Steps

1. `docs/guide/customization.md` の YAML 例コメント（L42-43）を以下に変更する（→ AC1、AC2）:
   ```
   # Watchdog timeout (default: 1800 seconds)
   # Claude's extended thinking time on Size L+ tasks (especially Opus with high effort)
   # can produce silent periods exceeding 1800 seconds. Set to 3600 for meta-development.
   ```

2. `docs/guide/customization.md` の Available Keys テーブルの `watchdog-timeout-seconds` 行（L84）を以下に変更する（→ AC1、AC2）:
   ```
   | `watchdog-timeout-seconds` | integer | `1800` | Watchdog timeout in seconds before killing a silent `claude -p` process. Claude's extended thinking time on Size L+ tasks (especially Opus with high effort) can produce silent periods exceeding 1800 seconds; set to `3600` for meta-development or Size L+ work. Values ≤0 fall back to the default. |
   ```

3. `docs/ja/guide/customization.md` の YAML 例コメント（L36-37）を以下に変更する（→ 翻訳同期）:
   ```
   # watchdog タイムアウト（デフォルト: 1800 秒）
   # Size L+ タスク（特に Opus / xhigh effort）では claude の長い思考時間により
   # 1800 秒を超える silent 期間が発生しうる。メタ開発用途では 3600 を推奨。
   ```

4. `docs/ja/guide/customization.md` の Available Keys テーブルの `watchdog-timeout-seconds` 行（L78）を以下に変更する（→ 翻訳同期）:
   ```
   | `watchdog-timeout-seconds` | integer | `1800` | watchdog が silent な `claude -p` プロセスを kill するまでのタイムアウト秒数。Size L+ タスク（特に Opus / xhigh effort）では claude の長い思考時間により 1800 秒を超える silent 期間が発生しうる。メタ開発や Size L+ 作業では `3600` を推奨。0 以下の値はデフォルトにフォールバック。 |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "thinking" "docs/guide/customization.md" --> `docs/guide/customization.md` の `watchdog-timeout-seconds` 関連記述に "thinking" が含まれている
- <!-- verify: rubric "docs/guide/customization.md の watchdog-timeout-seconds の説明に、claude モデルの長い思考時間や Size L+ Issue で 1800 秒を超える silent 期間が発生しうる事と、それに対する推奨設定値（例: 3600 秒）の運用ガイダンスが含まれている" --> 長時間 silent 状態に対する運用ガイダンスが明記されている

### Post-merge

- Size L Issue で `/auto` を実行し、`watchdog-timeout-seconds: 3600` を設定した場合に従来 1800s で kill されていたケースが完走することを確認する <!-- verify-type: manual -->

## Notes

- AC1 の `grep "thinking"` は実装後に新規追加するテキストで満たされる（実装前は存在しない）
- `docs/guide/customization.md` は `docs/` 直下ではなく `docs/guide/` にあるが、`docs/ja/guide/customization.md` という日本語ミラーが存在するため、`translation-workflow.md` の sync 趣旨に則り日本語ミラーも更新する
- README.md はすでに `customization.md` へのリンクを持つ（L51: `See the [Customization guide](docs/guide/customization.md) for details`）ため本 Issue の対象外
