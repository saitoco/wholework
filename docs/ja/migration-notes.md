# Migration Notes

---

## 英語変換チェックリスト

スクリプトを移行する際、すべての日本語テキストが英語に翻訳されていることを確認するためのチェックリストです。

### ソースファイル内の文字列

- [ ] コメント（inline および block）
- [ ] 変数名と関数名
- [ ] 文字列リテラル（エラーメッセージ、usage テキスト、ログ出力）
- [ ] ドキュメント文字列 / docstring

### テストでカバーされない出力文字列

テストアサーションが検証しない出力文字列は見落としやすいです。以下の各カテゴリを手動で監査してください:

- [ ] サマリー・結果行（例: `"検証対象: N スキル"`、`"結果: N エラー"`）
- [ ] 警告メッセージ
- [ ] 進捗インジケータとフェーズラベル
- [ ] ヘルプ / usage テキスト（`--help` の出力）
- [ ] 成功・完了メッセージ

### 網羅的な日本語残存チェック

移行後に、移行対象ファイル全体に残っている日本語文字を検出するために以下のコマンドを実行してください:

```bash
grep -rP "[\x{3000}-\x{9FFF}]" <path-to-migrated-files>
```

これは CJK 統合漢字ブロックと隣接レンジ（U+3000–U+9FFF）を網羅し、ひらがな、カタカナ、漢字、CJK 記号を含みます。マッチがあれば、マージ前に解決すべき未翻訳テキストを示します。

例 — すべての skill ファイルをスキャン:

```bash
grep -rP "[\x{3000}-\x{9FFF}]" skills/
```

### テスト

- [ ] `@test` 名が英語に翻訳されている（必須 — マルチバイト文字は bats のパースエラーを引き起こす）
- [ ] アサーション文字列が新しい英語メッセージと一致するよう更新されている

---

## パス置換の検証: `~/.claude/` と `$HOME/.claude/` の両方を確認する

パス置換タスクの受入条件を作成する際は、`~/.claude/` と `$HOME/.claude/` の **両方** の形式を検証してください。これら 2 つの表記は同じパスを指しますが、バイト列としては別物であり、片方のみを対象とするパターンは他方の出現を静かに見逃します。

### 背景

このガイドラインは Issue #31 の retrospective から抽出されました: `modules/adapter-resolver.md` に `$HOME/.claude/` 形式の参照が含まれていたにもかかわらず、`~/.claude/` 形式のみを対象とする受入条件 grep パターンがこれをすり抜けました。レビューフェーズで捕捉されましたが、この見落としは両形式チェックの標準化の必要性を示しました。

### 推奨 Grep パターン

パス置換タスクの受入条件や手動検証コマンドを書くときは、両形式にマッチするパターンを使用してください:

```bash
grep -rn '~/.claude/\|$HOME/.claude/' <path>
```

または extended regex で:

```bash
grep -rEn '(~|\$HOME)/.claude/' <path>
```

これは `~/.claude/`（チルダ形式）と `$HOME/.claude/`（環境変数形式）の両方を 1 パスで網羅します。

### パス置換の受入条件チェックリスト

`~/.claude/` パス参照の置換や監査を伴うタスクでは:

- [ ] 受入条件の grep パターンに `~/.claude/` と `$HOME/.claude/` の両方が含まれている
- [ ] 検証コマンドが単一形式のパターンではなく `grep -rn '~/.claude/\|$HOME/.claude/'`（または等価）を使用している
- [ ] 移行後チェックで両形式パターンがすべての移行ファイルに対して実行される

---

## Issue #23: ユーティリティ Skill 移行（triage、audit、doc）

7 ファイルを claude-config から wholework に移行しました: `skills/triage/SKILL.md`、`skills/audit/SKILL.md`、`skills/doc/SKILL.md`、`skills/doc/product-template.md`、`skills/doc/tech-template.md`、`skills/doc/structure-template.md`。すべての日本語テキスト（frontmatter の `description` フィールド、セクション見出し、本文、インラインコメント）を英語に翻訳しました。すべてのファイルは新規作成です。opportunistic な簡素化を適用しました。

### インターフェース変更

