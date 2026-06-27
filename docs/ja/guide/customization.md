[English](../../guide/customization.md) | 日本語

# 🛠️ カスタマイズ

Wholework は 3 層の設定でプロジェクトに適応します: フィーチャーフラグ用の `.wholework.yml`、スキルフェーズ指示用の `.wholework/domains/`、ツール統合用の adapter。

## `.wholework.yml`

プロジェクトルートに `.wholework.yml` を作成してオプション機能を有効化しパスを設定します。

```yaml
# .wholework.yml

# レビューツール連携（デフォルトは全て無効）
copilot-review: true        # マージ前に GitHub Copilot review を待つ
claude-code-review: true    # マージ前に Claude Code Review を待つ
coderabbit-review: true     # マージ前に CodeRabbit review を待つ
review-bug: false           # /review でバグ検出 agent を無効化

# /auto 実行時のセッションタイトル自動リネーム
session-auto-rename: true   # /auto N 実行時にセッションタイトルを Issue 番号とタイトルにリネーム

# スキル後検証
opportunistic-verify: true  # スキル完了時に軽量 verify command を実行

# スキル改善提案
skill-proposals: true       # /verify 中に Wholework 改善 issue を生成

# Steering ヒント（デフォルト有効、false にするとオプトアウト）
steering-hint: false        # steering docs 欠如時に表示される「/doc init」ヒントを抑制

# カスタムパス（括弧内はデフォルト）
spec-path: docs/spec              # spec の保存先
steering-docs-path: docs          # steering documents の配置先

# ブラウザベース verify command 用の本番 URL
production-url: https://yourapp.example.com

# watchdog タイムアウト（デフォルト: 2700 秒）
# Size L+ タスク（特に Opus / xhigh effort）では claude の長い思考時間により
# 2700 秒を超える silent 期間が発生しうる。メタ開発用途では 3600 を推奨。
watchdog-timeout-seconds: 3600

# フェーズ別上書き（オプション; watchdog-timeout-seconds より優先）
# watchdog-timeout-spec-seconds: 1800
# watchdog-timeout-code-seconds: 1800
# watchdog-timeout-review-seconds: 2000
# watchdog-timeout-merge-seconds: 600
# watchdog-timeout-issue-seconds: 600

# main ブランチへの push 用 lock タイムアウト（デフォルト: 300 秒、lock は git merge + push 中のみ保持）
patch-lock-timeout: 300

# /verify のダーティファイル検出から除外するパス
# サポート: dir/** プレフィックスマッチ; 単純 bash glob（*, ?, [...]）によるフルパス完全一致
# 非対応: 中間 **（例: a/**/b）や否定パターン（!）
verify-ignore-paths:
  - vault/**
  - vault/.obsidian/**

# /auto サブプロセスの permission mode（デフォルト: auto）
# "auto" は --permission-mode auto を allow rules テンプレートと共に使用（docs/guide/auto-mode-template.json 参照）
# "bypass" は --dangerously-skip-permissions を使用（レガシー / オプトアウト）
permission-mode: auto

# XL sub-issue 並列実行の同時実行数キャップ（デフォルト: 5）
# auto-max-concurrent: 5

# verify reopen ループの最大試行回数（default: 3、max: 20）
# N 回 FAIL した時点で reopen を停止し、Issue を phase/verify に留めて人間の判断を促す
verify-max-iterations: 3

# verify FAIL 時の自動リトライ（opt-in; autonomy: L2 または L3 が必要）
# 有効時、/verify は自動的に /code を再発火して FAIL 後にリトライを行う。
# max_iterations 回または budget_tokens 消費まで繰り返す。
# auto-retry-on-fail:
#   enabled: true
#   max_iterations: 3
#   budget_tokens: 500000

# orchestration-recoveries.md の symptom 数が閾値を超えた際に改善 Issue を自動起票
# （opt-in; autonomy: L2 または L3 が必要）
# recoveries-auto-fire:
#   enabled: true
#   threshold: 3

# オプション capability
capabilities:
  browser: true             # Playwright ベースの verify command を有効化
  workflow: true            # /review --full で Workflow ベースのマルチエージェント実行を有効化
  pr-preview: true          # PR が preview URL を生成することを宣言（pre-merge-preview AC 層を有効化）

# website 系プロジェクト設定: PR route 強制 + 自動 merge 前に停止
# (autonomy: tier と直交 — パイプライン到達点を制御し、意思決定自律度には影響しない)
# always-pr: true           # Size に関わらず PR route を強制（XS/S も branch + PR 経由）
# auto-stop-at: review      # review phase 完了後に /auto を停止、手動で /merge を実行
```

