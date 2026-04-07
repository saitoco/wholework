# Issue #7: scripts: Migrate GitHub API utility scripts and tests

## 概要

親 Issue #6 の sub-issue。claude-config リポジトリから GitHub API ユーティリティスクリプト 8 本と対応する bats テスト 8 本を wholework に移植する。Migration Guidelines（CLAUDE.md）に従い、日本語テキストの英語化、ハードコードされたパスの除去、汎用化を行う。

これらのスクリプト（特に gh-graphql.sh）は他の全スクリプト（run-\*.sh, get-issue-\*.sh 等）の基盤となるため、移植の第1弾として実施する。

## 変更対象ファイル

### 新規作成（16 files）

**scripts/**（8 files）:
- `scripts/gh-graphql.sh`: 新規作成（claude-config から移植・英語化）
- `scripts/gh-issue-comment.sh`: 新規作成（claude-config から移植・英語化）
- `scripts/gh-issue-edit.sh`: 新規作成（claude-config から移植・英語化）
- `scripts/gh-label-transition.sh`: 新規作成（claude-config から移植・英語化）
- `scripts/gh-check-blocking.sh`: 新規作成（claude-config から移植・英語化・フォールバックパス除去）
- `scripts/gh-extract-issue-from-pr.sh`: 新規作成（claude-config から移植・英語化）
- `scripts/gh-pr-merge-status.sh`: 新規作成（claude-config から移植・英語化）
- `scripts/gh-pr-review.sh`: 新規作成（claude-config から移植・英語化）

**tests/**（8 files）:
- `tests/gh-graphql.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-issue-comment.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-issue-edit.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-label-transition.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-check-blocking.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-extract-issue-from-pr.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-pr-merge-status.bats`: 新規作成（claude-config から移植・英語化）
- `tests/gh-pr-review.bats`: 新規作成（claude-config から移植・英語化）

**docs/**（1 file）:
- `docs/migration-notes.md`: 新規作成（インターフェース変更記録）

## 実装ステップ

### Step 1: ディレクトリ作成とベーススクリプト移植（→ 受け入れ条件A, J）

1. `scripts/` と `tests/` ディレクトリを作成する
2. `gh-graphql.sh` を claude-config（`~/src/claude-config/scripts/gh-graphql.sh`）からコピーし、以下を実施:
   - 日本語コメント・エラーメッセージ・usage を英語に変換
   - 変数名・関数名は英語のため変更不要
   - `#!/bin/bash` shebang と `set -euo pipefail` を維持
3. `tests/gh-graphql.bats` を claude-config からコピーし、以下を実施:
   - 日本語テスト名（`@test` 行）を英語に変換
   - 日本語アサーション文字列を英語に変換
   - テストの `PROJECT_ROOT` パス設定がリポジトリルートを正しく指すことを確認
4. `bats tests/gh-graphql.bats` でテスト PASS を確認

### Step 2: Issue 操作スクリプト移植（Step 1 の後）（→ 受け入れ条件B, C, D）

1. 以下3スクリプトを claude-config からコピーし英語化:
   - `scripts/gh-issue-comment.sh`
   - `scripts/gh-issue-edit.sh`
   - `scripts/gh-label-transition.sh`
2. 対応する bats テスト3本をコピーし英語化:
   - `tests/gh-issue-comment.bats`
   - `tests/gh-issue-edit.bats`
   - `tests/gh-label-transition.bats`
3. `bats tests/gh-label-transition.bats` でテスト PASS を確認

### Step 3: gh-check-blocking.sh 移植とフォールバックパス除去（Step 1 の後）（→ 受け入れ条件E, K）

1. `scripts/gh-check-blocking.sh` を claude-config からコピーし英語化
2. `~/.claude/scripts/gh-graphql.sh` フォールバックパスを削除し、`$SCRIPT_DIR/gh-graphql.sh` に統一
3. `tests/gh-check-blocking.bats` をコピーし英語化
4. テストの gh-graphql.sh モックが新しいパス解決ロジックと整合することを確認

### Step 4: PR 操作・ユーティリティスクリプト移植（Step 1 の後）（→ 受け入れ条件F, G, H）

1. 以下3スクリプトを claude-config からコピーし英語化:
   - `scripts/gh-extract-issue-from-pr.sh`
   - `scripts/gh-pr-merge-status.sh`
   - `scripts/gh-pr-review.sh`
2. 対応する bats テスト3本をコピーし英語化:
   - `tests/gh-extract-issue-from-pr.bats`
   - `tests/gh-pr-merge-status.bats`
   - `tests/gh-pr-review.bats`

### Step 5: テスト全件実行と migration-notes 作成（Step 2, 3, 4 の後）（→ 受け入れ条件I, L, M, N, O）

1. `bats tests/gh-*.bats` で全テスト PASS を確認
2. `docs/migration-notes.md` を作成し、以下を記載:
   - 各スクリプトごとのインターフェース変更の有無
   - gh-check-blocking.sh のフォールバックパス除去について記録
   - 変更がないスクリプトは「変更なし」と明記

## 検証方法

### マージ前

- <!-- verify: file_exists "scripts/gh-graphql.sh" --> `scripts/gh-graphql.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-issue-comment.sh" --> `scripts/gh-issue-comment.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-issue-edit.sh" --> `scripts/gh-issue-edit.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-label-transition.sh" --> `scripts/gh-label-transition.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-check-blocking.sh" --> `scripts/gh-check-blocking.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-extract-issue-from-pr.sh" --> `scripts/gh-extract-issue-from-pr.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-pr-merge-status.sh" --> `scripts/gh-pr-merge-status.sh` が移植されている
- <!-- verify: file_exists "scripts/gh-pr-review.sh" --> `scripts/gh-pr-review.sh` が移植されている
- <!-- verify: file_exists "tests/gh-graphql.bats" --> 対応する bats テスト 8 本が移植されている（代表: `gh-graphql.bats`）
- <!-- verify: file_not_contains "scripts/gh-graphql.sh" "GraphQL API 呼び出し" --> 日本語コメント・文字列が英語に変換されている（代表: `gh-graphql.sh`）

### マージ前（続き）

- <!-- verify: file_not_contains "scripts/gh-check-blocking.sh" "~/.claude/scripts/" --> `gh-check-blocking.sh` の `~/.claude/scripts/` フォールバックパスが削除されている
- <!-- verify: command "bats tests/gh-graphql.bats" --> gh-graphql.bats テストが PASS する
- <!-- verify: command "bats tests/gh-label-transition.bats" --> gh-label-transition.bats テストが PASS する
- <!-- verify: file_exists "docs/migration-notes.md" --> `docs/migration-notes.md` が作成されている
- <!-- verify: grep "gh-graphql" "docs/migration-notes.md" --> リファクタリングによるインターフェース変更が `docs/migration-notes.md` に記録されている

### マージ後

- 全 bats テスト (`bats tests/gh-*.bats`) が PASS すること
- 各スクリプトに実行権限 (`chmod +x`) が付与されていること
- `install.sh` 実行後、`~/.claude/skills/wholework/scripts/` 経由でスクリプトにアクセスできること

## 注意事項

- **英語化のスコープ**: コメント、エラーメッセージ、usage テキスト、テスト名（`@test` 行）、テスト内のアサーション文字列が対象。変数名・関数名は既に英語のため変更不要
- **bats テスト名の日本語**: bats には日本語テスト名でパースエラーが発生する既知バグがあるため、`@test` 行は必ず英語に変換すること
- **gh-check-blocking.sh のパス解決**: `SCRIPT_DIR` 変数で同ディレクトリの `gh-graphql.sh` を参照する方式に統一する。`~/.claude/scripts/` フォールバックは wholework の自己完結設計と矛盾するため削除する
- **テストの PATH 設定**: bats テストは `MOCK_DIR` パターン（`$BATS_TEST_TMPDIR/mocks`）で gh コマンドをモックしている。`PROJECT_ROOT` が worktree 環境でも正しく解決されることを確認すること
- **docs/migration-notes.md**: インターフェース変更がないスクリプトも「変更なし」として記載し、後続の skills 移植 Issue (#6 の他の sub-issue) で参照できるようにする
- **ISSUE_TYPE=Task のため、代替案の検討・不確定要素・UIデザインセクションは省略**

## spec レトロスペクティブ

### 軽微な観察
- Issue 本文の受け入れ条件は具体的で、移植対象ファイルとテスト対象が明確に定義されている。`/issue` フェーズの成果物として十分な品質
- wholework リポジトリには scripts/ も tests/ もまだ存在しないため、既存コードとの衝突リスクなし

### 判断経緯
- 実装ステップを5つにグループ化: ベーススクリプト（gh-graphql.sh）を Step 1 で先行移植し、依存するスクリプト群を Step 2-4 で並行移植可能とした。Step 3 はフォールバックパス除去という追加作業があるため独立ステップとした
- docs/structure.md と README.md は個別スクリプト一覧を持たないため変更対象外と判断

### 不確定要素の解決
- 特になし（移植作業のため外部仕様への依存なし）