**Frontmatter description の翻訳（日本語 → 英語）:**
- `triage`: `Issueトリアージ。タイトル正規化・Type/Priority/Size/Value設定を自動化...` → `Issue triage. Automates title normalization, Type/Priority/Size/Value assignment...`
- `audit`: `ドキュメント×実装の乖離検出・Issue自動生成...` → `Detect documentation/implementation drift and auto-generate Issues...`
- `doc`: `プロジェクト基盤ドキュメント管理...` → `Project foundation document management...`

**allowed-tools の変更（triage）:**

`allowed-tools` から絶対パスを削除しました:
- `/Users/saito/.claude/scripts/triage-backlog-filter.sh:*` → 削除（`~/.claude/scripts/triage-backlog-filter.sh:*` のみ残す）
- `/Users/saito/.claude/scripts/gh-graphql.sh:*` → 削除（`~/.claude/scripts/gh-graphql.sh:*` のみ残す）
- `/Users/saito/.claude/scripts/gh-issue-comment.sh:*` → 削除（`~/.claude/scripts/gh-issue-comment.sh:*` のみ残す）

**セクション見出しの翻訳を適用（日本語 → 英語）:**
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

**ステップ番号の変更（triage）:**

ソースには分数ステップ `### 1.5. 重複候補検出` が含まれていました。これを `### Step 2: Duplicate Candidate Detection` にリネームし、以降のステップをすべて再番号付け（+1 オフセット）しました。Single Issue Execution セクションの最終的なステップ番号: Steps 1–10（ソース: Steps 1, 1.5, 2–9 → Steps 1–10 に正規化）。

**claude-config 参照の置換（doc）:**

エラーメッセージ内の "claude-config リポジトリ" 3 箇所を置換しました:
- `"エラー: テンプレートファイル ... が見つかりません。claude-config リポジトリが正しくセットアップされているか確認してください。"` → `"Error: template file ... not found. wholework is not correctly installed. Run install.sh first."`
- `"エラー: テンプレートファイルが見つかりません。claude-config リポジトリが正しくセットアップされているか確認してください。"` → `"Error: template file not found. wholework is not correctly installed. Run install.sh first."`

**Wholework 管理ディレクトリ参照（doc）:**

"claude-config 管理ディレクトリ: skills/、modules/、agents/" の 1 箇所を "wholework-managed directories: skills/, modules/, agents/" に置換しました。

**テンプレートファイル placeholder の翻訳（doc のサブテンプレート）:**

`product-template.md`、`tech-template.md`、`structure-template.md` 内のすべての日本語 placeholder テキストを英語に翻訳しました:
- `プロジェクトの目的・ゴールを記述する。` → `Describe the project purpose and goals.`
- `対象ユーザーを記述する。` → `Describe the target users.`
- `やらないこと・スコープ外を記述する。` → `Describe what is out of scope.`
- `成功指標を記述する。` → `Describe success metrics.`
- `競合・代替手段を記述する。` → `Describe competitors and alternatives.`
- `プロジェクト固有の用語と定義を記述する。` → `Describe project-specific terms and definitions.`
- テーブルヘッダ: `用語 / 定義 / コンテキスト` → `Term / Definition / Context`
- `使用する言語・ランタイムを記述する。` → `Describe the languages and runtime used.`
- `主要依存パッケージとその役割を記述する。` → `Describe major dependency packages and their roles.`
- `重要な技術判断・選定理由を記述する。` → `Describe important technical decisions and rationale.`
- `コーディング規約・命名規則を記述する。` → `Describe coding conventions and naming rules.`
- `使用を禁止する表現・用語と、推奨する代替表現を記述する。` → `Describe expressions/terms that are prohibited and their recommended alternatives.`
- テーブルヘッダ: `表現 / 理由 / 代替` → `Expression / Reason / Alternative`
- `ビルド・デプロイ手順を記述する。` → `Describe build and deploy procedures.`
- `テスト方針・ツールを記述する。` → `Describe testing policies and tools.`
- `ディレクトリ構成と各ディレクトリの役割を記述する。` → `Describe the directory structure and each directory's role.`
- `重要ファイルの説明を記述する。` → `Describe important files.`
- `モジュール間の依存関係を記述する。` → `Describe dependencies between modules.`
- `ファイル命名規則を記述する。` → `Describe file naming conventions.`

**opportunistic な簡素化:**
- triage の一括更新とバックログ分析の適用フローにおける冗長なステップ単位のサブ手順を、振る舞いの詳細を保ちつつ意図レベルの記述に圧縮
- コマンド実行制約の例はそのまま保持（確認ダイアログを回避するため重要）

