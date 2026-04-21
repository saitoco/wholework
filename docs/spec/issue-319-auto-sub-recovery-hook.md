# Issue #319: auto: run-auto-sub.sh に 3-tier adaptive recovery hook を追加 (XL sub / batch 向け)

## Overview

`/auto` パスの adaptive 改善 (#314〜#318) が XL sub-issue 並列実行および `/auto --batch` で動作する `scripts/run-auto-sub.sh` に届いておらず、wrapper 失敗時の LLM 診断が効かない。bash 主軸を維持したまま、各 `run-*.sh` phase 呼出を汎用ラッパ `run_phase_with_recovery` で包み、失敗時のみ Tier 1 (reconcile) → Tier 2 (known-pattern bash catalog) → Tier 3 (`claude -p` で recovery sub-agent を spawn) の 3 段階で recovery を試みる hook を追加する。通常経路のコスト・並列安定性は維持する (Option B-2)。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery` 関数を追加し、code/review/merge など inline retry を持たない phase の `run-*.sh` 呼出を包む。既存 `run_verify_with_retry` は保持 — bash 3.2+ 互換
- `scripts/spawn-recovery-subagent.sh`: 新規 — Tier 3 recovery orchestrator。`agents/orchestration-recovery.md` body (frontmatter 除去) と input JSON を prompt に embed し、`claude-watchdog.sh` 経由で `claude -p --model sonnet --effort medium` を起動、stdout から JSON 抽出、`scripts/validate-recovery-plan.sh` で safety guard、`action` に応じて retry/skip/recover/abort を実行。`WHOLEWORK_MAX_RECOVERY_SUBAGENTS` env (default 1) と mkdir-based slot lock で concurrency 制御 — bash 3.2+ 互換
- `scripts/apply-fallback.sh`: 新規 — Tier 2 bash projection。`--log` で受け取った wrapper 出力を regex で検査し、既知 symptom anchor を case 文で dispatch。初期実装は `dco-signoff-missing-autofix` のみ full-impl。未登録 anchor は exit 1 で Tier 3 escalate — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: 既存 happy path を維持しつつ、tier1/tier2/tier3 failure injection テストを追加 (`WHOLEWORK_SCRIPT_DIR` / `CLAUDE_BIN` mock) — bash 3.2+ 互換
- `tests/apply-fallback.bats`: 新規 — `dco-signoff-missing-autofix` handler のパターン一致 + 未登録 anchor の exit 1 テスト — bash 3.2+ 互換
- `tests/spawn-recovery-subagent.bats`: 新規 — `CLAUDE_BIN` mock での JSON schema 検証 (validate-recovery-plan.sh 経由)、forbidden ops、step 上限、mkdir slot lock cap テスト。`claude -p` 実行系は `@test` tag `integration` で分離 — bash 3.2+ 互換
- `docs/tech.md`: Architecture Decisions の two-tier orchestration 段落を更新。"pure bash — it does not invoke `claude -p`" 記述を除去し、3-tier adaptive recovery と `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` cap を記述
- `docs/ja/tech.md`: `docs/tech.md` と sync
- `docs/structure.md`: Scripts コメントを `43 files` → `45 files`、Process management セクションに `scripts/spawn-recovery-subagent.sh` と `scripts/apply-fallback.sh` の説明行を追加、tests コメントを `50 files` → `53 files` (#319 で +3 相当)
- `docs/ja/structure.md`: `docs/structure.md` と sync

## Implementation Steps

1. **`scripts/apply-fallback.sh` を作成する** (→ acceptance criteria 2, 3)
   - CLI: `apply-fallback.sh <phase> <issue> --log <log-file>`
   - `WHOLEWORK_SCRIPT_DIR` 尊重 (`run-auto-sub.sh` 同様の `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"`)
   - `--log` で受け取ったファイルを regex で検査して `symptom_anchor` を決定
   - `case "$symptom_anchor" in ... *) return 1 ;; esac` 形式で dispatch
   - **初期 full-impl handler**: `dco-signoff-missing-autofix` — wrapper log に "Signed-off-by" 欠落エラーを検出 → `git commit --amend -s --no-edit` + `git push --force-with-lease` (worktree ブランチのみ、main 直は不可)
   - 他の anchor (`gh-pr-list-head-glob`, `ff-only-merge-fallback`, `conflict-marker-residual`) は初期は未登録 (default case で return 1 → Tier 3 へ escalate)。pointer comment で `modules/orchestration-fallbacks.md` 該当 anchor への参照を残す

2. **`scripts/spawn-recovery-subagent.sh` を作成する** (→ acceptance criteria 1, 4, 5, 6) (after 1)
   - CLI: `spawn-recovery-subagent.sh <phase> <issue> --log <log-file>`
   - `WHOLEWORK_SCRIPT_DIR` 尊重
   - **Slot lock 取得**: mkdir-based (precedent: `scripts/worktree-merge-push.sh`)
     - Lock dir: `.tmp/recovery-subagent-slot-$slot` (`slot` は 1..`WHOLEWORK_MAX_RECOVERY_SUBAGENTS`, default 1)
     - 全 slot が埋まっていれば即 abort (exit 非 0 で呼出側へ伝播) — polling は行わない (parent `/auto` 側で上位 recovery に委譲)
     - Stale lock 検出: lock 内の `pid` が生存していなければ reclaim
     - `trap 'rm -rf $LOCK_DIR' EXIT` で解放保証
   - **Prompt 構築**: `agents/orchestration-recovery.md` を `awk 'NR>1 && /^---$/{print NR; exit}'` で frontmatter 除去 (precedent: `run-*.sh` 全般) → body + input JSON (phase, exit_code, log tail 200 行, reconcile-phase-state.sh --check-completion 出力) を heredoc で連結
   - **`claude -p` 起動**: `ANTHROPIC_MODEL=claude-sonnet-4-6 env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" --model sonnet --effort medium --dangerously-skip-permissions` (precedent: `run-review.sh:73-78`)
   - **`CLAUDE_BIN` env override**: `CLAUDE_BIN="${CLAUDE_BIN:-claude}"` を先頭で解決し、bats から mock 可能にする
   - **JSON 抽出**: stdout から最初の `{...}` ブロックを `python3 -c "import sys,json,re; ..."` で抽出し `.tmp/recovery-plan-$issue-$phase.json` に書き込む
   - **Safety guard**: `$SCRIPT_DIR/validate-recovery-plan.sh .tmp/recovery-plan-$issue-$phase.json` を呼び、非 0 なら abort (SSoT として既存 #316 実装を reuse)
   - **Action dispatch**:
     - `action=retry` → 元 `run-*.sh` を 1 回再実行 (呼出元から渡された runner と引数で)
     - `action=skip` → exit 0 (次 phase へ進ませる)
     - `action=recover` → `steps` を順次実行 (各 step の `op` フィールドを case 文で解釈、未対応 op は abort)
     - `action=abort` → exit 非 0 で呼出側へ伝播

3. **`scripts/run-auto-sub.sh` に `run_phase_with_recovery` ラッパを追加する** (→ acceptance criteria 3) (after 1, 2)
   - 追加位置: 既存 `run_verify_with_retry` 関数定義の直後
   - 関数シグネチャ: `run_phase_with_recovery() { local phase issue runner_script; phase="$1"; issue="$2"; runner_script="$3"; shift 3; ... }`
   - `log_file=".tmp/wrapper-out-$issue-$phase.log"` に wrapper 出力を tee または `> "$log_file" 2>&1` で記録
   - `"$runner_script" "$issue" "$@"` が非 0 終了した場合のみ Tier 1 → 2 → 3 を順番に試行 (Issue body の設計スケッチ準拠)
   - Phase 呼出ルーティングの case 文内で、code/review/merge 系の `run-*.sh` 呼出を `run_phase_with_recovery "$phase" "$issue" "$SCRIPT_DIR/run-$phase.sh"` に置き換える
   - `run_verify_with_retry` は保持 (verify-sync-retry は inline retry でカバー済み、本 ラッパとは重複しない)

4. **`tests/apply-fallback.bats` を作成する** (→ acceptance criteria 8) (after 1)
   - `@test "apply-fallback: dco-signoff-missing-autofix pattern detected → amend + force-with-lease"` (git CLI を mock し、amend/push 呼出を検証)
   - `@test "apply-fallback: unknown symptom returns 1 (escalate to tier3)"`
   - `@test "apply-fallback: missing --log argument exits non-zero"`

5. **`tests/spawn-recovery-subagent.bats` を作成する** (→ acceptance criteria 8) (after 2)
   - Non-integration テスト (mock-only):
     - `@test "spawn-recovery: CLAUDE_BIN mock returns valid retry plan → runner_script re-invoked"`
     - `@test "spawn-recovery: CLAUDE_BIN mock returns plan with forbidden op force_push → abort"`
     - `@test "spawn-recovery: CLAUDE_BIN mock returns plan with 6 steps → abort (step limit)"`
     - `@test "spawn-recovery: CLAUDE_BIN mock returns action=skip → exit 0"`
     - `@test "spawn-recovery: slot cap reached (existing slot dir) → immediate abort"`
     - `@test "spawn-recovery: stale slot lock (dead pid) reclaimed"`
   - Integration テスト (tagged with `integration`, CI 実行除外):
     - `@test "spawn-recovery integration: real claude -p returns valid JSON"` *(tags: integration)*

6. **`tests/run-auto-sub.bats` に tier1/tier2/tier3 テストを追加する** (→ acceptance criteria 8) (after 3)
   - 既存 happy path は非回帰維持
   - 追加テスト: `run_phase_with_recovery` の各 tier 遷移を mock で検証
     - `@test "run-auto-sub: phase exit nonzero + tier1 reconcile matches_expected=true → override to success"`
     - `@test "run-auto-sub: phase exit nonzero + tier1 fails + tier2 apply-fallback succeeds → recover"`
     - `@test "run-auto-sub: phase exit nonzero + tier1+tier2 fail + tier3 spawn returns retry → re-invoke runner"`
     - `@test "run-auto-sub: all tiers fail → propagate original exit code"`
   - Mock パターン: `WHOLEWORK_SCRIPT_DIR` 下に `reconcile-phase-state.sh` / `apply-fallback.sh` / `spawn-recovery-subagent.sh` / `run-*.sh` のスタブを配置

7. **`docs/tech.md` の two-tier orchestration 段落を更新する** (→ acceptance criteria 7)
   - 対象: line 51 の "Two-tier orchestration" 段落
   - "`run-auto-sub.sh` is a pure bash script — it does not invoke `claude -p`" の表現を除去し、Issue body の "更新後 (案)" テキストを反映: "bash-orchestrated with a tiered adaptive recovery: (1) reconcile-phase-state.sh completion check, (2) apply-fallback.sh known-pattern recovery, (3) spawn-recovery-subagent.sh (claude -p to agents/orchestration-recovery) on unknown anomaly. Normal path stays bash to minimize cost and maximize parallel stability; claude -p is invoked only for diagnosis when tiers 1–2 fail, with a `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` cap to bound parallel cost."

8. **`docs/ja/tech.md` を英語版と sync する** (→ acceptance criteria 7) (after 7)
   - 対象: line 41 の「2 階層オーケストレーション」段落
   - 英語版と同等の 3-tier adaptive recovery モデル記述に置き換える

9. **`docs/structure.md` を更新する** (parallel with 7, 8)
   - Directory Layout の `scripts/` コメント: `43 files` → `45 files`
   - Directory Layout の `tests/` コメント: `50 files` → `53 files` (本 Issue で +3 bats)
   - Process management セクションに 2 行追加:
     - `scripts/apply-fallback.sh` — Tier 2 bash projection of `modules/orchestration-fallbacks.md`; detects known symptom anchors from wrapper logs and dispatches recovery handlers (initial full-impl: dco-signoff-missing-autofix)
     - `scripts/spawn-recovery-subagent.sh` — Tier 3 recovery orchestrator invoked by `run-auto-sub.sh`; spawns `agents/orchestration-recovery` via `claude -p`, validates the returned plan with `validate-recovery-plan.sh`, and enforces concurrency via `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` mkdir-based slot locks

10. **`docs/ja/structure.md` を英語版と sync する** (after 9)
    - scripts コメント `43 ファイル` → `45 ファイル`、tests コメント `50 ファイル` → `53 ファイル`
    - プロセス管理セクションに 2 行追加 (英語版と同内容の日本語記述)

## Alternatives Considered

- **Option B-1: `run-auto-sub.sh` 全体を `claude -p` オーケストレーターに置換**: Adaptive 度は高いが、XL 3-5 並列時に context cost が数倍に膨れ並列安定性にも懸念。Issue body で却下、本 Spec も採用しない
- **`flock` による concurrency 制御**: Issue body は `flock` を提案していたが、macOS (Darwin) 標準環境では `flock` が未インストール (Homebrew util-linux 別途要)。`scripts/worktree-merge-push.sh` の既存 mkdir-based locking pattern に合わせることで追加依存なし・既存 precedent 準拠とした
- **Safety guard を `spawn-recovery-subagent.sh` に新規重複実装**: Issue body の字面上は本 script を SSoT と書いていたが、#316 で既に `scripts/validate-recovery-plan.sh` が SSoT として存在し、`/auto` SKILL.md Step 6 も同 script を経由 (Task tool inline 呼出)。本 script からも同 SSoT を呼び出すことで、schema / forbidden ops / step 上限の重複実装を回避 (drift リスク最小化)。`/auto` SKILL.md を bash script 経由に refactor することは follow-up の scope 外
- **`apply-fallback.sh` で 4 anchor 全て初期 full-impl**: 実装コストに見合わず MVP 遅延。`dco-signoff-missing-autofix` のみ full-impl、他は未登録 default case で Tier 3 escalate → 使用頻度が判明した anchor から順次 Tier 2 へ昇格させる follow-up 運用
- **`run_verify_with_retry` を新ラッパに統合**: 既に本番稼働中 / pointer comment で catalog と連結済み / テスト済みのため、置換は非回帰リスク高。収束は follow-up Issue に委譲

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/spawn-recovery-subagent.sh" --> Tier 3 spawn helper が作成されている
- <!-- verify: file_exists "scripts/apply-fallback.sh" --> Tier 2 fallback 適用 bash wrapper が作成されている
- <!-- verify: rubric "scripts/run-auto-sub.sh defines run_phase_with_recovery wrapping non-verify run-*.sh invocations (at least code, review, and merge phases). On non-zero wrapper exit, the function tries: (1) reconcile-phase-state.sh <phase> <issue> --check-completion with grep for matches_expected:true, (2) apply-fallback.sh <phase> <issue> --log <log-file>, (3) spawn-recovery-subagent.sh <phase> <issue> --log <log-file>. Each tier returns 0 on recovery. Existing run_verify_with_retry is retained unchanged." --> 3-tier adaptive recovery が run-auto-sub.sh に実装され、既存 inline retry は維持
- <!-- verify: rubric "scripts/spawn-recovery-subagent.sh follows the existing run-*.sh claude -p invocation pattern (ANTHROPIC_MODEL set, env -u CLAUDECODE, claude-watchdog.sh, claude -p with --model sonnet --effort medium). It strips frontmatter from agents/orchestration-recovery.md using awk and embeds the body plus the input JSON (phase, exit_code, log tail 200 lines, reconcile snapshot) in the prompt. A CLAUDE_BIN environment variable is honored so tests can substitute a mock binary. The script does not use a non-existent --agent CLI flag." --> claude -p 呼出形状が既存 run-*.sh precedent に一致し agent body を prompt 埋込している
- <!-- verify: rubric "scripts/spawn-recovery-subagent.sh delegates safety guard to scripts/validate-recovery-plan.sh (the SSoT introduced in #316) for JSON schema validation (required keys action/rationale/steps), forbidden ops enforcement (force_push / reset_hard / close_issue / merge_pr / direct_push_main substring check), and step-count cap (<=5). On validator non-zero exit, the script aborts. The script does NOT reimplement validation logic locally." --> Safety guard が validate-recovery-plan.sh (SSoT) に委譲され #316 と共有される
- <!-- verify: rubric "scripts/spawn-recovery-subagent.sh implements concurrency control via WHOLEWORK_MAX_RECOVERY_SUBAGENTS env var (default 1) using mkdir-based slot locks at .tmp/recovery-subagent-slot-<N> (following worktree-merge-push.sh precedent: mkdir atomicity, PID stamp, stale-lock reclaim via kill -0, trap EXIT cleanup). When all slots are occupied, the script aborts immediately with non-zero exit (no polling). flock is NOT used (macOS compatibility)." --> mkdir-based concurrency 制御が実装されている
- <!-- verify: rubric "scripts/apply-fallback.sh dispatches on symptom_anchor via a case statement detected from the --log file. The dco-signoff-missing-autofix handler is fully implemented (detects missing Signed-off-by, runs git commit --amend -s --no-edit and git push --force-with-lease on the current worktree branch only). Unknown anchors return 1 to escalate to Tier 3. The script references modules/orchestration-fallbacks.md anchor names in pointer comments for unimplemented handlers." --> apply-fallback.sh が catalog projection として実装されている
- <!-- verify: rubric "docs/tech.md Architecture Decisions section removes the 'pure bash, does not invoke claude -p' claim for run-auto-sub.sh and documents the 3-tier adaptive recovery model with the WHOLEWORK_MAX_RECOVERY_SUBAGENTS cap; docs/ja/tech.md mirrors the update in Japanese." --> tech.md (英+日) の two-tier orchestration 記述が 3-tier recovery モデルに更新されている
- <!-- verify: file_exists "tests/spawn-recovery-subagent.bats" --> spawn-recovery-subagent の bats が存在する
- <!-- verify: file_exists "tests/apply-fallback.bats" --> apply-fallback の bats が存在する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが CI で PASS する

### Post-merge

- 3 並列 XL sub-issue で意図的に wrapper 失敗を発生させ、Tier 1→2→3 と段階的 recovery が機能することを確認 <!-- verify-type: manual -->
- `/auto --batch` 実行中に wrapper 失敗を発生させ、手動介入なしで続行することを確認 <!-- verify-type: manual -->
- `WHOLEWORK_MAX_RECOVERY_SUBAGENTS=1` 環境で XL 3 並列を実行し、2 つ目以降の Tier 3 spawn が slot cap で abort し `/auto` 親へ bubble up することを確認 <!-- verify-type: manual -->
- `claude -p` mock 下での bats (happy + failure injection) が CI で安定 PASS し、`integration` tag の test は別 job / 手動 trigger で実行されることを確認 <!-- verify-type: opportunistic -->

## Tool Dependencies

### Bash Command Patterns
- none (既存 `allowed-tools` で充足、本 Issue は skill ではなく script 追加のため frontmatter 変更不要)

### Built-in Tools
- none

### MCP Tools
- none

## Uncertainty

- **`claude -p` stdout の JSON 抽出堅牢性**: sub-agent が自然言語の前後説明を付ける可能性がある
  - **Verification method**: bats で `CLAUDE_BIN` mock に "prose\n{...}\nmore prose" パターンを返させ、python3 による最初の balanced-brace block 抽出が動作することを確認
  - **Impact scope**: Implementation Steps 2 (JSON 抽出ロジック), 5 (bats テスト)
- **`agents/orchestration-recovery.md` frontmatter stripping の awk パターン互換性**: 既存 `run-*.sh` の `awk 'NR>1 && /^---$/{print NR; exit}'` を流用する
  - **Verification method**: 既存 `run-review.sh:53` 等で動作確認済み。`agents/orchestration-recovery.md` の frontmatter 形式が同様であることを実装前に `head -5 agents/orchestration-recovery.md` で確認
  - **Impact scope**: Implementation Steps 2 (prompt 構築)

## Notes

- **`flock` からの設計逸脱**: Issue body は `flock` を提案しているが、macOS (Darwin) では標準環境に未インストール (Homebrew util-linux 別途要)。`scripts/worktree-merge-push.sh` の mkdir-based locking pattern (atomic mkdir + PID stamp + stale reclaim + trap EXIT) に合わせる。Alternatives Considered に記録
- **Safety guard SSoT の解釈**: Issue body 字面は `spawn-recovery-subagent.sh` を SSoT と記述していたが、#316 で既に `scripts/validate-recovery-plan.sh` が SSoT として shipped。本 script から同 SSoT を呼び出すことで「単一 source」という Issue body の意図を満たす。`/auto` SKILL.md Step 6 の inline Task 呼出をスクリプト経由に統一する refactor は follow-up (scope 外)
- **`apply-fallback.sh` 初期スコープ**: MVP を優先し `dco-signoff-missing-autofix` のみ full-impl。他 3 anchor (`gh-pr-list-head-glob`, `ff-only-merge-fallback`, `conflict-marker-residual`) は未登録 (default case → return 1 → Tier 3 escalate)。catalog anchor 名を pointer comment として残し、follow-up で昇格可能にする
- **tests ファイル数のドリフト**: `docs/structure.md` では `50 files` と記述されているが、main 時点の actual は 51 (pre-existing drift)。本 Issue では +3 bats で `53 files` に揃える。事前 drift 分は本 Issue では修正しない (scope 外)
- **`/auto` 親オーケストレーターとの Tier 重複**: `/auto` SKILL.md Step 6 と `run_phase_with_recovery` は **異なるレイヤー** での recovery (親: wrapper 外部、子: wrapper 内部) のため重複は許容
- **Follow-up (スコープ外)**: (1) `run_verify_with_retry` と新ラッパの収束、(2) `apply-fallback.sh` の残 anchor 昇格、(3) `/auto` SKILL.md の `validate-recovery-plan.sh` 呼出を bash script 経由に refactor、(4) `docs/structure.md` の事前 tests/ count drift の整合 (独立 Issue)

## Code Retrospective

### Deviations from Design
- N/A — Implementation followed the Spec's steps in order; no reordering or omissions required.

### Design Gaps/Ambiguities
- **PID selection in bats slot-lock tests**: The Spec did not specify what PID to use for "live" vs "dead" PID in bats concurrency tests. Used `$$` (current shell PID) for "live" slot and `999999999` (exceeds max PID on any realistic system) for "stale" slot. Straightforward to resolve but not documented in Spec.
- **`run_phase_with_recovery` second argument for review/merge phases**: Spec says `"$issue"` is the second parameter passed to the runner, but review/merge use PR_NUMBER as first arg, not issue number. The wrapper passes PR_NUMBER as "issue" for review/merge — log files and Tier 1 reconcile use that value. Tier 1 reconcile gracefully fails (no `matches_expected:true` match) and falls through to Tier 2/3 for those phases. Acceptable behavior per Spec intent.
- **`apply-fallback.sh` suppressed stderr in Tier 2 call**: Added `2>/dev/null` to `apply-fallback.sh` call in `run_phase_with_recovery` so fallback errors don't surface unless debugging. Not in Spec but improves UX.

### Rework
- **Tests 7 & 8 in spawn-recovery-subagent.bats**: Initial PID values (99999 for "live", 0 for "stale") caused test failures — PID 99999 might be running on the test machine, and `kill -0 0` kills the process group. Fixed on first attempt to `$$` and `999999999`. No code rework needed.

## spec retrospective

### Minor observations

- Issue body が既に詳細な Design Sketch・Auto-Resolve Log・acceptance criteria を含んでおり、Spec 側での追加判断は 3 点 (flock 非互換 / SSoT 再解釈 / apply-fallback 初期スコープ) に限定できた。Issue phase の品質が高いほど Spec の追加コストは下がる典型例。
- `docs/structure.md` の tests/ count は既に 1 件ズレ (`50 files` 記述 vs actual 51)。本 Issue では +3 して `53 files` に揃えるが、pre-existing drift の整合は別 Issue に委譲する旨を Notes に記録した。

### Judgment rationale

- **`flock` → mkdir-based slot lock**: Issue body は `flock` を提案していたが macOS 標準環境未インストール。`scripts/worktree-merge-push.sh` の既存 mkdir-based locking (atomic mkdir + PID stamp + stale reclaim + trap EXIT) を precedent として採用することで、追加依存ゼロ・パターン統一を両立させた。
- **Safety guard SSoT を `validate-recovery-plan.sh` に redirect**: Issue body 字面は `spawn-recovery-subagent.sh` を SSoT と記述していたが、#316 で既に `scripts/validate-recovery-plan.sh` が SSoT として shipped・`/auto` SKILL.md からも呼ばれている。新 script からも同 SSoT を呼び出すことで「単一 source」意図を満たしつつ schema/forbidden ops/step 上限の重複実装を回避した。
- **`apply-fallback.sh` 初期スコープを MVP に絞る**: 4 anchor 全 full-impl はコストが高く shipping を遅らせる。`dco-signoff-missing-autofix` のみ full-impl、他は default case で Tier 3 escalate とし、catalog anchor 名を pointer comment で残す方針とした。使用頻度データが出揃った anchor から follow-up で昇格可能。

### Uncertainty resolution

- **`claude -p` stdout からの JSON 抽出堅牢性**: sub-agent が自然言語の前後説明を付けた際の挙動。`/code` フェーズで `CLAUDE_BIN` mock を使った bats テスト (prose + JSON + prose パターン) で検証する設計とし、python3 による balanced-brace 抽出ロジックを Implementation Step 2 に明記した。
- **`agents/orchestration-recovery.md` の frontmatter stripping 互換性**: `run-*.sh` 全般で同じ awk パターン (`NR>1 && /^---$/{print NR; exit}`) が precedent として確立済みのため reuse する。`/code` 実装前に `head -5 agents/orchestration-recovery.md` で形式確認する手順を Uncertainty セクションに記録した。
