# Issue #769: auto-events — phase event emission for run-*.sh wrappers

## Overview

`run-issue.sh` と `run-spec.sh` が `phase_start` / `phase_complete` event を emit しておらず、`/audit auto-session` レポートの Per-Issue Durations が実態の約 50% しか捕捉できていない。`run-code.sh` と `run-auto-sub.sh` は既に `emit-event.sh` を source して emit 済みのため、未対応の 2 wrapper に同じパターンを適用し、全 run-*.sh で共通 helper (`scripts/emit-event.sh`) を介した phase event emission を達成する。

あわせて `modules/event-emission.md` を新設し、各 wrapper の event emission contract を SSoT として文書化する。

## Consumed Comments

- 2026-06-27: saito (MEMBER/OWNER) による Issue Retrospective を消費。Auto-resolved items:
  1. `run-spec.sh` の AC 欠落 → AC 追加済み (issue body 反映済み)
  2. `run-merge.sh` / `run-review.sh` はスコープ外 (既に emit_event あり)
  3. 共通 helper の実装アプローチ → 実装者判断 (既存の `emit-event.sh` 直接 source パターンを採用)

## Changed Files

- `scripts/run-issue.sh`: AUTO_EVENTS_LOG + PGID/AUTO_SESSION_ID + `source emit-event.sh` + `_maybe_emit_phase_complete` + trap + `_EMIT_PHASE_OWNED` pattern + `emit_event phase_start/phase_complete` を追加 — bash 3.2+ compatible
- `scripts/run-spec.sh`: PGID/AUTO_SESSION_ID + `source emit-event.sh` + `_maybe_emit_phase_complete` + trap + `_EMIT_PHASE_OWNED` pattern + `emit_event phase_start/phase_complete` を追加 (AUTO_EVENTS_LOG は既存) — bash 3.2+ compatible
- `modules/event-emission.md`: 新規 — event emission contract SSoT (phase event スキーマ、emit-event.sh 使用法、wrapper 適用表)
- `tests/run-issue.bats`: setup() に `emit-event.sh` no-op mock 追加 + emit 系 @test 3 件追加
- `tests/run-spec.bats`: setup() に `emit-event.sh` no-op mock 追加 + emit 系 @test 3 件追加
- `docs/structure.md`: modules カウント (40 files) → (41 files) に更新、Key Modules に `event-emission.md` エントリ追加
- `docs/ja/structure.md`: 翻訳 sync — "(40 ファイル)" → "(41 ファイル)"、Key Modules に日本語エントリ追加

## Implementation Steps

1. `scripts/run-issue.sh` に emit_event パターンを追加 (→ AC: grep emit_event run-issue.sh, rubric: 共通 helper):
   - `SCRIPT_DIR=...` の直後・`PERMISSION_MODE=...` の直前に以下を挿入:
     ```
     AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
     export AUTO_EVENTS_LOG
     PGID=$(ps -o pgid= -p $$ | tr -d ' ')
     AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
     export AUTO_SESSION_ID
     source "$SCRIPT_DIR/emit-event.sh"

     _maybe_emit_phase_complete() { ... }  # run-merge.sh と同一パターン
     trap '_maybe_emit_phase_complete' EXIT

     _EMIT_PHASE_OWNED=""
     if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
       _EMIT_PHASE_OWNED=1
       export EMIT_ISSUE_NUMBER="$ISSUE_NUMBER"
       export EMIT_PHASE_NAME="issue"
       emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
     fi
     ```
   - reconcile check 後・最終 `echo "---"` の直前に追加:
     ```
     if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
       emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
     fi
     ```

2. `scripts/run-spec.sh` に emit_event パターンを追加 (after 1, → AC: grep emit_event run-spec.sh, rubric: 共通 helper):
   - 既存の `export AUTO_EVENTS_LOG` 直後・`PERMISSION_MODE=...` 直前に挿入:
     ```
     PGID=$(ps -o pgid= -p $$ | tr -d ' ')
     AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
     export AUTO_SESSION_ID
     source "$SCRIPT_DIR/emit-event.sh"

     _maybe_emit_phase_complete() { ... }  # run-merge.sh と同一パターン
     trap '_maybe_emit_phase_complete' EXIT

     _EMIT_PHASE_OWNED=""
     if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
       _EMIT_PHASE_OWNED=1
       export EMIT_ISSUE_NUMBER="$ISSUE_NUMBER"
       export EMIT_PHASE_NAME="spec"
       emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
     fi
     ```
   - reconcile check 後・最終 `echo "---"` 直前に追加:
     ```
     if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
       emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
     fi
     ```