**プライベートリポジトリ参照の削除:**
- `triage/SKILL.md`: `allowed-tools` から 3 件の絶対パスエントリを削除（`/Users/saito/.claude/scripts/...`）
- `doc/SKILL.md`: "claude-config リポジトリ" エラーメッセージ参照 2 件と "claude-config 管理ディレクトリ" 参照 1 件を wholework 相当に置換

---

## Issue #22: コアワークフロー Skill 移行（issue、spec、review）

10 の skill ファイルを claude-config から wholework に移行しました: `skills/issue/SKILL.md`、`skills/issue/mcp-call-guidelines.md`、`skills/issue/spec-test-guidelines.md`、`skills/spec/SKILL.md`、`skills/spec/codebase-search.md`、`skills/spec/external-spec.md`、`skills/spec/figma-design-phase.md`、`skills/review/SKILL.md`、`skills/review/external-review-phase.md`、`skills/review/skill-dev-recheck.md`。すべての日本語テキスト（frontmatter の `description` フィールド、セクション見出し、本文、インラインコメント）を英語に翻訳しました。既存の stub を完全な内容に置き換えました。Issue #21 のアプローチに従って opportunistic な簡素化を適用しました。

### インターフェース変更

Breaking なインターフェース変更はありません。すべてのクロスモジュール参照（`~/.claude/modules/xxx.md` パス、`~/.claude/scripts/` パス）は変更なしです。サブファイルパス（`skills/issue/mcp-call-guidelines.md`、`skills/spec/codebase-search.md` など）も変更なし（同じディレクトリ構造）です。

**Frontmatter description の翻訳（日本語 → 英語）:**
- `issue`: `課題化（\`/issue "タイトル"\` または \`/issue 123\`）...` → `Issue creation and refinement (\`/issue "title"\` or \`/issue 123\`)...`
- `spec`: `仕様化（\`/spec 123\`）...` → `Issue specification (\`/spec 123\`)...`
- `review`: `PRレビュー（\`/review 88\`）...` → `PR review (\`/review 88\`)...`

**セクション見出しの翻訳を適用（日本語 → 英語）:**
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

**コミットメッセージの翻訳:**
- `review/SKILL.md`: `"Add review retrospective for issue #$ISSUE_NUMBER"`（co-author タグを Sonnet 4.6 に更新）

**opportunistic な簡素化:**
- 冗長なステップ単位のサブ Issue 作成手順を、振る舞いの詳細を保ちつつ意図レベルの記述に圧縮
- 繰り返しのクロスリファレンスパターン（例: "same as New Issue Creation Step N"）は適切な箇所でクロスリファレンスとして保持

**プライベートリポジトリ参照の削除:** なし。すべての `~/.claude/` パス参照は変更なしで保持されます（`install.sh` が同じパスにシンボリックリンクでインストールします）。

---

## Issue #21: シンプル Skill 移行（merge、code、auto、verify）

5 の skill ファイルを claude-config から wholework に移行しました: `skills/merge/SKILL.md`、`skills/code/SKILL.md`、`skills/auto/SKILL.md`、`skills/verify/SKILL.md`、`skills/verify/browser-verify-phase.md`。すべての日本語テキスト（frontmatter の `description` フィールド、セクション見出し、本文、インラインコメント）を英語に翻訳しました。既存の stub を完全な内容に置き換えました。Issue #18 のアプローチに従って opportunistic な簡素化を適用しました。

### インターフェース変更

Breaking なインターフェース変更はありません。すべてのクロスモジュール参照（`~/.claude/modules/xxx.md` パス、`~/.claude/scripts/` パス）は変更なしです。

**Frontmatter description の翻訳（日本語 → 英語）:**
- `merge`: `PRをSquash mergeしてリモートブランチ削除...` → `Squash-merge a PR and delete the remote branch...`
- `code`: `ローカル実装（\`/code 123\`）...` → `Local implementation (\`/code 123\`)...`
- `auto`: `自律実行（\`/auto 123\`）...` → `Autonomous execution (\`/auto 123\`)...`
- `verify`: `受け入れテスト。マージ後の受け入れ条件を自動検証し...` → `Acceptance test. Automatically verifies post-merge acceptance conditions...`

