[English](../migration-notes.md) | 日本語

# Migration Notes

---

## 英語変換チェックリスト

スクリプトを移行する際、すべての日本語テキストが英語に翻訳されていることを確認するためのチェックリスト。

### ソースファイルの文字列

- [ ] コメント（インライン・ブロック）
- [ ] 変数名・関数名
- [ ] 文字列リテラル（エラーメッセージ、usage、ログ出力）
- [ ] ドキュメンテーション文字列 / docstring

### テストでカバーされない出力文字列

テスト assertion が検証しない出力文字列は見落としやすい。以下の各カテゴリを手動で監査すること:

- [ ] サマリー・結果行（例: `"検証対象: N スキル"`、`"結果: N エラー"`）
- [ ] 警告メッセージ
- [ ] 進捗表示・フェーズラベル
- [ ] Help / usage テキスト（`--help` 出力）
- [ ] 成功・完了メッセージ

### 日本語残存の包括チェック

移行後に以下のコマンドを実行し、移行対象ファイルに残っている日本語文字を検出する:

```bash
grep -rP "[\x{3000}-\x{9FFF}]" <path-to-migrated-files>
```

これは CJK 統合漢字ブロックと隣接範囲（U+3000–U+9FFF）をカバーし、ひらがな、カタカナ、漢字、CJK 記号を含む。マッチが見つかれば、マージ前に解決すべき未翻訳テキストである。

例 — 全スキルファイルをスキャン:

```bash
grep -rP "[\x{3000}-\x{9FFF}]" skills/
```

### テスト

- [ ] `@test` 名が英語に翻訳されている（必須 — マルチバイト文字は bats の parse エラーになる）
- [ ] Assertion 文字列が新しい英語メッセージと一致するよう更新されている

---

## パス置換検証: `~/.claude/` と `$HOME/.claude/` の両方を確認

パス置換タスクの受入条件を作成するときは、`~/.claude/` と `$HOME/.claude/` の **両方** を検証すること。両者は同じパスを指すが異なるバイト列であり、片方のみを狙うパターンはもう一方の出現を静かに見逃す。

### 背景

このガイドラインは Issue #31 のレトロスペクティブから抽出された。`modules/adapter-resolver.md` が `$HOME/.claude/` 参照を含んでおり、`~/.claude/` のみを狙う受入条件の grep パターンをすり抜けた。レビューフェーズで捕捉されたが、デュアルフォームチェックの標準化の必要性を示した事例。

### 推奨 grep パターン

パス置換タスクの受入条件または手動検証コマンドを書くときは、両形式にマッチするパターンを使う:

```bash
grep -rn '~/.claude/\|$HOME/.claude/' <path>
```

または拡張正規表現で:

```bash
grep -rEn '(~|\$HOME)/.claude/' <path>
```

どちらも `~/.claude/`（tilde 形式）と `$HOME/.claude/`（環境変数形式）の両方を 1 回でカバーする。

### パス置換受入条件のチェックリスト

`~/.claude/` パス参照の置換や監査を含むタスクでは:

- [ ] 受入条件の grep パターンが `~/.claude/` と `$HOME/.claude/` の両方を含む
- [ ] 検証コマンドが `grep -rn '~/.claude/\|$HOME/.claude/'`（または同等）を使い、片方のみのパターンを使わない
- [ ] 移行後チェックが全移行ファイルに対してデュアルフォームパターンを実行する

---

## Issue #23: Utility Skills Migration (triage, audit, doc)

7 files were migrated from claude-config to wholework: `skills/triage/SKILL.md`, `skills/audit/SKILL.md`, `skills/doc/SKILL.md`, `skills/doc/product-template.md`, `skills/doc/tech-template.md`, and `skills/doc/structure-template.md`. All Japanese text (frontmatter `description` field, section headings, body text, inline comments) was translated to English. All files are new creations. Opportunistic simplification was applied.

### Interface Changes

**Frontmatter description translations (Japanese → English):**
- `triage`: `Issueトリアージ。タイトル正規化・Type/Priority/Size/Value設定を自動化...` → `Issue triage. Automates title normalization, Type/Priority/Size/Value assignment...`
- `audit`: `ドキュメント×実装の乖離検出・Issue自動生成...` → `Detect documentation/implementation drift and auto-generate Issues...`
- `doc`: `プロジェクト基盤ドキュメント管理...` → `Project foundation document management...`

