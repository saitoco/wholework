[English](../environment-adaptation.md) | 日本語

# 環境適応アーキテクチャ

## 概要

同一のスキル定義を、ツール構成の異なる環境で動作させるためのアーキテクチャ。4 層で構成されます。

```
Layer 1: Declaration    .wholework.yml で「何が利用可能か」を静的に定義
Layer 2: Detection      宣言またはセッション内検出から環境の capability を判定
Layer 3: Disclosure     Core/Domain 分離 — 必要なロジックだけを読み込む
Layer 4: Execution      safe/full モード分岐 + adapter への委譲
```

## Layer 1: Declaration（`.wholework.yml`）

プロジェクトルートに置く YAML ファイル。プロジェクトで利用可能な capability とツールを宣言します。

```yaml
# .wholework.yml
copilot-review: true          # GitHub Copilot review 連携
coderabbit-review: true       # CodeRabbit AI review 連携
opportunistic-verify: true    # Opportunistic 検証（マージ後条件の自動実行）
skill-proposals: true         # スキル提案機能
spec-path: custom/specs       # Spec ファイル保存先（デフォルト: docs/spec）
steering-docs-path: custom/docs  # Steering Documents ディレクトリ（デフォルト: docs）
capabilities:
  browser: true               # ブラウザベースの検証が利用可能
  mcp:                        # 利用可能な MCP ツール
    - mf_list_quotes
    - mf_list_invoices
  invoice-api: true           # カスタム capability → HAS_INVOICE_API_CAPABILITY=true
```

設計意図: MCP セッションの可用性やツールインストール状況は実行時に変動しうる。静的宣言により再現可能な挙動を保証する。

各設定フィールドの詳細は `modules/detect-config-markers.md` のマーカー定義表を参照してください。

## Layer 2: Detection（detect-config-markers + ToolSearch + CLI 検出）

Layer 1 の宣言を読み、欠けている情報はセッション内で動的検出します。

### 検出メカニズム

| メカニズム | 検出対象 | 使用箇所 |
|-----------|----------------|---------|
| `detect-config-markers.md`（固定マッピング） | `.wholework.yml` の既知フラグ → 環境変数 | `/review`、`/verify`、`/issue` |
| `detect-config-markers.md`（動的マッピング） | 任意の `capabilities.{name}: true` → `HAS_{UPPERCASE_NAME}_CAPABILITY` 変数 | `detect-config-markers.md` を Read する全スキル |
| `ToolSearch` | セッション内の MCP ツール可用性 | `/issue`（宣言なしの場合）、`verify-executor`（`mcp_call` 実行時） |
| `command -v` | CLI ツール可用性 | `browser-adapter`（browser-use CLI）、`lighthouse-adapter`（lighthouse） |

### MCP ツール検出: 宣言ファースト + フォールバック

`/issue` が `mcp_call` verify command を提案する際に適用:

```
1. MCP_TOOLS が空でない（宣言あり）    → 宣言を信頼、ToolSearch をスキップ
2. MCP_TOOLS が空（宣言なし）         → ToolSearch による動的検出
3. どちらも検出できず                 → mcp_call ヒントを提案しない
```

## Layer 3: Disclosure Control（Core/Domain 分離）

SKILL.md のコアを軽量に保ち、環境依存のロジック（Domain）は条件付きで読み込みます。

### 判断基準

「このロジックは、対象のツールやプロジェクト種別を使わないプロジェクトでも必要か？」→ No なら Domain ファイルとして切り出す。

### 切り出しパターン

| パターン | 条件チェック | 例 |
|---------|----------------|---------|
| Marker 検出 | `.wholework.yml` の値 | `external-review-phase.md`（`copilot-review: true` で Read） |
| ファイル存在 | 特定ファイルの存在 | `skill-dev-recheck.md`（`validate-skill-syntax.py` があれば Read） |
| ディレクトリスキャン | `.wholework/domains/{skill}/` を Glob | プロジェクトローカル domain ファイル（存在すればロード） |

### Domain ファイル（網羅的）