3. `modules/event-emission.md` を新規作成 (→ AC: rubric: SSoT 文書化):
   - 以下のセクションを含む:
     - Purpose: auto-events.jsonl への phase event emission の SSoT
     - Events: `phase_start` / `phase_complete` / `wrapper_exit` / `token_usage` スキーマ (emit-event.sh ドキュメントから転記)
     - Usage: `source emit-event.sh` + `_EMIT_PHASE_OWNED` パターンの説明
     - Wrapper Coverage Table: 全 run-*.sh が emit する phase 一覧 (issue / spec / code-pr / code-patch / code / review / merge)
     - Backfill: `_maybe_emit_phase_complete()` トラップの役割

4. `tests/run-issue.bats` と `tests/run-spec.bats` を更新 (after 1,2 → test coverage):
   - 各ファイルの `setup()` に `emit-event.sh` no-op mock を追加:
     ```
     cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
     emit_event() { return 0; }
     MOCK
     ```
   - 各ファイルに以下の 3 @test を追加 (run-merge.bats と同パターン):
     - `"emit: phase_start emitted when EMIT_PHASE_NAME is not set"` — emit_event mock でログを記録し `phase_start` を確認
     - `"emit: phase_start not emitted when EMIT_PHASE_NAME is pre-set (no double emit)"` — `EMIT_PHASE_NAME` を事前設定して run すると `phase_start` が emit されないことを確認
     - `"emit: phase_complete emitted on success"` — 成功時に `phase_complete` が emit されることを確認

5. `docs/structure.md` と `docs/ja/structure.md` を更新 (after 3 → SHOULD: docs sync):
   - `docs/structure.md`: `(40 files)` → `(41 files)`、Key Modules に `modules/event-emission.md — event emission contract SSoT (phase event schema, _EMIT_PHASE_OWNED pattern, wrapper coverage)` を追加
   - `docs/ja/structure.md`: `(40 ファイル)` → `(41 ファイル)`、Key Modules に対応する日本語エントリを追加

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/lib/phase-events.sh または同等の共通 helper を介して run-issue.sh / run-spec.sh / run-code.sh / run-auto-sub.sh がそれぞれの phase 開始・終了で phase_start / phase_complete event を emit する仕組みが導入されている" --> 全 run-*.sh が共通 helper で phase event を emit する
- <!-- verify: grep "emit_event" "scripts/run-auto-sub.sh" --> run-auto-sub.sh に emit_event 呼び出しが含まれる
- <!-- verify: grep "emit_event" "scripts/run-issue.sh" --> run-issue.sh に emit_event 呼び出しが含まれる
- <!-- verify: grep "emit_event" "scripts/run-spec.sh" --> run-spec.sh に emit_event 呼び出しが含まれる
- <!-- verify: grep "emit_event" "scripts/run-code.sh" --> run-code.sh に emit_event 呼び出しが含まれる
- <!-- verify: rubric "modules/event-emission.md または同等 SSoT に各 wrapper の event emission contract が文書化されている" --> event emission contract の SSoT 文書追加

### Post-merge

- 次回 batch 実行後の `/audit auto-session --full` で、Per-Issue Durations table が actual processed Issue 数と一致することを観察 (data-layer と L3 retro の乖離率 < 10%) <!-- verify-type: manual -->

## Notes

- `run-code.sh` と `run-auto-sub.sh` は既に `emit-event.sh` を source して `emit_event` を呼び出している。Issue body の Purpose は「強制」の文脈であり、これらは既に満たしている。実装対象は `run-issue.sh` と `run-spec.sh` のみ。
- `run-spec.sh` は既に `AUTO_EVENTS_LOG` を export しているが `AUTO_SESSION_ID` と `source emit-event.sh` が欠落している。
- `_maybe_emit_phase_complete()` は `AUTO_SESSION_ID` が空の場合に return する (standalone 実行時も `emit_event` 呼び出し自体は機能する — session_id が空文字列になるだけ)。
- `EMIT_PHASE_NAME` が事前設定されている場合 (`run-auto-sub.sh` から呼ばれる場合) は `_EMIT_PHASE_OWNED=""` のまま → `phase_start` / `phase_complete` を emit しない (二重 emit 防止)。
- Auto-resolved (Non-interactive mode): 共通 helper は新規 `scripts/lib/phase-events.sh` ではなく既存 `scripts/emit-event.sh` を直接 source するアプローチを採用。Issue Retrospective で確認済みの判断。
- `modules/event-emission.md` 追加で `docs/structure.md` の module count が 40 → 41 になる。

## review retrospective

### Spec vs. implementation divergence patterns

`modules/event-emission.md` (PR で新規追加) の Backfill セクションで「SIGTERM / watchdog timeout exits を反映する」という記述と、guard 条件「Exit code must be 0」が矛盾していた。SIGTERM は exit code 143 (非ゼロ) を返すため実際には backfill が発火しない。新設ドキュメントへのレビューが必要なことを示す事例。今後 SSoT ドキュメントを新規作成する際は、コードの guard 条件と説明文の一貫性をレビューチェックリストに含めることを推奨。