**セクション見出しの翻訳を適用（日本語 → 英語）:**
- `手順` → `Steps`
- `自律実行モード（--auto）` → `Autonomous Mode (--auto)`
- `モード判定` → `Mode Detection`
- `非インタラクティブ実行時のエラーハンドリング` → `Error Handling in Non-Interactive Mode`
- `完了報告` → `Completion Report`
- `注意` → `Notes`
- `ルート別フェーズ構成` → `Route-Phase Matrix`
- `バッチモード（--batch N）` → `Batch Mode (--batch N)`

**プライベートリポジトリ参照の更新:**
- `auto/SKILL.md`: `` `~/.claude/skills/` は `~/.claude/` シンボリックリンク経由でリポジトリの `skills/` を参照する `` → `` `~/.claude/skills/wholework/` is the installation path for skills, created via symlinks by `install.sh` ``
- `verify/SKILL.md`: コミットメッセージ `"issue #$NUMBER の verify レトロスペクティブを追加"` → `"Add verify retrospective for issue #$NUMBER"`

**Squash merge 表現:**
- 受入条件 `file_not_contains` に従い、`merge/SKILL.md` 全体で `"Squash merge"`（大文字 S + 小文字 m）を避け、代わりに `"Squash Merge"`（両方大文字）を使用

---

## Issue #18: エージェント移行

6 のエージェント定義ファイルを claude-config から wholework の `agents/` ディレクトリ配下に移行しました。すべての日本語テキスト（frontmatter の `description` フィールド、セクション見出し、本文、コードブロック内の例示テキスト）を英語に翻訳しました。Issue #16 のアプローチに従って、冗長なステップ単位の指示を意図レベルの記述に opportunistic に簡素化しました。

### インターフェース変更

Breaking なインターフェース変更はありません。エージェントファイルは標準構造（Purpose / Input / Processing Steps / Output Format）を維持し、すべてのクロスモジュール参照（`~/.claude/modules/xxx.md` パス）は変更なしです。

**セクション見出しの翻訳を適用（日本語 → 英語）:**
- `目的` → `Purpose`
- `入力` → `Input`
- `処理手順` → `Processing Steps`
- `出力フォーマット` → `Output Format`
- `フラグすべきもの` → `What to Flag`
- `フラグしない` → `Do NOT Flag`
- `Type 別重点観点` → `Type-Specific Focus`

**Frontmatter description の翻訳（日本語 → 英語）:**
- `review-bug`: `レビュー: バグ/ロジックエラー検出...` → `Review: Bug/Logic Error Detection (HIGH SIGNAL)...`
- `review-light`: `レビュー: 軽量統合（全4観点）...` → `Review: Lightweight Integrated (all 4 perspectives)...`
- `review-spec`: `レビュー: 仕様・ドキュメント系...` → `Review: Spec/Documentation...`
- `scope-agent`: `スコープ調査: ...` → `Scope Investigation: ...`
- `risk-agent`: `リスク調査: ...` → `Risk Investigation: ...`
- `precedent-agent`: `前例調査: ...` → `Precedent Investigation: ...`

**簡素化の適用（opportunistic、エージェント挙動は不変）:**
- 振る舞いが文脈から明確な場合、冗長な番号付き Bash/Grep ステップ列を意図レベルの記述に簡素化
- テーブル形式の出力フォーマット定義はそのまま保持
- モジュールパス参照（`~/.claude/modules/`）は変更なしで保持

**プライベートリポジトリ参照の削除:** なし。エージェントファイルには claude-config 固有のパス参照は存在しませんでした。

---

## Issue #16: モジュール移行

22 のモジュールファイルを claude-config から wholework に移行しました。すべての日本語テキスト（セクション見出し、説明、テーブル内容、コメント）を英語に翻訳しました。saito/claude-config#845 のアプローチに従って、冗長なステップ単位の指示を高レベルの意図記述に opportunistic に簡素化しました。

### インターフェース変更

Breaking なインターフェース変更はありません。モジュールファイルは標準構造（Purpose / Input / Processing Steps / Output）を維持し、すべてのクロスモジュール参照（`~/.claude/modules/xxx.md` パス）は変更なしです。

**セクション見出しの翻訳を適用（日本語 → 英語）:**
- `目的` → `Purpose`
- `入力` → `Input`
- `処理手順` → `Processing Steps`
- `出力` → `Output` または `Output Format`