| ファイル | スキル | ロード条件 | Domain |
|------|-------|---------------|--------|
| `skills/spec/figma-design-phase.md` | `/spec` | UI 設計要件を自動検出 | UI/デザイン |
| `skills/spec/codebase-search.md` | `/spec` | `SPEC_DEPTH=full` | 深度ベースのコードベース調査 |
| `skills/spec/external-spec.md` | `/spec` | 外部 spec 依存が存在 | 外部ドキュメント参照 |
| `skills/review/external-review-phase.md` | `/review` | `copilot-review`/`claude-code-review`/`coderabbit-review` のいずれかが true | 外部レビューツール連携 |
| `skills/review/skill-dev-recheck.md` | `/review` | `validate-skill-syntax.py` が存在 | スキル開発プロジェクト固有 |
| `skills/issue/spec-test-guidelines.md` | `/issue` | `validate-skill-syntax.py` が存在 | スキル開発テスト推奨事項 |
| `skills/verify/browser-verify-phase.md` | `/verify` | `HAS_BROWSER_CAPABILITY=true` | ブラウザ検証 |
| `skills/issue/mcp-call-guidelines.md` | `/issue` | `MCP_TOOLS` が空でない | MCP ツール検出 |
| `skills/doc/translate-phase.md` | `/doc` | `translate` サブコマンド | 翻訳生成 |
| `.wholework/domains/{skill}/*.md` | `/spec`、`/code`、`/review` | ディレクトリスキャン（`.wholework/domains/{skill}/` にファイル存在） | プロジェクトローカル（ユーザー定義） |

**プロジェクトローカル Domain ファイル** はディレクトリスキャンで発見されます。スキル起動時に `domain-loader` モジュールが `.wholework/domains/{skill}/*.md` を Glob し、見つかったファイルをアルファベット順にすべて読み込みます。marker 検出やファイル存在条件を使うバンドル Domain ファイルと異なり、プロジェクトローカル Domain ファイルは存在すれば無条件でロードされます — ディレクトリに `.md` ファイルを置くだけで有効化されます。この仕組みは `modules/domain-loader.md` で実装され、`/spec`、`/code`、`/review` スキルから呼び出されます。

## Layer 4: Execution（verify-executor + adapter）

検証コマンドを実行します。ツール固有の処理は adapter へ委譲します。

### safe/full モード分岐

| モード | 使用箇所 | 特徴 |
|------|---------|----------------|
| `safe` | `/review` | 外部コマンド実行を制限、CI 参照にフォールバック |
| `full` | `/verify` | 全コマンド実行可能 |

### 環境別コマンド対応表

| 検証コマンド | safe モード | full モード |
|---------------------|-----------|-----------|
| `file_exists`、`grep`、`section_contains` など | 実行可能 | 実行可能 |
| `http_status`、`html_check`、`api_check` | URL セキュリティチェックで実行可能 | 制限なし |
| `command`、`build_success` | UNCERTAIN（CI フォールバック） | 実行 |
| `lighthouse_check` | UNCERTAIN | adapter-resolver 経由で `lighthouse-adapter.md` に委譲、CLI 検出は adapter 内 |
| `browser_check`、`browser_screenshot` | UNCERTAIN | capability 宣言チェック（`HAS_BROWSER_CAPABILITY`）後に adapter-resolver 経由で委譲、未宣言なら UNCERTAIN |
| `mcp_call` | UNCERTAIN | ToolSearch + read-only 制約 |

### Adapter パターン

Adapter は capability（例: `browser`）をカプセル化します。3 層の解決順序でツール固有の実装を選択します（`modules/adapter-resolver.md` 参照）:

```
1. .wholework/adapters/{capability}-adapter.md   (プロジェクトローカル)
2. ~/.wholework/adapters/{capability}-adapter.md  (ユーザーグローバル)
3. ${CLAUDE_PLUGIN_ROOT}/modules/{capability}-adapter.md      (バンドルデフォルト)
```

Adapter は 3 ステップで動作します: 検出 → コマンド変換 → 実行委譲。

#### Adapter パターン適用要件

Adapter は複数の実装選択肢を抽象化する必要がある場合に価値があります — 例えば `browser`（browser-use CLI vs Playwright MCP）や `lighthouse`（CLI 検出）では、ツール選択、コマンド変換、フォールバック分岐が必要です。

#### なぜ `mcp_call` は adapter を使わないのか

`mcp_call` は ToolSearch を直接使い、adapter レイヤを迂回します。理由: Claude セッション内での MCP ツール検出と呼び出しのメカニズムは ToolSearch ただ一つです。`browser` や `lighthouse` と異なり、複数実装間の選択肢がないため、adapter レイヤを追加しても機能的利益なしに複雑さが増えるだけです。

#### 将来の拡張方針

将来、前処理/後処理のカスタマイズが必要になった場合（例: 引数変換、結果正規化）、adapter ではなく hook 機構（例: `.wholework/hooks/mcp-pre.sh`）として追加すべきです。これは現行実装の範囲外です。