**allowed-tools changes (triage):**

Removed absolute paths from `allowed-tools`:
- `/Users/saito/.claude/scripts/triage-backlog-filter.sh:*` → removed (kept `~/.claude/scripts/triage-backlog-filter.sh:*` only)
- `/Users/saito/.claude/scripts/gh-graphql.sh:*` → removed (kept `~/.claude/scripts/gh-graphql.sh:*` only)
- `/Users/saito/.claude/scripts/gh-issue-comment.sh:*` → removed (kept `~/.claude/scripts/gh-issue-comment.sh:*` only)

**Section heading translations applied (Japanese → English):**
- `Issueトリアージ` / `Issue トリアージ` → `Issue Triage`
- `引数パース（最初に実行）` → `Argument Parsing (execute first)`
- `コマンド実行の制約` → `Command Execution Constraints`
- `単体実行` → `Single Issue Execution`
- `一括実行` → `Bulk Execution`
- `バックログ分析` → `Backlog Analysis`
- `注意事項` → `Notes`
- `audit: ドキュメント × 実装の乖離検出` → `audit: Documentation × Implementation Drift Detection`
- `コマンドルーティング` → `Command Routing`
- `doc: プロジェクト基盤情報管理` → `doc: Project Foundation Information Management`
- `テンプレート定義` → `Template Definitions`
- `ドキュメント走査（共通手順）` → `Document Traversal (common procedure)`
- `ステータス表示` → `Status Display`
- `個別作成・更新` → `Individual Create/Update`
- `init ウィザード` → `init Wizard`
- `sync 双方向正規化` → `sync Bidirectional Normalization`
- `sync 個別逆生成` → `sync Individual Reverse-Generation`
- `add — 既存ドキュメントの登録` → `add — Register Existing Document`
- `project — 新規 project document の作成` → `project — Create New Project Document`

**Step numbering change (triage):**

The source contained a fractional step `### 1.5. 重複候補検出`. This was renamed to `### Step 2: Duplicate Candidate Detection` and all subsequent steps were renumbered (+1 offset). Final step numbering in the Single Issue Execution section: Steps 1–10 (source: Steps 1, 1.5, 2–9 → normalized to Steps 1–10).

**claude-config references replaced (doc):**

3 occurrences of "claude-config リポジトリ" in error messages replaced:
- `"エラー: テンプレートファイル ... が見つかりません。claude-config リポジトリが正しくセットアップされているか確認してください。"` → `"Error: template file ... not found. wholework is not correctly installed. Run install.sh first."`
- `"エラー: テンプレートファイルが見つかりません。claude-config リポジトリが正しくセットアップされているか確認してください。"` → `"Error: template file not found. wholework is not correctly installed. Run install.sh first."`

**Wholework-managed directories reference (doc):**

1 occurrence of "claude-config 管理ディレクトリ: skills/、modules/、agents/" replaced with "wholework-managed directories: skills/, modules/, agents/".

**Template file placeholder translations (doc sub-templates):**

All Japanese placeholder text in `product-template.md`, `tech-template.md`, and `structure-template.md` was translated to English:
- `プロジェクトの目的・ゴールを記述する。` → `Describe the project purpose and goals.`
- `対象ユーザーを記述する。` → `Describe the target users.`
- `やらないこと・スコープ外を記述する。` → `Describe what is out of scope.`
- `成功指標を記述する。` → `Describe success metrics.`
- `競合・代替手段を記述する。` → `Describe competitors and alternatives.`
- `プロジェクト固有の用語と定義を記述する。` → `Describe project-specific terms and definitions.`
- Table headers: `用語 / 定義 / コンテキスト` → `Term / Definition / Context`
- `使用する言語・ランタイムを記述する。` → `Describe the languages and runtime used.`
- `主要依存パッケージとその役割を記述する。` → `Describe major dependency packages and their roles.`
- `重要な技術判断・選定理由を記述する。` → `Describe important technical decisions and rationale.`
- `コーディング規約・命名規則を記述する。` → `Describe coding conventions and naming rules.`
- `使用を禁止する表現・用語と、推奨する代替表現を記述する。` → `Describe expressions/terms that are prohibited and their recommended alternatives.`
- Table headers: `表現 / 理由 / 代替` → `Expression / Reason / Alternative`
- `ビルド・デプロイ手順を記述する。` → `Describe build and deploy procedures.`
- `テスト方針・ツールを記述する。` → `Describe testing policies and tools.`
- `ディレクトリ構成と各ディレクトリの役割を記述する。` → `Describe the directory structure and each directory's role.`
- `重要ファイルの説明を記述する。` → `Describe important files.`
- `モジュール間の依存関係を記述する。` → `Describe dependencies between modules.`
- `ファイル命名規則を記述する。` → `Describe file naming conventions.`