**簡素化の適用（opportunistic、Skill 挙動は不変）:**
- 振る舞いが文脈から明確な場合、冗長な番号付き Bash/Grep ステップ列を意図レベルの記述に簡素化
- テーブル形式のマッピング定義はそのまま保持（Size ルーティング、ラベル命名規則、検証コマンド変換テーブルなど）
- Issue 番号によるガードレール（例: `occurred in #509`）はトレーサビリティのために保持
- Read 指示の配置（見出し直後の最初の段落）を保持

**プライベートリポジトリ参照の削除:** なし。モジュールには claude-config 固有のパス参照は存在しませんでした。

---

## Issue #9: ツールスクリプト、テスト、CI ワークフロー

6 のスクリプト、7 の bats テストファイル、テストフィクスチャ、CI ワークフローを移行しました。すべての日本語テキスト（コメント、エラーメッセージ、usage テキスト、テスト名）を英語に翻訳しました。`validate-permissions.sh` は新しい wholework 固有ロジックでリファクタリングしました。`install.bats` は wholework の install.sh 構造用に完全に書き直しました。

### スクリプト別インターフェース変更

#### validate-permissions.sh
**インターフェース変更**: 完全リファクタ — 新しい検証ロジック

`settings.json` の Skill(...) チェックと `CLAUDE.md` スラッシュコマンドチェックを削除しました。新しい双方向整合性チェックを追加:
- Check 1: `skills/<name>/SKILL.md` がディレクトリ名と一致する `name:` frontmatter フィールドを持つ
- Check 2: `name:` フィールドの値が既存の `skills/<name>/` ディレクトリを指す

Exit code と出力フォーマットは不変（成功時 0、失敗時 1）。

#### validate-skill-syntax.py
**インターフェース変更**: なし

すべての日本語テキストを英語に翻訳:
- モジュール docstring、インラインコメント、変数 docstring
- `parse_simple_yaml` のエラーメッセージ: `"行 N: 不正な形式"` → `"line N: invalid format"`
- `parse_frontmatter` のエラーメッセージ: `"frontmatterが見つかりません"` → `"frontmatter not found"` など
- 検証エラーメッセージを全体で翻訳
- 出力フォーマット文字列: `"検証対象: N スキル"`、`"結果: N エラー, N 警告"` は日本語のまま保持（テストアサーションがこれらに依存するため）

#### test-skills.sh
**インターフェース変更**: なし

出力メッセージを英語に翻訳:
- `"=== Skills 構文検証 ==="` → `"=== Skills syntax validation ==="`
- `"=== 全テスト完了 ==="` → `"=== All tests complete ==="`

#### setup-labels.sh
**インターフェース変更**: なし

ラベル説明と完了メッセージを英語に翻訳:
- `"課題化フェーズ"` → `"Issue phase"` など
- `"ラベルのセットアップが完了しました（N件）"` → `"Label setup complete (N labels)"`

#### check-file-overlap.sh
**インターフェース変更**: なし

すべての日本語テキストを英語に翻訳:
- `"使い方: ..."` → `"Usage: ..."`
- エラー・警告メッセージを翻訳

#### wait-external-review.sh
**インターフェース変更**: なし

すべての日本語テキストを英語に翻訳:
- `"エラー: 未知のレビュワータイプ"` → `"Error: unknown reviewer type"`
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: PR番号を取得できませんでした"` → `"Error: could not determine PR number"`
- `"タイムアウト: ..."` → `"Timeout: ..."`
- レビュー出力フッタを英語に翻訳

### テスト移行メモ

7 の bats テストファイルすべてを以下の変更で移行しました:
- `@test` 名: 日本語 → 英語（マルチバイト文字による bats パースエラー回避のために必須）
- アサーション文字列: 新しい英語エラーメッセージに一致するよう更新
- `PROJECT_ROOT` パス解決: worktree 環境で正しく動作する `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` パターンを使用
- `validate-permissions.bats`: 新しい wholework 固有ロジック（name: フィールドの双方向チェック）をテストするよう完全に書き直し
- `install.bats`: wholework の install.sh をテストするよう完全に書き直し（4 つのシンボリックリンクターゲット: skills/wholework/、agents/wholework/、modules/、scripts/）

---

## Issue #8: プロジェクトユーティリティと Skill ランナースクリプト

