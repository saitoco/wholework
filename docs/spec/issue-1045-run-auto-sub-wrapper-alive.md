# Issue #1045: auto: run-auto-sub.sh に wrapper_alive heartbeat event を追加し external kill の切り分けを可能にする

## Overview

`run-auto-sub.sh` の external kill (`[[project_external_kill_pattern]]`、通算25回以上) について、kill が「claude subprocess 実行中」か「wrapper 制御フロー中」かを機械的に判別できるようにする。`run-auto-sub.sh` の wrapper 制御フロー中の checkpoint で `wrapper_alive` heartbeat event を `.tmp/auto-events.jsonl` に emit し、次回 external kill 発生時に直近 `wrapper_alive` と kill 時刻の差分から2パターンを判別する材料を蓄積する。本 Issue は investigation 起点であり、原因特定後の修正対応は別 Issue のスコープとする。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class
  - 内容: `/issue 1045 --non-interactive` の retrospective コメント。AC 分類 (post-merge 条件の verify-type を `manual` に修正) の経緯を記録するとともに、Pre-merge AC の Option A/B/C 実装方式決定は `/issue` (What) / `/spec` (How) の責務境界 (`docs/product.md`) に従い `/spec` フェーズに委譲する旨を明記。
  - URL: https://github.com/saitoco/wholework/issues/1045#issuecomment-5058895944

### code phase (cutoff: 2026-07-23T13:43:22Z, phase/ready label assignment)

