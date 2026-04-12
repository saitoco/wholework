# Issue #56: config: Spec 保存場所のパスをプロジェクト単位で設定可能に

## issue retrospective

### Ambiguity Resolution

5つの曖昧ポイントを検出、2つユーザー確認、3つ自動解決:

**ユーザー確認で解決:**
1. **キー名規則**: flat kebab-case (`spec-path`, `steering-docs-path`) を選択。既存 `production-url` と同パターン。
2. **実装方針**: ヘルパー導入を選択。`detect-config-markers.md` に `SPEC_PATH` / `STEERING_DOCS_PATH` 変数追加 → 各 SKILL.md/モジュールで変数参照に置換。

**自動解決:**
3. **デフォルト値**: 現行値 (`docs/spec`, `docs`) を維持、後方互換性確保
4. **Steering Documents 粒度**: 1ディレクトリのみ（Issue 本文指示通り）
5. **マイグレーション**: 既存ファイル移動は本 Issue スコープ外

### Title Normalization

- **旧**: `config: Spec 保存場所などのパスをプロジェクト単位で設定可能にする`
- **新**: `config: Spec 保存場所のパスをプロジェクト単位で設定可能に`

タイトル正規化ルール（noun-ending, 末尾の「する」削除）を適用。「など」も除去し焦点を明確化（Steering Documents もスコープだが主要対象は Spec パス）。

### Scope Impact

- `docs/spec` 参照: 27件（spec, code, review, auto, verify SKILL.md）
- `docs/` 参照: 20件（主に modules/）
- スクリプト: `check-file-overlap.sh` 1件
- 合計 47+ 箇所の置換が必要

実装は機械的だが網羅性が重要。ヘルパー導入によりフォールバック（デフォルト値）が単一箇所 (`detect-config-markers.md`) に集約され、今後の保守性も向上。

### Verify Command Design

- 10件の pre-merge 条件で 主要 SKILL.md の変数参照を個別検証
- 2件の post-merge opportunistic 条件で実運用検証（カスタムパス動作 + 後方互換）

## Overview

`.wholework.yml` に `spec-path` と `steering-docs-path` を追加し、Spec 保存場所と Steering Documents 格納ディレクトリをプロジェクト単位で設定可能にする。既存 SKILL.md / モジュール / スクリプトで `docs/spec` / `docs/` がハードコードされている箇所を、`detect-config-markers.md` が出力する `$SPEC_PATH` / `$STEERING_DOCS_PATH` 変数参照に置換する。デフォルト値は現行の `docs/spec` / `docs` を維持し、後方互換性を確保する。

## Changed Files

### Configuration helper (SSoT)

- `modules/detect-config-markers.md`: Marker Definition Table に `spec-path` / `steering-docs-path` 行を追加、Output Format セクションに `SPEC_PATH` / `STEERING_DOCS_PATH` 変数を追加
- `scripts/get-config-value.sh`: 新規作成（bash 環境から `.wholework.yml` の値を取得するヘルパー。引数: `key [default]`）
- `tests/get-config-value.bats`: 新規作成（ヘルパースクリプトの bats テスト）

### Bash script that reads config

- `scripts/check-file-overlap.sh`: `$REPO_ROOT/docs/spec` ハードコード（line 57）を `get-config-value.sh` 経由で解決する形に変更
- `tests/check-file-overlap.bats`: カスタム `spec-path` 設定時のテストケース追加

### Core workflow skills

