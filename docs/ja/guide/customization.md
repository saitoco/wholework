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

# オプション capability
capabilities:
  browser: true             # Playwright ベースの verify command を有効化
```

すべてのキーはオプションです。`.wholework.yml` が存在しない場合、すべての設定はデフォルトで動作します。

### Available Keys

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

カスタム adapter や verify command ハンドラの書き方詳細は [docs/ja/adapter-guide.md](../adapter-guide.md) を参照してください。

## Steering Documents

Steering Documents（`docs/product.md`、`docs/tech.md`、`docs/structure.md`）は Wholework に深いプロジェクトコンテキストを与える主要手段です。スキルは存在すれば自動的に読み込みます。

`/doc init` でコードベースから初期セットを生成します。`/doc sync` でプロジェクトの進化に合わせて同期を保ちます。
