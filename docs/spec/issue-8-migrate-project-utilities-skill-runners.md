# Issue #8: scripts: Migrate project utilities and skill runner scripts

## 概要

親 Issue #6 の sub-issue（第2弾）。claude-config リポジトリからプロジェクトユーティリティスクリプト 6 本、スキルランナー 7 本、対応する bats テスト 10 本を wholework に移植する。Migration Guidelines（CLAUDE.md）に従い、日本語テキストの英語化・リファクタリング・汎用化を行う。

Issue #7（GitHub API ユーティリティスクリプト移植）で移植済みの `gh-graphql.sh` 等を `$SCRIPT_DIR` 相対で呼び出すため、#7 完了後に着手する。

## 変更対象ファイル

### 新規作成（23 files）

**scripts/**（13 files）:

プロジェクトユーティリティ:
- `scripts/get-issue-size.sh`: 新規作成（claude-config から移植・英語化）— `gh-graphql.sh` に依存
- `scripts/get-issue-type.sh`: 新規作成（claude-config から移植・英語化）— `gh-graphql.sh` に依存
- `scripts/get-sub-issue-graph.sh`: 新規作成（claude-config から移植・英語化）— `gh-graphql.sh` に依存
- `scripts/log-permission.sh`: 新規作成（claude-config から移植・英語化）— 外部依存なし（`jq`, `date` のみ）
- `scripts/opportunistic-search.sh`: 新規作成（claude-config から移植・英語化）— `gh` CLI に依存
- `scripts/triage-backlog-filter.sh`: 新規作成（claude-config から移植・英語化）— `gh` CLI に依存

スキルランナー:
- `scripts/run-code.sh`: 新規作成（claude-config から移植・英語化）— `$SCRIPT_DIR/../skills/code/SKILL.md` を参照
- `scripts/run-issue.sh`: 新規作成（claude-config から移植・英語化）— `$SCRIPT_DIR/../skills/issue/SKILL.md` を参照
- `scripts/run-merge.sh`: 新規作成（claude-config から移植・英語化）— `$SCRIPT_DIR/../skills/merge/SKILL.md` を参照
- `scripts/run-review.sh`: 新規作成（claude-config から移植・英語化）— `$SCRIPT_DIR/../skills/review/SKILL.md` を参照
- `scripts/run-spec.sh`: 新規作成（claude-config から移植・英語化）— `$SCRIPT_DIR/../skills/spec/SKILL.md` を参照
- `scripts/run-verify.sh`: 新規作成（claude-config から移植・英語化）— `$SCRIPT_DIR/../skills/verify/SKILL.md` を参照
- `scripts/run-auto-sub.sh`: 新規作成（claude-config から移植・英語化）— `get-issue-size.sh`, `run-spec.sh`, `run-code.sh`, `run-review.sh`, `run-merge.sh`, `run-verify.sh` に依存

**tests/**（10 files）:

プロジェクトユーティリティ:
- `tests/get-issue-size.bats`: 新規作成（claude-config から移植・英語化）
- `tests/get-issue-type.bats`: 新規作成（claude-config から移植・英語化）
- `tests/log-permission.bats`: 新規作成（claude-config から移植・英語化）
- `tests/opportunistic-search.bats`: 新規作成（claude-config から移植・英語化）
- `tests/triage-backlog-filter.bats`: 新規作成（claude-config から移植・英語化）

スキルランナー:
- `tests/run-code.bats`: 新規作成（claude-config から移植・英語化）
- `tests/run-issue.bats`: 新規作成（claude-config から移植・英語化）
- `tests/run-merge.bats`: 新規作成（claude-config から移植・英語化）
- `tests/run-review.bats`: 新規作成（claude-config から移植・英語化）
- `tests/run-verify.bats`: 新規作成（claude-config から移植・英語化）

**docs/**（既存ファイル更新）:
- `docs/migration-notes.md`: 追記（Issue #8 のインターフェース変更記録を追加）

### テストファイルが存在しないスクリプト（3 files）

以下のスクリプトは claude-config にも対応する bats テストが存在しないため、テストなしで移植する:
- `get-sub-issue-graph.sh`（テスト未作成）
- `run-auto-sub.sh`（テスト未作成）
- `run-spec.sh`（テスト未作成）

## 実装ステップ

### Step 1: プロジェクトユーティリティスクリプト移植（→ 受け入れ条件A, B, C, L）

1. 以下3スクリプトを `~/src/claude-config/scripts/` からコピーし、英語化を実施:
   - `scripts/get-issue-size.sh`（68行）— GraphQL + ラベルフォールバックで Issue Size を取得
   - `scripts/get-issue-type.sh`（82行）— GraphQL + ラベルフォールバックで Issue Type を取得
   - `scripts/get-sub-issue-graph.sh`（87行）— sub-issue 依存グラフ JSON を生成
2. 英語化対象: コメント、エラーメッセージ（`使い方:` → `Usage:`, `エラー:` → `Error:` 等）、ヘルプテキスト
3. `$SCRIPT_DIR/gh-graphql.sh` 参照パスは変更不要（#7 で移植済みの gh-graphql.sh と同ディレクトリに配置）
4. 対応する bats テスト2本をコピーし英語化:
   - `tests/get-issue-size.bats`（139行）
   - `tests/get-issue-type.bats`（152行）
5. `bats tests/get-issue-size.bats` でテスト PASS を確認
6. `chmod +x` で実行権限を付与

### Step 2: スタンドアロンユーティリティスクリプト移植（Step 1 と並行可）（→ 受け入れ条件D, E, F）

1. 以下3スクリプトを claude-config からコピーし英語化:
   - `scripts/log-permission.sh`（16行）— PermissionRequest hook、`$CLAUDE_PROJECT_DIR/.tmp/` にログ記録
   - `scripts/opportunistic-search.sh`（89行）— phase/verify Issue から未チェック opportunistic 条件を検索
   - `scripts/triage-backlog-filter.sh`（65行）— triaged/phase ラベルなし Issue をフィルタ
2. 対応する bats テスト3本をコピーし英語化:
   - `tests/log-permission.bats`（76行）
   - `tests/opportunistic-search.bats`（129行）
   - `tests/triage-backlog-filter.bats`（131行）
3. `chmod +x` で実行権限を付与

### Step 3: スキルランナースクリプト移植（Step 1 と並行可）（→ 受け入れ条件G, H, K）

全スキルランナーは共通パターン: SKILL.md のフロントマターを除去してボディを抽出 → ARGUMENTS を注入 → `claude -p` で実行（`--dangerously-skip-permissions`、`env -u CLAUDECODE`）。

1. 以下6スクリプトを claude-config からコピーし英語化:
   - `scripts/run-code.sh`（115行）— `--patch`/`--pr`/`--base` フラグ対応
   - `scripts/run-issue.sh`（67行）— Issue 番号を受け取り `/issue` スキル実行
   - `scripts/run-merge.sh`（56行）— PR 番号を受け取り `/merge` スキル実行
   - `scripts/run-review.sh`（64行）— `--light`/`--full`/`--review-only` フラグ対応
   - `scripts/run-spec.sh`（72行）— `--opus` フラグ対応
   - `scripts/run-verify.sh`（95行）— VERIFY_FAILED マーカー検出による exit code 変換
2. `SKILL_FILE` パス `${SCRIPT_DIR}/../skills/{name}/SKILL.md` は wholework のリポジトリ構造でも正しく解決されるため変更不要
3. 対応する bats テスト5本をコピーし英語化:
   - `tests/run-code.bats`（174行）
   - `tests/run-issue.bats`（125行）
   - `tests/run-merge.bats`（92行）
   - `tests/run-review.bats`（123行）
   - `tests/run-verify.bats`（113行）
4. `chmod +x` で実行権限を付与

### Step 4: run-auto-sub.sh 移植（Step 1, 3 の後）（→ 受け入れ条件H）

1. `scripts/run-auto-sub.sh`（191行）を claude-config からコピーし英語化
2. 英語化対象: コメント、エラーメッセージ、ログ出力（`patch ロック取得タイムアウト` → `Patch lock acquisition timeout` 等）
3. 内部で呼び出すスクリプト参照パス（`$SCRIPT_DIR/get-issue-size.sh`, `$SCRIPT_DIR/run-*.sh`）は変更不要（同ディレクトリに配置）
4. `/tmp/claude-auto-patch-lock-${LOCK_HASH}` ロックメカニズムは現状維持（Issue 本文の設計方針に従う）
5. `chmod +x` で実行権限を付与

### Step 5: 全テスト実行と migration-notes 更新（Step 1, 2, 3, 4 の後）（→ 受け入れ条件I, J, K, L, M, N）

1. 全 bats テスト実行: `bats tests/get-issue-size.bats tests/get-issue-type.bats tests/log-permission.bats tests/opportunistic-search.bats tests/triage-backlog-filter.bats tests/run-code.bats tests/run-issue.bats tests/run-merge.bats tests/run-review.bats tests/run-verify.bats`
2. `docs/migration-notes.md` に Issue #8 セクションを追記:
   - 各スクリプト（13本）ごとのインターフェース変更の有無を記録
   - 変更がないスクリプトは「Interface changes: None」と明記
   - 日本語→英語変換の代表例を記載

## 検証方法

### マージ前

- <!-- verify: file_exists "scripts/get-issue-size.sh" --> `scripts/get-issue-size.sh` が移植されている
- <!-- verify: file_exists "scripts/get-issue-type.sh" --> `scripts/get-issue-type.sh` が移植されている
- <!-- verify: file_exists "scripts/get-sub-issue-graph.sh" --> `scripts/get-sub-issue-graph.sh` が移植されている
- <!-- verify: file_exists "scripts/log-permission.sh" --> `scripts/log-permission.sh` が移植されている
- <!-- verify: file_exists "scripts/opportunistic-search.sh" --> `scripts/opportunistic-search.sh` が移植されている
- <!-- verify: file_exists "scripts/triage-backlog-filter.sh" --> `scripts/triage-backlog-filter.sh` が移植されている
- <!-- verify: file_exists "scripts/run-code.sh" --> run-*.sh スキルランナー 7 本が移植されている（代表: `run-code.sh`）
- <!-- verify: file_exists "scripts/run-auto-sub.sh" --> `scripts/run-auto-sub.sh` が移植されている
- <!-- verify: file_exists "tests/get-issue-size.bats" --> 対応する bats テストが移植されている（代表: `get-issue-size.bats`）
- <!-- verify: file_exists "tests/run-code.bats" --> run-*.bats テストが移植されている（代表: `run-code.bats`）
- <!-- verify: file_not_contains "scripts/run-code.sh" "使い方:" --> 日本語エラーメッセージが英語に変換されている（代表: `run-code.sh`）
- <!-- verify: command "bats tests/get-issue-size.bats" --> get-issue-size.bats テストが PASS する
- <!-- verify: command "bats tests/run-code.bats" --> run-code.bats テストが PASS する
- <!-- verify: grep "run-code\|get-issue-size" "docs/migration-notes.md" --> リファクタリングによるインターフェース変更が `docs/migration-notes.md` に追記されている（変更がない場合は「変更なし」と記載）

### マージ後

- 全 bats テスト（`bats tests/*.bats`）が PASS すること
- 各スクリプトに実行権限（`chmod +x`）が付与されていること
- `install.sh` 実行後、`~/.claude/skills/wholework/scripts/` 経由でスクリプトにアクセスできること
- run-*.sh が `$SCRIPT_DIR/../skills/{name}/SKILL.md` を正しく参照できること（skills 移植後に検証）

## 注意事項

- **英語化のスコープ**: コメント、エラーメッセージ（`使い方:` → `Usage:`, `エラー:` → `Error:`, `Issue番号は数値である必要があります` → `Issue number must be numeric` 等）、usage テキスト、テスト名（`@test` 行）、テスト内のアサーション文字列が対象。変数名・関数名は既に英語のため変更不要
- **bats テスト名の日本語**: bats には日本語テスト名でパースエラーが発生する既知バグがあるため、`@test` 行は必ず英語に変換すること（#7 と同じ）
- **SKILL_FILE パス解決**: run-*.sh の `${SCRIPT_DIR}/../skills/{name}/SKILL.md` パスは wholework のリポジトリ構造（`scripts/` と `skills/` が同階層）でも正しく解決される。変更不要
- **テストの PATH 設定**: bats テストは `MOCK_DIR` パターン（`$BATS_TEST_TMPDIR/mocks`）で外部コマンドをモックしている。`PROJECT_ROOT` は `"$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` パターンを使用し、worktree 環境でも正しく解決されることを確認（#7 で確立済みのパターン）
- **run-auto-sub.sh のロックメカニズム**: `/tmp/claude-auto-patch-lock-${LOCK_HASH}` は現状維持（Issue 本文の設計方針「CI 並列実行しなければ問題なし」に従う）
- **テストファイルが存在しない3スクリプト**: `get-sub-issue-graph.sh`, `run-auto-sub.sh`, `run-spec.sh` は claude-config にもテストが存在しないため、テストなしで移植する
- **自動解決済みの曖昧ポイント**:
  1. テストファイル数（Issue「~13 本」→ 実際 10 本）: 実在するファイルのみ移植。根拠: claude-config の `tests/` を全件確認し、対象スクリプトに対応するテストは 10 ファイルのみ存在
  2. 「汎用化」の範囲: Issue #7 パターン（英語化 + パス修正、Breaking change なし）に準拠。根拠: 同一 parent Issue の sub-issue として一貫した移植方針を適用
