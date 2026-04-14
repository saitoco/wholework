[English](../adapter-guide.md) | 日本語

# Adapter 執筆ガイド

Wholework 向けにプロジェクト固有の capability adapter を作成するためのステップバイステップガイド。

本ガイドは **自己完結型** です。Claude Code はこのファイルだけを読んで新しい adapter を作成できます。Wholework のソースリポジトリへのアクセスは不要です。

## 概要

Wholework の adapter パターンは、プロジェクト固有の capability — MCP server、CLI ツール、外部サービス — を Wholework のワークフロー（`/issue`、`/code`、`/verify`）へ統合するための仕組みです。

Adapter は統一された contract に従う Markdown ファイルです。Wholework は 3 層の優先順位で adapter を解決するため、Wholework plugin 本体を変更せずにプロジェクト固有の振る舞いを追加できます。

---

## 前提

### `.wholework.yml` で capabilities を宣言

プロジェクトルートに `.wholework.yml` を置き、利用可能な capability を宣言します。

```yaml
# .wholework.yml
capabilities:
  browser: true               # ブラウザベースの検証が利用可能
  mcp:                        # このプロジェクトセッションで利用可能な MCP ツール
    - my_service_list_items
    - my_service_create_item
```

**`capabilities.browser`** — browser 自動化ツール（`browser-use` CLI または Playwright MCP）が利用可能な場合に `true` を設定。`browser_check` / `browser_screenshot` verify command の実行に必要です。

**`capabilities.mcp`** — このプロジェクトセッションで利用可能な MCP ツール名のリスト。`mcp_call` verify command に必要です。Wholework は宣言済みリストを使って `/issue` で `mcp_call` 受入条件を提案し、`/verify` で実行します。

> `.wholework.yml` が存在しない、または capability が宣言されていない場合、Wholework は動的検出（ToolSearch / `command -v`）にフォールバックします。明示宣言はセッション状態に依存しない再現可能な挙動を提供します。

---

## Adapter 解決

Wholework は **3 層の優先順位** で adapter を解決します:

| 優先度 | レイヤ | パス |
|----------|-------|------|
| 1 | プロジェクトローカル | `.wholework/adapters/{capability}-adapter.md` |
| 2 | ユーザーグローバル | `~/.wholework/adapters/{capability}-adapter.md` |
| 3 | バンドルデフォルト | `${CLAUDE_PLUGIN_ROOT}/modules/{capability}-adapter.md` |

Wholework はこの順序で検索し、**最初に見つかったファイル** を使います。

- **プロジェクトローカル**（`.wholework/adapters/`） — プロジェクト単位のオーバーライド。プロジェクトリポジトリに commit する。MCP server やプロジェクト固有の CLI ツールに使う
- **ユーザーグローバル**（`~/.wholework/adapters/`） — ユーザーの全プロジェクトに適用。個人の CLI 設定に使う
- **バンドルデフォルト** — Wholework に同梱。`browser` と `lighthouse` を out-of-the-box でカバー

新しい capability を追加するには、プロジェクトローカルのパスに adapter ファイルを作成します:

```
.wholework/
└── adapters/
    └── my-service-adapter.md
```

---

## Adapter Contract テンプレート

すべての adapter はこの contract に従わなければなりません。以下のテンプレートをコピーし、capability 固有の詳細を埋めてください。

テンプレートには 3 つの必須セクションがすべて含まれます:
**Detection**、**Tool-specific Execution**、**Return Result**。

```markdown
# {capability} adapter

## Purpose

{この adapter が何をするか、どの capability を提供するかの説明}

Caller: `modules/verify-executor.md` (via `modules/adapter-resolver.md`)

## Input

呼び出し側は以下を提供します:

- **Command type**: {サポートする verify command のリスト、例: `my_service_list`}
- **Arguments**: {コマンドごとの引数}

## Processing Steps

### Step 1: Tool Detection

以下の優先順位で利用可能なツールを検出します。最初に見つかったツールを使います。

| 優先度 | ツール | 検出方法 |
|----------|------|-----------------|
| 1 | {Tool A} | Bash で `command -v tool-a` を実行、exit code が 0 なら検出 |
| 2 | {MCP tool} | ToolSearch `select:{mcp_tool_name}` で検出、利用可能なら検出 |
| 3 | 未検出 | 上記のいずれも利用不可 |

**未検出の場合**: 詳細説明とともに UNCERTAIN を返す。

### Step 2: Tool-specific Execution

検出したツールに応じて実行します。

#### {Tool A}

**`{command_type}` の実行手順:**

1. 初期化または認証ステップを実行
2. 提供された引数でツールを呼び出す
3. 出力を検査し PASS / FAIL / UNCERTAIN を判定

#### {MCP tool}

**`{command_type}` の実行手順:**

1. 提供された引数で `{mcp_tool_name}` を呼び出す
2. レスポンスを検査し PASS / FAIL / UNCERTAIN を判定

### Step 3: Return Result

結果を以下のいずれかで返します:

- **PASS**: 検証条件を満たした
- **FAIL**: 検証条件を満たさなかった（詳細な理由を含める）
- **UNCERTAIN**: 自動判定不可（ツール未発見、実行エラー、など）

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: 検証結果の説明

## Reference Marker

このファイルを Read した呼び出し側は最終出力に以下のマーカーを含めなければなりません:

`[ref:{capability}-adapter:{random-4-char-alphanum}]`
```

