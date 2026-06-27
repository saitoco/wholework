# Issue #701: auto: フェーズ遷移 tail に loop-state heartbeat を追記

## Overview

`/auto` の各フェーズ完了直後 (既存の `reconcile-phase-state.sh --check-completion` 呼び出しの直後) に、
`docs/reports/loop-state-{YYYY-MM-DD}.md` へ 1 行を追記するステップを追加する。
これにより、repo 全体のフェーズ状態スナップショットを durable な human-readable ファイルとして残す。

## Consumed Comments

- saitoco / MEMBER / first-class / Auto-Resolve Log (AC2 format definition → SKILL.md inline; AC1 file_contains → grep) / https://github.com/saitoco/wholework/issues/701#issuecomment-4757366919
- saitoco / MEMBER / first-class / /verify FAIL 2026-06-27: heartbeat never appeared in `docs/reports/loop-state-{2026-06-26,2026-06-27}.md`. The LLM-driven inline procedure in skills/auto/SKILL.md was not firing in batch mode (`run-auto-sub.sh`) or in parent single-Issue auto runs. Re-implementation moves the procedure into bash. / https://github.com/saitoco/wholework/issues/701#issuecomment-4793020100

## Changed Files

- `scripts/append-loop-state-heartbeat.sh` (new): bash 3.2+ best-effort helper that aggregates open `phase/*` label counts via a single `gh issue list` call and appends a row to `docs/reports/loop-state-{DATE}.md`. Failures (gh/jq unavailable, fs errors) are swallowed silently so the caller is never blocked.
- `scripts/run-auto-sub.sh`: call the helper from `run_phase_with_recovery` after every successful phase completion (normal path + Tier 1/2/3 recoveries) for `code-patch`, `code-pr`, `review`, and `merge`. Phase-name → from/to mapping lives in two small `case` helpers.
- `skills/auto/SKILL.md`: replace the five inline LLM-driven "append loop-state heartbeat" steps with explicit `${CLAUDE_PLUGIN_ROOT}/scripts/append-loop-state-heartbeat.sh` invocations; rewrite the `## Loop State Heartbeat` section to document the bash helper as the single execution path; align the file-format example with the existing #703 schema (`Time (UTC) | Phase | Event | Detail`) so phase-transition heartbeats and next-cycle-seed rows coexist in one append-only daily log; add the new script to `allowed-tools`.
- `tests/append-loop-state-heartbeat.bats` (new): 9 unit tests covering argument validation, file creation with shared schema, row append, gh failure tolerance, and the `--phase-label` override.

## Implementation Steps

> **Implementation Iteration 2 (2026-06-27)**. The first iteration (commit `c13eccb`) defined the heartbeat as an LLM-driven inline procedure in `skills/auto/SKILL.md`. `/verify` confirmed in two subsequent batches that no `loop-state-{DATE}.md` rows were ever written by `run-auto-sub.sh` (batch mode) or the parent single-Issue path — the LLM steps simply weren't being followed reliably. This iteration migrates the procedure to bash so the heartbeat fires deterministically from the same code path as `phase_complete` event emission.

1. **Add `scripts/append-loop-state-heartbeat.sh` (the bash helper)** (→ AC1, AC2, AC3)

   Best-effort: never blocks the caller. CLI:
   ```
   append-loop-state-heartbeat.sh --issue N --from <phase> --to <phase> [--phase-label <label>]
   ```
   Behavior:
   - Resolves repo root as `dirname(dirname($0))`
   - Aggregates open `phase/*` label counts via `gh issue list --state open --json labels --limit 1000 | jq ...` (single gh call). Omits `phase/ready` and `phase/done`.
   - On gh/jq failure, falls back to `snapshot-unavailable` and still appends a row.
   - Creates `docs/reports/loop-state-{DATE}.md` with the schema shared with #703 (`Time (UTC) | Phase | Event | Detail`) when absent.
   - Appends row: `| HH:MM:SS | <to> | phase-transition | #N from→to snapshot:[issue:N spec:N code:N review:N verify:N] |`.

