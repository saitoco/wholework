[English](../../guide/adapter-guide.md) | 日本語

# Adapter 執筆ガイド

Wholework 向けにプロジェクト固有の capability adapter を作成するためのステップバイステップガイド。

このガイドは **自己完結型** — Claude Code はこのファイルだけを読めば新しい adapter を作成できる。
Wholework のソースリポジトリへのアクセスは不要。

## 概要

Wholework の adapter パターンを使うと、プロジェクト固有の capability — MCP サーバー、
CLI ツール、外部サービス — を Wholework のワークフロー (`/issue`、`/code`、`/verify`) に統合できる。

adapter は統一された contract に従う Markdown ファイル。Wholework は 3 層の優先順位で
adapter を解決するため、Wholework プラグイン自体を変更することなくプロジェクト固有の挙動を追加できる。

---

## 前提条件

### `.wholework.yml` で capability を宣言する

プロジェクトルートに `.wholework.yml` を配置し、利用可能な capability を宣言する。

```yaml
# .wholework.yml
capabilities:
  browser: true               # ブラウザベースの検証が利用可能
  mcp:                        # このプロジェクトで利用可能な MCP ツール
    - my_service_list_items
    - my_service_create_item
```

**`capabilities.browser`** — ブラウザ自動操作ツール (`browser-use` CLI または Playwright MCP) が
利用可能な場合に `true` を設定する。`browser_check` / `browser_screenshot` の verify command を
実行するために必要。

**`capabilities.mcp`** — このプロジェクトセッションで利用可能な MCP ツール名のリスト。
`mcp_call` の verify command に必要。Wholework は宣言済みリストを使って `/issue` で
`mcp_call` の acceptance condition を提案し、`/verify` でそれを実行する。

> `.wholework.yml` が存在しない、または capability が宣言されていない場合、
> Wholework は動的検出 (ToolSearch / `command -v`) にフォールバックする。
> 明示的な宣言により、セッション状態によらず再現可能な挙動が得られる。

**`preview-url-command`** — 関連するが別の仕組み: `scripts/run-review.sh` が
`bash -c` 経由で直接呼び出し `PREVIEW_URL` を解決する、プロジェクトローカルの
*スクリプト* (adapter contract の `.md` ファイルではない)。GitHub deployment を
作らないホスティングプロバイダ (AWS Amplify Hosting 等) 向け。スクリプトは他の
adapter と並べて `.wholework/adapters/` 配下に置く (例:
`.wholework/adapters/resolve-preview-url.sh`) と発見しやすく、`.wholework.yml`
で `preview-url-command: ".wholework/adapters/resolve-preview-url.sh {pr}"` の
ように宣言する。これは下記の 3 層 Adapter 解決を**通らない** — `run-review.sh`
は bash wrapper であり、skill のように adapter contract の `.md` ファイルを
「読んで従う」ことができないため、設定キーに直接スクリプトパスを宣言する形を
取る。完全な契約 (フォールバック挙動・`{pr}` 置換・カバー範囲) は
[`docs/ja/guide/customization.md`](customization.md) の
「`preview-url-command` による `PREVIEW_URL` 解決の自動化」節を参照。

---

## Adapter 解決

Wholework は **3 層の優先順位** で adapter を解決する:

| 優先度 | 層 | パス |
|----------|-------|------|
| 1 | Project-local | `.wholework/adapters/{capability}-adapter.md` |
| 2 | User-global | `~/.wholework/adapters/{capability}-adapter.md` |
| 3 | Bundled default | `${CLAUDE_PLUGIN_ROOT}/modules/{capability}-adapter.md` |

Wholework はこの順序で検索し、**最初に見つかったファイル** を使用する。

- **Project-local** (`.wholework/adapters/`) — プロジェクトごとの上書き。プロジェクトリポジトリに
  コミットされる。MCP サーバーやプロジェクト固有の CLI ツールに使う。
- **User-global** (`~/.wholework/adapters/`) — ユーザーの全プロジェクトに適用される。
  個人的な CLI の好みに使う。
- **Bundled default** — Wholework に同梱される。`browser` と `lighthouse` を標準で
  カバーする。

新しい capability を追加するには、project-local パスに adapter ファイルを作成する:

```
.wholework/
└── adapters/
    └── my-service-adapter.md
```

---

## Adapter Contract テンプレート

すべての adapter はこの contract に従う必要がある。以下のテンプレートをコピーし、
capability 固有の詳細を記入する。

テンプレートには必須の 3 セクションがすべて含まれる:
**Detection**、**Tool-specific Execution**、**Return Result**。

