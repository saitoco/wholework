# Issue #9: scripts: Migrate tooling scripts, add CI workflow

## 概要

wholework に tooling・検証スクリプト 6 本とテスト（7 bats ファイル + fixtures）を移植し、GitHub Actions CI ワークフローを追加する。

- `validate-permissions.sh`: wholework 向けリファクタリング（settings.json/CLAUDE.md チェックを削除し、`skills/<name>/SKILL.md` と `name:` フロントマターフィールドの双方向整合性チェックに変更）
- `validate-skill-syntax.py`, `test-skills.sh`, `setup-labels.sh`, `check-file-overlap.sh`, `wait-external-review.sh`: 英訳のみ（インターフェース変更なし）
- `install.bats`: wholework の 4 ターゲット symlink 構造向けに全面書き直し
- CI ワークフロー: `bats tests/` を GitHub Actions で自動実行

## 変更対象ファイル

**新規作成（スクリプト 6 本）:**
- `scripts/validate-permissions.sh`: 新規作成（wholework 向けリファクタリング済み）
- `scripts/validate-skill-syntax.py`: 新規作成（日本語→英語翻訳済み）
- `scripts/test-skills.sh`: 新規作成（日本語→英語翻訳済み）
- `scripts/setup-labels.sh`: 新規作成（日本語→英語翻訳済み）
- `scripts/check-file-overlap.sh`: 新規作成（日本語→英語翻訳済み）
- `scripts/wait-external-review.sh`: 新規作成（日本語→英語翻訳済み）

**新規作成（テスト 7 本 + fixtures）:**
- `tests/validate-permissions.bats`: 新規作成（リファクタリング済み validate-permissions.sh に対応）
- `tests/validate-skill-syntax.bats`: 新規作成（日本語→英語翻訳済み）
- `tests/test-skills.bats`: 新規作成（日本語→英語翻訳済み）
- `tests/setup-labels.bats`: 新規作成（日本語→英語翻訳済み）
- `tests/wait-external-review.bats`: 新規作成（日本語→英語翻訳済み）
- `tests/install.bats`: 新規作成（全面書き直し）
- `tests/spec-verification-hints.bats`: 新規作成（日本語→英語翻訳済み）
- `tests/fixtures/browser-verify-test.html`: 新規作成（直接コピー）

**新規作成（CI）:**
- `.github/workflows/test.yml`: 新規作成（bats テスト全量自動実行）

**更新:**
- `docs/structure.md`: `tests/fixtures/` ディレクトリエントリ追加
- `docs/migration-notes.md`: Issue #9 の migration notes セクション追加

## 実装ステップ

1. 6 スクリプトを移植する。`validate-skill-syntax.py` / `test-skills.sh` / `setup-labels.sh` / `check-file-overlap.sh` / `wait-external-review.sh` は日本語テキスト（コメント、エラーメッセージ、ヘルプテキスト）を英訳して `scripts/` に配置する。`validate-permissions.sh` は以下の通りリファクタリングする:
   - `settings.json` の `Skill(...)` チェックを削除（wholework は settings.json を持たない）
   - `CLAUDE.md` のスラッシュコマンドチェックを削除（wholework の CLAUDE.md は同形式ではない）
   - 新規チェック追加: `skills/<name>/SKILL.md` が `name: <name>` フロントマターフィールドを持つかの双方向整合性チェック（ディレクトリ名と name: フィールドの一致）
   （→ 受け入れ条件: scripts 6 本の存在）

2. テスト 7 本を移植する。`validate-skill-syntax.bats` / `test-skills.bats` / `setup-labels.bats` / `wait-external-review.bats` / `spec-verification-hints.bats` は `@test` 名とアサーション文字列を英訳し `tests/` に配置する。`validate-permissions.bats` は新しい validate-permissions.sh のロジック（スキル名と `name:` フィールドの双方向整合性）に合わせて書き直す。`install.bats` は wholework の install.sh（4 ターゲット: `skills/wholework/`, `agents/wholework/`, `modules/`, `scripts/`）向けに全面書き直しする（クリーンインストール・アンインストールの動作をテスト）。`tests/fixtures/browser-verify-test.html` を直接コピーする。
   （→ 受け入れ条件: tests 7 本・fixtures の存在）