No new comments since last phase.

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` 内および top-level 制御フローに `wrapper_alive` heartbeat event の emit を追加 (bash 3.2+ compatible、既存構文のみ使用)
- `scripts/emit-event.sh`: ヘッダーコメントブロックに `wrapper_alive` event schema (checkpoint 値と判別ロジック) を追記 (コメントのみの変更)
- `tests/run-auto-sub.bats`: `wrapper_alive` emit の呼び出しを検証するテストを追加
- `tests/auto-sub-observability.bats`: `wrapper_alive` event が `AUTO_EVENTS_LOG` に実際に記録されることを検証するテストを追加
- Issue body (`gh-issue-edit.sh` 経由): AC1 に `file_contains "scripts/run-auto-sub.sh" "wrapper_alive"` verify command を既存の `rubric` と併記で追加 (定数名の決定的検証、`modules/verify-patterns.md` §9 準拠)

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、既存の `emit_event "phase_start" "phase=${phase}"` 行の直後 (`set +e` / ブロッキングする `run_with_retry_on_kill` 呼び出しの前) に `emit_event "wrapper_alive" "checkpoint=pre_subprocess" "phase=${phase}"` を追加する。この関数は code-patch/code-pr/review/merge 全ての phase 呼び出しで共有されるため、1箇所の編集で全 phase call site をカバーする。wrapper が子 `claude -p` subprocess をブロッキング呼び出しする直前の「最後に wrapper が生存を確認できた時点」を記録する。(→ AC1)
2. `scripts/run-auto-sub.sh` の top-level 制御フローに、#1042 で実際に kill が発生した「phase 呼び出し間」の gap を狙って2箇所 checkpoint を追加する。(after 1) (→ AC1)
   - (a) `always-pr` 昇格チェック直後、`# Execute phases according to Size-based route.` コメント / `case "$EFFECTIVE_SIZE" in` 文の直前に `emit_event "wrapper_alive" "checkpoint=pre_phase_dispatch"` を追加 (spec-phase dispatch + Size 再取得 + always-pr チェックの経過時間を1点に集約)
   - (b) Size M route ブロックと Size L route ブロックの両方 (ほぼ同一コード形状で2箇所存在) で、`PR_NUMBER=$(gh pr list --json number,headRefName ...)` 行の直前に `emit_event "wrapper_alive" "checkpoint=post_code_pre_review"` を追加 (#1042 の実際の kill 発生箇所と同じ gap)
3. `scripts/emit-event.sh` の `emit_event()` 関数定義より上のヘッダーコメントブロックに、`manual_intervention`/`comments_consumed` 等の既存の記法に倣って `# wrapper_alive: ...` ドキュメントブロックを追加する。`checkpoint=` の値 (`pre_subprocess` / `pre_phase_dispatch` / `post_code_pre_review`) と判別ロジック (直近 heartbeat からの差分が小さい → wrapper 制御フロー中の kill、差分が phase 所要時間相当に達する → heartbeat が emit されない subprocess 実行中の kill) を記述する。(parallel with 1, 2) (→ AC1)
4. bats テストを追加する。(after 1, 2) (→ AC2)
   - `tests/run-auto-sub.bats`: 既存の `token_usage` テストと同じ手法 (`$MOCK_DIR/emit-event.sh` を呼び出しログ記録用にオーバーライド) で、phase 実行時に `emit_event wrapper_alive checkpoint=pre_subprocess phase=...` が呼び出されることを assert するテストを追加
   - `tests/auto-sub-observability.bats`: このファイルの既存の実データ書き込み型 `emit-event.sh` モックを使い、実行後に `$AUTO_EVENTS_LOG` に `"event":"wrapper_alive"` を含む行が記録されることを assert するテストを追加 (Size XS route、このファイルのデフォルトパス)
5. Issue body の AC1 行に `<!-- verify: file_contains "scripts/run-auto-sub.sh" "wrapper_alive" -->` を既存の `rubric` タグと並べて追記する (`gh-issue-edit.sh` 経由)。本 Spec の Verification セクションにも同内容を反映する。(→ AC1)

## Verification

### Pre-merge

- <!-- verify: rubric "run-auto-sub.sh に wrapper_alive などの heartbeat event を emit するコードが追加され、少なくとも phase 呼び出し間の kill 検出材料として機能する" --> <!-- verify: file_contains "scripts/run-auto-sub.sh" "wrapper_alive" --> `scripts/run-auto-sub.sh` に wrapper 制御フロー中の heartbeat event を emit する仕組みが追加されている (Option A/B/C のいずれか)
- <!-- verify: rubric "run-auto-sub.sh 実行時に wrapper_alive event が auto-events.jsonl に少なくとも 1 件記録されることを検証するテストが追加されている" --> heartbeat event が `.tmp/auto-events.jsonl` に記録されることを bats テストまたは同等の検証コードで確認できる

### Post-merge

- 次回 external kill 発生時に、`.tmp/auto-events.jsonl` の直近 `wrapper_alive` event と kill 時刻の差分から control-flow kill vs subprocess kill が判別できる (実観測必要) <!-- verify-type: manual -->

## Notes

- **Option 選定 (A を採用、B/C は不採用)**: 理由は3点。(1) 本 Issue の起点である `docs/sessions/5059-1784734082-2026-07-23/session.md` の Auto Retrospective Improvement Proposal 原文が「emit a synthetic `wrapper_alive` heartbeat event... **during control-flow gaps between phase invocations**」と明記しており、これは常時 tick する background loop (Option B) ではなく、wrapper 制御フロー中のみ emit される Option A のセマンティクスと一致する。(2) Option B は Issue 本文が指摘する通り EXIT trap 複雑化リスクを伴うが、`modules/orchestration-fallbacks.md#external-kill-parent-respawn` により「wrapper 自身の EXIT trap (`_maybe_emit_phase_complete`) が疑わしい kill 機序 (SIGKILL、trap 不可能) の下で既に発火しない」ことが確認されており、既に脆弱な trap 機構に2つ目の background process cleanup 依存を追加することは、診断上の利得に対してリスクが不釣り合いに大きい。(3) `scripts/retry-on-kill.sh` の `run_with_retry_on_kill()` は子 subprocess を同一 bash プロセス内で `"$@" || _exit=$?` として直接フォアグラウンド実行するため、wrapper はその間完全にブロックされる — Option A の「heartbeat が subprocess 実行中は自然に途切れる」という設計前提と合致し、Purpose セクションが定義する判別ロジック (差分小 = 制御フロー中の kill、差分大 = heartbeat が emit されない subprocess 実行中の kill) をそのまま実装できる。
- **「every N seconds」記述の簡略化**: session.md 原提案の periodic な文言は、実装上は個々の wrapper-only control-flow checkpoint での単発 emit とした。現状のコードにおける phase 間の制御フロー区間 (label 確認、`gh pr list`、`auto-checkpoint.sh` 呼び出し等) はいずれも数秒程度の単発 API 呼び出しであり、1 gap 内で複数回 tick させる実質的な必要性がないため。
- **スコープ外**: tier3-skip-recovery が発見した stray PR に対する review/merge 分岐 (`XS|S` ケース、`_TIER3_RECOVERY_ACTION == "skip"`) には `post_code_pre_review` 相当の checkpoint を追加しない。まれな recovery-only 経路であり、最小差分方針の対象外とする。
- `docs/reports/external-kill-investigation.md` は本 Issue では更新しない。Issue 本文が明記する通り、本 Issue は instrumentation の追加のみがスコープであり、蓄積された `wrapper_alive` データの分析・レポート反映は原因特定後の別 Issue に委ねる (`doc-checker.md` の対象からも `docs/reports/` は除外されている)。
- `modules/event-emission.md` (cross-wrapper phase lifecycle event の SSoT) は更新しない。`wrapper_alive` は `run-auto-sub.sh` 内部の制御フロー専用 event であり、`phase_start`/`phase_complete`/`wrapper_exit`/`token_usage` のような複数 wrapper 共通の phase lifecycle event ではない。既存の `manual_intervention`/`comments_consumed` 等と同様、`scripts/emit-event.sh` のヘッダーコメントブロックにドキュメントする方針で統一する。
- Steering Docs sync candidate 確認: `docs/structure.md`/`docs/ja/structure.md` の `scripts/emit-event.sh` 該当行は `emit_event()`/`restore_auto_session_pointer()` という汎用ヘルパーの説明であり、個別の event type を列挙していないため、更新不要と判断した。
- verify-type tag 確認: Issue body の post-merge 条件 (`verify-type: manual`) は妥当と確認した。次回の実際の external kill 発生という不定期な未来事象を待って人手で `.tmp/auto-events.jsonl` を確認する必要があり、`modules/verify-patterns.md` §11 の代替候補 (`mcp_call`/`command`/`http_status`/`rubric`/`file_exists`/`file_contains`) はいずれも適用できない (事象発生前は検証対象の成果物が存在しないため)。
- Issue body と既存実装との間に矛盾は検出されなかった (Background セクションの記述はコードベースの実際の挙動と整合)。

## Auto Retrospective

### Manual recovery (spec)
- **Date**: 2026-07-23 13:44 UTC
- **Issue**: #1045, phase: spec
- **Source**: parent session manual recovery
- **Recovery type**: respawn
- **Wrapper exit code**: unknown
- **Outcome**: success

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. PR diff (`scripts/run-auto-sub.sh`, `scripts/emit-event.sh`, `tests/run-auto-sub.bats`, `tests/auto-sub-observability.bats`) matched Implementation Steps 1–3 exactly, including checkpoint names, `phase=` field presence/absence per checkpoint, and the `_maybe_emit_phase_complete()` backfill extension. No structural divergence found.

### Recurring issues

One recurring pattern worth naming: a PR that changes shared control-flow logic (`_maybe_emit_phase_complete()`'s OR-condition) can silently invalidate an existing test's premise without the test itself failing. Here, adding `emit_event "wrapper_alive" ...` immediately after `emit_event "phase_start" ...` meant the existing "phase_start only" backfill test could no longer produce a bare-`phase_start`-as-last-event scenario through the real code path — it kept passing, but for the wrong reason (it started exercising a different OR-branch). The only test that still constructed that raw scenario did so via a hand-duplicated, unsynced copy of the function, so the real branch had silently lost coverage. This class of bug (test still green, but no longer covering what its name claims) is not caught by CI pass/fail alone — worth flagging in review whenever a diff touches a helper function that tests duplicate inline via heredoc/mock rather than sourcing directly. No process change proposed here (fixed inline this cycle), but noting the pattern for future `/review` passes on this file.

### Acceptance criteria verification difficulty

Nothing to note. Both pre-merge ACs had unambiguous verify commands (`file_contains` + `rubric`) and resolved cleanly to PASS; the post-merge AC's `manual` verify-type was already confirmed appropriate at `/spec` time (see Notes section above).

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Merged via squash without conflicts (`gh-pr-merge-status.sh` reported `mergeable=true, reason=clean`); no rebase/conflict-resolution path was needed.
- Local branch `worktree-code+issue-1045` failed to auto-delete after merge because a stale `code+issue-1045` worktree still held it checked out — removed that worktree and the branch manually as part of this merge, no functional impact on the squash merge itself (remote branch and PR were already merged/deleted).

### Deferred Items
- Post-merge AC ("次回 external kill 発生時に control-flow kill vs subprocess kill が判別できる", `verify-type: manual`) remains open — requires an actual future external-kill observation against `.tmp/auto-events.jsonl`, out of scope for `/merge` and carried forward to `/verify`.

### Notes for Next Phase
- No policy/design changes were made during merge; Issue #1045 will auto-close via `closes #1045` since base branch is `main`.
- `/verify` should confirm the manual post-merge AC stays open (pending future observation) rather than treating it as resolved by this merge.
