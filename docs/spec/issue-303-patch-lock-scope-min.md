# Issue #303: patch-lock: スコープを最小化し worktree-lifecycle に移譲 (方針 D)

## Overview

`/auto` XL route の patch route sub-issue 並列実行で発生していた lock timeout 失敗の根本原因（lock スコープが `run-code.sh --patch` の全体 = 30 分超を覆っていたこと）を解消する。lock 取得・保持を `git merge --ff-only` + `git push origin main` の数秒だけに縮小し、worktree 内の実装フェーズは完全に並列化する（方針 D）。

実装としては、lock + merge + push の 1 連の操作を新スクリプト `scripts/worktree-merge-push.sh` に集約し、`modules/worktree-lifecycle.md` の Exit: merge-to-main セクションがそのスクリプトを呼ぶ形に変更する。`scripts/run-auto-sub.sh` から `acquire_patch_lock` / `release_patch_lock` の呼び出しと関数定義を削除する。デフォルト timeout は 3600 秒 → 300 秒に巻き戻す。

副次的効果として、lock は patch route だけでなく `/spec` および `/verify` の merge-to-main 経路にも自動的に適用される（並列 push 競合の保護範囲が広がる）。

## Changed Files

- `scripts/worktree-merge-push.sh`: 新規 — lock 取得（PID stamping、stale 検出、`.wholework.yml` 経由 timeout 上書き、診断ログ） + `git merge --ff-only`（rebase retry 付き）+ conflict marker check + `git push origin <base>` + EXIT trap での lock 解放。args `[--from <worktree-branch>] [--base <branch>]`。bash 3.2+ 互換
- `tests/worktree-merge-push.bats`: 新規 — 9 件の bats テスト（lock 生成/解放、stale PID 再取得、診断ログ、yml timeout、デフォルト 300、--from FF success、--from rebase retry、--base 非 main、conflict marker abort）。bash 3.2+ 互換
- `modules/worktree-lifecycle.md`: change "Exit: merge-to-main Section" の steps 3-5（merge / conflict check / push）を `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh --from $WORKTREE_BRANCH [--base $BASE_BRANCH]` 1 行に置換。`ENTERED_WORKTREE=false` 分岐も同スクリプト（`--from` 省略）呼び出しに置換。step 6 cleanup は維持
- `scripts/run-auto-sub.sh`: change `acquire_patch_lock` / `release_patch_lock` 関数定義および XS / S case 内の呼び出しを削除。`PATCH_LOCK_DIR` 定数、関連 `mkdir` 行、診断コメント (`Patch route commits directly to main, running sequentially...`) を削除。bash 3.2+ 互換
- `tests/run-auto-sub.bats`: change PATCH_LOCK 系 4 件のテスト（`PATCH_LOCK: lock dir is created...`, `PATCH_LOCK: stale PID is reclaimed...`, `PATCH_LOCK: diagnostic log...`, `PATCH_LOCK: timeout is read from .wholework.yml...`）を削除。代替に negative test 1 件（`Size XS: lock dir is NOT created by run-auto-sub wrapper`）を追加。teardown の lock cleanup 行も削除。bash 3.2+ 互換
- `modules/detect-config-markers.md`: change `patch-lock-timeout` 行のデフォルト値 3600 → 300、参照スクリプト `scripts/run-auto-sub.sh` → `scripts/worktree-merge-push.sh`。3 箇所（Marker Definition Table、YAML Parsing Rules、Output Format）すべて更新
- `docs/guide/customization.md`: change YAML サンプルの `patch-lock-timeout: 3600` → `patch-lock-timeout: 300`、コメント文言を新セマンティクスに更新（XL 並列 → main-branch push lock）。Available Keys テーブル行のデフォルト値 3600 → 300、説明文を新セマンティクスに更新
- `docs/ja/guide/customization.md`: change 英語版との翻訳同期（YAML サンプル、テーブル行、コメント・説明文）
- `docs/structure.md`: add Scripts > Process management セクションに `scripts/worktree-merge-push.sh — acquire short-lived lock and merge worktree branch + push to main (with rebase retry)` 行を追加

## Implementation Steps

**Step recording rules:**
- Step 番号は整数のみ
- Step 1 完了後、他 Step は依存順に実行
- 各 Step 末尾に対応する Acceptance Criteria を記載