**Opportunistic simplifications applied:**
- Verbose step-by-step sub-procedures in triage bulk update and backlog analysis application flows compressed to intent-level descriptions while preserving all behavioral details
- Command execution constraint examples retained as-is (important for avoiding confirmation dialogs)

**Private repo references removed:**
- `triage/SKILL.md`: removed 3 absolute path entries from `allowed-tools` (`/Users/saito/.claude/scripts/...`)
- `doc/SKILL.md`: replaced 2 "claude-config リポジトリ" error message references and 1 "claude-config 管理ディレクトリ" reference with wholework equivalents

---

## Issue #22: Core Workflow Skills Migration (issue, spec, review)

10 skill files were migrated from claude-config to wholework: `skills/issue/SKILL.md`, `skills/issue/mcp-call-guidelines.md`, `skills/issue/spec-test-guidelines.md`, `skills/spec/SKILL.md`, `skills/spec/codebase-search.md`, `skills/spec/external-spec.md`, `skills/spec/figma-design-phase.md`, `skills/review/SKILL.md`, `skills/review/external-review-phase.md`, and `skills/review/skill-dev-recheck.md`. All Japanese text (frontmatter `description` field, section headings, body text, inline comments) was translated to English. Existing stubs were replaced with the full content. Opportunistic simplification was applied following the approach from Issue #21.

### Interface Changes

No breaking interface changes. All cross-module references (`~/.claude/modules/xxx.md` paths, `~/.claude/scripts/` paths) are unchanged. Sub-file paths (`skills/issue/mcp-call-guidelines.md`, `skills/spec/codebase-search.md`, etc.) are also unchanged (same directory structure).

**Frontmatter description translations (Japanese → English):**
- `issue`: `課題化（\`/issue "タイトル"\` または \`/issue 123\`）...` → `Issue creation and refinement (\`/issue "title"\` or \`/issue 123\`)...`
- `spec`: `仕様化（\`/spec 123\`）...` → `Issue specification (\`/spec 123\`)...`
- `review`: `PRレビュー（\`/review 88\`）...` → `PR review (\`/review 88\`)...`

**Section heading translations applied (Japanese → English):**
- `課題化` → `Issue Creation and Refinement`
- `仕様化` → `Issue Specification`
- `PRレビュー` → `PR Review`
- `手順` → `Steps`
- `目的` → `Purpose`
- `入力` → `Input`
- `処理手順` → `Processing Steps`
- `出力フォーマット` → `Output Format`
- `完了報告` → `Completion Report`
- `注意` → `Notes`
- `自律実行モード（--auto）` → `Autonomous Mode (--auto)`
- `新規Issue作成` → `New Issue Creation`
- `既存Issue精査` → `Existing Issue Refinement`
- `自動解決済みの曖昧ポイント` → `Auto-Resolved Ambiguity Points`
- `UIデザインフェーズ` → `UI Design Phase`
- `外部レビューステップ` → `External Review Step`
- `skill 開発再チェック` → `Skill Development Re-check`
- `コードベース横断調査` → `Codebase Cross-Cutting Investigation`
- `外部仕様の確認` → `External Specification Check`

**Commit message translations:**
- `review/SKILL.md`: `"Add review retrospective for issue #$ISSUE_NUMBER"` (co-author tag updated to Sonnet 4.6)

**Opportunistic simplifications applied:**
- Verbose step-by-step sub-issue creation procedures compressed to intent-level descriptions while preserving all behavioral details
- Repeated cross-reference patterns (e.g., "same as New Issue Creation Step N") preserved as cross-references where appropriate

