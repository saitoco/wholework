# Issue #129: watchdog: /code の claude -p ハング回避策を追加

## Overview

`claude -p` の初期 silent thinking 時間（出力なし期間）を watchdog が hang と誤検出して kill することで、複雑なタスク（Size L）で `/auto` が失敗する問題を解決する。

対処方針（Issue body のオプション組み合わせから採用）:
1. `claude-watchdog.sh` のデフォルト WATCHDOG_TIMEOUT を 600s → 1800s に延長（初期 silent thinking の余裕を確保）
2. heartbeat 出力を追加（診断性向上：沈黙中でも watchdog が動作中であることを示す）
3. `run-code.sh` に残留 worktree/ブランチのクリーンアップを追加（watchdog kill による残留物が次回実行の hang を引き起こすリスクを除去）

不採用: stream-json 出力（出力形式変更の複雑さ）、リトライ戦略改善（スコープ外）

## Changed Files

- `scripts/claude-watchdog.sh`: デフォルト WATCHDOG_TIMEOUT を 600 → 1800 に変更、`WATCHDOG_HEARTBEAT_INTERVAL` env var と heartbeat ログを追加
- `scripts/run-code.sh`: `claude-watchdog.sh` 呼び出し前に残留 worktree/ブランチのクリーンアップ処理を追加
- `tests/claude-watchdog.bats`: heartbeat テストケースを追加（コメントの "600s" 言及も更新）
- `tests/run-code.bats`: setup に git モックを追加、cleanup テストケースを追加

## Implementation Steps

1. `scripts/claude-watchdog.sh` を修正（→ 受け入れ基準 A）:
   - Line 11: `WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-600}"` → `WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-1800}"` に変更
   - Line 12 の `_CHECK_INTERVAL` 定義の直前に追加: `WATCHDOG_HEARTBEAT_INTERVAL="${WATCHDOG_HEARTBEAT_INTERVAL:-60}"`
   - `_run_with_watchdog` 関数内の `local last_size=0` と同じ位置に追加: `local _next_heartbeat="${WATCHDOG_HEARTBEAT_INTERVAL}"`
   - ウォッチドッグループ内の kill チェック（`if [[ "$unchanged_time" -ge "$WATCHDOG_TIMEOUT" ]]`）の直前に heartbeat チェックを挿入:
     ```bash
     if [[ "$unchanged_time" -ge "$_next_heartbeat" ]]; then
         echo "watchdog: still waiting, silent for ${unchanged_time}s (pid=${cmd_pid})" >&2
         _next_heartbeat=$(( _next_heartbeat + WATCHDOG_HEARTBEAT_INTERVAL ))
     fi
     ```
   - `else` ブランチ（出力再開時、`last_size="$current_size"` の後）に追加: `_next_heartbeat="${WATCHDOG_HEARTBEAT_INTERVAL}"`

2. `scripts/run-code.sh` を修正（after 1）（→ 受け入れ基準 B）:
   - `echo "Started at: ..."` の後、`SKILL_FILE=...` の前に cleanup セクションを追加:
     ```bash
     # Cleanup stale worktrees/branches from previous failed runs
     WORKTREE_PATH="${SCRIPT_DIR}/../.claude/worktrees/code+issue-${ISSUE_NUMBER}"
     WORKTREE_BRANCH="worktree-code+issue-${ISSUE_NUMBER}"
     if [[ -d "$WORKTREE_PATH" ]]; then
         echo "run-code.sh: stale worktree detected, cleaning up: $WORKTREE_PATH"
         git worktree remove --force "$WORKTREE_PATH" 2>/dev/null \
             || echo "Warning: Failed to remove stale worktree: $WORKTREE_PATH"
     fi
     if git branch --list "$WORKTREE_BRANCH" 2>/dev/null | grep -q .; then
         echo "run-code.sh: stale branch detected, cleaning up: $WORKTREE_BRANCH"
         git branch -D "$WORKTREE_BRANCH" 2>/dev/null \
             || echo "Warning: Failed to delete stale branch: $WORKTREE_BRANCH"
     fi
     ```

3. `tests/claude-watchdog.bats` を修正（after 1）（→ 受け入れ基準 C）:
   - Line 111 のコメント `"default 600s would take much longer"` → `"default 1800s would take much longer"` に更新
   - 末尾に heartbeat テストを追加:
     ```bash
     @test "heartbeat: diagnostic message emitted during silence" {
         cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
     #!/bin/bash
     sleep 60
     MOCK
         chmod +x "$MOCK_DIR/cmd.sh"

         run env WATCHDOG_TIMEOUT=3 WATCHDOG_HEARTBEAT_INTERVAL=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
         [ "$status" -ne 0 ]
         [[ "$output" == *"watchdog: still waiting"* ]]
     }
     ```
   - 既存テストはすべて `WATCHDOG_TIMEOUT=2` を明示指定するため、デフォルト変更の影響なし

4. `tests/run-code.bats` を修正（after 2）（→ 受け入れ基準 C）:
   - setup 内に git モックを追加（`git branch --list` → empty 出力で clean 状態をシミュレート）:
     ```bash
     cat > "$MOCK_DIR/git" <<'MOCK'
     #!/bin/bash
     exit 0
     MOCK
     chmod +x "$MOCK_DIR/git"
     ```
   - cleanup テストを追加（stale branch あり → cleanup メッセージが出力される）:
     ```bash
     @test "cleanup: stale branch detected and cleaned up before execution" {
         cat > "$MOCK_DIR/git" <<'MOCK'
     #!/bin/bash
     if [[ "$1" == "branch" && "$2" == "--list" ]]; then
         echo "  worktree-code+issue-123"
         exit 0
     fi
     exit 0
     MOCK
         chmod +x "$MOCK_DIR/git"

         run bash "$SCRIPT" 123
         [ "$status" -eq 0 ]
         [[ "$output" == *"stale branch"* ]]
     }
     ```

