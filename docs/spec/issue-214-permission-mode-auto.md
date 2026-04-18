# Issue #214: auto: --permission-mode auto を /auto の代替パーミッションモードとして導入

## Overview

`/auto` の各フェーズ（`run-*.sh`）は現在 `claude -p --dangerously-skip-permissions` で全権限チェックをバイパスする。Claude Code の `--permission-mode auto` を opt-in で利用できるよう `.wholework.yml` に `permission-mode` キーを追加し、`auto`（`--permission-mode auto`）と `bypass`（`--dangerously-skip-permissions`）を切り替え可能にする。

`auto` モード選択時は、auto mode のデフォルト `soft_deny` と wholework 操作の衝突（Git Push to Default Branch、External System Writes）を、最小権限原則に基づく allow rules テンプレート（`docs/guide/auto-mode-template.json`）を `.claude/settings.local.json` へ手動適用することで解消する。デフォルトは `bypass`（従来動作・breaking change 回避）。

`auto` + 最小 allow rules は、bypass と比較して (1) 未列挙の destructive pattern への `soft_deny` が残存（最小権限）、(2) 評価フレームワーク自体が機能（defense in depth）という二点で安全性で勝る。これを SECURITY.md に明文化する。

## Changed Files

- `scripts/run-code.sh`: `get-config-value.sh` で `permission-mode` を読み、`--permission-mode auto` / `--dangerously-skip-permissions` を切り替え — bash 3.2+ 互換
- `scripts/run-spec.sh`: 同上 — bash 3.2+ 互換
- `scripts/run-review.sh`: 同上 — bash 3.2+ 互換
- `scripts/run-merge.sh`: 同上 — bash 3.2+ 互換
- `scripts/run-verify.sh`: 同上 — bash 3.2+ 互換
- `scripts/run-issue.sh`: 同上 — bash 3.2+ 互換
- `docs/guide/auto-mode-template.json`: 新規。wholework が使う `gh` サブコマンド（`gh issue`/`gh pr`/`gh label`/`gh api`/`gh run`）および `git push origin main` を最小 enumerate した `autoMode` allow rules テンプレート
- `SECURITY.md`: `## Permission Bypass (\`/auto\`)` を `## Permission Modes (\`/auto\`)` にリネームし、`auto` / `bypass` 選択肢・最小権限（least privilege）・defense in depth の安全性比較を追記
- `docs/guide/customization.md`: `permission-mode` キーを YAML サンプルと Available Keys 表（SSoT）に追加
- `tests/run-code.bats`: 既存テストでは `--dangerously-skip-permissions` のみ検証。`permission-mode: auto` 設定時に `--permission-mode auto` が渡されることをカバーする bats ケースを追加 — bash 3.2+ 互換
- `tests/run-spec.bats`: 同上 — bash 3.2+ 互換
- `tests/run-review.bats`: 同上 — bash 3.2+ 互換
- `tests/run-merge.bats`: 同上 — bash 3.2+ 互換
- `tests/run-verify.bats`: 同上 — bash 3.2+ 互換
- `tests/run-issue.bats`: 同上 — bash 3.2+ 互換

## Implementation Steps

1. **各 `run-*.sh` に permission-mode 解決ロジックを追加**（→ AC 1〜6）: 既存の `WATCHDOG_TIMEOUT` 読み取りブロック（`get-config-value.sh watchdog-timeout-seconds 1800` の直後）に続けて、`PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode bypass)` を追加。値 `auto` なら `PERMISSION_FLAG="--permission-mode auto"`、それ以外（`bypass` or 未設定）なら `PERMISSION_FLAG="--dangerously-skip-permissions"` に解決。`claude -p` 呼び出しのハードコード `--dangerously-skip-permissions` を `$PERMISSION_FLAG` に置換。起動時の `echo "Permissions: ..."` メッセージも動的に（`auto` → `permission-mode auto (with allow rules template)`, `bypass` → `skip (autonomous mode)`）。6 スクリプト全てに同一パターンを適用。`--permission-mode auto` フラグは未クオート変数として展開し、空白で CLI 引数が分離されるようシェル展開を考慮（`eval` は使わない）。

2. **`docs/guide/auto-mode-template.json` を新規作成**（→ AC 7〜11）: JSON 構造はトップレベル `autoMode` キー配下に `allowRules` 配列。wholework が使用する最小 enumerate パターンを列挙:
   - Git: `git push origin main`（`/code --patch` の Git Push to Default Branch 対策）
   - gh: `gh issue`, `gh pr`, `gh label`, `gh api`, `gh run`（External System Writes 対策。`gh *` のようなブランケット許可は採用しない）
   - 各 rule にコメント相当の `description` フィールドで用途を明記（JSON 標準にはコメントがないため `description` フィールドとして記録）。