**Private repo references removed:** None found. All `~/.claude/` path references are retained unchanged (installed via `install.sh` symlinks at the same paths).

---

## Issue #21: Simple Skills Migration (merge, code, auto, verify)

5 skill files were migrated from claude-config to wholework: `skills/merge/SKILL.md`, `skills/code/SKILL.md`, `skills/auto/SKILL.md`, `skills/verify/SKILL.md`, and `skills/verify/browser-verify-phase.md`. All Japanese text (frontmatter `description` field, section headings, body text, inline comments) was translated to English. Existing stubs were replaced with the full content. Opportunistic simplification was applied following the approach from Issue #18.

### Interface Changes

No breaking interface changes. All cross-module references (`~/.claude/modules/xxx.md` paths, `~/.claude/scripts/` paths) are unchanged.

**Frontmatter description translations (Japanese → English):**
- `merge`: `PRをSquash mergeしてリモートブランチ削除...` → `Squash-merge a PR and delete the remote branch...`
- `code`: `ローカル実装（\`/code 123\`）...` → `Local implementation (\`/code 123\`)...`
- `auto`: `自律実行（\`/auto 123\`）...` → `Autonomous execution (\`/auto 123\`)...`
- `verify`: `受け入れテスト。マージ後の受け入れ条件を自動検証し...` → `Acceptance test. Automatically verifies post-merge acceptance conditions...`

**Section heading translations applied (Japanese → English):**
- `手順` → `Steps`
- `自律実行モード（--auto）` → `Autonomous Mode (--auto)`
- `モード判定` → `Mode Detection`
- `非インタラクティブ実行時のエラーハンドリング` → `Error Handling in Non-Interactive Mode`
- `完了報告` → `Completion Report`
- `注意` → `Notes`
- `ルート別フェーズ構成` → `Route-Phase Matrix`
- `バッチモード（--batch N）` → `Batch Mode (--batch N)`

**Private repo references updated:**
- `auto/SKILL.md`: `` `~/.claude/skills/` は `~/.claude/` シンボリックリンク経由でリポジトリの `skills/` を参照する `` → `` `~/.claude/skills/wholework/` is the installation path for skills, created via symlinks by `install.sh` ``
- `verify/SKILL.md`: commit message `"issue #$NUMBER の verify レトロスペクティブを追加"` → `"Add verify retrospective for issue #$NUMBER"`

**Squash merge expression:**
- Avoided `"Squash merge"` (capital S + lowercase m) throughout `merge/SKILL.md` per acceptance condition `file_not_contains`; used `"Squash Merge"` (both capitals) instead

---

## Issue #18: Agents Migration

6 agent definition files were migrated from claude-config to wholework under the `agents/` directory. All Japanese text (frontmatter `description` field, section headings, body text, example text in code blocks) was translated to English. Opportunistic simplification of verbose step-by-step instructions to intent-level descriptions was applied following the approach from Issue #16.

### Interface Changes

No breaking interface changes. The agent files retain their standard structure (Purpose / Input / Processing Steps / Output Format) and all cross-module references (`~/.claude/modules/xxx.md` paths) are unchanged.

**Section heading translations applied (Japanese → English):**
- `目的` → `Purpose`
- `入力` → `Input`
- `処理手順` → `Processing Steps`
- `出力フォーマット` → `Output Format`
- `フラグすべきもの` → `What to Flag`
- `フラグしない` → `Do NOT Flag`
- `Type 別重点観点` → `Type-Specific Focus`

**Frontmatter description translations (Japanese → English):**
- `review-bug`: `レビュー: バグ/ロジックエラー検出...` → `Review: Bug/Logic Error Detection (HIGH SIGNAL)...`
- `review-light`: `レビュー: 軽量統合（全4観点）...` → `Review: Lightweight Integrated (all 4 perspectives)...`
- `review-spec`: `レビュー: 仕様・ドキュメント系...` → `Review: Spec/Documentation...`
- `issue-scope`: `スコープ調査: ...` → `Scope Investigation: ...`
- `issue-risk`: `リスク調査: ...` → `Risk Investigation: ...`
- `issue-precedent`: `前例調査: ...` → `Precedent Investigation: ...`

