# 環境適応アーキテクチャ

## 概要

異なるツール構成を持つ環境間で同じ Skill 定義を動作させるためのアーキテクチャです。4 つのレイヤーで構成されます。

```
Layer 1: Declaration    .wholework.yml で "何が利用可能か" を静的に宣言
Layer 2: Detection      宣言またはセッション内検出によって環境ケイパビリティを判定
Layer 3: Disclosure     Core/Domain 分離 — 必要なロジックのみを読み込む
Layer 4: Execution      safe/full モード分岐 + アダプタ委譲
```

## Layer 1: 宣言（`.wholework.yml`）

プロジェクトルートに配置する YAML ファイル。プロジェクトで利用可能なケイパビリティとツールを宣言します。

```yaml
# .wholework.yml
copilot-review: true          # GitHub Copilot レビュー連携
coderabbit-review: true       # CodeRabbit AI レビュー連携
opportunistic-verify: true    # 日和見検証（post-merge 条件の自動実行）
skill-proposals: true         # Skill 提案機能
capabilities:
  browser: true               # ブラウザベース検証が利用可能
  mcp:                        # 利用可能な MCP ツール
    - mf_list_quotes
    - mf_list_invoices
```

設計根拠: MCP セッションの可用性やツールのインストール状態は実行時に変動する可能性があります。静的な宣言により再現性のある挙動を保証します。

各設定フィールドの詳細は `modules/detect-config-markers.md` のマーカー定義表を参照してください。

## Layer 2: 検出（detect-config-markers + ToolSearch + CLI 検出）

Layer 1 の宣言を読み込み、不足している情報をセッション内で動的に検出します。

### 検出メカニズム

| メカニズム | 検出対象 | 使用元 |
|------------|----------|--------|
| `detect-config-markers.md` | `.wholework.yml` の各フラグ → 環境変数 | `/review`、`/verify`、`/issue` |
| `ToolSearch` | セッション内の MCP ツール可用性 | `/issue`（宣言なし時）、`verify-executor`（`mcp_call` 実行時） |
| `command -v` | CLI ツールの可用性 | `browser-adapter`（browser-use CLI）、`lighthouse-adapter`（lighthouse） |

### MCP ツール検出: 宣言優先フォールバック

`/issue` が `mcp_call` 受入チェックを提案する際に適用:

```
1. MCP_TOOLS が非空（宣言あり）       → 宣言を信頼、ToolSearch をスキップ
2. MCP_TOOLS が空（宣言なし）         → ToolSearch による動的検出
3. いずれでも検出されない             → mcp_call hint を提案しない
```

## Layer 3: 開示制御（Core/Domain 分離）

SKILL.md のコアを軽量に保ち、環境依存ロジック（Domain）を条件付きで読み込みます。

### 判断基準

「このロジックは対象ツールやプロジェクト種別を使用しないプロジェクトでも必要か？」→ No なら Domain ファイルに抽出します。

### 抽出パターン

| パターン | 条件チェック | 例 |
|----------|--------------|---|
| マーカー検出 | `.wholework.yml` の値 | `external-review-phase.md`（`copilot-review: true` のときに Read） |
| ファイル存在 | 特定ファイルの存在 | `skill-dev-recheck.md`（`validate-skill-syntax.py` が存在するときに Read） |

### Domain ファイル（網羅的）

| ファイル | Skill | 読み込み条件 | Domain |
|----------|-------|--------------|--------|
| `skills/spec/figma-design-phase.md` | `/spec` | UI デザイン要件の自動検出 | UI/デザイン |
| `skills/spec/codebase-search.md` | `/spec` | `SPEC_DEPTH=full` | 深度ベースのコードベース調査 |
| `skills/spec/external-spec.md` | `/spec` | 外部仕様依存あり | 外部ドキュメント参照 |
| `skills/review/external-review-phase.md` | `/review` | `copilot-review`、`claude-code-review`、または `coderabbit-review` が true | 外部レビューツール連携 |
| `skills/review/skill-dev-recheck.md` | `/review` | `validate-skill-syntax.py` が存在 | Skill 開発プロジェクト固有 |
| `skills/issue/spec-test-guidelines.md` | `/issue` | `validate-skill-syntax.py` が存在 | Skill 開発テスト推奨 |
| `skills/verify/browser-verify-phase.md` | `/verify` | `HAS_BROWSER_CAPABILITY=true` | ブラウザ検証 |
| `skills/issue/mcp-call-guidelines.md` | `/issue` | `MCP_TOOLS` が非空 | MCP ツール検出 |

