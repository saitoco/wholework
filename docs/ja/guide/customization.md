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

# watchdog タイムアウト（デフォルト: 1800 秒）
# 遅い repo、Size L 以上のタスク、または低速マシンでは増やすことを推奨
watchdog-timeout-seconds: 3600

# XL 並列 sub-issue 実行時の patch lock タイムアウト（デフォルト: 3600 秒）
patch-lock-timeout: 3600

# /auto サブプロセスの permission mode（デフォルト: bypass）
# "auto" は --permission-mode auto を allow rules テンプレートと共に使用（docs/guide/auto-mode-template.json 参照）
# "bypass" は --dangerously-skip-permissions を使用（後方互換）
permission-mode: auto

# verify reopen ループの最大試行回数（default: 3、max: 20）
# N 回 FAIL した時点で reopen を停止し、Issue を phase/verify に留めて人間の判断を促す
verify-max-iterations: 3

# オプション capability
capabilities:
  browser: true             # Playwright ベースの verify command を有効化
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
| `steering-hint` | boolean | `true` | steering docs が欠如している場合に `/doc init` ヒントを表示する |
| `production-url` | string | `""` | ブラウザベース verify command 用の本番 URL |
| `spec-path` | string | `docs/spec` | spec の保存先 |
| `steering-docs-path` | string | `docs` | steering document の配置先 |
| `capabilities.browser` | boolean | `false` | Playwright ベースの verify command を有効化する |
| `capabilities.mcp` | list | `[]` | スキルから利用できる MCP ツール名 |
| `capabilities.{name}` | boolean | `false` | 動的 capability マッピング（例: `capabilities.invoice-api: true`） |
| `watchdog-timeout-seconds` | integer | `1800` | watchdog が silent な `claude -p` プロセスを kill するまでのタイムアウト秒数。遅い repo、Size L 以上のタスク、低速マシンでは増やす（例: `3600`）。0 以下の値はデフォルトにフォールバック。 |
| `patch-lock-timeout` | integer | `3600` | patch lock 取得タイムアウト秒数。XL 並列 sub-issue がロック待ちでタイムアウトする場合に増やす。0 以下または非数値の場合は `3600` にフォールバック。 |
| `permission-mode` | string | `"bypass"` | `/auto` サブプロセスの permission mode。`auto` は `--permission-mode auto` を allow rules テンプレートと共に有効化（`docs/guide/auto-mode-template.json` 参照）; `bypass` は `--dangerously-skip-permissions` を使用。 |
| `verify-max-iterations` | integer | `3` | verify-reopen ループの最大試行回数。N 回 FAIL した時点で停止し、Issue を `phase/verify` に留めて人間の判断を促す。0 以下、20 超、または非数値の場合は `3` にフォールバック。 |

実装の詳細や YAML パースルールを含む完全なリファレンスは [`modules/detect-config-markers.md`](../../../modules/detect-config-markers.md) を参照してください。

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