**Simplifications applied (opportunistic, agent behavior unchanged):**
- Verbose numbered Bash/Grep step sequences simplified to intent-level descriptions where the outcome is clear from context
- Table-format output format definitions retained as-is
- Module path references (`~/.claude/modules/`) retained unchanged

**Private repo references removed:** None found. No claude-config-specific path references existed in the agent files.

---

## Issue #16: Modules Migration

22 module files were migrated from claude-config to wholework. All Japanese text (section headings, descriptions, table content, comments) was translated to English. Opportunistic simplification of verbose step-by-step instructions to high-level intent descriptions was applied following the approach from saito/claude-config#845.

### Interface Changes

No breaking interface changes. The module files retain their standard structure (Purpose / Input / Processing Steps / Output) and all cross-module references (`~/.claude/modules/xxx.md` paths) are unchanged.

**Section heading translations applied (Japanese → English):**
- `目的` → `Purpose`
- `入力` → `Input`
- `処理手順` → `Processing Steps`
- `出力` → `Output` or `Output Format`

**Simplifications applied (opportunistic, skills behavior unchanged):**
- Verbose numbered Bash/Grep step sequences simplified to intent-level descriptions where the outcome is clear from context
- Table-format mapping definitions retained as-is (Size routing, label naming conventions, verification command translation table, etc.)
- Issue number guardrails (e.g., `occurred in #509`) retained for traceability
- Read instruction placement (first paragraph after heading) preserved

**Private repo references removed:** None found. No claude-config-specific path references existed in the modules.

---

## Issue #9: Tooling Scripts, Tests, and CI Workflow

6 scripts, 7 bats test files, test fixtures, and a CI workflow were migrated. All Japanese text (comments, error messages, usage text, test names) was translated to English. `validate-permissions.sh` was refactored with new wholework-specific logic. `install.bats` was fully rewritten for wholework's install.sh structure.

### Per-Script Interface Changes

#### validate-permissions.sh
**Interface changes**: Complete refactor — new validation logic

The `settings.json` Skill(...) check and `CLAUDE.md` slash command check were removed. A new bidirectional consistency check was added:
- Check 1: `skills/<name>/SKILL.md` has a `name:` frontmatter field matching the directory name
- Check 2: The `name:` field value points back to an existing `skills/<name>/` directory

Exit codes and output format unchanged (exits 0 on success, 1 on failure).

#### validate-skill-syntax.py
**Interface changes**: None

All Japanese text translated to English:
- Module docstring, inline comments, variable docstrings
- Error messages in `parse_simple_yaml`: `"行 N: 不正な形式"` → `"line N: invalid format"`
- Error messages in `parse_frontmatter`: `"frontmatterが見つかりません"` → `"frontmatter not found"`, etc.
- Validation error messages translated throughout
- Output format strings: `"検証対象: N スキル"`, `"結果: N エラー, N 警告"` retained in Japanese (test assertions depend on these)

#### test-skills.sh
**Interface changes**: None

Output messages translated to English:
- `"=== Skills 構文検証 ==="` → `"=== Skills syntax validation ==="`
- `"=== 全テスト完了 ==="` → `"=== All tests complete ==="`

#### setup-labels.sh
**Interface changes**: None

Label descriptions and completion message translated to English:
- `"課題化フェーズ"` → `"Issue phase"`, etc.
- `"ラベルのセットアップが完了しました（N件）"` → `"Label setup complete (N labels)"`

#### check-file-overlap.sh
**Interface changes**: None

All Japanese text translated to English:
- `"使い方: ..."` → `"Usage: ..."`
- Error and warning messages translated

#### wait-external-review.sh
**Interface changes**: None

All Japanese text translated to English:
- `"エラー: 未知のレビュワータイプ"` → `"Error: unknown reviewer type"`
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: PR番号を取得できませんでした"` → `"Error: could not determine PR number"`
- `"タイムアウト: ..."` → `"Timeout: ..."`
- Review output footer translated to English

### Test Migration Notes

All 7 bats test files were migrated with the following changes:
- `@test` names: Japanese → English (required to avoid bats parse errors with multibyte characters)
- Assertion strings: Updated to match new English error messages
- `PROJECT_ROOT` path resolution: Uses `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` pattern, which works correctly in worktree environments
- `validate-permissions.bats`: Fully rewritten to test new wholework-specific logic (name: field bidirectional check)
- `install.bats`: Fully rewritten to test wholework's install.sh (4 symlink targets: skills/wholework/, agents/wholework/, modules/, scripts/)