## Verification

### Pre-merge

- <!-- verify: grep "WATCHDOG_TIMEOUT" "scripts/claude-watchdog.sh" --> `scripts/claude-watchdog.sh` にタイムアウト延長の仕組みが実装されている（環境変数または effort 連動）
- <!-- verify: grep -i "cleanup\|leftover\|stale" "scripts/run-code.sh" --> `scripts/run-code.sh` に残留 worktree/ブランチのクリーンアップ処理が追加されている
- <!-- verify: command "bats tests/claude-watchdog.bats" --> claude-watchdog.sh の bats テストが PASS する

### Post-merge

- Size L の Issue で `/auto` を実行して code phase が watchdog timeout なしで完遂する <!-- verify-type: opportunistic -->
- 残留 worktree が蓄積せず、再試行時に競合しない <!-- verify-type: opportunistic -->

## Notes

- heartbeat が kill チェックと同一イテレーションで発火するケース（WATCHDOG_TIMEOUT と WATCHDOG_HEARTBEAT_INTERVAL が同じ値の倍数の場合）: heartbeat チェックを kill チェックより前に配置するため、heartbeat が先に出力される
- run-code.sh の cleanup は `run-spec.sh` など他の run-*.sh には追加しない（Issue body の acceptance criteria が `run-code.sh` のみを対象としているため）
- worktree ブランチ命名の根拠: EnterWorktree は `code/issue-$NUMBER` という名前に対し `worktree-code+issue-$NUMBER` ブランチを作成する（`/` → `+` 変換、`worktree-` プレフィックス付与 — EnterWorktree 実行時の出力 "branch worktree-spec+issue-129" で確認済み）
- WATCHDOG_HEARTBEAT_INTERVAL のデフォルト 60s は production では heartbeat が 60s ごとに出力される。テストでは `WATCHDOG_HEARTBEAT_INTERVAL=2` など短い値を指定してテスト時間を抑える
- run-code.bats の git モックはデフォルト `exit 0` のみで CI/CD 環境でも safe（実際の git コマンドを呼ばない）

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- `run-code.sh` の `WORKTREE_PATH` に指定するディレクトリ名が spec では `code+issue-$NUMBER`（`+` 区切り）だが、実際の EnterWorktree の動作（`code/issue-$NUMBER` → ディレクトリは `code/issue-$NUMBER`）と一致するか未検証。Spec Notes に「branch worktree-code+issue-$NUMBER」と記載があり、ブランチ名については確認済みだが、ディレクトリパスの `+` 変換については実際の EnterWorktree 出力から明示的に確認できなかった。cleanup 処理は `2>/dev/null ||` で失敗を無視するため、パス不一致でも安全に動作する。

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

- 逸脱なし。すべての実装ステップが Spec 定義と一致していた。Code Retrospective の Design Gaps で懸念されていた `WORKTREE_PATH` のディレクトリ命名（`code+issue-$NUMBER`）については、review フェーズで worktree 実例（`review/pr-131` → `review+pr-131`）から `+` 変換が正しく行われることを確認し、懸念を解消できた。

### Recurring Issues

- 特になし。SHOULD レベルの指摘（stale worktree テストの欠如）は Spec 要件外であり、`2>/dev/null ||` で安全に処理されているため問題ない。

### Acceptance Criteria Verification Difficulty

- `command "bats tests/claude-watchdog.bats"` は safe モードでは UNCERTAIN（CI 実行中）となった。CI が IN_PROGRESS の場合は結果待ちとなるため、verify 実行タイミングと CI 完了タイミングの関係が重要。今回は Validate skill syntax と Forbidden Expressions check が SUCCESS で主要な品質チェックは通過しており、問題なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件に verify コマンドが適切に付与されており、3件すべてが自動検証可能だった。pre-merge と post-merge のセクション分割が明確で、opportunistic 条件の扱いが適切。
- `grep "WATCHDOG_TIMEOUT"` と `grep -i "cleanup\|leftover\|stale"` は実装対象のファイルと検索キーワードが正確に対応しており、曖昧さなし。

#### design
- Spec の設計方針（タイムアウト延長 + heartbeat + stale cleanup）が実装に忠実に反映された。不採用オプション（stream-json、リトライ戦略改善）の除外理由も明記されており、設計判断の妥当性が高い。
- Notes に worktree ブランチ命名の根拠（`/` → `+` 変換）が記載されており、実装での不確実性を事前にカバーしていた。

#### code
- Code Retrospective によれば逸脱・手戻りなし（N/A）。ただし `WORKTREE_PATH` の `+` 変換について「実際の EnterWorktree 出力から明示的に確認できなかった」という Design Gap が残っており、review フェーズで解消された点は記録に値する。

#### review
- Review Retrospective によれば逸脱なし。WORKTREE_PATH のパス名検証（`+` 変換）が review で解消されており、有効なレビューが行われた。
- `command "bats tests/claude-watchdog.bats"` が CI 実行中のため UNCERTAIN となったが、主要な品質チェックは SUCCESS。

#### merge
- PR #131 として clean merge。commit `0290a76` で確認済み。コンフリクト・CI 失敗の痕跡なし。

#### verify
- Pre-merge 3件すべて PASS（`grep` 2件 + `bats` テスト 8件 OK）。
- Post-merge の opportunistic 条件（watchdog timeout なし完遂、stale worktree 非蓄積）は実環境検証が必要なため、`phase/verify` ラベル付きで Issue をクローズ済みのまま残す。

### Improvement Proposals

- N/A