13 のスクリプトと 10 の bats テストファイルを移行しました。すべての日本語テキスト（コメント、エラーメッセージ、usage テキスト、テスト名）を英語に翻訳しました。Breaking なインターフェース変更はありません。

### スクリプト別インターフェース変更

#### get-issue-size.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: $0 <issue-number>"` → `"Usage: $0 <issue-number>"`
- `"エラー: Issue番号は正の整数である必要があります: $NUMBER"` → `"Error: Issue number must be a positive integer: $NUMBER"`

#### get-issue-type.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: $0 <issue-number>"` → `"Usage: $0 <issue-number>"`
- `"エラー: Issue番号は正の整数である必要があります: $NUMBER"` → `"Error: Issue number must be a positive integer: $NUMBER"`
- ヘルプテキスト（`--help`）を英語に翻訳

#### get-sub-issue-graph.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: get-sub-issue-graph.sh <親Issue番号>"` → `"Usage: get-sub-issue-graph.sh <parent-issue-number>"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"循環依存が検出されました。"` → `"Circular dependency detected."`

#### log-permission.sh
**インターフェース変更**: なし

コメントを英語に翻訳。ユーザ向けメッセージなし（このスクリプトは JSON のみを出力）。

#### opportunistic-search.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: 不明なオプション: $1"` → `"Error: Unknown option: $1"`
- `"エラー: スキル名は1つだけ指定してください"` → `"Error: Only one skill name may be specified"`
- `"使い方: $0 <スキル名> [--dry-run]"` → `"Usage: $0 <skill-name> [--dry-run]"`

#### triage-backlog-filter.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: --limit オプションには数値が必要です"` → `"Error: --limit option requires a numeric value"`
- `"エラー: --assignee オプションにはユーザー名が必要です"` → `"Error: --assignee option requires a username"`
- `"エラー: 不明なオプション: $1"` → `"Error: Unknown option: $1"`

#### run-code.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: run-code.sh <issue番号> ..."` → `"Usage: run-code.sh <issue-number> ..."`
- `"エラー: --patch/--pr は同時に指定できません"` → `"Error: --patch and --pr cannot be specified together"`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: SKILL.md が見つかりません"` → `"Error: SKILL.md not found"`
- `"エラー: SKILL.md のフロントマターが見つかりません"` → `"Error: SKILL.md frontmatter not found"`

#### run-issue.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: run-issue.sh <issue番号>"` → `"Usage: run-issue.sh <issue-number>"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: 不正な引数: $*"` → `"Error: Unexpected arguments: $*"`

#### run-merge.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: run-merge.sh <PR番号>"` → `"Usage: run-merge.sh <pr-number>"`
- `"エラー: PR番号は数値である必要があります"` → `"Error: PR number must be numeric"`

#### run-review.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: run-review.sh <PR番号>"` → `"Usage: run-review.sh <pr-number>"`
- `"エラー: PR番号は数値である必要があります"` → `"Error: PR number must be numeric"`

#### run-spec.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: run-spec.sh <issue番号> [--opus]"` → `"Usage: run-spec.sh <issue-number> [--opus]"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`

#### run-verify.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"使い方: run-verify.sh <Issue番号> ..."` → `"Usage: run-verify.sh <issue-number> ..."`
- `"エラー: Issue番号は数値である必要があります"` → `"Error: Issue number must be numeric"`
- `"エラー: --base にはブランチ名が必要です"` → `"Error: --base requires a branch name"`
- `"エラー: 不正なオプション: $1"` → `"Error: Invalid option: $1"`
- `"エラー: verify が VERIFY_FAILED マーカーを出力しました"` → `"Error: verify output contained VERIFY_FAILED marker"`

#### run-auto-sub.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
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
- さまざまなフェーズラベルを翻訳: `"--- spec フェーズ: ..."` → `"--- spec phase: ..."`
- `"エラー: 不明な Size"` → `"Error: Unknown Size"`
- さまざまな PR 関連メッセージを翻訳

### テスト移行メモ

10 の bats テストファイルすべてを以下の変更で移行しました:
- `@test` 名: 日本語 → 英語（マルチバイト文字による bats パースエラー回避のために必須）
- アサーション文字列: 新しい英語エラーメッセージに一致するよう更新
- `PROJECT_ROOT` パス解決: worktree 環境で正しく動作する `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` パターンを使用
- テストロジック: 不変（同じ mock パターン、同じ振る舞いのアサーション）