- `skills/spec/SKILL.md`: 設定検出ステップ追加（Step 0 または Step 5 直前）、`docs/spec` → `$SPEC_PATH`（5 箇所）、`docs/structure.md` / `docs/tech.md` / `docs/product.md` → `$STEERING_DOCS_PATH/...`（3 箇所）、`docs/tech.md` 相互参照 → `$STEERING_DOCS_PATH/tech.md`（1 箇所）
- `skills/code/SKILL.md`: 設定検出ステップ追加、`docs/spec` → `$SPEC_PATH`（4 箇所）、`docs/tech.md` / `docs/structure.md` → `$STEERING_DOCS_PATH/...`（3 箇所）
- `skills/review/SKILL.md`: 設定検出ステップ追加（外部 review phase が既存検出するため tie-in）、`docs/spec` → `$SPEC_PATH`（4 箇所）、`docs/product.md` / `docs/tech.md` / `docs/structure.md` Glob → `$STEERING_DOCS_PATH/...`（2 箇所、`STEERING_DOCS_PATHS`（複数形）変数とは別）
- `skills/verify/SKILL.md`: 既存 `detect-config-markers` 読み込み箇所に `SPEC_PATH` 取得を追加、`docs/spec` → `$SPEC_PATH`（4 箇所）
- `skills/auto/SKILL.md`: 設定検出ステップ追加、`docs/spec` → `$SPEC_PATH`（4 箇所）
- `skills/issue/SKILL.md`: 既存 `detect-config-markers` 読み込み箇所に `STEERING_DOCS_PATH` 取得を追加、`docs/product.md` / `docs/tech.md` → `$STEERING_DOCS_PATH/...`（2 箇所）、`docs/spec/*.md` → `$SPEC_PATH/*.md`（1 箇所）
- `skills/audit/SKILL.md`: 設定検出ステップ追加、`docs/spec/` 除外パス → `$SPEC_PATH/`（1 箇所）、Steering Documents 参照 → `$STEERING_DOCS_PATH/...`（1 箇所）
- `skills/doc/SKILL.md`: 設定検出ステップ追加、Steering Document 書き込みパス `docs/{doc}.md` → `$STEERING_DOCS_PATH/{doc}.md`（複数箇所）、`docs/spec/` 除外パス → `$SPEC_PATH/`（2 箇所）。Glob `docs/*.md` → `$STEERING_DOCS_PATH/*.md`
- `skills/triage/SKILL.md`: `docs/product.md` / `docs/tech.md` 参照 → `$STEERING_DOCS_PATH/...`（4 箇所）

### Agents (receive resolved paths from parent skill)

- `agents/review-spec.md`: Input セクションの Steering Documents パス例 / Spec パス例を変数表記に変更、Processing Steps 内の `docs/tech.md` / `docs/product.md` / `docs/structure.md` 参照を `$STEERING_DOCS_PATH/...` に変更（6 箇所）
- `agents/review-light.md`: 同様に Spec / Steering Documents 参照を変数表記に変更（2 箇所）
- `agents/issue-scope.md`: Steering Documents 参照を変数表記に変更（3 箇所）
- `agents/issue-risk.md`: `docs/spec/` → `$SPEC_PATH/`（1 箇所）
- `agents/issue-precedent.md`: `docs/spec/` → `$SPEC_PATH/`（4 箇所）

### Modules

- `modules/doc-checker.md`: Glob の `docs/*.md` → `$STEERING_DOCS_PATH/*.md`、`docs/spec/` 除外 → `$SPEC_PATH/` 除外（計 7 箇所のうち、Steering / Spec パス依存の箇所のみ変更、`docs/workflow.md` など Project Documents 参照は変更しない）
- `modules/measurement-scope.md`: 例示の `docs/spec/` → `$SPEC_PATH/`（1 箇所）

### Documentation

- `docs/environment-adaptation.md`: Layer 1 の `.wholework.yml` 設定例に `spec-path: custom/specs` と `steering-docs-path: custom/docs` を追加
- `docs/ja/environment-adaptation.md`: 同じ設定例をミラー

### 変更しないファイル（スコープ外）

- `docs/workflow.md`, `docs/environment-adaptation.md` 等の Project Documents 参照（frontmatter `type: project` による動的検出で既に任意パス対応）
- `docs/{lang}/*.md`（翻訳出力、`/doc translate` が管理）
- `docs/reports/*` 関連（本 Issue のスコープ外）
- `docs/product.md` の "Required Dependencies" テーブル内の `docs/spec/` 説明文（Future Direction で既に記載済みのため追加の文面変更は不要）
- `.github/workflows/test.yml`（wholework リポジトリ自体の CI で、ユーザープロジェクト用の設定可能パスとは別軸）
- `docs/spec/issue-*.md` 既存 Spec 履歴ファイル内のパス記載（過去記録）

## Implementation Steps

**Step recording rules:**
- Step numbers: integers only
- Dependencies: "(after N)" / "(parallel with N, M)"
- Acceptance criteria mapping: "(→ acceptance criterion X)"