### カスタム verify command ハンドラ

プロジェクトローカルなカスタム検証コマンドを追加する機構。`.wholework/verify-commands/{name}.md` に Markdown ハンドラファイルを配置すると、`{name}` という名のカスタム verify command が登録されます。

#### 宣言パス

```
.wholework/verify-commands/{name}.md
```

capability 宣言は不要です。ファイルを置くだけでハンドラが有効化されます。

#### 名前解決規約

`<!-- verify: {name} "arg" -->` のコマンド名がハンドラのファイル名（拡張子なし）と照合されます。例: `<!-- verify: api-contract "endpoint" -->` は `.wholework/verify-commands/api-contract.md` に解決されます。

**ビルトイン優先**: `{name}` がビルトインコマンド（例: `file_exists`、`grep`）と一致する場合、常にビルトインが使われ、ハンドラファイルは警告とともに無視されます。

#### ハンドラ Contract

カスタムハンドラファイルは 4 セクションの Markdown 構造に従います（adapter contract と同じ）:

```markdown
# {name} verify command handler

**Safe mode:** compatible   ← または "uncertain"（下記参照）

## Purpose

{このハンドラが何を検証するかの説明}

## Input

- **Arguments**: {このコマンドが受け取る引数}

## Processing Steps

{ステップごとの検証ロジック — ハンドラ解決時に LLM が実行する}

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: 検証結果の説明
```

#### 結果フォーマット

カスタムハンドラは以下のいずれかを返さなければなりません:

- **PASS**: 検証条件を満たした
- **FAIL**: 検証条件を満たさなかった（詳細な理由を含める）
- **UNCERTAIN**: 自動判定できない（詳細な理由を含める）

#### Safe Mode 自己宣言

各ハンドラはファイル冒頭近くで safe モード互換性を自己宣言します:

| 宣言 | 挙動 |
|-------------|----------|
| `**Safe mode:** compatible` | ハンドラは safe と full の両モードで実行される |
| `**Safe mode:** uncertain` | ハンドラは safe モードで UNCERTAIN を返し、full モードでのみ実行される |
| （未宣言） | `uncertain` として扱う — safe モードで UNCERTAIN を返す |

`compatible` は副作用のないチェック（ファイル読み取り、静的解析など）にのみ使います。外部サービス呼び出しや shell コマンド実行を行うハンドラには `uncertain` を使います。

#### Adapter パターンとの関係

カスタム verify command ハンドラは adapter と次の点で異なります: ハンドラはツール選択分岐のない単一実装を想定して設計されています。Adapter パターン（下記 `### Adapter パターン` 参照）は複数ツール実装の抽象化が必要な場合に価値を生みます。ハンドラはシンプルです — 1 ハンドラファイル、1 検証アプローチ — adapter が使う 3 層解決順序は不要です。

### Adapter Contract テンプレート

Adapter は統一 contract に従います。ユーザーはこのテンプレートに従い、上記のプロジェクトローカルまたはユーザーグローバルのパスに配置することでカスタム adapter を作成できます。

リファレンス実装: `modules/browser-adapter.md`。新しい adapter を作成する際のガイドとして使ってください。

#### 必須セクション

**1. Detection 手順**

利用可能なツールを自動検出する手順を記述します。複数ツールをサポートする場合は優先度テーブルに列挙します。

```markdown
### Step N: Tool Detection

優先度順に利用可能なツールを検出します。最初に見つかったツールを使います。

| Priority | Tool   | Detection Method |
|----------|--------|-----------------|
| 1        | Tool A | `command -v tool-a` で検出 |
| 2        | Tool B | ToolSearch で MCP ツールを検索、必要ツールがすべて利用可能なら検出 |
| 3        | None   | 上記のいずれも利用不可 |

**When not detected**: 検出失敗の詳細理由とともに UNCERTAIN を返す
```

**2. コマンド変換表**

受入チェック表記をツール固有コマンドへマッピングする記述。検出ツールごとにサブセクションを作り、コマンドごとの実行手順を番号付きで記します。

```markdown
### Step N: Tool-specific Execution

#### Tool A

**`command_x` の実行手順:**

1. Tool A の初期化コマンドを実行
2. 対象リソースにアクセス
3. 条件を検証
4. セッションをクローズ

#### Tool B

**`command_x` の実行手順:**

1. ...
```

**3. Fallback**