## Layer 4: 実行（verify-executor + アダプタ）

検証コマンドを実行します。ツール固有の処理はアダプタに委譲されます。

### safe/full モード分岐

| モード | 使用元 | 特徴 |
|--------|--------|------|
| `safe` | `/review` | 外部コマンド実行を制限、CI 参照にフォールバック |
| `full` | `/verify` | すべてのコマンドが実行可能 |

### 環境別コマンドテーブル

| 検証コマンド | safe モード | full モード |
|--------------|-------------|-------------|
| `file_exists`、`grep`、`section_contains` など | 実行可能 | 実行可能 |
| `http_status`、`html_check`、`api_check` | URL セキュリティチェック付きで実行可能 | 制限なし |
| `command`、`build_success` | UNCERTAIN（CI フォールバック） | 実行 |
| `lighthouse_check` | UNCERTAIN | adapter-resolver 経由で `lighthouse-adapter.md` に委譲、CLI 検出はアダプタ内部 |
| `browser_check`、`browser_screenshot` | UNCERTAIN | ケイパビリティ宣言チェック（`HAS_BROWSER_CAPABILITY`）後、adapter-resolver 経由で委譲、未宣言なら UNCERTAIN |
| `mcp_call` | UNCERTAIN | ToolSearch + read-only 制限 |

### アダプタパターン

アダプタはケイパビリティ（例: `browser`）をカプセル化します。3 層の解決順序（`modules/adapter-resolver.md` 参照）でツール固有の実装を選択します:

```
1. .wholework/adapters/{capability}-adapter.md   （project-local）
2. ~/.wholework/adapters/{capability}-adapter.md  （user-global）
3. ${CLAUDE_PLUGIN_ROOT}/modules/{capability}-adapter.md      （bundled default）
```

アダプタは 3 ステップで動作します: 検出 → コマンド変換 → 実行委譲。

### アダプタコントラクトのテンプレート

アダプタは統一されたコントラクトに従います。ユーザはこのテンプレートに従い、上記の project-local または user-global パスに配置することでカスタムアダプタを作成できます。

リファレンス実装: `modules/browser-adapter.md`。新しいアダプタを作成する際はこのファイルをガイドとして使用してください。

#### 必須セクション

**1. 検出手順**

利用可能なツールを自動検出する手順を記述します。複数ツールをサポートする場合は優先度表に列挙します。

```markdown
### Step N: ツール検出

優先度順に利用可能なツールを検出します。最初に見つかったツールを使用します。

| 優先度 | ツール | 検出方法 |
|--------|--------|----------|
| 1      | Tool A | `command -v tool-a` で検出 |
| 2      | Tool B | ToolSearch で MCP ツールを検索、必要ツールがすべて利用可能なときのみ検出 |
| 3      | なし   | 上記いずれも利用不可 |

**未検出時**: UNCERTAIN を返し、検出失敗の理由を詳細に説明します。
```

**2. コマンド変換表**

受入チェック表記からツール固有コマンドへのマッピングを記述します。検出ツールごとにサブセクションを作成し、各コマンドの実行をステップ番号で記述します。

```markdown
### Step N: ツール固有実行

#### Tool A

**`command_x` の実行ステップ:**

1. Tool A の初期化コマンドを実行
2. 対象リソースにアクセス
3. 条件を検証
4. セッションをクローズ

#### Tool B

**`command_x` の実行ステップ:**

1. ...
```

**3. フォールバック**

ツールが検出されなかった場合の振る舞いを定義します。原則として UNCERTAIN を返し、ユーザを手動検証に誘導します。