```markdown
# {capability} adapter

## Purpose

{Description of what this adapter does and what capability it provides}

Caller: `modules/verify-executor.md` (via `modules/adapter-resolver.md`)

## Input

The caller provides the following:

- **Command type**: {list of supported verify commands, e.g., `my_service_list`}
- **Arguments**: {arguments per command}

## Processing Steps

### Step 1: Tool Detection

Detect available tools in the following priority order. Use the first tool found.

| Priority | Tool | Detection Method |
|----------|------|-----------------|
| 1 | {Tool A} | Run `command -v tool-a` in Bash; detected if exit code is 0 |
| 2 | {MCP tool} | Use ToolSearch with `select:{mcp_tool_name}`; detected if available |
| 3 | Not detected | None of the above available |

**When not detected**: Return UNCERTAIN with a detailed explanation.

### Step 2: Tool-specific Execution

Execute according to the detected tool.

#### {Tool A}

**Execution steps for `{command_type}`:**

1. Run the initialization or authentication step
2. Invoke the tool with the provided arguments
3. Inspect the output and determine PASS / FAIL / UNCERTAIN

#### {MCP tool}

**Execution steps for `{command_type}`:**

1. Call `{mcp_tool_name}` with the provided arguments
2. Inspect the response and determine PASS / FAIL / UNCERTAIN

### Step 3: Return Result

Return the result as one of:

- **PASS**: Verification condition satisfied
- **FAIL**: Verification condition not satisfied (include detailed reason)
- **UNCERTAIN**: Cannot determine automatically (tool not found, execution error, etc.)

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: Description of the verification result

## Reference Marker

The caller that has Read this file must include the following marker in its final output:

`[ref:{capability}-adapter:{random-4-char-alphanum}]`
```

---

## ワークフロー統合の例

このセクションでは、MCP ベースの請求書サービスを具体例として使い、`mcp_call` verify command
を使う acceptance criteria の設計方法を示す。

### シナリオ

あるプロジェクトが `invoice_list` と `invoice_create` ツールを持つ invoice MCP サーバーを
統合している。`.wholework.yml` は以下を宣言する:

```yaml
capabilities:
  mcp:
    - invoice_list
    - invoice_create
```

### Issue 本文の acceptance criteria

`/issue` が宣言済みの MCP ツールを検出すると、acceptance criteria セクションに
`mcp_call` の条件を提案する。例:

```markdown
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: mcp_call "invoice_list" {} "items" --> `invoice_list` returns a list with an `items` field
- [ ] <!-- verify: file_exists "src/invoice-handler.ts" --> Invoice handler module is created

### Post-merge

- [ ] <!-- verify: mcp_call "invoice_create" {"title": "Test"} "id" --> `invoice_create` returns a response with an `id` field
```

**`mcp_call` の構文:**
```
mcp_call "{tool_name}" {json_args} "{expected_field_or_string}"
```

- `tool_name` — `.wholework.yml` で宣言された MCP ツール名
- `json_args` — ツールに渡す JSON オブジェクト (引数なしの場合は `{}`)
- `expected_field_or_string` — レスポンスに含まれるべきフィールド名または文字列

### Adapter の作成

`/verify` がこれらの条件を実行できるようにするには、project-local adapter を作成する:

**`.wholework/adapters/invoice-adapter.md`** — 上記の contract テンプレートに従う。

Step 1 (Tool Detection) では、ToolSearch 経由で MCP ツールを確認する:
```markdown
| 1 | invoice MCP | ToolSearch `select:invoice_list,invoice_create`; detected if both are available |
```

Step 2 (Execution) では、`mcp_call "invoice_list" {} "items"` を以下のように変換する:
- `{}` を引数に `invoice_list` MCP ツールを呼び出す
- レスポンスの `items` フィールドを確認 → 存在すれば PASS、なければ FAIL

---

## Claude Code プロンプトテンプレート

以下のプロンプトを使って、Claude Code にプロジェクト向けの adapter 作成を依頼する。
プレースホルダーを置き換えて、プロンプトを Claude Code に貼り付ける。

### プロンプト

```
Please create a Wholework adapter for the {SERVICE_NAME} capability in this project.

Read the adapter authoring guide first:
https://raw.githubusercontent.com/saitoco/wholework/main/docs/guide/adapter-guide.md

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

### 記入済みの例 (invoice MCP サーバー)

```
Please create a Wholework adapter for the invoice service in this project.

Read the adapter authoring guide first:
https://raw.githubusercontent.com/saitoco/wholework/main/docs/guide/adapter-guide.md

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

## 参考資料

以下のドキュメントは、adapter パターンと環境適応アーキテクチャの背景をより深く理解するための
資料。adapter を作成するために **必須ではない** — このガイドは自己完結型 — が、
内部構造を理解したい場合や、同梱の adapter を拡張したい場合に有用。

- **`docs/environment-adaptation.md`** (Wholework repo) — 4 層の環境適応アーキテクチャ
  (Declaration → Detection → Disclosure → Execution) の完全な説明。`detect-config-markers.md`、
  `--when` モディファイア、層間の関係図をカバーする。

- **`modules/browser-adapter.md`** (Wholework repo) — 同梱 adapter のリファレンス実装。
  マルチツール検出 (browser-use CLI vs. Playwright MCP)、コマンド変換テーブル、
  Basic 認証の扱い、セキュリティ制約を示す。自分の adapter を書く際の具体例として利用できる。