1. `modules/detect-config-markers.md` を更新: Marker Definition Table に 2 行追加（`spec-path` → `SPEC_PATH`、`steering-docs-path` → `STEERING_DOCS_PATH`、値は "Path string (extract value as-is)"、デフォルト `docs/spec` / `docs`）。YAML Parsing Rules セクションに "path string handling" 記述を追加（`production-url` と同扱い）。Output Format セクションの変数リストに `SPEC_PATH` / `STEERING_DOCS_PATH` の 2 行を追加。(→ acceptance criteria 1, 2, 3, 4)

2. `scripts/get-config-value.sh` を新規作成 (parallel with 1): `.wholework.yml` から指定キーの値を抽出する bash ヘルパー。Usage: `get-config-value.sh <key> [default]`。`detect-config-markers.md` の YAML Parsing Rules と整合（`key: value` の value 部を抽出、クオート除去、未設定または未存在時はデフォルト返却）。`--help` サポート。対応キー: flat kebab-case（`spec-path`, `steering-docs-path`, `production-url` 等）。ネスト記法（`capabilities.browser` 等）はスコープ外。

3. `tests/get-config-value.bats` を新規作成 (after 2): 基本ケース（キー存在、キー不在、`.wholework.yml` 不在、デフォルト返却、値クオート除去、コメント行無視）を網羅。

4. `scripts/check-file-overlap.sh` を更新 (after 2): line 57 の `$REPO_ROOT/docs/spec` を `$REPO_ROOT/$(${SCRIPT_DIR}/get-config-value.sh spec-path docs/spec)` に置換。`tests/check-file-overlap.bats` に `.wholework.yml` でカスタム `spec-path` 設定時のテストケースを追加。

5. `skills/spec/SKILL.md` を更新 (parallel with 1): Step 5 (Reference Steering Documents) の冒頭または Step 0 に `Read ${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md and follow the "Processing Steps" section. Retain SPEC_PATH and STEERING_DOCS_PATH for use in subsequent steps.` を追加。以降の `docs/spec` → `$SPEC_PATH`、`docs/structure.md` / `docs/tech.md` / `docs/product.md` → `$STEERING_DOCS_PATH/structure.md` 等に機械的置換。Step 10 のテンプレート内の `docs/spec/issue-$NUMBER-short-title.md` も `$SPEC_PATH/issue-$NUMBER-short-title.md` に置換。GitHub blob URL の `blob/main/docs/spec/...` も `blob/main/$SPEC_PATH/...` に変更。(→ acceptance criterion 5)

6. `skills/code/SKILL.md` を更新 (parallel with 5): 同様に Step 0 or 早期ステップに設定検出を追加、`docs/spec` → `$SPEC_PATH`、`docs/tech.md` / `docs/structure.md` → `$STEERING_DOCS_PATH/...`。(→ acceptance criterion 6)

7. `skills/verify/SKILL.md` を更新 (parallel with 5): Step 4（`{{base_url}}` 解決の直前）に `detect-config-markers.md` の一括 Read を挿入し、`SPEC_PATH`、`STEERING_DOCS_PATH`、`PRODUCTION_URL` をまとめて取得。以降の個別 Read 参照（line 175, 200）は「Step 4 で取得済み変数を再利用」に変更。`docs/spec` → `$SPEC_PATH` に置換。(→ acceptance criterion 7)

8. `skills/auto/SKILL.md` を更新 (parallel with 5): Step 0 or 早期ステップに設定検出を追加、`docs/spec` → `$SPEC_PATH`。(→ acceptance criterion 8)

9. その他の skill / agent / module を更新 (parallel with 5-8): `skills/review/SKILL.md` / `skills/issue/SKILL.md` / `skills/audit/SKILL.md` / `skills/doc/SKILL.md` / `skills/triage/SKILL.md` / `agents/review-spec.md` / `agents/review-light.md` / `agents/issue-scope.md` / `agents/issue-risk.md` / `agents/issue-precedent.md` / `modules/doc-checker.md` / `modules/measurement-scope.md`。各 SKILL.md に必要に応じて設定検出ステップを追加し、`docs/spec` → `$SPEC_PATH`、`docs/{product|tech|structure}.md` → `$STEERING_DOCS_PATH/...` を機械的置換。Agent は親 skill から解決済パスを受け取る設計のため、Agent ファイル内の記述はデフォルト値表記の変更のみで動作上の追加処理は不要。(→ acceptance criterion 10、他 criteria 5-8 の補完)