すべてのキーはオプションです。`.wholework.yml` が存在しない場合、すべての設定はデフォルトで動作します。

### Available Keys

このテーブルは `.wholework.yml` の全設定キーにおける **Single Source of Truth (SSoT)** です。キーを追加・変更する際はこのテーブルを更新してください。

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `copilot-review` | boolean | `false` | マージ前に GitHub Copilot review を待つ |
| `claude-code-review` | boolean | `false` | マージ前に Claude Code Review を待つ |
| `coderabbit-review` | boolean | `false` | マージ前に CodeRabbit review を待つ |
| `review-bug` | boolean | `true` | `/review` でバグ検出 agent を実行する |
| `opportunistic-verify` | boolean | `false` | スキル完了時に軽量 verify command を実行する |
| `skill-proposals` | boolean | `false` | `/verify` 中に Wholework 改善 issue を生成する |
| `session-auto-rename` | boolean | `false` | `/auto N` 実行時にセッションタイトルを Issue 番号とタイトルにリネームする |
| `steering-hint` | boolean | `true` | steering docs が欠如している場合に `/doc init` ヒントを表示する |
| `production-url` | string | `""` | ブラウザベース verify command 用の本番 URL |
| `spec-path` | string | `docs/spec` | spec の保存先 |
| `steering-docs-path` | string | `docs` | steering document の配置先 |
| `capabilities.browser` | boolean | `false` | Playwright ベースの verify command を有効化する |
| `capabilities.workflow` | boolean | `false` | `/review --full` で Workflow ベースのマルチエージェント実行を有効化する（opt-in; 未設定時は static Task fan-out にフォールバック） |
| `capabilities.pr-preview` | boolean | `false` | PR preview URL の存在を宣言する。URL/UX 系 AC を pre-merge-preview に分類し、`PREVIEW_URL` 環境変数が設定されている場合に `/review` 時に実行する。`/verify` post-merge では二重検証防止のため skip する。 |
| `capabilities.mcp` | list | `[]` | スキルから利用できる MCP ツール名 |
| `capabilities.{name}` | boolean | `false` | 動的 capability マッピング（例: `capabilities.invoice-api: true`） |
| `watchdog-timeout-seconds` | integer | `2700` | watchdog が silent な `claude -p` プロセスを kill するまでのタイムアウト秒数。Size L+ タスク（特に Opus / xhigh effort）では claude の長い思考時間により 2700 秒を超える silent 期間が発生しうる。メタ開発や Size L+ 作業では `3600` を推奨。0 以下の値はデフォルトにフォールバック。 |
| `watchdog-timeout-spec-seconds` | integer | `""` (フォールバック: `1800`) | `/spec` フェーズ用 watchdog タイムアウト上書き。優先順位: このキー > `watchdog-timeout-seconds` > `1800`。 |
| `watchdog-timeout-code-seconds` | integer | `""` (フォールバック: `1800`) | `/code` フェーズ用 watchdog タイムアウト上書き。優先順位: このキー > `watchdog-timeout-seconds` > `1800`。 |
| `watchdog-timeout-review-seconds` | integer | `""` (フォールバック: `2000`) | `/review` フェーズ用 watchdog タイムアウト上書き。優先順位: このキー > `watchdog-timeout-seconds` > `2000`。 |
| `watchdog-timeout-merge-seconds` | integer | `""` (フォールバック: `600`) | `/merge` フェーズ用 watchdog タイムアウト上書き。優先順位: このキー > `watchdog-timeout-seconds` > `600`。 |
| `watchdog-timeout-issue-seconds` | integer | `""` (フォールバック: `600`) | `/issue` フェーズ用 watchdog タイムアウト上書き。優先順位: このキー > `watchdog-timeout-seconds` > `600`。 |
| `patch-lock-timeout` | integer | `300` | `git merge --ff-only` + `git push origin main` の lock 取得タイムアウト秒数。lock 保持は数秒のためデフォルトは余裕値。push 取得が常時失敗する場合のみ増やす。0 以下または非数値の場合は `300` にフォールバック。ファイルを編集せずに per-run で上書きする (緊急用) には `WHOLEWORK_PATCH_LOCK_TIMEOUT` env var を設定する。優先順位: env var > このキー > `300`。 |
| `permission-mode` | string | `"auto"` | `/auto` サブプロセスの permission mode。`auto` は `--permission-mode auto` を allow rules テンプレートと共に有効化（`docs/guide/auto-mode-template.json` 参照）; `bypass` は `--dangerously-skip-permissions` を使用（レガシー / オプトアウト）。 |
| `verify-max-iterations` | integer | `3` | verify-reopen ループの最大試行回数。N 回 FAIL した時点で停止し、Issue を `phase/verify` に留めて人間の判断を促す。0 以下、20 超、または非数値の場合は `3` にフォールバック。 |
| `auto-max-concurrent` | integer | `5` | XL 並列ルートで同時実行できる sub-issue の最大数。依存グラフの各レベルに適用。0 以下または非数値の場合は `5` にフォールバック。 |
| `auto-retry-on-fail.enabled` | boolean | `false` | verify FAIL 時の自動 `/code` 再発火 + `/verify` リトライを有効化する（`autonomy: L2` または `L3` が必要）。`false` または autonomy が `L1` の場合はアドバイザリーガイダンスのみ出力。 |
| `auto-retry-on-fail.max_iterations` | integer | `3` | 自動リトライの最大試行回数。上限到達後はユーザーに制御を戻す。0 以下または非数値の場合は `3` にフォールバック。 |
| `auto-retry-on-fail.budget_tokens` | integer | `500000` | 自動リトライのトークン予算概算。初期実装は試行回数カウントのみ; トークン追跡は将来の改善項目。0 以下または非数値の場合は `500000` にフォールバック。 |
| `recoveries-auto-fire.enabled` | boolean | `false` | `orchestration-recoveries.md` の symptom 数が閾値を超えた際に改善 Issue を自動起票する（`autonomy: L2` または `L3` が必要）。`false` または autonomy が `L1` の場合は推奨メッセージを出力するのみ。 |
| `recoveries-auto-fire.threshold` | integer | `3` | 自動起票のトリガーとなる symptom 発生回数の閾値。0 以下または非数値の場合は `3` にフォールバック。 |
| `next-cycle-seed.enabled` | boolean | `false` | バッチ完了後に次サイクル候補 Issue を emit する（`autonomy: L2` または `L3` が必要）。バッチセッション中に作成された `audit/*` Issue を `.tmp/next-cycle.json` に書き出す。`false` または autonomy が `L1` の場合は推奨メッセージを出力するのみ。 |
| `retro-proposals-upstream` | string | `""` | Upstream リポジトリ (`owner/repo`) — `/verify` レトロスペクティブから得られた Skill infrastructure improvement 提案の起票先。設定すると、対象提案はサニタイズ（regex で絶対パスと下流固有 Issue 番号を除去、LLM でビジネス文脈用語を除去）されて upstream リポジトリへ起票される。下流リポジトリへの起票はスキップされる。未設定時は従来どおり下流リポジトリへ起票（後方互換）。 |
| `verify-ignore-paths` | list | `[]` | `/verify` のダーティファイル検出から除外するパスの glob パターン（block list）。サポート: `dir/**` プレフィックスマッチ（ディレクトリ配下の任意ファイル）、単純 bash glob（`*`、`?`、`[...]`）によるフルパス完全一致。非対応: 中間 `**`（例: `a/**/b`）や否定パターン（`!`）。いずれかのパターンにマッチするファイルは除外され stderr に警告出力される。未設定時は除外なし。 |
| `always-pr` | boolean | `false` | Size に関わらず PR route (branch + PR) を強制する。通常 main に直接 commit する XS/S Issues も PR 経由になる。`--patch` と同時指定した場合は `--patch` を無視して PR route を使用する。`autonomy:` tier と直交（パイプラインのルートを制御し、意思決定自律度には影響しない）。 |
| `auto-stop-at` | string | `"verify"` | `/auto` が停止するフェーズを宣言する。有効値: `spec`、`code`、`review`、`merge`、`verify`。デフォルト `verify` はフルパイプライン実行（現状の動作）。merge = 公開になる website 系プロジェクトでは `review` を推奨（人間が gate した後 `/merge` を手動実行）。per-invocation override: `--stop-at=<phase>`。`autonomy:` tier と直交。 |

