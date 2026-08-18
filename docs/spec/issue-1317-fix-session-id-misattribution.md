# Issue #1317: auto: run-*.sh の auto-session-current fallback による並行セッションへの session_id 誤帰属を解消

## Overview

`/auto` の session 初期化 (Step 1) を経ずに `run-*.sh` (5 本: `run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh`) を手動実行した場合、各スクリプトが独自に持つ inline fallback ロジックが `.tmp/auto-session-current` (`/auto` Step 1 でのみ書き込まれる PGID 非依存のグローバルファイル) を読んでしまい、並行稼働中の別 `/auto` セッションの `session_id` を誤って採用する。同型の問題は #1075/#1224 で `scripts/emit-event.sh` の `restore_auto_session_pointer()` に対して既に対処済みだが、5 本の wrapper 自身が持つ独立した inline fallback (`restore_auto_session_pointer()` を経由しない) は未対処のまま残っていた。本 Issue はこの inline fallback を fail-closed 化し、`session_id` の誤帰属を解消する。

## Reproduction Steps

1. `/auto` セッション A を起動する。Step 1 で `.tmp/auto-session-current` にセッション A の `SESSION_ID` が書き込まれる
2. セッション A が稼働中に、`/auto` を経由せず `run-issue.sh` (または他 4 本のいずれか) を手動実行する。この呼び出しは新しい PGID を持つため `.tmp/auto-session-${PGID}` は存在しない
3. `run-issue.sh` の inline fallback (`AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || cat ".tmp/auto-session-current" 2>/dev/null || echo '')}"`) が `.tmp/auto-session-current` を読み、セッション A の `SESSION_ID` を採用する
4. 手動実行が emit する `phase_start` / `phase_complete` / `wrapper_exit` / `token_usage` イベントが、`.tmp/auto-events.jsonl` にセッション A の `session_id` で誤って記録される
5. 実測 (2026-08-08): セッション `46468-1786195191` (`/auto 1278` 単独実行) に、無関係な #1274/#1275/#1276 の `phase=issue` イベント一式 (`phase_start`/`max_silent_window`/`phase_complete`/`token_usage`/`wrapper_exit`) が誤帰属した

## Root Cause

`scripts/run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` の 5 本が、`AUTO_SESSION_ID` を解決する際に `scripts/emit-event.sh` の `restore_auto_session_pointer()` を経由しない独自の inline fallback を持つ。#1224 は `restore_auto_session_pointer()` から `.tmp/auto-session-current` へのフォールバックを削除したが (「その file は `/auto` Step 1 でのみ書き込まれるため、Step 1 を経ない呼び出し元が読んでも所有者たり得ない」という理由)、5 本の wrapper 自身の inline fallback はこの関数を経由しないため、#1224 の修正の対象外のまま同型の欠陥を残していた。

## Changed Files