10. `docs/environment-adaptation.md` Layer 1 と `docs/ja/environment-adaptation.md` Layer 1 の `.wholework.yml` 設定例に `spec-path: custom/specs` と `steering-docs-path: custom/docs` を追加（既存の `production-url` 行の直下など適切な位置に挿入）。(→ acceptance criterion 9)

## Alternatives Considered

1. **Bash スクリプトから `.wholework.yml` を読む方法**:
   - **採用**: 専用ヘルパー `scripts/get-config-value.sh` を新規作成
   - **不採用**: `check-file-overlap.sh` 内にインライン grep を書く。→ 将来他スクリプトで同様のニーズが発生した場合に重複実装となるため不採用。bats テスト化も容易でないため。
   - **不採用**: `detect-config-markers.md` を直接 bash から呼ぶ。→ `detect-config-markers.md` は LLM が読んで解釈する markdown ドキュメントで、bash パーサではないため技術的に不可。

2. **Agent ファイルでの設定検出**:
   - **採用**: 親 skill で解決し、解決済パスを Task プロンプトに埋め込んで渡す
   - **不採用**: Agent 内で `detect-config-markers.md` を直接 Read する。→ Agent は独立 context で動作するが、`.wholework.yml` 検出は親 skill 側で既に行っているため重複。Agent のシンプルさを保つため、解決済パスを入力として受け取る形式が妥当。

3. **`docs/` プロジェクト全体の置換**:
   - **採用**: Steering Documents（product.md, tech.md, structure.md）への参照のみ置換
   - **不採用**: `docs/workflow.md` など Project Documents への参照も置換。→ Issue 本文で "Project Documents は既に任意のパス配置可能（frontmatter `type: project` で判別）" と明記されているため、スコープ外。

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/detect-config-markers.md" "### 2." "spec-path" --> `detect-config-markers.md` のマーカー定義テーブルに `spec-path` キーが追加されている
- <!-- verify: section_contains "modules/detect-config-markers.md" "### 2." "steering-docs-path" --> `detect-config-markers.md` のマーカー定義テーブルに `steering-docs-path` キーが追加されている
- <!-- verify: section_contains "modules/detect-config-markers.md" "## Output Format" "SPEC_PATH" --> Output Format セクションに `SPEC_PATH` 変数が定義されている（デフォルト `docs/spec`）
- <!-- verify: section_contains "modules/detect-config-markers.md" "## Output Format" "STEERING_DOCS_PATH" --> Output Format セクションに `STEERING_DOCS_PATH` 変数が定義されている（デフォルト `docs`）
- <!-- verify: grep "SPEC_PATH" "skills/spec/SKILL.md" --> `/spec` SKILL.md が `$SPEC_PATH` を参照している（ハードコード置換）
- <!-- verify: grep "SPEC_PATH" "skills/code/SKILL.md" --> `/code` SKILL.md が `$SPEC_PATH` を参照している
- <!-- verify: grep "SPEC_PATH" "skills/verify/SKILL.md" --> `/verify` SKILL.md が `$SPEC_PATH` を参照している
- <!-- verify: grep "SPEC_PATH" "skills/auto/SKILL.md" --> `/auto` SKILL.md が `$SPEC_PATH` を参照している
- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 1" "spec-path" --> `docs/environment-adaptation.md` Layer 1 の `.wholework.yml` 設定例に新キーが含まれている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> 変更後の全 SKILL.md が構文検証を PASS する

### Post-merge

- `.wholework.yml` に `spec-path: custom/path` を設定した状態で `/spec` を実行し、`custom/path/issue-N-*.md` に Spec が作成されることを確認 <!-- verify-type: opportunistic -->
- `spec-path` 未設定のプロジェクトで `/spec` 実行し、従来通り `docs/spec/` に Spec が作成されること（後方互換）を確認 <!-- verify-type: opportunistic -->