3. **`SECURITY.md` の Permission セクションを更新**（→ AC 12〜14）: `## Permission Bypass (\`/auto\`)` を `## Permission Modes (\`/auto\`)` にリネーム。本文に 2 モード（`auto` / `bypass`）の選択方法（`.wholework.yml` の `permission-mode` キー）、default=`bypass` の理由（既存ユーザー互換）、`auto` 選択時の手順（テンプレートを `.claude/settings.local.json` に手動適用・セッション再起動が必要）を記載。さらに `auto` + 最小 allow rules が `bypass` より安全な根拠として「least privilege（最小権限の原則）」と「defense in depth」の 2 点を明示。セクション内に `permission-mode auto`, `bypass`, `least privilege` の 3 語句を全て含める。

4. **`docs/guide/customization.md` に `permission-mode` キーを追加**（SSoT 更新）: 冒頭 YAML サンプルに `permission-mode: auto` の行例を追加、Available Keys 表に `permission-mode | string | "bypass" | Permission mode for \`/auto\` subprocess (\`auto\` enables \`--permission-mode auto\` with allow rules template; \`bypass\` uses \`--dangerously-skip-permissions\`)` の行を追加。

5. **各 `tests/run-*.bats` に permission-mode 切替ケースを追加**（→ AC 15）: mock `claude` スクリプトの `for arg in "$@"; do case "$arg" in ...` 節に `--permission-mode) echo "FLAG_PERM_MODE=1" >> "$CLAUDE_CALL_LOG" ;;` と、次の引数値を拾う分岐（または `--permission-mode auto` 全体を検出するマッチャ）を追加。新規テストケースとして (a) `.wholework.yml` 不在時に `FLAG_SKIP_PERMS=1`（既存デフォルト挙動を維持）、(b) `.wholework.yml` に `permission-mode: auto` 設定時に `--permission-mode auto` が渡る（`FLAG_PERM_MODE=1` かつ引数に `auto` が含まれる）、(c) `permission-mode: bypass` 明示時に `FLAG_SKIP_PERMS=1` の 3 ケースを 6 bats ファイル全てに追加。テスト実行ディレクトリ内で `.wholework.yml` を fixture として作成する。

## Verification

### Pre-merge

- <!-- verify: grep "permission-mode" "scripts/run-code.sh" --> `run-code.sh` が `get-config-value.sh` 経由で `permission-mode` を `.wholework.yml` から読み、`--permission-mode auto` または `--dangerously-skip-permissions` を切り替える
- <!-- verify: grep "permission-mode" "scripts/run-spec.sh" --> `run-spec.sh` が同様に切り替える
- <!-- verify: grep "permission-mode" "scripts/run-review.sh" --> `run-review.sh` が同様に切り替える
- <!-- verify: grep "permission-mode" "scripts/run-merge.sh" --> `run-merge.sh` が同様に切り替える
- <!-- verify: grep "permission-mode" "scripts/run-verify.sh" --> `run-verify.sh` が同様に切り替える
- <!-- verify: grep "permission-mode" "scripts/run-issue.sh" --> `run-issue.sh` が同様に切り替える
- <!-- verify: file_exists "docs/guide/auto-mode-template.json" --> 推奨 auto mode カスタムルールのテンプレートが `docs/guide/auto-mode-template.json` に存在する
- <!-- verify: file_contains "docs/guide/auto-mode-template.json" "autoMode" --> テンプレートに `autoMode` セクションが含まれる
- <!-- verify: file_contains "docs/guide/auto-mode-template.json" "gh issue" --> テンプレートが wholework が使用する `gh issue` サブコマンドを enumerate している（最小権限原則）
- <!-- verify: file_contains "docs/guide/auto-mode-template.json" "gh pr" --> テンプレートが `gh pr` サブコマンドを enumerate している
- <!-- verify: file_contains "docs/guide/auto-mode-template.json" "git push origin main" --> テンプレートが Git Push to Default Branch の allow rule を含む
- <!-- verify: section_contains "SECURITY.md" "## Permission" "permission-mode auto" --> SECURITY.md に auto mode の選択肢が文書化されている
- <!-- verify: section_contains "SECURITY.md" "## Permission" "bypass" --> SECURITY.md に bypass モードが文書化されている
- <!-- verify: section_contains "SECURITY.md" "## Permission" "least privilege" --> SECURITY.md に auto + 最小 allow rules の安全性根拠（最小権限・defense in depth）が記載されている
- <!-- verify: command "bats tests/" --> 全 bats テストが PASS する

### Post-merge