1. **Create `scripts/worktree-merge-push.sh`** (→ AC2, AC3)
   - shebang `#!/bin/bash` + `set -euo pipefail`
   - 引数解析: `[--from <worktree-branch>] [--base <branch>]`（`--base` 既定値 `main`）
   - `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`（CWD ベース、SCRIPT_DIR 相対ではない）
   - `PATCH_LOCK_DIR="${REPO_ROOT}/.tmp/claude-auto-patch-lock"`（既存 dir 名を維持）
   - timeout 解決: 環境変数 `WHOLEWORK_PATCH_LOCK_TIMEOUT` > `${SCRIPT_DIR}/get-config-value.sh patch-lock-timeout ""` > **default 300**
   - log_interval: 環境変数 `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` > default 30
   - `acquire_lock()` 関数: mkdir loop、PID stamping (`echo $$ > ${PATCH_LOCK_DIR}/pid`)、stale 検出 (`kill -0 $existing_pid` → 死んでいれば `rm -rf` で再取得)、`waiting for lock held by pid=... (age=Ns)` を log_interval 間隔で stderr 出力、timeout 経過で `Patch lock acquisition timeout (Ns)` を出力して exit 1
   - acquire 直後に `trap 'rm -rf "$PATCH_LOCK_DIR" 2>/dev/null || true' EXIT` を設定
   - `--from` 指定時: `git merge "$FROM_BRANCH" --ff-only`、失敗時 `git pull --rebase origin "$BASE_BRANCH"` → 再 `git merge --ff-only`、それでも失敗なら exit 1
   - Conflict marker check: `grep -rn '<<<<<<' .` がヒットしたら error 出力して exit 1（push しない）
   - `git push origin "$BASE_BRANCH"`
   - exit 0（trap が lock 解放）
   - bash 3.2+ 互換（`mkdir`, `kill -0`, `rm -rf`, `cat`, `grep` のみ使用）

2. **Create `tests/worktree-merge-push.bats`** (→ AC2, AC3, AC6) (parallel with 1)
   - `setup()`: `MOCK_DIR="$BATS_TEST_TMPDIR/mocks"` に PATH 追加、`WHOLEWORK_SCRIPT_DIR=$MOCK_DIR`
   - mock `git`: `rev-parse --show-toplevel` で `${BATS_TEST_TMPDIR}/test-repo` を返す、`merge`/`pull`/`push` は exit 0（テストごとに上書き可）
   - mock `get-config-value.sh`: 既定で空文字を返す
   - mock `grep`: 既定で空（conflict marker なし）
   - `teardown()`: `rm -rf "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"`
   - tests:
     - `lock dir is created during execution and released after with --from`
     - `stale PID is reclaimed and lock is acquired`
     - `diagnostic log is output when waiting for a live lock holder`（短 timeout で検証）
     - `timeout is read from .wholework.yml via get-config-value.sh`
     - `default timeout is 300 seconds`（acquire 内の `${...:-300}` 形式を確認）
     - `--from triggers git merge --ff-only`（mock git で merge 呼び出しログ確認）
     - `--from with FF failure triggers git pull --rebase and retry`
     - `--base targets non-main branch`（push origin <base> ログ確認）
     - `conflict markers cause abort with non-zero exit and no push`
   - bash 3.2+ 互換、`BATS_TEST_TMPDIR` 利用で per-test 独立