## Tool Dependencies

### Bash Command Patterns

- `scripts/get-config-value.sh`: 新規ヘルパー、bats test / check-file-overlap.sh から呼び出し

### Built-in Tools

- `Read`, `Write`, `Edit`, `Glob`, `Grep`: 既存の skill 編集に使用（追加設定不要）

### MCP Tools

- none

## Uncertainty

- **設定検出ステップの挿入位置**: 各 SKILL.md で `detect-config-markers.md` Read 指示を Step 0 として追加するか、最初に `$SPEC_PATH` / `$STEERING_DOCS_PATH` を使うステップの直前に挿入するか。
  - **検証方法**: 既存の `/verify` / `/issue` / `/review` のパターンを参照。これらは必要なタイミングで `detect-config-markers.md` を Read する。最もシンプルなのは、Step 5（Steering Documents 参照）直前 or 内部に挿入する形式。
  - **影響範囲**: Implementation Steps 5, 6, 7, 8, 9 の記述方針。実装時に各 skill の既存パターンに合わせて決定する。

- **`/doc` skill の扱い**: `/doc` は Steering Documents を生成する skill 本体。書き込み先が `$STEERING_DOCS_PATH` 化することで、自己参照的になる部分がある（例: `/doc product` で `$STEERING_DOCS_PATH/product.md` に書き込む）。
  - **検証方法**: 現行 `/doc` SKILL.md の書き込みロジックを読み、変数化が機能的に問題ないかを確認。Glob パターンも `$STEERING_DOCS_PATH/*.md` に変更する必要がある。
  - **影響範囲**: Implementation Step 9。実装時に `/doc` SKILL.md 全体の一貫性を確認。

## Notes

### Auto-resolved ambiguity points（調査段階で解消済）

- **Bash 環境から config を読む方法**: 専用ヘルパースクリプト `scripts/get-config-value.sh` を新規作成（理由: 再利用性、bats テスト容易性、`detect-config-markers.md` の YAML Parsing Rules と整合させやすい）
- **`/doc` skill での書き込みパス**: `STEERING_DOCS_PATH` を使用（理由: 本機能の一貫性を保つため）
- **Project Documents への影響**: 変更しない（理由: Issue 本文で明示的にスコープ外）
- **CI 設定ファイル（`.github/workflows/test.yml`）**: 変更しない（理由: wholework 自身の CI で、ユーザープロジェクト用設定とは別軸）
- **`STEERING_DOCS_PATH` vs 既存 `STEERING_DOCS_PATHS`（複数形）変数**: 別変数として共存。`STEERING_DOCS_PATH`（単数、ディレクトリ）は設定値。`STEERING_DOCS_PATHS`（複数形、カンマ区切りパスリスト）は既存の review/issue で使用される検出済みファイルのリスト。命名衝突なし。

### Issue body と実装の conflict 検出

なし（Issue 本文と既存実装の間に前提条件の矛盾は検出されなかった）。

### Tool detection pattern consistency

本 Issue は MCP ToolSearch 等のツール検出を含まない（純粋なファイル内ハードコード置換）。

### bats テスト入力フォーマット

`tests/get-config-value.bats` の入力 `.wholework.yml` は以下の YAML 形式:
- `key: value` の flat kebab-case 形式
- 値はクオート付き（`"value"`）、クオート無し両方対応
- コメント行（`#` 始まり）無視
- 空ファイル / ファイル不在の場合はデフォルト返却

### 後方互換性

`.wholework.yml` 不在 or `spec-path` / `steering-docs-path` 未設定の場合、全ての skill は従来通り `docs/spec` / `docs` を使用する。既存プロジェクトの `docs/spec/issue-*.md` や `docs/product.md` は移動不要（機能追加のみ）。

### 変更の網羅性

`grep -rn 'docs/spec' .` の結果（28 ファイル、68 occurrences）と `grep -rnE 'docs/(product|tech|structure)\.md' .` の結果を変更対象ファイルリストと照合。historical records（`docs/spec/issue-*.md` 内の `docs/spec` 記述）は過去記録として変更対象外。

## Code Retrospective

### Deviations from Design