- `scripts/run-issue.sh`: `.tmp/auto-session-current` への無条件フォールバックを削除 (line 26-27)
- `scripts/run-spec.sh`: 同上 (line 78-79)
- `scripts/run-code.sh`: 同上 (line 78-83、コメントがやや詳細)
- `scripts/run-review.sh`: 同上 (line 57-58)
- `scripts/run-merge.sh`: 同上 (line 48-49)
- `tests/run-code.bats`: 既存 4 テストケース (line 631-690) を変更後の実装に合わせて更新
- `tests/run-issue.bats`: 誤帰属防止の新規テストケースを追加
- `tests/run-spec.bats`: 同上
- `tests/run-review.bats`: 同上
- `tests/run-merge.bats`: 同上
- `modules/event-emission.md`: Concurrent-session attribution problem 節・Manual Orchestration (Issue #1224) 節の `.tmp/auto-session-current` に関する記述を更新
- `skills/audit/SKILL.md`: Session Boundary Identification 節 (line 1091) の記述を更新
- `skills/auto/SKILL.md`: Step 1 のコメント (line 38) を更新 — `.tmp/auto-session-current` の読み手の記述を変更 (file 自体の書き込みは維持)

## Implementation Steps

1. `scripts/run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` の 5 本から `.tmp/auto-session-current` への無条件フォールバックを削除する。各ファイルの該当行を次のように変更する: `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || cat ".tmp/auto-session-current" 2>/dev/null || echo '')}"` → `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"`。直前のコメント行 (`# Primary: PGID-based file (Issue #770). Fallback: auto-session-current (Issue #791 iter B).` および `run-code.sh` の詳細版コメント) は、PGID ポインタで解決できない場合は空文字列になる (fail-closed、Issue #1317) 旨の説明に更新する。bash 3.2+ compatible を維持する (→ 受入条件 A)
2. (after 1) `tests/run-code.bats` の既存 4 テストケースを、変更後のシェルスニペットに合わせて更新する。"AUTO_SESSION_ID resolves from .tmp/auto-session-current when PGID file absent" は、`.tmp/auto-session-current` に別セッションの ID がある状況で `AUTO_SESSION_ID` が空になる (誤帰属しない) ことを検証する内容に反転させる。`tests/run-issue.bats` / `run-spec.bats` / `run-review.bats` / `run-merge.bats` それぞれに同様の新規テストケースを 1 件ずつ追加する — 各ファイルが呼ぶスクリプト自身の該当行と同一のシェルスニペットを再現し、`.tmp/auto-session-${PGID}` が存在せず `.tmp/auto-session-current` に別セッション ID がある状況で `AUTO_SESSION_ID` が空文字列になることをアサートする (→ 受入条件 C, D)
3. (parallel with 1, 2) `modules/event-emission.md` の Concurrent-session attribution problem 節および Manual Orchestration (Issue #1224) 節、`skills/audit/SKILL.md` の Session Boundary Identification 節、`skills/auto/SKILL.md` Step 1 のコメントを、変更後の実装 (5 本の `run-*.sh` はもう `.tmp/auto-session-current` を読まない。同ファイルは `scripts/collect-run-facts.sh` / `scripts/filter-session-verified-issues.sh` の fail-open フォールバックとして引き続き書き込まれる — 詳細は Notes 参照) に整合するよう更新する (→ 受入条件 B)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-issue.sh / run-spec.sh / run-code.sh / run-review.sh / run-merge.sh の 5 本すべてについて、PGID ポインタで解決できない場合に .tmp/auto-session-current へ無条件フォールバックしない実装になっている" --> 5 本の wrapper が PGID ポインタで解決できない場合に .tmp/auto-session-current へ無条件フォールバックしない実装になっている
- <!-- verify: rubric "modules/event-emission.md の Concurrent-session attribution problem 節と skills/audit/SKILL.md の Session Boundary Identification 節にある .tmp/auto-session-current の記述が、変更後の実装と整合するよう更新されている" --> ドキュメント側の記述が実装と整合している
- <!-- verify: rubric "tests/ 配下に、/auto Step 1 を経ない wrapper 呼び出しかつ .tmp/auto-session-current に別セッションの ID がある状況を再現し、event の session_id が当該別セッションに帰属しないことを検証するケースが追加されている" --> 誤帰属条件がテストで保護されている
- <!-- verify: command "bats tests/run-issue.bats tests/run-spec.bats tests/run-code.bats tests/run-review.bats tests/run-merge.bats tests/emit-event.bats" --> 関連 wrapper と emit-event の bats がすべて通る

### Post-merge

- 並行して `/auto` が稼働している状態で `/auto` を経ない `/issue` を実行し、`.tmp/auto-events.jsonl` の当該 event が稼働中セッションの `session_id` を持たないことを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **`.tmp/auto-session-current` file 自体の存続要否 (Issue コメントの Auto-Resolve Log で `/spec` の判断に委ねられた事項)**: 削除せず維持すると判断する。理由: `scripts/collect-run-facts.sh` (line 111-122) と `scripts/filter-session-verified-issues.sh` (line 42-48) が、`--session` 引数省略時の fail-open フォールバックとして引き続きこのファイルを読む設計になっている。いずれも意図的にドキュメント化された fail-open 挙動であり (`filter-session-verified-issues.sh` はヘッダーコメントで明示的に "Fail-open: ... best-effort" と記載)、通常の呼び出し経路 (`skills/auto/SKILL.md` の `--session <SESSION_ID>` 明示渡し、`modules/opportunistic-verify.md` の `--session "$AUTO_SESSION_ID"` 明示渡し) ではこのフォールバックに到達しない。したがってファイルの書き込み (`skills/auto/SKILL.md` Step 1) は維持し、コメント文言のみ実装に合わせて更新する
- **スコープ外の発見**: `scripts/collect-run-facts.sh` と `scripts/filter-session-verified-issues.sh` にも `.tmp/auto-session-current` への同型フォールバックが存在するが、本 Issue の Pre-merge AC1 は「5 本の run-*.sh」に明示的に限定しており、この 2 スクリプトは対象外。両者とも fail-open 設計のため、`.tmp/auto-session-current` から誤った (並行稼働中の別セッションの) session_id を拾った場合、observation フィルタリングや run-fact 突合が誤ったデータで進行するリスクは構造的に残る。実害は emit-event の attribution 問題 (集計指標の誤帰属) と異なり「observation scan の一部 Issue 誤スキップ」「`when=` 条件の誤判定」程度に留まるため、本 Issue のスコープには含めない。再発頻度が高まる場合は別 Issue で扱う
- `scripts/emit-event.sh` の `restore_auto_session_pointer()` / `persist_auto_session_pointer()` は変更対象外。両関数は #1224 で既に `.tmp/auto-session-current` へのフォールバックを削除済みで、今回の 5 本の wrapper とは独立したコードパスのため。`tests/emit-event.bats` の既存テスト (line 198 以降) もこの関数群を対象としており、変更不要
- `modules/observation-trigger.md` / `modules/opportunistic-verify.md` は `collect-run-facts.sh` の fallback ladder を説明しているが、`collect-run-facts.sh` 自体を変更しないため更新不要

## Consumed Comments

| login | authorAssociation | trust tier | 内容 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。Pre-merge AC 1 の rubric 常時 PASS リスク指摘 (Pattern 2) を受け「または当該フォールバックを残す設計判断とその安全性の根拠が明示的に文書化されている」の削除で対応済み (Issue body に反映済み)。AC 4 の bats タイムアウトに関する参考情報 (CI reference fallback 条件を満たすため恒久的 UNCERTAIN に該当しないと判断済み、対応不要)。Autonomous Auto-Resolve Log で「`.tmp/auto-session-current` file 自体の存続要否は `/spec` の判断に委ねる」「`session_id` 空の event の集計側ハンドリングは追加 AC を設けない」の 2 点を明記 | https://github.com/saitoco/wholework/issues/1317#issuecomment-5327871143 |

## Code Retrospective

### Deviations from Design
- None. Implemented all 3 Implementation Steps as written: (1) removed the `.tmp/auto-session-current` fallback from the 5 `run-*.sh` wrappers, (2) updated `tests/run-code.bats`'s 4 existing tests and added 1 new test each to `tests/run-issue.bats`/`run-spec.bats`/`run-review.bats`/`run-merge.bats`, (3) updated `modules/event-emission.md`, `skills/audit/SKILL.md`, and `skills/auto/SKILL.md`.

### Design Gaps/Ambiguities
- `/code`'s "New Verification-Test Pre-implementation FAIL Check" (targets asserts that verify a target file's content via string matching — `grep`/`file_contains`-equivalent) was judged out of scope for the 5 new AUTO_SESSION_ID misattribution test cases: each replays the wrapper's shell snippet inline and asserts the resulting variable value, rather than grepping the actual `scripts/run-*.sh` file content, so there is no pre-implementation-state file version to check the assert against.

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Kept the `.tmp/auto-session-current` file itself (Spec Notes: option A retains it, per the Autonomous Auto-Resolve Log deferring this to `/spec`) — only removed the 5 wrappers' read path. `scripts/collect-run-facts.sh` / `scripts/filter-session-verified-issues.sh` still read it as a documented fail-open fallback.
- Extended the exact same inline-snippet-replay test pattern already used by `tests/run-code.bats` to the other 4 wrapper bats files, rather than introducing a new test helper — keeps the 5 new/updated tests structurally identical and easy to audit together.
- Did not add a new AC for how the collector/aggregation side handles empty `session_id` events (Auto-Resolve Log during `/issue` explicitly deferred this) — out of scope for this Issue.

### Deferred Items
- Post-merge observation AC (concurrent `/auto` + manual `/issue` reproduction) is unresolved pending a live concurrent-session scenario after merge.
- Spec Notes' scope-out: `scripts/collect-run-facts.sh` and `scripts/filter-session-verified-issues.sh` retain the same-shape `.tmp/auto-session-current` fallback (fail-open, not fail-closed like the 5 wrappers) — explicitly out of scope for this Issue; revisit if misattribution recurs through that path.

### Notes for Next Phase
- Pre-merge AC 4's `bats` command already covers all 5 touched wrapper test files plus `emit-event.bats`; the full suite (`bats --jobs 18 tests/`, 1871/1871 PASS) was also run due to behavioral-change detection (multiple test files beyond direct counterparts reference the modified scripts/docs).
- No `github_check "gh pr checks"` AC exists on this Issue, so the CI verification AC exclusion note in `/code` Step 10 does not apply here.