3. **Update `modules/worktree-lifecycle.md` "Exit: merge-to-main Section"** (after 1) (→ AC2)
   - **`ENTERED_WORKTREE=true` ブロック**:
     - 既存 step 1（ExitWorktree(action: "keep")）と step 2（WORKTREE_BRANCH 保持）は維持
     - 既存 step 3（git merge --ff-only with rebase retry）、step 4（conflict marker check）、step 5（git push）を統合し、新 step 3 として下記に置換:

       ```
       3. Run the new script which acquires a short-lived lock, merges the worktree branch into the base branch, performs the conflict marker check, and pushes — all as a single atomic unit:

          ```bash
          ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh --from "$WORKTREE_BRANCH" [--base "$BASE_BRANCH"]
          ```

          The script handles: lock acquisition (PID stamping, stale detection, configurable timeout), `git merge --ff-only` (with `git pull --rebase` retry on FF failure), conflict marker check, `git push origin <base>`, and lock release via EXIT trap. On script failure (non-zero exit), abort and skip cleanup.
       ```

     - 既存 step 6（cleanup）はそのまま新 step 4 として保持
   - **`ENTERED_WORKTREE=false` ブロック**: 既存の `git push origin main`（または `git push origin $BASE_BRANCH`）を以下に置換:

     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh [--base "$BASE_BRANCH"]
     ```

     （`--from` を省略すると merge 操作はスキップし、lock 取得 + push のみ実行）

4. **Update `scripts/run-auto-sub.sh`** (after 1, parallel with 3) (→ AC1)
   - 削除対象（行番号は現状基準、実装時は再確認）:
     - `REPO_ROOT="..."` および `PATCH_LOCK_DIR="..."` 定数定義（acquire_lock 関数から離して定義されていた場合は両方）
     - `acquire_patch_lock()` 関数定義全体
     - `release_patch_lock()` 関数定義全体
     - XS case 内の `acquire_patch_lock` 呼び出しと `release_patch_lock` 呼び出し
     - S case 内の同様の呼び出し
     - XS / S case の "Patch route commits directly to main, running sequentially..." コメント行
   - 残すもの: `case "$SIZE" in XS) ... S) ...` の `run-code.sh "$SUB_NUMBER" --patch ${BASE_FLAG:-}` 呼び出しと `run_verify_with_retry` 呼び出しはそのまま（lock なしで実行）
   - bash 3.2+ 互換維持

5. **Update `tests/run-auto-sub.bats`** (after 4) (→ AC5)
   - 削除する @test:
     - `PATCH_LOCK: lock dir is created during code execution and released after for Size XS`
     - `PATCH_LOCK: stale PID is reclaimed and lock is acquired`
     - `PATCH_LOCK: diagnostic log is output when waiting for a live lock holder`
     - `PATCH_LOCK: timeout is read from .wholework.yml via get-config-value.sh`
   - 削除する setup() 要素:
     - `get-config-value.sh` mock（run-auto-sub.sh が patch-lock-timeout を読まなくなるため）
   - 削除する teardown() 要素:
     - `rm -rf "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"` 行
   - 追加する @test: `Size XS: lock dir is NOT created by run-auto-sub wrapper`
     - mock run-code.sh は何もせず exit 0
     - run-auto-sub.sh 実行後に `[ ! -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]` をアサート
   - bash 3.2+ 互換維持

6. **Update `modules/detect-config-markers.md`** (parallel with 1, 3) (→ AC4)
   - Marker Definition Table の `patch-lock-timeout` 行:
     - 旧: `Integer string (extract as-is; use \`3600\` if ≤0 or non-numeric) | \`3600\` (used by \`scripts/run-auto-sub.sh\`)`
     - 新: `Integer string (extract as-is; use \`300\` if ≤0 or non-numeric) | \`300\` (used by \`scripts/worktree-merge-push.sh\`)`
   - YAML Parsing Rules の対応行（「is treated as an integer: extract the numeric string; if the value is ≤0 or non-numeric, fall back to the default」の `3600` → `300`、参照先 `scripts/run-auto-sub.sh` → `scripts/worktree-merge-push.sh`）
   - Output Format コードブロックの `PATCH_LOCK_TIMEOUT_SECONDS` 行: `default: "3600"` → `default: "300"`、`falls back to "3600"` → `falls back to "300"`

7. **Update `docs/guide/customization.md`** (parallel with 1, 3, 6) (→ ドキュメント整合性)
   - YAML サンプル:
     - 旧コメント: `# Patch lock timeout for parallel XL sub-issue execution (default: 3600 seconds)`
     - 新コメント: `# Patch lock timeout for main-branch push (default: 300 seconds; lock is held only during git merge + push)`
     - 旧値: `patch-lock-timeout: 3600`
     - 新値: `patch-lock-timeout: 300`
   - Available Keys テーブル行:
     - 旧: ``| `patch-lock-timeout` | integer | `3600` | Patch lock acquisition timeout in seconds. Increase when XL parallel sub-issues time out waiting for the lock. Values ≤0 or non-numeric fall back to `3600`. |``
     - 新: ``| `patch-lock-timeout` | integer | `300` | Lock acquisition timeout in seconds for `git merge --ff-only` + `git push origin main` (the only protected critical section). The default is generous since the lock is held only for seconds. Increase only if push consistently fails to acquire. Values ≤0 or non-numeric fall back to `300`. |``

8. **Update `docs/ja/guide/customization.md`** (after 7) (→ ドキュメント整合性)
   - YAML サンプル: コメントを `# main ブランチへの push 用 lock タイムアウト（デフォルト: 300 秒、lock は git merge + push 中のみ保持）` に変更、値を `300` に変更
   - Available Keys テーブル行: デフォルト `300`、説明を「`git merge --ff-only` + `git push origin main` の lock 取得タイムアウト秒数。lock 保持は数秒のためデフォルトは余裕値。push 取得が常時失敗する場合のみ増やす。0 以下または非数値の場合は `300` にフォールバック。」に変更

9. **Update `docs/structure.md`** (parallel with 1) (→ ドキュメント整合性)
   - Scripts > Process management セクションに行を追加（`scripts/watchdog-reconcile.sh` 行の直後など適切な位置）:
     ``- `scripts/worktree-merge-push.sh` — acquire short-lived patch lock and merge worktree branch + push to main (with rebase retry)``

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh no longer calls acquire_patch_lock/release_patch_lock around run-code.sh --patch invocations; the patch route case directly invokes run-code.sh without lock wrapping" --> `run-auto-sub.sh` から `acquire_patch_lock` / `release_patch_lock` の呼び出しが削除されている
- <!-- verify: rubric "modules/worktree-lifecycle.md's 'Exit: merge-to-main Section' delegates lock+merge+push to scripts/worktree-merge-push.sh, which acquires a short-lived lock with PID stamping and stale detection preserved" --> `worktree-lifecycle.md` の Exit: merge-to-main セクションが新スクリプト `worktree-merge-push.sh` に lock+merge+push を委譲している
- <!-- verify: rubric "The default patch-lock-timeout in scripts/worktree-merge-push.sh (the new lock owner) is set to 300 seconds, with the value documented inline" --> lock timeout のデフォルトが 300 秒に戻されている
- <!-- verify: rubric "modules/detect-config-markers.md's patch-lock-timeout entry has default value 300 (not 3600) and references scripts/worktree-merge-push.sh as the consumer" --> `detect-config-markers.md` の `patch-lock-timeout` 行のデフォルト値が 300 に更新され、参照先が `worktree-merge-push.sh` に変わっている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `run-auto-sub.bats` の全テストが PASS する
- <!-- verify: command "bats tests/worktree-merge-push.bats" --> `worktree-merge-push.bats` の全テストが PASS する

### Post-merge

- 3 件以上の patch route sub-issue を持つ XL Issue で `/auto` を実行し、全 sub-issue が並列の実装フェーズを完走することを確認
- 上記実行で lock timeout 失敗が発生しないこと、および merge-to-main 段階で `git pull --rebase` retry が必要に応じて機能することを確認

## Tool Dependencies

新規ツール権限の追加なし（既存の `Bash`, `Read`, `Edit`, `Write`, `Glob`, `Grep` のみ使用）。

## Notes

### Auto-Resolved Ambiguity Points

- **lock + merge + push 実装方式**: 単一の新スクリプト `scripts/worktree-merge-push.sh` に集約（user 確認済）
  - 理由: PID stamping は単一プロセスのライフサイクル内でのみ正しく機能する。複数 Bash 呼び出しに分割すると acquire 用シェルが終了 → PID dead → 即時 stale 判定で他プロセスが lock を奪う問題が発生
  - 既存パターン: `scripts/` 配下は `claude-watchdog.sh`, `wait-ci-checks.sh` 等の小型単機能スクリプトで構成
- **新スクリプト名**: `worktree-merge-push.sh`（lock + merge + push の操作を反映）
- **lock dir 名**: `.tmp/claude-auto-patch-lock` を維持（後方互換、内部名）
- **設定キー名**: `patch-lock-timeout` を維持（rename はユーザー設定の breaking change）
- **REPO_ROOT 計算**: `git rev-parse --show-toplevel || pwd` を CWD ベースで実行（SCRIPT_DIR 相対ではない）。新スクリプトは ExitWorktree(keep) 直後に呼ばれるため CWD は main repo

### Backward Compatibility

- 環境変数 `WHOLEWORK_PATCH_LOCK_TIMEOUT` は新スクリプトでも引き続き有効
- 環境変数 `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` も同様に維持
- `.wholework.yml` の `patch-lock-timeout` キー名は変更なし（説明文のみ更新）
- 旧 timeout 値 3600 を `.wholework.yml` で設定済みのユーザーはそのまま動作（過剰だが安全側）

### Lock Semantics の拡張（副次的効果）

- 旧設計: lock は `/code patch route` の run-auto-sub.sh ラッパー内でのみ取得 → `/code patch` 同士のみ serialize
- 新設計: lock は worktree-lifecycle.md の Exit: merge-to-main セクションで取得 → `/spec`, `/code patch`, `/verify` の **全 main push** が serialize
- 効果: 並列 `/spec` push 競合や `/verify` push 競合も自動的に防がれる
- リスクなし: lock 保持時間が数秒のため、追加で serialize 対象が増えても実害は無視できる

### Conflict Marker Check 移譲

- 旧: worktree-lifecycle.md step 4 で LLM が `grep -rn '<<<<<<' .` を実行
- 新: 新スクリプトが内部で実行。検出時は push せず exit 1（lock は trap で解放）
- LLM 側の負担減、LLM 実行ミスの可能性も減る

### Test Coverage の責務分離

- `tests/run-auto-sub.bats`: lock テストを削除（lock は run-auto-sub.sh から消える）。代替に negative test 1 件（wrapper が lock を取得しないこと）
- `tests/worktree-merge-push.bats`: 新規。lock の全挙動 + merge + push + conflict check を網羅

### Issue 本文の AC を改善

- 旧 AC #4 は `file_contains "modules/detect-config-markers.md" "patch-lock-timeout"` で key 存在のみを検証していた（default 300 の確認が漏れる）
- 新 AC #4 を rubric に変更し、default 値 300 と参照先 `worktree-merge-push.sh` の両方を検証
- 新規 AC #6 として `bats tests/worktree-merge-push.bats` の実行を追加
- Issue 本文も同期更新

### Architecture Decisions

- `docs/tech.md` Architecture Decisions の確認: 新スクリプトは `claude -p` への CLI フラグではなく shell 単体スクリプト。Architecture Decisions への影響なし
- `docs/structure.md` の Scripts セクションは新スクリプト追加のため更新対象（Step 9）

### bash 3.2+ 互換性

- 新スクリプトは `mkdir`, `kill -0`, `rm -rf`, `cat`, `grep`, `git`, `trap` のみ使用 — すべて bash 3.2 互換
- `mapfile` (bash 4+) や `[[ ... =~ ... ]]` の高度な機能は使用しない

## spec retrospective

### Minor observations

- worktree-lifecycle.md が `/spec`, `/code patch`, `/verify` の 3 経路から共有されている影響を spec 段階で網羅できた。lock 範囲の拡張（patch route 限定 → 全 main push）が単なる副作用ではなく設計上のプラスである点を Notes に明記
- run-auto-sub.sh の `REPO_ROOT="$(git -C "${SCRIPT_DIR}/.." ...)"` 計算は plugin 経由 install ではユーザーの project repo を指さない可能性があるが、現状の `run-auto-sub.sh` は同等の問題を抱えており既存挙動を変えない範囲で新スクリプトは CWD ベースを採用。lock dir 位置の plugin/project ずれは別 Issue で扱うべき潜在課題

### Judgment rationale

- **lock を新スクリプトに集約 vs worktree-lifecycle.md にインライン**: PID stamping を維持するため単一プロセスで lock のライフサイクルを完結させる必要があり、新スクリプト集約を採用（user 確認済）
- **lock dir 名の維持**: 内部識別子のため変更による直接的なユーザー利益はゼロ。一方テスト・既存運用への disruption はゼロ → 維持
- **`patch-lock-timeout` キー名の維持**: `.wholework.yml` を編集済みのユーザーへの breaking change を回避。説明文のみ新セマンティクスに更新
- **デフォルト値 300 の選定**: lock 保持時間が数秒（merge --ff-only + push）のため 300s は 100x 余裕。fail-fast 原則と矛盾せず、ネットワーク不調時の保険値としても十分

### Uncertainty resolution

- `git rev-parse --show-toplevel` が worktree 内から実行された場合の挙動: worktree path を返す（main repo path ではない）。本 Spec では新スクリプトを ExitWorktree(keep) **直後** に呼ぶ前提のため CWD は main repo であり問題なし。Spec 内に明記
- AC #4 の verify command 精度: 旧版の `file_contains "patch-lock-timeout"` は key 存在のみを検証していたため、default 値 300 と参照先の更新を確認できる rubric に置換。Issue 本文も同期更新済

### Improvement Proposals

N/A

## review retrospective

### Spec divergence patterns

The SKILL.md frontmatter changes (adding `worktree-merge-push.sh` to `allowed-tools` in 5 skill files) were necessary for the implementation but not listed in the spec's Changed Files or Tool Dependencies sections. The spec's "新規ツール権限の追加なし" note refers to Claude tool permissions, not bash allowed-tools entries; however, future specs should explicitly enumerate SKILL.md frontmatter updates when a new script is introduced to prevent reviewers from treating these as out-of-scope changes.

### Recurring issues

The conflict marker grep pattern `grep -rn '<<<<<<' .` was migrated as-is from the LLM-executed `worktree-lifecycle.md` step. The LLM was smart enough to filter false positives (documentation backticks, test echo commands), but the shell script equivalent treated any grep match as a real conflict. This regression was not caught by tests because the bats tests use isolated temp directories. Going forward, when migrating LLM-side checks to shell scripts, explicitly verify that the script's pattern is tight enough to avoid false positives that the LLM would have filtered implicitly. Fixed by anchoring to `^<<<<<<`.

### Acceptance criteria verification difficulty

All 6 pre-merge conditions used either `rubric` or `command` hints and were deterministically verifiable. No UNCERTAIN results. The rubric conditions effectively caught the semantic requirements. No improvements needed for verify commands in this spec.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec stage was thorough: identified the shared impact of `worktree-lifecycle.md` across `/spec`, `/code patch`, and `/verify` routes and noted the lock scope expansion (patch route only → all main pushes) as a design plus, not a side effect.
- AC#4 was proactively upgraded from `file_contains` (key existence only) to `rubric` (semantic check of both default value and consumer reference). This improved automation accuracy.
- No improvement proposals from the Spec retrospective.

#### design
- The design (single new script `worktree-merge-push.sh`) was correctly chosen to keep PID stamping within a single process lifecycle. The alternative (inline in `worktree-lifecycle.md`) would have broken stale PID detection.
- Spec notes did not enumerate SKILL.md `allowed-tools` frontmatter updates as a changed file, though the implementation required adding `worktree-merge-push.sh` to 5 SKILL.md files. Future specs should list SKILL.md frontmatter changes explicitly when a new script is introduced.

#### code
- Single squash commit with no fixup/amend patterns. Clean implementation.
- The conflict marker grep pattern (`grep -rn '<<<<<<' .`) was migrated as-is from the LLM-executed step, creating a false-positive risk on documentation and test files. This regression was not caught by bats tests (isolated temp dirs don't contain docs). Caught at review stage and fixed (`^<<<<<<` anchor).

#### review
- Review was effective: caught the 1 critical bug (conflict marker grep false positive) before merge.
- The review retrospective correctly identifies the migration pattern risk: LLM-executed checks use implicit judgment to filter false positives; shell script equivalents need explicit pattern tightening.
- 0 SHOULD/CONSIDER issues; only 1 MUST, which was resolved cleanly.

#### merge
- Single squash commit, no conflicts, all CI jobs passed (DCO, bats, validate-skill-syntax, forbidden-expressions, macOS shell compat).

#### verify
- All 6 pre-merge conditions PASS: 13/13 and 9/9 bats tests passed; 4 rubric conditions confirmed via grep and file reads.
- 2 post-merge manual conditions remain (verify-type: manual) requiring real XL Issue `/auto` execution to confirm parallel run behavior.
- Verify commands were well-designed: rubric conditions for semantic checks, command conditions for test suite runs. No UNCERTAIN or FAIL results.

### Improvement Proposals
- When migrating LLM-executed checks to shell scripts, add a checklist item to verify the grep/awk pattern does not false-positive on documentation or test fixture files. The implicit LLM filter does not carry over to shell context.