3. `.github/workflows/test.yml` を新規作成する。`ubuntu-latest` で `bats` と `python3` をセットアップし、`bats tests/` を実行するワークフローを定義する。トリガーは `push` と `pull_request`。
   （→ 受け入れ条件: CI ワークフローの存在と bats 実行設定）

4. `docs/structure.md` に `tests/fixtures/` エントリを追加し、`docs/migration-notes.md` に Issue #9 のセクション（スクリプト 6 本のインターフェース変更概要）を追記する。
   （→ 受け入れ条件: docs/structure.md の tests/ 記載、migration-notes.md の更新）

5. `bats tests/` をローカルで実行し、全テストが PASS することを確認する。FAIL したテストは修正する。
   （→ 受け入れ条件: bats tests/ PASS）

## 検証方法

### マージ前

<!-- verify ヒントは受け入れ条件 15 件を 5 件のグルーピングパターンで集約 -->

- <!-- verify: file_exists "scripts/validate-permissions.sh" --> `scripts/validate-permissions.sh` が移植されている
- <!-- verify: file_exists ".github/workflows/test.yml" --> bats テスト実行用の CI ワークフローが作成されている
- <!-- verify: command "for f in scripts/validate-skill-syntax.py scripts/test-skills.sh scripts/setup-labels.sh scripts/check-file-overlap.sh scripts/wait-external-review.sh tests/validate-permissions.bats tests/install.bats tests/spec-verification-hints.bats tests/fixtures/browser-verify-test.html; do [ -f \"$f\" ] || { echo \"missing: $f\"; exit 1; }; done && echo 'all files present'" --> 全スクリプト・テスト・fixtures が存在する
- <!-- verify: grep "bats" ".github/workflows/test.yml" --> CI ワークフローで bats テストが実行される設定になっている
- <!-- verify: command "bats tests/" --> 全 bats テストがローカルで PASS する

### マージ後

- GitHub Actions で bats テストが自動実行され、全て PASS することを確認 <!-- verify-type: auto -->
<!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->

## 注意事項

- `validate-permissions.sh` の新ロジック: `skills/<name>/SKILL.md` の `name:` フィールドがディレクトリ名と一致するかを双方向チェックする（ディレクトリ名 → SKILL.md name: チェック、name: フィールド → ディレクトリ存在チェック）。settings.json と CLAUDE.md のチェックは削除する。
- `install.bats`: wholework の install.sh は `$HOME/.claude/skills/wholework/` 配下に個別スキルの symlink を作成する構造。claude-config の install.bats（9 本 symlink + backup 機能）とは根本的に異なるため全面書き直し。テストする主要動作: (1) `skills/wholework/` 実ディレクトリ作成、(2) 各スキルの symlink 作成、(3) `agents/wholework/`・`modules/`・`scripts/` の symlink 作成、(4) `--uninstall` による削除。
- `tests/` の `@test` 名は英語のみ使用すること（bats はマルチバイト文字のテスト名を処理できない）。
- `PROJECT_ROOT` パス解決は `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` パターンを使用すること（worktree 環境で正しく動作する）。
- `tests/fixtures/scripts/` サブディレクトリ（claude-config の tests/fixtures/scripts/get-sub-issue-graph.bats）は wholework には不要。`browser-verify-test.html` のみを移植する。
- スクリプト内の全日本語テキスト（コメント、エラーメッセージ、ヘルプテキスト、変数名等）を英語に翻訳すること（CLAUDE.md の "English conversion" ガイドラインに準拠）。