実装の詳細や YAML パースルールを含む完全なリファレンスは [`modules/detect-config-markers.md`](../../../modules/detect-config-markers.md) を参照してください。

### Website 系プロジェクト推奨設定

main ブランチが本番ブランチ (merge = 公開) のプロジェクトでは、`always-pr` と `auto-stop-at` を組み合わせて `/auto` を安全に使用できます。

```yaml
# website 系プロジェクト推奨設定
always-pr: true       # Size に関わらず全変更を PR 経由にする
auto-stop-at: review  # AI review 後に停止、人間が PR を確認してから /merge を手動実行
```

この組み合わせにより、`/auto` の orchestration 恩恵 (issue/spec/code/review の連続実行) を受けつつ、merge = 公開ステップは人間が gate できます。`/auto` が `review` で停止した後、preview URL の確認と AI review コメントの確認を行い、`/merge <issue-number>` を実行して公開します。

注: `always-pr` と `auto-stop-at` は `autonomy:` tier と直交する軸です。`autonomy:` tier は GitHub state 書き込みとループ発火パスの許可範囲を制御し、`always-pr` は PR ルートを制御し、`auto-stop-at` はパイプライン到達点を制御します。

### AC 検証層

Wholework は acceptance criteria を 3 層に分類します。

| 層 | 実行タイミング | 対象 AC 例 |
|---|---|---|
| **pre-merge-local** | `/review` safe mode（常時） | ファイル存在・テキスト一致・コード品質・テスト結果 |
| **pre-merge-preview** | `PREVIEW_URL` が設定された `/review` 時 | `http_status`、`html_check`、`api_check`、`http_header`、`http_redirect`、`browser_check`、`browser_screenshot`、`lighthouse_check` |
| **post-merge-production** | `/verify` full mode | 本番デプロイ確認・本番固有の動作 |