- `verify/SKILL.md` の `detect-config-markers.md` 参照: Spec では「既存の Read 箇所に `SPEC_PATH` 取得を追加」と記載していたが、実装では Step 4（`{{base_url}}` 解決の直前）に統合した 1 回の Read として整理した。既存の line 175, 200 の個別参照をキャッシュ済み変数の再利用に変更したため、実際の動作はより効率的になった。
- `triage/SKILL.md` の挿入位置: Spec では「Fallback level determination の直前」と暗示していたが、実装では "Argument Parsing" と "Command Execution Constraints" の後、"Single Issue Execution" セクションの前に "Configuration Detection" セクションとして追加した。これにより全コマンド（single/bulk/backlog）に共通で設定検出が適用される。
- `doc/SKILL.md` の挿入位置: Spec の Step 9 では「各ルーティング先で `$SPEC_PATH` を使う箇所に設定検出を追加」と記載していたが、実装では "Command Routing" の直前に "Configuration Detection" セクションを設け、全コマンド共通の一元検出とした。これによりコマンドルーティング先ごとの重複 Read が不要になった。

### Design Gaps/Ambiguities

- `detect-config-markers.md` の既存参照整理: 実装時に `verify/SKILL.md` の line 175（Browser capability check）と line 200（Browser-verifiable case exclusion）に既存の `detect-config-markers.md` 個別 Read 指示があることが判明。これらを Step 4 での一括取得で代替するよう更新した。Spec には「既存 Read 箇所に追加」とあったが、重複を避けるため整理が必要だった。

### Rework

- N/A

## spec retrospective

### Minor observations

- `STEERING_DOCS_PATH`（単数形、ディレクトリ）と既存 `STEERING_DOCS_PATHS`（複数形、カンマ区切りパスリスト）が共存する点は命名がやや紛らわしい。将来的に `/review` / `/issue` 側の複数形変数をリネームするか、本 Issue で導入する単数形を別名（例: `STEERING_DIR`）にするか検討の余地あり。今回はスコープ外として両立。
- Issue 本文の acceptance criteria は主要 4 skill（spec/code/verify/auto）のみ `SPEC_PATH` 参照を検証対象としているが、実装上は `/review` / `/issue` / `/audit` / `/doc` / `/triage` / agents / modules も変更対象となる。criterion 10（`validate-skill-syntax.py PASS`）でまとめて網羅される想定。
- `/doc` skill は Steering Documents を管理する skill 本体であり、書き込み先を `$STEERING_DOCS_PATH` 化することで自己参照的になる。実装時に `/doc sync` や `/doc product` の Glob / Write パスの整合を丁寧に確認する必要あり。

### Judgment rationale

- **ヘルパースクリプト `get-config-value.sh` の新設**: bash 環境から `.wholework.yml` を読む方法として、インライン grep ではなく専用ヘルパーを採用。理由: `detect-config-markers.md` の YAML Parsing Rules との整合、bats テスト容易性、将来の他スクリプトでの再利用可能性。
- **Agent 側での設定検出を採用しない**: Agent ファイル (`review-spec.md` 等) は独立 context で動作するが、`.wholework.yml` 検出は親 skill 側が既に行うため、解決済パスを Task プロンプトに埋め込んで渡す形式が妥当。Agent 側の変更はデフォルト値の表記のみで動作上の追加処理は不要。
- **Project Documents を変更対象に含めない**: Issue 本文の "Project Documents は既に任意のパス配置可能（frontmatter `type: project` で判別）" に準拠。`docs/workflow.md` 等の参照はリテラルのまま。
- **CI 設定 `.github/workflows/test.yml` を変更対象に含めない**: wholework 自身の CI は wholework リポジトリ内部で動作する固定構成。ユーザープロジェクト用の設定可能パスとは別軸。

### Uncertainty resolution

- **設定検出ステップの挿入位置**: 各 skill の既存パターンに合わせて柔軟に決定（実装 Step 5-9 で個別判断）。Uncertainty セクションに記載し、実装時に `/verify` / `/issue` / `/review` の既存パターンを参照。
- **`/doc` skill の書き込みパス変数化**: `STEERING_DOCS_PATH` を使用する方針で確定。実装 Step 9 で `/doc` SKILL.md 全体の一貫性を確認する責務を明示。