---

## ワークフロー統合例

本セクションでは MCP ベースの invoice サービスを具体例に、`mcp_call` verify command を使う受入条件の設計方法を示します。

### シナリオ

あるプロジェクトが `invoice_list` と `invoice_create` というツールを持つ invoice MCP server を統合します。`.wholework.yml` は以下を宣言します:

```yaml
capabilities:
  mcp:
    - invoice_list
    - invoice_create
```

### Issue 本文の受入条件

`/issue` は宣言された MCP ツールを検出すると、受入条件セクションに `mcp_call` 条件を提案します。例:

```markdown
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: mcp_call "invoice_list" {} "items" --> `invoice_list` が `items` フィールドを含むリストを返す
- [ ] <!-- verify: file_exists "src/invoice-handler.ts" --> Invoice handler モジュールが作成されている

### Post-merge

- [ ] <!-- verify: mcp_call "invoice_create" {"title": "Test"} "id" --> `invoice_create` が `id` フィールドを含むレスポンスを返す
```

**`mcp_call` の構文:**
```
mcp_call "{tool_name}" {json_args} "{expected_field_or_string}"
```

- `tool_name` — `.wholework.yml` で宣言された MCP ツール名
- `json_args` — ツールに渡す JSON オブジェクト（引数なしは `{}`）
- `expected_field_or_string` — レスポンスに現れるべきフィールド名または文字列

### Adapter の作成

`/verify` がこれらの条件を実行できるようにするため、プロジェクトローカル adapter を作成します:

**`.wholework/adapters/invoice-adapter.md`** — 上記の contract テンプレートに従う。

Step 1（Tool Detection）では ToolSearch で MCP ツールを確認します:
```markdown
| 1 | invoice MCP | ToolSearch `select:invoice_list,invoice_create`、両方とも利用可能なら検出 |
```

Step 2（Execution）では `mcp_call "invoice_list" {} "items"` を以下に変換します:
- `invoice_list` MCP ツールを `{}` で呼び出す
- レスポンスに `items` フィールドがあれば PASS、なければ FAIL

---

## Claude Code プロンプトテンプレート

以下のプロンプトを使って Claude Code にプロジェクト向けの adapter 作成を依頼できます。プレースホルダを置換して Claude Code に貼り付けてください。

### プロンプト

```
Please create a Wholework adapter for the {SERVICE_NAME} capability in this project.

Read the adapter authoring guide first:
https://raw.githubusercontent.com/saitoco/wholework/main/docs/adapter-guide.md

Then create `.wholework/adapters/{capability}-adapter.md` following the contract template
in the guide. The adapter should support the following verify commands:

- `{command_1}` — {description of what it verifies}
- `{command_2}` — {description of what it verifies}

Available tools for this capability:
- MCP tool: `{mcp_tool_name}` (or CLI: `{cli_tool_name}`)

Also update `.wholework.yml` to declare the capability:

capabilities:
  {capability_key}: true   # or list MCP tool names

After creating the adapter, show me an example acceptance condition I can add
to an Issue for pre-merge verification.
```

### 埋めた例（invoice MCP server）

```
Please create a Wholework adapter for the invoice service in this project.

Read the adapter authoring guide first:
https://raw.githubusercontent.com/saitoco/wholework/main/docs/adapter-guide.md

Then create `.wholework/adapters/invoice-adapter.md` following the contract template
in the guide. The adapter should support the following verify commands:

- `mcp_call "invoice_list"` — verifies the invoice list API returns a valid response
- `mcp_call "invoice_create"` — verifies invoice creation returns an id field

Available tools for this capability:
- MCP tools: `invoice_list`, `invoice_create`

Also update `.wholework.yml` to declare the capability:

capabilities:
  mcp:
    - invoice_list
    - invoice_create

After creating the adapter, show me an example acceptance condition I can add
to an Issue for pre-merge verification.
```

---

## さらに深く読む

以下のドキュメントは adapter パターンと環境適応アーキテクチャの背景をより深く説明します。adapter 作成に **必須ではありません** — 本ガイドは自己完結型です — が、内部構造を理解したい、あるいはバンドル adapter を拡張したい場合に役立ちます。

- **`docs/environment-adaptation.md`**（Wholework リポジトリ） — 4 層環境適応アーキテクチャ（Declaration → Detection → Disclosure → Execution）の完全な説明。`detect-config-markers.md`、`--when` 修飾子、レイヤ間関係図を扱う
- **`modules/browser-adapter.md`**（Wholework リポジトリ） — バンドル adapter のリファレンス実装。マルチツール検出（browser-use CLI vs Playwright MCP）、コマンド変換表、Basic 認証処理、セキュリティ制約を示す。自前の adapter を書く際の具体例として使う
