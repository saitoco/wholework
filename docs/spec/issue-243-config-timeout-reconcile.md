# Issue #243: watchdog: config timeout + 事後リコンサイルで false positive kill を運用無害化

## Overview

`claude-watchdog.sh` の silent 誤検知による false positive kill を二層防御で運用的に無害化する:

- **Layer 2**: `.wholework.yml` の `watchdog-timeout-seconds` で `WATCHDOG_TIMEOUT` を上書き可能にする (repo / Size / マシン性能差を吸収)
- **Layer 3**: 各 `run-*.sh` が exit 143 時に期待状態 (phase ごとの success signature) を検証し、到達済みなら exit 0 に書き換える共有 helper を導入する

## Reproduction Steps

1. 大きな repo または Size L 以上の Issue で `/auto N` を実行 (例: #230)
2. `run-code.sh` 内で claude -p が `bats tests/` などの長時間 tool call を含み、stdout が 1800s 間無出力になる
3. `claude-watchdog.sh` が hang と判定し SIGTERM
4. kill 直後に claude -p がバッファ済みの Summary をフラッシュ (commit / push / Issue state 遷移は既に完了)
5. `run-auto-sub.sh` は exit 143 を受け取り、バッチを失敗扱いで停止 (#230 と同型の false positive)

## Root Cause

`claude -p` の text 出力モードが実行中の進捗を stdout にストリームせず、終了時に一括フラッシュする。`claude-watchdog.sh` は stdout ファイルサイズ変化のみで hang 判定するため、silent thinking と真のハングを区別できない。

**直接対策**: stream-json / CPU ライブネスは副作用 (UX 退行 / クロスプラットフォーム複雑性) が大きいため却下。代替として (a) ユーザが repo 特性に応じて timeout を調整できる config エスケープハッチ、(b) kill が発動しても実作業完了済みなら success に昇格する事後リコンサイル、の二層で運用的無害化を狙う。

## Changed Files

- `modules/detect-config-markers.md`: marker table に `watchdog-timeout-seconds` → `WATCHDOG_TIMEOUT_SECONDS` 行を追加
- `scripts/watchdog-reconcile.sh`: 新規作成 — phase + issue 番号 + 追加コンテキストで期待状態を検証する共有 helper (bash 3.2+ 互換)
- `scripts/run-code.sh`: `watchdog-timeout-seconds` を config から読んで `WATCHDOG_TIMEOUT` env 設定 + exit 143 時に `watchdog-reconcile.sh` 呼び出し
- `scripts/run-review.sh`: 同上
- `scripts/run-merge.sh`: 同上
- `scripts/run-verify.sh`: 同上
- `scripts/run-spec.sh`: 同上
- `scripts/run-issue.sh`: 同上
- `tests/watchdog-reconcile.bats`: 新規作成 — reconcile の phase 別判定ロジックを bats 3.2+ 互換で検証
- `docs/guide/customization.md`: `watchdog-timeout-seconds` 設定項目の説明 (デフォルト 1800、調整指針、例) を追加

## Implementation Steps

**ステップ記録方針**: 光テンプレート上限 (5 ステップ) 内に収めるため関連作業をグルーピング。各ステップは並列・順次の依存関係を明記。

1. **Config marker 追加** (→ AC: Layer 2 marker)
   - `modules/detect-config-markers.md` の marker table に `watchdog-timeout-seconds` 行を追加
   - Variable: `WATCHDOG_TIMEOUT_SECONDS`、default: `1800` (現行動作維持)
   - Parsing rule: 既存の数値 key と同様に扱う (`production-url` 節のルールに倣う)

2. **Reconcile helper 作成** (parallel with 1) (→ AC: Layer 3 helper exists)
   - `scripts/watchdog-reconcile.sh` を新規作成 (bash 3.2+ 互換)
   - Usage: `watchdog-reconcile.sh <phase> <issue_number> [--pr <pr_number>] [--route patch|pr]`
   - Phase 別の success signature 検証 (下記テーブル参照)
   - 到達時 exit 0、未到達時 exit 143、gh/git エラー時 exit 2 (warning)

   | phase | 期待状態 (検証方法) |
   |-------|--------------------|
   | `issue` | `triaged` ラベル存在 (`gh issue view --json labels`) |
   | `spec` | `$SPEC_PATH/issue-$NUMBER-*.md` 存在 + `phase/ready` 以降ラベル |
   | `code-patch` | `origin/main` の直近コミットに `closes #$NUMBER` パターン (`git log origin/main --grep`) |
   | `code-pr` | `issue-$NUMBER-*` ブランチに対する PR 存在 (`gh pr list --head`) |
   | `review` | PR に `## Review Summary` マーカーコメント (`gh pr view --json comments`) |
   | `merge` | PR state = `MERGED` (`gh pr view --json state`) |
   | `verify` | Issue state = `CLOSED` または `phase/verify`/`phase/done` ラベル |

3. **6 run-*.sh の統合改修** (after 1, 2) (→ AC: Layer 2 per-script + Layer 3 per-script)
   - 各スクリプト (code / review / merge / verify / spec / issue) で共通の変更:
     - `env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" ...` の直前に `WATCHDOG_TIMEOUT=$(/Users/saito/src/wholework/scripts/get-config-value.sh watchdog-timeout-seconds 1800)` を挿入し env として渡す
     - 既存の `EXIT_CODE=$?` capture の直後に `if [[ $EXIT_CODE -eq 143 ]]; then "$SCRIPT_DIR/watchdog-reconcile.sh" <phase> "$ISSUE_NUMBER" [options] && EXIT_CODE=0; fi` を追加
   - `run-code.sh` は `--patch` / `--pr` route で `code-patch` / `code-pr` を渡し分ける
   - `run-review.sh` / `run-merge.sh` は `--pr $PR_NUMBER` を追加

4. **bats テスト作成** (after 2) (→ AC: watchdog-reconcile.bats exists + tests PASS)
   - `tests/watchdog-reconcile.bats` を新規作成、以下のシナリオを検証:
     - 各 phase の期待状態を満たすモック入力で exit 0
     - 期待状態未達で exit 143
     - gh API 失敗時 exit 2 + stderr warning
   - mock は `gh` / `git` を bats の `PATH` 先頭に配置する stub で代替
   - `tests/claude-watchdog.bats` は変更不要 (`WATCHDOG_TIMEOUT` env の既存読み取りをそのまま利用)

5. **ドキュメント更新** (parallel with 3, 4) (→ AC: customization.md 更新)
   - `docs/guide/customization.md` に `watchdog-timeout-seconds` セクションを追加
   - デフォルト値 (1800)、調整指針 (遅い repo / Size L 以上 / CI 遅延時に 3600 推奨)、設定例 (`watchdog-timeout-seconds: 3600`) を記載

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/detect-config-markers.md" "watchdog-timeout-seconds" --> `modules/detect-config-markers.md` の marker table に `watchdog-timeout-seconds` → `WATCHDOG_TIMEOUT_SECONDS` マッピングが追加されている
- <!-- verify: file_contains "scripts/run-code.sh" "WATCHDOG_TIMEOUT" --> `scripts/run-code.sh` が config 値を `WATCHDOG_TIMEOUT` env として `claude-watchdog.sh` に渡している
- <!-- verify: file_contains "scripts/run-review.sh" "WATCHDOG_TIMEOUT" --> `scripts/run-review.sh` が同様に渡している
- <!-- verify: file_contains "scripts/run-merge.sh" "WATCHDOG_TIMEOUT" --> `scripts/run-merge.sh` が同様に渡している
- <!-- verify: file_contains "scripts/run-verify.sh" "WATCHDOG_TIMEOUT" --> `scripts/run-verify.sh` が同様に渡している
- <!-- verify: file_contains "scripts/run-spec.sh" "WATCHDOG_TIMEOUT" --> `scripts/run-spec.sh` が同様に渡している
- <!-- verify: file_contains "scripts/run-issue.sh" "WATCHDOG_TIMEOUT" --> `scripts/run-issue.sh` が同様に渡している
- <!-- verify: file_contains "docs/guide/customization.md" "watchdog-timeout-seconds" --> `docs/guide/customization.md` に `watchdog-timeout-seconds` の説明が追加されている
- <!-- verify: file_exists "scripts/watchdog-reconcile.sh" --> 共有リコンサイル helper `scripts/watchdog-reconcile.sh` が存在する
- <!-- verify: file_contains "scripts/run-code.sh" "watchdog-reconcile" --> `run-code.sh` が exit 143 時に reconcile を呼び、期待状態到達なら exit 0 に書き換える
- <!-- verify: file_contains "scripts/run-review.sh" "watchdog-reconcile" --> `run-review.sh` が同様に reconcile する
- <!-- verify: file_contains "scripts/run-merge.sh" "watchdog-reconcile" --> `run-merge.sh` が同様に reconcile する
- <!-- verify: file_contains "scripts/run-verify.sh" "watchdog-reconcile" --> `run-verify.sh` が同様に reconcile する
- <!-- verify: file_contains "scripts/run-spec.sh" "watchdog-reconcile" --> `run-spec.sh` が同様に reconcile する
- <!-- verify: file_contains "scripts/run-issue.sh" "watchdog-reconcile" --> `run-issue.sh` が同様に reconcile する
- <!-- verify: file_exists "tests/watchdog-reconcile.bats" --> reconcile ロジックの bats テスト `tests/watchdog-reconcile.bats` が存在する
- <!-- verify: command "bats tests/claude-watchdog.bats tests/watchdog-reconcile.bats" --> watchdog 関連の bats テストが全て PASS する

### Post-merge

- `/auto` 実行中に watchdog kill が発生した場合でも、期待状態に到達していればバッチが継続する
- `.wholework.yml` で `watchdog-timeout-seconds: 3600` に変更した repo で、30 分超の Size L タスクが kill なしで完遂する

## Spec Retrospective

N/A (no spec phase issues noted)

## Code Retrospective

### Deviations from Design

- Spec の `get-config-value.sh` パス指定が `/Users/saito/src/wholework/scripts/get-config-value.sh` という絶対パスだったが、正しく `$SCRIPT_DIR/get-config-value.sh` に変更した。Spec のコードスニペットは例示用と判断し、実装では既存の `SCRIPT_DIR` パターンに従った
- `run-review.sh` / `run-merge.sh` の reconcile 呼び出しには issue 番号が必要なため、`gh-extract-issue-from-pr.sh` で PR から issue 番号を動的に取得するパターンを採用した (Spec では省略されていた詳細)
- Spec では `--route patch|pr` オプションも Usage に記載されていたが、`code-patch`/`code-pr` という phase 名でルートを直接表現できるため、`--route` フラグは実装を省略した

### Design Gaps/Ambiguities

- `run-review.sh` と `run-merge.sh` は PR 番号を主引数に取るため、reconcile に必要な issue 番号をどう取得するかが Spec では未記載。実装では `gh-extract-issue-from-pr.sh` を利用し、取得失敗時はスキップ (reconcile なし) とした
- `watchdog-reconcile.sh` の `spec` phase では `spec-path` を `get-config-value.sh` で取得するが、WHOLEWORK_SCRIPT_DIR が mock に向いている場合 mock の `get-config-value.sh` が呼ばれる。テストで `MOCK_SPEC_PATH` env 変数を使って mock を制御した

### Rework

- bats テスト作成時、`verify` phase の `--json state` / `--json labels` 呼び出し分岐を単一の `gh` mock で処理するため、`$*` でフラグを判別するパターンに修正した

## Notes

- **Size 超過注意**: 光テンプレートの pre-merge 上限 (5 項目) を大きく超え 17 項目となる。6 つの run-*.sh 個別検証が Issue の性質上必須 (1 スクリプトで実装漏れがあれば false positive が残る) のため、verify command は per-file 維持。実装ステップ側は 5 ステップ内にグルーピング済み
- **bash 3.2+ 互換性**: `watchdog-reconcile.sh` は macOS system bash (3.2) 互換で書く。`mapfile` / `[[ =~ ]]` の一部拡張 / 連想配列 (`declare -A`) は避ける
- **reconcile の `closes #N` パターン**: コミット SHA 厳密一致ではなく `git log --grep="closes #$NUMBER"` 等のパターン一致で済ませる。false positive 救済が目的でありコミット内容の正当性は `/review` / `/verify` の責務
- **auto-resolve 記録** (Issue body の Auto-Resolved Ambiguity Points より):
  - `WATCHDOG_HEARTBEAT_INTERVAL` の config 化は本 Issue スコープ外 (follow-up)
  - reconcile ロジックは共有 helper 集約 (各 run-*.sh に重複実装しない)
  - reconcile は `closes #N` パターン一致で十分
- **却下アプローチの記録**: stream-json 化とサブプロセスツリー CPU ライブネスは副作用分析の結果不採用 (詳細は Issue body Design Considerations)

## review retrospective

### Spec vs. 実装乖離パターン

Nothing to note。全 17 項目の受け入れ条件が PASS。Spec に記載された Layer 2（config timeout）・Layer 3（post-kill reconcile）の両層とも、6 つの run-*.sh・共有 helper・bats テスト・ドキュメント（英語・日本語両方）が揃って実装されており、Spec との乖離は確認されなかった。

### 再発イシューパターン

review-light エージェントが `docs/ja/guide/customization.md` 未更新・`docs/structure.md` のスクリプト未記載を指摘したが、いずれも実コードを確認した結果 false positive だった。エージェントが diff の partial view から判断する前に実ファイルを確認しなかった可能性がある。verify ステップで false positive を除去できたため運用上の問題はなかった。

### 受け入れ条件検証の難易度

Nothing to note。17 項目中 16 項目が `file_exists`/`file_contains` で直接検証可能。残り 1 項目（`command` bats テスト実行）は CI "Run bats tests" SUCCESS による代替検証が機能し UNCERTAIN ゼロで完了した。6 つの run-*.sh を個別に verify している設計（Notes に記載）は正しい選択であり、実装漏れを確実に検出できる。