2. **Wire helper into `run-auto-sub.sh`** (→ AC1)

   `run_phase_with_recovery` is the single chokepoint where all phase completions emit `phase_complete`. Add two `case` helpers (`_loop_state_from_phase`, `_loop_state_to_phase`) and a wrapper `_append_loop_state_heartbeat <phase> <issue>` that invokes the helper with stderr/stdout discarded and `|| true`. Call the wrapper after every `emit_event "phase_complete"` invocation (4 sites: normal success, Tier 1 reconciler recovery, Tier 2 fallback recovery, Tier 3 sub-agent recovery). Phase-name → from/to mapping:

   | phase (internal) | from   | to     |
   |------------------|--------|--------|
   | `code-patch`     | spec   | code   |
   | `code-pr`        | spec   | code   |
   | `review`         | code   | review |
   | `merge`          | review | merge  |

   Phases outside the map (none today) produce no heartbeat.

3. **Update `skills/auto/SKILL.md`** (→ AC1, AC2, AC3)

   - Replace the five "append loop-state heartbeat (from=X, to=Y; see `## Loop State Heartbeat`)" phrases in the per-phase steps with explicit `${CLAUDE_PLUGIN_ROOT}/scripts/append-loop-state-heartbeat.sh --issue $NUMBER --from X --to Y` invocations. This covers patch (step 3, step 16 verify) and pr (steps 3, 7, 10, 16 verify) routes.
   - Rewrite the `## Loop State Heartbeat` section so the file format example aligns with the existing #703 schema (`Time (UTC) | Phase | Event | Detail`), and describe the bash helper as the single execution path (parent session + run-auto-sub.sh both call it).
   - Add `${CLAUDE_PLUGIN_ROOT}/scripts/append-loop-state-heartbeat.sh:*` to `allowed-tools`.

4. **Add `tests/append-loop-state-heartbeat.bats`** (regression guard)

   9 hermetic tests: arg validation (3), unknown option rejection (1), file creation with shared schema (1), row content with from→to and snapshot (1), repeated append with single header (1), gh failure tolerance (1), `--phase-label` override (1). gh is mocked via PATH.

## Verification

### Pre-merge

- <!-- verify: grep "loop-state" "skills/auto/SKILL.md" --> `/auto` SKILL.md にフェーズ遷移 tail での `loop-state-*.md` 追記ステップが記述されている
- <!-- verify: grep "Loop State" "skills/auto/SKILL.md" --> フォーマット定義 (セクションヘッダ `Loop State`) が SKILL.md に記述されている
- <!-- verify: grep "reconcile-phase-state.sh" "skills/auto/SKILL.md" --> snapshot 取得に既存 `reconcile-phase-state.sh` を利用している

### Post-merge