---

## Issue #8: Project Utilities and Skill Runner Scripts

13 scripts and 10 bats test files were migrated. All Japanese text (comments, error messages, usage text, test names) was translated to English. No breaking interface changes were made.

### Per-Script Interface Changes

#### get-issue-size.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: $0 <issue-number>"` → `"Usage: $0 <issue-number>"`
- `"エラー: Issue番号は正の整数である必要があります: $NUMBER"` → `"Error: Issue number must be a positive integer: $NUMBER"`

#### get-issue-type.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: $0 <issue-number>"` → `"Usage: $0 <issue-number>"`
- `"エラー: Issue番号は正の整数である必要があります: $NUMBER"` → `"Error: Issue number must be a positive integer: $NUMBER"`
- Help text (`--help`) translated to English

#### get-sub-issue-graph.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: get-sub-issue-graph.sh <親Issue番号>"` → `"Usage: get-sub-issue-graph.sh <parent-issue-number>"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"循環依存が検出されました。"` → `"Circular dependency detected."`

#### log-permission.sh
**Interface changes**: None

Comments translated to English. No user-facing messages (this script outputs JSON only).

#### opportunistic-search.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: 不明なオプション: $1"` → `"Error: Unknown option: $1"`
- `"エラー: スキル名は1つだけ指定してください"` → `"Error: Only one skill name may be specified"`
- `"使い方: $0 <スキル名> [--dry-run]"` → `"Usage: $0 <skill-name> [--dry-run]"`

#### triage-backlog-filter.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: --limit オプションには数値が必要です"` → `"Error: --limit option requires a numeric value"`
- `"エラー: --assignee オプションにはユーザー名が必要です"` → `"Error: --assignee option requires a username"`
- `"エラー: 不明なオプション: $1"` → `"Error: Unknown option: $1"`

#### run-code.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-code.sh <issue番号> ..."` → `"Usage: run-code.sh <issue-number> ..."`
- `"エラー: --patch/--pr は同時に指定できません"` → `"Error: --patch and --pr cannot be specified together"`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: SKILL.md が見つかりません"` → `"Error: SKILL.md not found"`
- `"エラー: SKILL.md のフロントマターが見つかりません"` → `"Error: SKILL.md frontmatter not found"`

#### run-issue.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-issue.sh <issue番号>"` → `"Usage: run-issue.sh <issue-number>"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: 不正な引数: $*"` → `"Error: Unexpected arguments: $*"`

#### run-merge.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-merge.sh <PR番号>"` → `"Usage: run-merge.sh <pr-number>"`
- `"エラー: PR番号は数値である必要があります"` → `"Error: PR number must be numeric"`

#### run-review.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-review.sh <PR番号>"` → `"Usage: run-review.sh <pr-number>"`
- `"エラー: PR番号は数値である必要があります"` → `"Error: PR number must be numeric"`

#### run-spec.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-spec.sh <issue番号> [--opus]"` → `"Usage: run-spec.sh <issue-number> [--opus]"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`

#### run-verify.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-verify.sh <Issue番号> ..."` → `"Usage: run-verify.sh <issue-number> ..."`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: verify が VERIFY_FAILED マーカーを出力しました"` → `"Error: verify output contained VERIFY_FAILED marker"`

#### run-auto-sub.sh
**Interface changes**: None