**pre-merge-preview の有効化:**

`.wholework.yml` に `capabilities.pr-preview: true` を設定します。`/issue` が URL/UX 系 verify command を持つ AC を作成・更新する際、それらの AC は `### Pre-merge (auto-verified)` セクションに `<!-- ac-tier: preview -->` タグと `--when="test -n \"$PREVIEW_URL\""` ガードを付与して配置されます。

**`PREVIEW_URL` の解決:**

`PREVIEW_URL` 環境変数は `/review` 呼び出し前に export する必要があります。Wholework 側での自動解決は行いません — CI パイプラインまたはプロジェクト側スクリプトの責務です。例:

```bash
# CI (GitHub Actions 等) — /review 実行前に設定
export PREVIEW_URL="https://my-pr-123.example-preview.com"
```

**動作まとめ:**

- `/review` 時に `PREVIEW_URL` が設定されている: preview 層 AC を preview URL に対して実行する。
- `/review` 時に `PREVIEW_URL` が未設定: `--when` ガードが発動し preview 層 AC は SKIPPED になる（人間がフォローアップ）。
- `/verify` (post-merge) 時: `ac-tier: preview` 付き AC はすべて skip される（二重検証防止）。本番でも同 AC を検証したい場合は、`### Post-merge` セクションへタグなしで複製する。

## `.wholework/domains/`

Domain ファイルは Wholework 本体を変更せずに、個々のスキルフェーズへプロジェクト固有の指示を追加する仕組みです。

`.wholework/domains/{skill}/` 配下に Markdown ファイルを作成します:

```
.wholework/
└── domains/
    ├── spec/          # /spec がロード
    ├── code/          # /code がロード
    └── review/        # /review がロード
```

例えば `/spec` にプロジェクトの API 規約を伝えるには `.wholework/domains/spec/api-conventions.md` を作成します:

```markdown
# API Conventions

All new endpoints must follow REST naming: GET /resources, POST /resources, GET /resources/:id.
Authentication via Bearer token is required on all routes.
```

`/spec` 実行時、`.wholework/domains/spec/` 内のすべての `.md` ファイルを読み込み制約として取り込みます。これによりプロジェクト固有のルールを `CLAUDE.md` から切り離し、構造化された場所に置けます。

## Adapter

Wholework はツールアクセス（ブラウザ自動化、CI チェック、外部サービス）を抽象化する adapter パターンを使います。Adapter は優先度順に解決されます:

1. **プロジェクトローカル** — リポジトリの `.wholework/adapters/`
2. **ユーザーグローバル** — 全プロジェクトで共有する `~/.wholework/adapters/`
3. **バンドル** — Wholework 同梱のデフォルト adapter

つまり Wholework を fork せずに、どのビルトイン adapter もプロジェクト向けにオーバーライドできます。`.wholework/adapters/` のプロジェクトローカル adapter がバンドル版を覆い隠します。

カスタム adapter や verify command ハンドラの書き方詳細は [docs/ja/guide/adapter-guide.md](adapter-guide.md) を参照してください。

## Steering Documents

Steering Documents（`docs/product.md`、`docs/tech.md`、`docs/structure.md`）は Wholework に深いプロジェクトコンテキストを与える主要手段です。スキルは存在すれば自動的に読み込みます。

`/doc init` でコードベースから初期セットを生成します。`/doc sync` でプロジェクトの進化に合わせて同期を保ちます。

---

← [ユーザーガイド](index.md)