### Recurring issues

特記なし。emit 系テストは全 PASS で、既知の pre-existing failure (append-loop-state-heartbeat.bats tests 11-15) は本 PR と無関係であることを確認。

### Acceptance criteria verification difficulty

全 Pre-merge 条件が PASS (UNCERTAIN なし)。rubric verify command での「scripts/lib/phase-events.sh または同等の共通 helper」の「同等」判定は AI 判断に依存しており、`scripts/emit-event.sh` を `scripts/lib/phase-events.sh` の同等として認定する判断が含まれる。verify command の rubric テキストに実際の helper パス (emit-event.sh) を明示することで将来の判定精度が上がる可能性がある。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash merged PR #801 into main despite ci_failing status (non-interactive auto-resolve); CI failure was confirmed pre-existing on main before merge
- Local branch deletion failed due to code+issue-769 worktree still active — remote branch was successfully deleted by gh pr merge; local cleanup deferred to worktree removal

### Deferred Items
- Post-merge observation: `/audit auto-session --full` Per-Issue Durations accuracy (< 10% deviation from L3 retro) — requires next batch execution to verify
- CONSIDER: test assertion style improvement for "no double emit" test (EMIT_LOG existence check) — left for future quality pass
- Local branch `worktree-code+issue-769` removal: run `git branch -d worktree-code+issue-769` after removing the code+issue-769 worktree

### Notes for Next Phase
- Merged commit is on main; verify phase can proceed against main
- CI (Run bats tests) failure is pre-existing on main and unrelated to this PR's changes
- New event emission tests cover run-issue.bats, run-spec.bats, run-code.bats, run-merge.bats, run-review.bats — all pass in isolation

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background が 2 session report の Limits and gaps #1 を引用、issue body の AC 設計が 6 件と充実 (5 grep + 1 rubric + 1 補強 rubric)。

#### spec
- 提案アプローチに沿って `scripts/lib/phase-events.sh` を `scripts/emit-event.sh` の同等として認定する spec 判断。`modules/event-emission.md` を新規 SSoT として追加し、契約を明文化する設計。

#### code
- `_maybe_emit_phase_complete()` + `trap EXIT` pattern を全 run-*.sh に対称導入。Watchdog kill (exit 143) でも backfill が trigger される設計を意図していたが…

#### review
- `modules/event-emission.md` の Backfill セクションと guard 条件の矛盾を検出: "SIGTERM / watchdog timeout exits を反映する" 説明と "Exit code must be 0" guard が同居していた。SIGTERM は exit 143 を返すため backfill 不発火。**新規 SSoT ドキュメントのコード一貫性 review 死角**。

#### merge
- pre-existing CI failure (append-loop-state-heartbeat.bats) を non-interactive auto-resolve で continue。#787 で起票済み follow-up。

#### verify
- pre-merge AC 6 件 PASS、post-merge AC は SKIP (本 batch 完了後の `/audit auto-session --full` で観測予定、batch 進行中の本 verify session 内では計測不可)。
- **Tier 3 recovery が Auto Retrospective に未記載** (#770 と同一パターン)。本 batch session 2 件目の同種事例 — #800 (Tier 2 と対称な Tier 3 Spec write) の必要性を強化する観察。
- review retrospective が指摘した "Backfill 説明と guard 条件の矛盾" は本 verify session 内では未修正 (PR diff は merged 済み、follow-up が必要)。

### Improvement Proposals

1. **modules/event-emission.md の Backfill 説明と guard 条件の矛盾修正**: `_maybe_emit_phase_complete()` の guard 条件 `[[ "${_last_event}" == "phase_start" ]]` は exit code 0 のみで trigger される暗黙の path にあり、SIGTERM/watchdog kill (exit 143) では trap EXIT 内で同じ judgment が走るが、event log への append 自体は OK でも doc 説明と矛盾。doc の "watchdog timeout を反映" 文言の正確性確認 (または guard 条件側を SIGTERM 対応に拡張) が candidate。**Tier 1 — Skill infrastructure improvement** (新規 SSoT との一貫性問題)。
2. **新規 SSoT ドキュメント review check item の追加**: `modules/event-emission.md` のように新規 SSoT 文書を追加する PR では、ドキュメント記述とコード guard 条件の一貫性を機械的にチェックする review check item の追加が candidate。本 batch session で #778 (verify command 対称性) と同根の "実装 vs 説明の同期" 論点として補強。
3. **Tier 3 recovery の Spec 反映 (#800 と重複)**: #770 と同パターン、#800 (auto: Tier 3 recovery 後の Spec 自動追記) で既起票済み。新規起票不要だが、本 batch session で 2 件目の同種観察として #800 の Priority/Value が上がる材料。