```markdown
### Step N: 結果返却

結果を以下のいずれかとして返します:

- **PASS**: 検証条件を満たす
- **FAIL**: 検証条件を満たさない（理由を詳細に含める）
- **UNCERTAIN**: 自動判定不可（ツール未検出、実行エラーなど — 理由を詳細に含める）
```

#### 任意セクション

**セキュリティ制約** — ツール固有のセキュリティ制約（URL フィルタリング、認証情報のマスキング、SSRF 防止など）を記述します。

**セットアップ手順** — 初回利用時のインストールガイドや前提条件を記述します。

#### ファイル構造テンプレート

```markdown
# {capability} adapter

## Purpose

{アダプタの役割と提供する抽象の説明}

Caller: {参照元モジュール/Skill}

## Input

呼び出し元が以下を提供:

- **Command type**: {サポートコマンドの一覧}
- **Arguments**: {コマンドごとの引数}

## Processing Steps

### Step 1: {Security Check（任意）}

{セキュリティ制約の検証手順}

### Step 2: Tool Detection

| Priority | Tool        | Detection Method |
|----------|-------------|-----------------|
| 1        | {Tool A}    | {検出方法} |
| 2        | None        | 上記いずれも利用不可 |

**When not detected**: Return UNCERTAIN.

### Step 3: Tool-specific Execution

#### {Tool A}

{コマンド変換表と実行ステップ}

### Step 4: Return Result

- **PASS**: 検証条件を満たす
- **FAIL**: 検証条件を満たさない（理由を詳細に含める）
- **UNCERTAIN**: 自動判定不可（理由を詳細に含める）

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: 検証結果の説明

## Reference Marker

このファイルを Read した呼び出し元は、最終出力に次のマーカーを含めること:

`[ref:{adapter-name}:{random-4-char-alphanum}]`
```

### `--when` 修飾子（計画中、未実装）

受入条件内の個別検証項目に環境ゲートを設定するためのメカニズムです。

```html
<!-- verify: browser_check "url" "h1" --when="command -v browser-use" -->
```

- 条件成立（exit 0）→ メインコマンドを実行
- 条件不成立（exit != 0）→ SKIPPED（無視、手動チェック不要）

Layer 1–3 が "Skill のどの部分を読み込むか" を制御するのに対し、`--when` は受入条件内の個別検証項目レベルで環境ゲートを提供します。

## レイヤー間の関係

```
.wholework.yml (Layer 1)
  │
  ├─→ copilot-review ────→ /review が external-review-phase.md を Read するか (Layer 3)
  ├─→ coderabbit-review ─→ /review が external-review-phase.md を Read するか (Layer 3)
  ├─→ capabilities.mcp ──→ /issue が mcp_call hint を提案するか (Layer 2)
  ├─→ capabilities.browser → アダプタが browser を解決するか (Layer 4)
  └─→ production-url ───→ verify-executor が {{base_url}} を解決するか (Layer 4)

ToolSearch (Layer 2) ─→ 動的な MCP ツール検出（宣言なし時のフォールバック）
command -v (Layer 2) ─→ CLI ツール可用性チェック（アダプタ内、--when 内）
--when (Layer 4) ────→ 受入条件ごとの環境ゲート（計画中）
```

## 拡張ガイド

### 新しい capability の追加

1. `modules/{capability}-adapter.md` を作成する（`modules/browser-adapter.md` を参照）
2. `modules/adapter-resolver.md` の説明に capability を追加する
3. `verify-executor.md` の変換表に新しいコマンドを追加し、adapter-resolver 経由で委譲する
4. `modules/detect-config-markers.md` のマーカー表に `capabilities.{name}` を追加する
5. `docs/structure.md` の Key Files テーブルに追加する

### 新しい Domain ロジックの追加

1. `skills/{skill-name}/{domain}-phase.md` を作成する
   - このファイルが参照するモジュールのフルパスをファイル先頭に列挙する（例: `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md`）。省略形（例: `detect-config-markers.md` のみ）は不可。フルパスを先頭に列挙することで、呼び出し側が読み込み前に参照モジュールを把握できます。
2. SKILL.md に条件付きの Read 指示を追加する（マーカー検出パターンまたはファイル存在パターン）
3. `docs/structure.md` の Domain Files テーブルに追加する