検出されなかった場合の挙動を定義します。原則として UNCERTAIN を返し、ユーザーを手動検証へ誘導します。

```markdown
### Step N: Return Result

結果を以下のいずれかで返します:

- **PASS**: 検証条件を満たした
- **FAIL**: 検証条件を満たさなかった（詳細な理由を含める）
- **UNCERTAIN**: 自動判定できない（ツール未発見、実行エラーなど — 詳細な理由を含める）
```

#### 任意セクション

**セキュリティ制約** — ツール固有のセキュリティ制約を記述します（例: URL フィルタリング、クレデンシャルマスキング、SSRF 防止）。

**セットアップ手順** — 初回使用のインストールガイドや前提条件を記述します。

#### ファイル構造テンプレート

```markdown
# {capability} adapter

## Purpose

{adapter の役割と提供する抽象化の説明}

Caller: {参照元モジュール/スキル}

## Input

呼び出し側は以下を提供します:

- **Command type**: {サポートコマンドのリスト}
- **Arguments**: {コマンドごとの引数}

## Processing Steps

### Step 1: {Security Check (optional)}

{セキュリティ制約検証手順}

### Step 2: Tool Detection

| Priority | Tool        | Detection Method |
|----------|-------------|-----------------|
| 1        | {Tool A}    | {検出方法} |
| 2        | None        | 上記のいずれも利用不可 |

**When not detected**: UNCERTAIN を返す。

### Step 3: Tool-specific Execution

#### {Tool A}

{コマンド変換表と実行手順}

### Step 4: Return Result

- **PASS**: 検証条件を満たした
- **FAIL**: 検証条件を満たさなかった（詳細な理由を含める）
- **UNCERTAIN**: 自動判定できない（詳細な理由を含める）

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Detail**: 検証結果の説明

## Reference Marker

このファイルを Read した呼び出し側は最終出力に以下のマーカーを含めなければなりません:

`[ref:{adapter-name}:{random-4-char-alphanum}]`
```

### `--when` 修飾子（計画中、未実装）

受入条件内の個別検証項目に環境ゲートを設ける仕組みです。

```html
<!-- verify: browser_check "url" "h1" --when="command -v browser-use" -->
```

- 条件成立（exit 0） → メインコマンドを実行
- 条件不成立（exit != 0） → SKIPPED（無視、手動チェック不要）

Layer 1–3 が「スキルのどの部分をロードするか」を制御するのに対し、`--when` は受入条件内の個別検証項目レベルで環境ゲートを提供します。

## 層間の関係

```
.wholework.yml (Layer 1)
  │
  ├─→ copilot-review ────→ /review が external-review-phase.md を Read するか (Layer 3)
  ├─→ coderabbit-review ─→ /review が external-review-phase.md を Read するか (Layer 3)
  ├─→ capabilities.mcp ──→ /issue が mcp_call ヒントを提案するか (Layer 2)
  ├─→ capabilities.browser → adapter が browser を解決するか (Layer 4)
  └─→ production-url ───→ verify-executor が {{base_url}} を解決するか (Layer 4)

ToolSearch (Layer 2) ─→ 動的 MCP ツール検出（宣言なしの場合のフォールバック）
command -v (Layer 2) ─→ CLI ツール可用性チェック（adapter 内、--when 内）
--when (Layer 4) ────→ 受入条件ごとの環境ゲート（計画中）
verify-executor (Layer 4) ─→ .wholework/verify-commands/*.md（プロジェクトローカルカスタムハンドラ）
```

## 拡張ガイド

### 新しい capability の追加

1. `modules/{capability}-adapter.md` を作成する（`modules/browser-adapter.md` を参照）
2. `modules/adapter-resolver.md` の説明にその capability を追加する
3. `verify-executor.md` の変換表に新コマンドを追加し、adapter-resolver 経由で委譲する
4. `modules/detect-config-markers.md` のマーカー表に `capabilities.{name}` を追加する
5. `docs/structure.md` の Key Files 表に追加する

### 新しい Domain ロジックの追加

1. `skills/{skill-name}/{domain}-phase.md` を作成する
   - このファイルが参照するすべてのモジュールのフルパスをファイル冒頭に列挙する（例: `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md`）。省略形（例: `detect-config-markers.md` だけ）は禁止。冒頭にフルパスを列挙することで、呼び出し側が事前に参照モジュールを把握できる
2. SKILL.md に条件付き Read 指示を追加する（marker 検出またはファイル存在パターン）
3. `docs/structure.md` の Domain Files 表に追加する