- `permission-mode: auto` を `.wholework.yml` に設定し、推奨テンプレートを `.claude/settings.local.json` に適用した状態で、XS Issue に対して `/auto` を実行し、全フェーズが auto mode で完走することを確認する
- テンプレート未列挙の destructive pattern（例: 任意の外部 URL への write 系操作、範囲外の破壊的 FS 操作）を仮プロンプトで試行した際に、auto mode の `soft_deny` が残存して阻止されることを確認する（最小権限の実効性検証）

## Notes

### Auto-Resolved Ambiguity Points

Issue 側で auto-resolve 済み:
- **テンプレート配置場所** → `docs/guide/auto-mode-template.json`
- **デフォルト値** → `bypass`（未設定時は従来通り `--dangerously-skip-permissions`）
- **共通ロジック配置** → 新規 `lib/` 作成せず各 `run-*.sh` で `get-config-value.sh` を直接呼ぶ（既存の `watchdog-timeout-seconds` パターンに合わせる）
- **Allow rule の粒度** → `gh *` 全許可は避け、サブコマンド単位で enumerate
- **SECURITY.md 記述深度** → 選択肢に加え安全性比較根拠（least privilege・defense in depth）まで記載
- **Post-merge 検証範囲** → `/auto` 完走＋未列挙 destructive pattern 阻止の 2 条件

### Design Premises (verify during /code)

以下は Issue 本文で前提とされた Claude Code CLI の仕様。`/code` 実行時に `claude --help` や公式ドキュメントで最新挙動を確認し、差異があれば該当箇所を修正する:

- **CLI flag**: `claude -p --permission-mode auto` が有効な呼び出し形式である
- **Settings ファイル**: auto mode の allow rules は checked-in な `.claude/settings.json` からは読まれず、gitignored な `.claude/settings.local.json` にのみ配置できる
- **Settings 形式**: `autoMode` キー配下に allow rules を記述する JSON 構造（キー名・ネスト構造は公式仕様に合わせる。`autoMode` という単語自体の存在は AC でチェック）
- **デフォルト soft_deny**: `Git Push to Default Branch` と `External System Writes` が soft_deny 対象であり、allow rules で上書き可能

### Gotcha: settings.local.json is not hot-reloaded

`docs/tech.md` Gotchas に記載の通り、`.claude/settings.json`（および `.local.json`）はセッション開始時にキャッシュされセッション中はリロードされない。Post-merge 手動検証時は、テンプレート適用後に必ず Claude Code セッションを再起動してから `/auto` を実行する。

### Test fixture behavior

各 `run-*.bats` のテストでは、`BATS_TEST_TMPDIR` 配下にテスト毎の `.wholework.yml` fixture を作成し、`cd "$BATS_TEST_TMPDIR"` してからスクリプトを実行する。`get-config-value.sh` は CWD の `.wholework.yml` を読むため、fixture 経由で `permission-mode` 値を注入できる。

### Count note

本 Spec の Pre-merge verification は Issue 本文から verbatim 同期しており 15 件。SPEC_DEPTH=light の推奨上限（5 件）を超過するが、Issue 側で粒度が細かく分割された verify command を再集約すると情報欠損となるためそのまま保持する。

## Code Retrospective

### Deviations from Design

- **permission-mode 解決タイミング**: Spec の「WATCHDOG_TIMEOUT ブロックの直後に追加」という配置指示に対し、`echo "Permissions:"` メッセージを動的にするため SCRIPT_DIR 設定直後（echo ブロックの前）に配置した。これにより起動バナーの Permissions 行も動的に表示される。Spec の意図（動的 echo）を満たすための合理的な逸脱。

### Design Gaps/Ambiguities

- **autoMode の実際のフォーマット**: Spec は `autoMode.allowRules[]` と記述しているが、`claude auto-mode defaults` の実際の出力は `{ "allow": [], "soft_deny": [], "environment": [] }` 構造であることが判明。テンプレートの AC は `autoMode` 文字列の存在のみチェックするため、実際のフォーマット（`autoMode.allow[]`）に合わせて実装した。Spec の `allowRules` は設計時の仮定であり、実際の CLI 仕様とは異なる。

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

`docs/tech.md` Architecture Decisions section was not listed in the Spec's Changed Files, but it contained an outdated description of `/auto`'s permission mechanism that needed updating. The Spec listed `docs/guide/customization.md` and `SECURITY.md` as documentation targets, but missed `docs/tech.md` even though it directly describes the changed behavior. When a configuration flag controlling behavior is added, the Architecture Decisions section of tech.md should always be included in the Changed Files list.

### Recurring issues

Nothing to note.

### Acceptance criteria verification difficulty

All 15 pre-merge conditions were auto-verifiable (grep, file_exists, file_contains, section_contains, CI reference). Zero UNCERTAINs. The verify commands were well-specified. The `section_contains` checks for SECURITY.md worked correctly once the worktree file path was used (there was a path confusion between the main repo and worktree during initial verification). No improvement needed for the verify commands themselves.