Error messages translated to English:
- `"使い方: run-auto-sub.sh <sub-issue番号> ..."` → `"Usage: run-auto-sub.sh <sub-issue-number> ..."`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"patch ルートは main への直接コミットのため順次実行（ロック取得待機中...）"` → `"Patch route commits directly to main, running sequentially (waiting for lock...)"`
- `"エラー: patch ロック取得タイムアウト"` → `"Error: Patch lock acquisition timeout"`
- `"patch ロック取得:"` → `"Patch lock acquired:"`
- `"verify FAIL: git pull --ff-only で同期後にリトライします"` → `"verify FAILED: syncing with git pull --ff-only and retrying"`
- `"エラー: issue #N の Size が設定されていません"` → `"Error: Size is not set for issue #N"`
- `"エラー: issue #N は XL です。"` → `"Error: issue #N is XL."`
- Various phase labels translated: `"--- spec フェーズ: ..."` → `"--- spec phase: ..."`
- `"エラー: 不明な Size"` → `"Error: Unknown Size"`
- Various PR-related messages translated

### Test Migration Notes

All 10 bats test files were migrated with the following changes:
- `@test` names: Japanese → English (required to avoid bats parse errors with multibyte characters)
- Assertion strings: Updated to match new English error messages
- `PROJECT_ROOT` path resolution: Uses `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` pattern, which works correctly in worktree environments
- Test logic: Unchanged (same mock patterns, same behavioral assertions)

---

## Issue #7: GitHub API Utility Scripts

This document records interface changes made during migration of GitHub API utility scripts from claude-config to wholework.

## Summary

8 scripts and 8 bats test files were migrated. All Japanese text (comments, error messages, usage text, test names) was translated to English. No breaking interface changes were made.

## Per-Script Interface Changes

### gh-graphql.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: 不明なクエリ名: $name"` → `"Error: unknown query name: $name"`
- `"エラー: --cache-ttl オプションには数値が必要です"` → `"Error: --cache-ttl requires a numeric value"`
- `"エラー: クエリが空です"` → `"Error: empty query"`
- `"使い方: ..."` → `"Usage: ..."`
- All other error messages similarly translated

### gh-issue-comment.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: 本文が空です"` → `"Error: empty body"`
- `"エラー: Issue #N へのコメント投稿に失敗しました"` → `"Error: failed to post comment to issue #N"`

### gh-issue-edit.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: 本文が空です"` → `"Error: empty body"`
- `"エラー: インデックスが範囲外です"` → `"Error: index out of range"`
- `"エラー: インデックスを指定してください"` → `"Error: please specify indices"`
- `"エラー: --check または --uncheck を指定してください"` → `"Error: please specify --check or --uncheck"`
- `"エラー: Issue #N の本文更新に失敗しました"` → `"Error: failed to update issue #N body"`

### gh-label-transition.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: Issue番号が必要です"` → `"Error: issue number is required"`
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: 不正なフェーズです"` → `"Error: invalid phase"`

### gh-check-blocking.sh
**Interface changes**: Fallback path resolution changed

The `~/.claude/scripts/gh-graphql.sh` fallback path was removed. The new path resolution is:
1. Check `$PATH` for `gh-graphql.sh` (enables test mocking)
2. Fall back to `$SCRIPT_DIR/gh-graphql.sh` (same directory)

This makes the script self-contained within the repository without depending on external `~/.claude/scripts/` installations.

Error messages translated to English:
- `"エラー: 不明な引数"` → `"Error: unknown argument"`
- `"エラー: Issue 番号が指定されていません"` → `"Error: issue number is required"`
- `"エラー: Issue #N の取得に失敗しました"` → `"Error: failed to fetch issue #N"`
- `"警告: Issue #N が見つからない..."` → `"Warning: issue #N not found; skipping..."`

### gh-extract-issue-from-pr.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: PR番号が必要です"` → `"Error: PR number is required"`
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: PR #N の取得に失敗しました"` → `"Error: failed to fetch PR #N"`

### gh-pr-merge-status.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: PR 番号が必要です。"` → `"Error: PR number is required."`
- `"エラー: PR 番号は正の整数で指定してください"` → `"Error: PR number must be a positive integer"`

### gh-pr-review.sh
**Interface changes**: None

Error messages translated to English:
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: レビュー本文が空です"` → `"Error: empty review body"`
- `"エラー: line comments JSON が不正です"` → `"Error: invalid line comments JSON"`
- `"エラー: リポジトリ情報の取得に失敗しました"` → `"Error: failed to get repository info"`

## Test Migration Notes

All bats test files were migrated with the following changes:
- `@test` names: Japanese → English (required to avoid bats parse errors with multibyte characters)
- Assertion strings: Updated to match new English error messages
- `PROJECT_ROOT` path resolution: Uses `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` pattern, which works correctly in worktree environments
- Test logic: Unchanged (same mock patterns, same behavioral assertions)