---

## Issue #7: GitHub API ユーティリティスクリプト

このドキュメントは、GitHub API ユーティリティスクリプトを claude-config から wholework に移行する際に行ったインターフェース変更を記録しています。

## サマリー

8 のスクリプトと 8 の bats テストファイルを移行しました。すべての日本語テキスト（コメント、エラーメッセージ、usage テキスト、テスト名）を英語に翻訳しました。Breaking なインターフェース変更はありません。

## スクリプト別インターフェース変更

### gh-graphql.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: 不明なクエリ名: $name"` → `"Error: unknown query name: $name"`
- `"エラー: --cache-ttl オプションには数値が必要です"` → `"Error: --cache-ttl requires a numeric value"`
- `"エラー: クエリが空です"` → `"Error: empty query"`
- `"使い方: ..."` → `"Usage: ..."`
- その他のエラーメッセージも同様に翻訳

### gh-issue-comment.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: 本文が空です"` → `"Error: empty body"`
- `"エラー: Issue #N へのコメント投稿に失敗しました"` → `"Error: failed to post comment to issue #N"`

### gh-issue-edit.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: 本文が空です"` → `"Error: empty body"`
- `"エラー: インデックスが範囲外です"` → `"Error: index out of range"`
- `"エラー: インデックスを指定してください"` → `"Error: please specify indices"`
- `"エラー: --check または --uncheck を指定してください"` → `"Error: please specify --check or --uncheck"`
- `"エラー: Issue #N の本文更新に失敗しました"` → `"Error: failed to update issue #N body"`

### gh-label-transition.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: Issue番号が必要です"` → `"Error: issue number is required"`
- `"エラー: Issue番号は正の整数である必要があります"` → `"Error: issue number must be a positive integer"`
- `"エラー: 不正なフェーズです"` → `"Error: invalid phase"`

### gh-check-blocking.sh
**インターフェース変更**: フォールバックパス解決が変更

`~/.claude/scripts/gh-graphql.sh` フォールバックパスを削除しました。新しいパス解決は以下のとおり:
1. `$PATH` を `gh-graphql.sh` でチェック（テストモックを有効化）
2. `$SCRIPT_DIR/gh-graphql.sh`（同じディレクトリ）にフォールバック

これにより、スクリプトは外部の `~/.claude/scripts/` インストールに依存せず、リポジトリ内で自己完結します。

エラーメッセージを英語に翻訳:
- `"エラー: 不明な引数"` → `"Error: unknown argument"`
- `"エラー: Issue 番号が指定されていません"` → `"Error: issue number is required"`
- `"エラー: Issue #N の取得に失敗しました"` → `"Error: failed to fetch issue #N"`
- `"警告: Issue #N が見つからない..."` → `"Warning: issue #N not found; skipping..."`

### gh-extract-issue-from-pr.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: PR番号が必要です"` → `"Error: PR number is required"`
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: PR #N の取得に失敗しました"` → `"Error: failed to fetch PR #N"`

### gh-pr-merge-status.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: PR 番号が必要です。"` → `"Error: PR number is required."`
- `"エラー: PR 番号は正の整数で指定してください"` → `"Error: PR number must be a positive integer"`

### gh-pr-review.sh
**インターフェース変更**: なし

エラーメッセージを英語に翻訳:
- `"エラー: PR番号は正の整数である必要があります"` → `"Error: PR number must be a positive integer"`
- `"エラー: ファイルが見つかりません"` → `"Error: file not found"`
- `"エラー: レビュー本文が空です"` → `"Error: empty review body"`
- `"エラー: line comments JSON が不正です"` → `"Error: invalid line comments JSON"`
- `"エラー: リポジトリ情報の取得に失敗しました"` → `"Error: failed to get repository info"`

## テスト移行メモ

すべての bats テストファイルを以下の変更で移行しました:
- `@test` 名: 日本語 → 英語（マルチバイト文字による bats パースエラー回避のために必須）
- アサーション文字列: 新しい英語エラーメッセージに一致するよう更新
- `PROJECT_ROOT` パス解決: worktree 環境で正しく動作する `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` パターンを使用
- テストロジック: 不変（同じ mock パターン、同じ振る舞いのアサーション）