- `/auto N` を実走させ、`docs/reports/loop-state-{今日の UTC 日付}.md` に当該フェーズ遷移行が追記されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **reconcile-phase-state.sh シグネチャ齟齬**: Issue body では `reconcile-phase-state.sh --check-completion --phase <next>` と記述されているが、実際のシグネチャは positional `<phase> <issue_number> [options]`。heartbeat は既存の completion check 呼び出しの直後に追加するため、呼び出し変更は不要。コンテキストから `from→to` を導出する。
- **Auto-Resolved ambiguity (SKILL.md インライン定義)**: フォーマット定義は `loop-state-template.md` 等の別ファイルは作成せず、SKILL.md 内インラインに記述する (Wholework 既存パターン準拠)。
- **Best-effort**: heartbeat append の失敗はメイン実行フローをブロックしてはならない。
- **snapshot 取得**: `gh issue list --label "phase/*" --json labels` で open issues の phase別集計値のみ取得。reconcile-phase-state.sh は phase 完了確認のトリガーとして使用 (再呼び出し不要)。
- **docs/reports/**: 既存ディレクトリ。`loop-state-*.md` は新規ファイルタイプだが、ディレクトリ新設ではないため structure.md 更新不要 (単一ファイル出力につき除外ルール適用)。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- None. Implementation followed all 3 steps in the Spec exactly: `## Loop State Heartbeat` section added after Daily rollup, heartbeat steps added to all PR route phase completions (steps 3, 7, 10, 16) and patch route phase completions (steps 3, 9).

### Design Gaps/Ambiguities

- The inline heartbeat references in the phase steps use "see `## Loop State Heartbeat`" which points to the new section. This is a forward reference within the same file — readable but not automatically validatable by grep-based verify commands. Acceptable given the best-effort nature of the feature.

### Rework

- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Migrated heartbeat from LLM-driven prose (commit `c13eccb`) to `scripts/append-loop-state-heartbeat.sh` (bash). The /verify FAIL comment on this Issue (2026-06-27) confirmed the prose approach was being skipped both in batch mode (`run-auto-sub.sh`, no LLM in path) and in parent single-Issue auto. Bash invocation is mechanically guaranteed at every `phase_complete` site.
- Single chokepoint in `run-auto-sub.sh::run_phase_with_recovery` — heartbeat call follows every `emit_event "phase_complete"`, covering normal success plus Tier 1/2/3 recoveries. No fragmentation across the case-statement size routes.
- Unified file schema with #703 (`Time (UTC) | Phase | Event | Detail`). The original Spec had defined a separate 4-column schema, but #703 (merged after `c13eccb`) had already started writing to the same file with its own schema. Adopting #703's columns lets both writers coexist append-only without a per-row format negotiation.
- `gh` snapshot aggregation packed into a single `gh issue list ... | jq` invocation in the helper (not per-phase queries). Bash 3.2+ compatible — no associative arrays.

### Deferred Items
- Forbidden-expressions stale entry in `docs/spec/issue-710-blocked-by-workflow.md` (旧称: verify hint) — unrelated to this change; already pre-existing.
- The aggregated snapshot omits `phase/ready` and `phase/done` by design (one transient, one terminal). If a future use case needs them, expose them via a `--include-phases` flag rather than changing the default.
- AC4 post-merge observation (`/auto` run produces `loop-state-{今日の UTC 日付}.md`) is now mechanically reliable in batch mode but still depends on `/auto` actually running today. `/verify` should run after the next `/auto` to flip the checkbox.

### Notes for Next Phase
- All 3 pre-merge ACs pass: `grep "loop-state"` (12), `grep "Loop State"` (9), `grep "reconcile-phase-state.sh"` (19) — script-driven implementation does not change the SKILL.md surface area being grep'd.
- New unit test file `tests/append-loop-state-heartbeat.bats` (9 tests) covers the helper hermetically via gh mocking. No new tests added to `tests/run-auto-sub.bats` — the heartbeat call uses `|| true` so existing `run-auto-sub.bats` mocks don't need a stub for the helper, and all 27 existing tests pass unchanged.
- For `/verify`: the previous code retrospective and verify retrospective sections are retained verbatim above; the new iteration-2 retrospective is appended as a separate `## Code Retrospective (iteration 2 — ...)` section so the audit trail is preserved.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec の AC 設計は `grep` 主体で minimal、verify 段階で UNCERTAIN/FAIL ゼロを達成。AC1/AC2 の Auto-Resolved Ambiguity Points で `file_contains` → `grep` の変更判断、テンプレートファイル不作成方針が verify 精度に直結した。

#### code
- 3 ステップ実装、deviations なし、rework なし。code retrospective の `forward reference` 観察 (Loop State Heartbeat section への "see" 参照) は grep ベース verify の限界として記録済み。

#### merge
- patch route のため PR なし、直 main コミット。conflicts なし。

#### verify
- pre-merge 3 件すべて PASS (各 grep が複数マッチ)。post-merge AC4 (observation event=auto-run) は本 /auto 終了時に event 発火予定で SKIPPED として記録。
- 注: `/verify` 開始時に check-verify-dirty.sh が exit=1 を返した (前 batch の auto-events-rollup-2026-06-20.md が untracked のまま)。verify 前に commit して回避。auto-events-rollup.sh が生成ファイルを自動 commit しない既存挙動が verify 起動を妨げる潜在パターン。

### Improvement Proposals

- **auto-events-rollup.sh の生成物コミット自動化**: `auto-events-rollup.sh` が `docs/reports/auto-events-rollup-{DATE}.md` を生成するが commit/push しないため、次回 `/verify` 起動時に check-verify-dirty.sh が exit=1 でブロックされる。複数の skill (`auto`, `verify`) と複数 PR にまたがる潜在的再発性。auto-events-rollup.sh または呼び出し側 (auto/SKILL.md Step 5) で自動コミットするか、`docs/reports/auto-events-rollup-*.md` を verify dirty チェックの除外パターンに加えるかを検討する価値あり。Tier 2 候補 (パターン認識ベースの workflow lesson)。

## Code Retrospective (iteration 2 — bash-driven heartbeat, 2026-06-27)

### Deviations from Design (original Spec)
- 完全な再設計。元 Spec はフォーマット定義を `## Loop State Heartbeat` (SKILL.md インライン) に置き、各フェーズ完了直後の append 手順を LLM 駆動の prose ステップとして実装することを想定していた。本 iteration ではこのアプローチが /verify FAIL を生んだため、procedure を `scripts/append-loop-state-heartbeat.sh` に bash 実装として移し、`skills/auto/SKILL.md` の各 site から script を直接呼び出す形に切り替えた。Implementation Steps セクションは新方針に合わせて全面書き換え済み。
- 元 Spec が `loop-state-{DATE}.md` 用に独自の列 (`ts (UTC) | issue | transition | repo phase/* snapshot`) を定義していたが、後に merge された #703 (next-cycle-seed) が同じファイルへ別スキーマ (`Time (UTC) | Phase | Event | Detail`) で書き始めていた。本 iteration は #703 のスキーマに統一し、phase-transition と next-cycle-seed の両イベントが同じ append-only daily log に共存できるようにした。SKILL.md の `## Loop State Heartbeat` セクションのフォーマット例も統一スキーマに書き換え。

### Design Gaps/Ambiguities (revealed in this iteration)
- **LLM 駆動の "best-effort" 手続きはオーケストレーション境界を跨ぐと信頼できない**。元 Spec のステップは parent /auto session の LLM が忠実に follow することを暗黙の前提としていたが、batch mode は `run-auto-sub.sh` (bash) で実行され LLM ステップが介在しない。さらに parent session 単体実行でも、コンテキスト量が多いと LLM がインライン best-effort ステップを暗黙にスキップするケースが本件 /verify で 5 回連続 (#765 含む) 観測された。**機械的に必須な副作用は bash に落とす** という設計則として記録する価値あり。
- **同一ファイルへの複数 writer の schema 調整は Spec フェーズで検出されなかった**。#701 と #703 が独立に loop-state-*.md にアクセスする計画を持っていたが、起票・spec 段階でも互いの schema が照合されなかった。今回の iteration で統一したが、ファイルレベルの SSoT を Spec フェーズで明示すべき (例: "writes to docs/reports/loop-state-*.md (shared with #703)" のような cross-reference)。

### Rework
- 元実装 (commit `c13eccb`) の SKILL.md 内インラインヒートビート手順は完全に置き換え。コード自体に削除は不要だが、prose 命令を bash script 呼び出しに置換し、`## Loop State Heartbeat` セクションを書き直した。

### Verification (this iteration)
- 単体テスト: `tests/append-loop-state-heartbeat.bats` 全 9 件 PASS。
- 回帰: `tests/run-auto-sub.bats` 全 27 件 PASS、`tests/auto-sub-observability.bats` 全 4 件 PASS、`tests/auto-recovery.bats` 全 5 件 PASS。
- 静的検査: `scripts/validate-skill-syntax.py skills/auto/SKILL.md` で error 0 (新スクリプトを allowed-tools に追加済み)、`scripts/check-forbidden-expressions.sh` exit 0。
- Pre-merge AC: `grep loop-state skills/auto/SKILL.md` → 12 件、`grep "Loop State" skills/auto/SKILL.md` → 9 件、`grep reconcile-phase-state.sh skills/auto/SKILL.md` → 19 件 — 全 PASS。
- Post-merge AC (observation event=auto-run): 次の `/auto N` 完走時に `docs/reports/loop-state-{今日の UTC 日付}.md` が生成されるかを観察。bash 駆動になったため、parent /auto session が当該ステップを LLM 的に skip しても run-auto-sub.sh 経由の batch mode では確実に発火する。
