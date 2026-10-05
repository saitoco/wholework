# Issue #1500: recoveries: manual-recovery-respawn/harness-oom-stop

## Overview

症状 `manual-recovery-respawn/harness-oom-stop` (`docs/reports/orchestration-recoveries.md` に 4 件、既定閾値 `3` 超) の原因・検出シグネチャ・緩和策・再 kill 時の扱いを、`modules/orchestration-fallbacks.md` に新エントリ `## harness-oom-stop` として記録する。再発時に調査をやり直さずに判断できる状態にすることが目的で、コード変更は含めない (メモリ逼迫はホスト側の問題で、緩和策のメモリ増設は適用済みのため)。増設後 30 日間の再発監視は Post-merge の observation で行う。

## Changed Files

- `modules/orchestration-fallbacks.md`: (1) `## harness-oom-stop` エントリを追加する。配置は `## external-kill-parent-respawn` エントリ末尾の `---` の直後、`## review-pending-not-failure` の直前。構成は必須 5 セクション (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) に `### Operational Policy: what differs from external-kill-parent-respawn` と `### Mitigation Status and Recurrence Watch` を加えたもの。(2) 既存の `## external-kill-parent-respawn` エントリに新エントリへの相互参照を 2 箇所追加する (Symptom の `Not a jetsam/OOM kill` 行の直後、Operational Policy の末尾)

## Implementation Steps

1. `modules/orchestration-fallbacks.md` に `## harness-oom-stop` エントリを追加する (→ 受入条件 1, 2, 3, 4)
   - 配置: `## external-kill-parent-respawn` の `### Threshold Detection Handling` に続く `---` の直後 (`## review-pending-not-failure` の直前)。新エントリの末尾にも `---` を置く
   - 本文は下の「Entry draft」を土台にする。事実 (日付・Issue 番号・件数・セッション ID・引用文言・出所) はそのまま保ち、表現の整形だけを許容する。書き込む直前に、本文が挙げる識別子 (Issue 番号、`scripts/*.sh`、関数名、セッション ID、cause slug) を grep / Read で実在確認する (Spec 作成時の確認結果は Notes に記載)
   - 本文は英語のみで書く (`modules/` は英語限定のパスで、CJK 文字を含めると language-convention check が失敗する)
   - verify command が参照する次の 3 つの文字列が、本文に literal で含まれること: `harness-oom-stop`、`running low on memory`、`#1461`

   Entry draft:

   ```markdown
   ## harness-oom-stop

   ### Symptom
   - A background `run-*.sh` wrapper (in practice `run-auto-sub.sh`, launched from the parent `/auto` session) is stopped while it runs (in #1462, right after the spec phase's `phase_complete`), and the stopped task's notification gives low system memory as the reason: `Background command "..." was stopped because the system is running low on memory`, with `status: killed` and no numeric exit code
   - The wrapper leaves no `Exit code:` trailer of its own and no `wrapper_exit` event, so its exit code is logged as `unknown` — the same missing-exit signature as `external-kill-parent-respawn`. The `phase/*` label and PR state are as they were before the stop, and a respawn resumes from them
   - `scripts/detect-external-kill.sh` matched this signature for #1462 but returned `no-match` for both stops of #1461, because the concatenated `run-auto-sub.sh` log still carried the inner `run-spec.sh`'s `Exit code: 0` trailer (Icebox #1093). The notification wording, not the detector, decides this pattern: when the detector says `no-match` but the notification states the memory reason, treat it as this pattern, as the #1461 handling did
   - Telling it apart from `external-kill-parent-respawn`: that entry's `Not a jetsam/OOM kill` check cannot separate the two, because neither is an OS-level kill — this stop is performed by the harness itself. Decide from the stop notification's wording:

     | Stop notification wording | Pattern | `--notification` class |
     |---|---|---|
     | `... was stopped because the system is running low on memory` (a reason is stated; no exit code) | `harness-oom-stop` (this entry) | `harness-stop` |
     | `... failed with exit code N` (numeric exit code, e.g. 137) | `external-kill-parent-respawn` | `external-signal` |
     | only `killed` or `was stopped` (no reason, no exit code) | `external-kill-parent-respawn`, unless the debug log below says otherwise | `indeterminate` |

   - A bare `was stopped` can be settled from the parent session's debug log (`~/.claude/debug/<session-id>.txt`) when debug logging was on: Claude Code records there why background tasks were stopped

   ### Applicable Phases
   - Any phase launched as a background wrapper by the parent `/auto` session: `run-auto-sub.sh`, `run-code.sh`, `run-spec.sh`, `run-review.sh`, `run-merge.sh`
   - Observed so far — the 4 entries with `cause: harness-oom-stop` in `docs/reports/orchestration-recoveries.md`: the spec phase twice and the review phase twice

     | Logged (UTC) | Issue | Phase | Stops | Outcome |
     |---|---|---|---|---|
     | 2026-09-09 08:45 | #1462 | spec (just after `phase_complete`) | 1 | respawn resumed from `phase/ready`; success |
     | 2026-09-10 02:57 | #1461 | review `--full` (Size L fan-out) | 2 | the respawn was stopped again and the parent session stopped for user judgement (Outcome: failed); a later re-run, with nothing changed, completed |
     | 2026-09-13 12:21 | #1468 | review (light) | 2 | third attempt completed |
     | 2026-10-03 03:55 | #1477 | spec | 1 | respawn completed |

   - The same wording was first logged on 2026-09-08 for #1457 (review, stopped twice at the start of `--full`) under the cause slug `oom-kill-review-full-fanout`. It is the same pattern, but `collect-recovery-candidates.sh` groups by slug, so it is outside the 4-entry count above. Record every new occurrence with `--cause harness-oom-stop`

   ### Fallback Steps
   1. Confirm the signature with the table above and keep the notification's raw wording for `--diagnosis`
   2. If it can be taken without a permission prompt, take a one-line host memory snapshot before respawning (for example `free -m` on Linux, `memory_pressure` on macOS) and add it to the `--diagnosis` text. None of the 4 entries above records a snapshot taken at the time of the stop, so this is what lets a later reader tell a real shortage from a misfire (see Rationale)
   3. Respawn the same `run-*.sh` with the same arguments — the `phase/*` label (SSoT) and the `code_phase_milestone` checkpoint restore existing progress. Do not enter Tier 1/2/3: the stop is not a phase failure
   4. After the respawned phase completes, record it via `#manual-recovery-spec-write` with recovery type `respawn`: always pass `--cause harness-oom-stop` (the group key that `collect-recovery-candidates.sh` and the watch below count), `--notification harness-stop`, and a `--diagnosis` carrying the raw wording and the snapshot; omit `EXIT_CODE`, which cannot be observed

   ### Escalation
   - A second stop of the same phase — the respawn itself is stopped, as in #1461 — is still not a phase failure: do not enter Tier 1/2/3, because the label and PR state are intact and the same respawn remains valid
   - Before each further respawn, take a fresh snapshot (Fallback Steps 2). If available memory is clearly low (for example `MemAvailable` near zero, or `memory_pressure` reporting a critical level), do not relaunch into it: stop and report instead. If memory looks normal, respawn at once — the stop is then unexplained, and the third attempt completed in #1457 and #1468
   - Respawn at most twice per Issue and phase within one parent session (three launches in total). If the third launch is stopped as well, stop there: leave the `phase/*` label as it is (a later `/auto N` resumes from it), record the stop with `--cause harness-oom-stop` and a `--diagnosis` saying the respawn was stopped again, and report `cause: harness-oom-stop` in the `skills/auto/SKILL.md` Step 6 stop banner (the convention `cause: ci-infra-outage` already uses) so that a person decides
   - The bound is a procedure for the parent session and is not enforced by code. A mechanical cap and a pre-respawn memory check are the code-side options deferred under Issue #1500 (see Mitigation Status and Recurrence Watch)

   ### Rationale
   - Introduced in Issue #1500: `manual-recovery-respawn/harness-oom-stop` reached the repeat-detection threshold (4 entries against the default `--threshold 3`), yet its cause, signature, and handling were recorded nowhere except the log entries themselves
   - Cause: a documented behavior of the Claude Code harness. Its documentation states that on macOS and Linux it stops running background tasks when the operating system reports critical memory pressure, provided the session has been idle for at least 30 minutes with no turn or subagent running (v2.1.193 or later; [Interactive mode — background bash commands](https://code.claude.com/docs/en/interactive-mode) and the `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` entry of [Environment variables](https://code.claude.com/docs/en/env-vars), both retrieved 2026-10-05). A parent `/auto` session waiting on a long background wrapper can meet that idle condition, which is consistent with the stops landing in long phases (spec, review). Because the harness stops the task itself, the wrapper never gets to write an exit trailer or emit `wrapper_exit`
   - "Low on memory" is the harness's judgement, not a free-memory measurement. On a macOS host with 48 GB of physical memory (session `90128-1788933783`, the 2026-09 stops), a 725-sample, 60-minute measurement of a later successful `review --full` re-run found total `claude` RSS peaking at 2.65 GB (the fan-out added 0.26 GB), the memory-pressure level normal in 94% of the samples (warning for 245 s), and `Pages free` down to 52 MB without a stop (#1146 comment of 2026-09-13). On Linux, upstream reports show the stop firing while `MemAvailable` is high and `MemFree` is low ([anthropics/claude-code#78674](https://github.com/anthropics/claude-code/issues/78674), [#92228](https://github.com/anthropics/claude-code/issues/92228); both open when checked on 2026-10-05). A stop therefore does not prove the host was short of memory, and a memory increase may not remove the trigger — take the snapshot in Fallback Steps 2 on a recurrence instead of re-deriving this
   - The 2026-10-03 stop (#1477) occurred on the host ct112; the 2026-09 stops were observed on a macOS host, which the ct112 memory increase below does not touch
   - Kept separate from `external-kill-parent-respawn` because that entry's policy rests on two premises that do not hold here: a root cause that is upstream-gated with no lever on the wholework side, and a respawn that has always succeeded (see Operational Policy below)
   - See also #1146 (the external-kill investigation, where the 2026-09 stops were first aggregated) and Icebox #1093 (`detect-external-kill.sh` false negative on concatenated logs)

   ### Operational Policy: what differs from external-kill-parent-respawn
   - **Accumulation is a signal here.** Unlike the upstream-gated external kill, this stop has host-side and harness-side levers (see below), so repeat entries after the mitigation are actionable. An Issue filed for `manual-recovery-respawn/harness-oom-stop` is therefore not closed as "expected recovery, no action needed"
   - **A respawn can fail.** #1461's respawn was stopped again and its review did not complete in that session (Outcome: failed); of the 4 entries, 3 recorded success and 1 failed. The "17/17, no work loss" track record in `external-kill-parent-respawn` was counted as of #1390 (2026-08-17), before these entries, and does not carry over
   - **Completed work is not lost.** In every entry the label and PR state were intact and the respawn resumed from them (#1462 from `phase/ready`; #1457's PR #1459 stayed OPEN with CI green), so the cost of a stop is the repeated time, not lost output
   - **Keep the tracking Issue's exact title** (`recoveries: manual-recovery-respawn/harness-oom-stop`): `_find_known_recoveries_issue()` links log entries to it by exact title match, and renaming it silently breaks the link, as #1014's rename did (see `external-kill-parent-respawn`, Threshold Detection Handling)

   ### Mitigation Status and Recurrence Watch
   - **Applied (host side)**: the memory of ct112, the host that runs the parent session and its wrappers, was increased after the #1477 entry (2026-10-03 03:55 UTC). Sizes before and after were not recorded
   - **Result so far**: the next batch (session `1123127-1791088655`, 2026-10-04, `/auto --batch` of 8 Issues over about 4 hours) had no stop of this kind: no Tier 1/2/3 recovery, no watchdog kill, and its single manual intervention was an unrelated label backfill (#1494). One 4-hour batch is a small sample, so this is encouraging, not proof
   - **Watch** (Issue #1500 Post-merge, `verify-type: observation`): for 30 days from 2026-10-03 (until 2026-11-02), `docs/reports/orchestration-recoveries.md` (and `docs/reports/orchestration-recoveries-archive.md` if entries were rotated) must hold no `cause: harness-oom-stop` entry dated after 2026-10-03 03:55 UTC. The baseline is the 4 entries above (`grep -c "cause: harness-oom-stop" docs/reports/orchestration-recoveries.md`); finding them still present confirms the scan ran against the right file
   - **Levers not applied**: (a) harness opt-out — setting `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` in the parent session's environment (for example through the `env` block of a Claude Code `settings.json`) turns off memory-pressure stops, at the price of dropping that protection entirely; (b) code-side — a memory check before respawn and a cap on repeated stops in `/auto` (this entry's Escalation bound is the manual form of the cap). Neither is justified without a recurrence
   - **If it recurs**: the mitigation was insufficient. Compare the snapshots recorded in `--diagnosis`, then decide on the levers above in a separate Issue; do not close the recurrence as expected recovery

   ---
   ```

2. 同ファイルの `## external-kill-parent-respawn` エントリに、新エントリへの相互参照を 2 箇所追加する (after 1) (→ 受入条件 2, 4)
   - Symptom: `- Not a jetsam/OOM kill: ...` で始まる bullet の直後に、次の bullet を追加する (原文のまま):

     ```markdown
     - Not `harness-oom-stop` either: if the stopped task's notification itself names low system memory as the reason (`was stopped because the system is running low on memory`), the pattern is `harness-oom-stop` — see `#harness-oom-stop` for the wording table that separates the two. The `Not a jetsam/OOM kill` check above cannot, since neither is an OS-level kill
     ```

   - Operational Policy: 末尾の bullet (`- **The root cause is out of scope for wholework.** ...`) の直後に、次の bullet を追加する (原文のまま):

     ```markdown
     - **Scope**: this policy does not cover `harness-oom-stop`, where accumulation is a signal and a respawn can itself be stopped again (#1461) — see `#harness-oom-stop`, Operational Policy
     ```

3. 検証する (after 1, 2) (→ 受入条件 1, 2, 3, 4)
   - `bats tests/orchestration-fallbacks.bats` が PASS すること (新エントリは必須 5 セクションを各 1 回ずつ持ち、Rationale に Issue 参照 `#N` を含む。構造検査は既存テストが新エントリを自動的に対象にするため、新規テストケースは追加しない)
   - `grep -c` で verify command の 3 つの文字列 (`harness-oom-stop`、`running low on memory`、`#1461`) が `modules/orchestration-fallbacks.md` に存在することを確認する
   - `bash scripts/check-forbidden-expressions.sh` と、/code がコミット前に実行する language-convention check (`skills/code/language-convention-check.md`) が PASS すること

## Verification

### Pre-merge

- `harness-oom-stop` の根本原因 (ホストのメモリ逼迫によりハーネスがバックグラウンドの `run-auto-sub.sh` を停止すること、wrapper に exit code が残らないこと) と、観測された発生フェーズ (spec 2 件・review 2 件) が `modules/orchestration-fallbacks.md` に記録されている <!-- verify: file_contains "modules/orchestration-fallbacks.md" "harness-oom-stop" --> <!-- verify: rubric "modules/orchestration-fallbacks.md に harness-oom-stop の根本原因 (ホストのメモリ逼迫によりハーネスがバックグラウンドの wrapper を停止し、wrapper 側に exit code が残らない) と、観測された発生フェーズ (spec と review) が記録されている" -->
- `harness-oom-stop` の検出シグネチャ (バックグラウンドタスクの通知が「システムのメモリ不足」を理由とする停止であること) と、`external-kill-parent-respawn` の `Not a jetsam/OOM kill` との切り分けが記録されている。両者のどちらに当たるかを、実際の停止通知を見た担当者が判別できる <!-- verify: file_contains "modules/orchestration-fallbacks.md" "running low on memory" --> <!-- verify: rubric "modules/orchestration-fallbacks.md に harness-oom-stop の検出シグネチャ (バックグラウンドタスク通知が system is running low on memory を理由とする停止であること) が記載され、external-kill-parent-respawn の Not a jetsam/OOM kill との切り分けが読み取れる" -->
- 緩和策として、ホスト (ct112) のメモリを 2026-10-03 の #1477 の後に増設したこと、および増設後の batch (session 1123127-1791088655, 8 件) で再発がなかったことが記録されている <!-- verify: rubric "modules/orchestration-fallbacks.md に harness-oom-stop の緩和策として、ホスト (ct112) のメモリ増設 (2026-10-03 の #1477 の後) と、増設後の batch (session 1123127-1791088655, 8 件) で再発がなかったことが記録されている" -->
- #1461 で respawn も同じメモリ逼迫で再 kill され review が完了しなかったことを踏まえ、`external-kill-parent-respawn` の「respawn は作業ロスなく成功する」という方針が `harness-oom-stop` には当てはまらないこと、および respawn が再 kill された場合に親セッションが取る対応が記録されている <!-- verify: file_contains "modules/orchestration-fallbacks.md" "#1461" --> <!-- verify: rubric "modules/orchestration-fallbacks.md に、#1461 で respawn が同じメモリ逼迫で再 kill され review が完了しなかったこと、このため external-kill-parent-respawn の「respawn は作業ロスなく成功する」前提が harness-oom-stop には当てはまらないこと、respawn が再 kill された場合に親セッションが取る対応が記録されている" -->

### Post-merge

- 2026-11-02 以降の最初の `/auto` 完了時に、`docs/reports/orchestration-recoveries.md` (ローテーション済みなら `docs/reports/orchestration-recoveries-archive.md` も含む) に、2026-10-03 03:55 UTC より後の日時で `cause: harness-oom-stop` のエントリが 1 件もない。対象期間は、ホスト (ct112) のメモリ増設日 (2026-10-03) から 30 日間。ベースラインは増設前の 4 件 (2026-09-09〜2026-10-03、`grep -c "cause: harness-oom-stop" docs/reports/orchestration-recoveries.md` で計測)。2026-11-02 より前に発火した場合は SKIPPED (観測期間不足)、期間内に新規エントリがあれば FAIL <!-- verify-type: observation event=auto-run -->

## Notes

### Conflict with existing records (Step 6 の矛盾検出、SPEC_DEPTH=light のため Notes のみに記録)

- 内容: Issue 本文は 4 件すべてを「ホスト (ct112) のメモリ逼迫により、Claude Code ハーネスがバックグラウンドの `run-auto-sub.sh` を停止した」と説明している。しかし 2026-09 の 3 件 (#1462, #1461, #1468。#1457 も同じ時期) は macOS (物理メモリ 48 GB) 上のセッションで、ハーネスの "running low on memory" という文言が実メモリ残量にも macOS の圧迫判定にも対応していなかったことが実測されている (`https://github.com/saitoco/wholework/issues/1146#issuecomment-5650701849`、`docs/sessions/90128-1788933783-2026-09-18/session.md` の Findings)。ct112 上で起きたのは 2026-10-03 の #1477 のみで、ct112 のメモリ増設はその後
- 対処: 受入条件どおり「ホストのメモリ逼迫を理由にハーネスがバックグラウンドの wrapper を停止し、exit code が残らない」を根本原因として記録しつつ、公式ドキュメント (OS が critical なメモリ圧迫を報告 + セッションが 30 分以上アイドル) による仕組みと、実測の限定事項 (停止は実メモリ不足の証明にならない、増設で trigger が消えるとは限らない) を Rationale に併記する。ct112 の増設は #1477 に対する緩和策として記録し、2026-09 の停止には作用しないことを明記する

### Auto-resolved decisions (非対話モード。Step 15 のコメントにも Auto-Resolve Log として記載)

- **再 kill 時の対応を「最大 2 回の再 respawn (計 3 回起動) + 各回の前のメモリスナップショット + 上限到達で停止・報告」とした** — 理由: 受入条件 4 が親セッションの対応の記録を求めるが、具体策は Issue に無い。実績は #1457 / #1468 が 3 回目で完走、#1461 は 2 回目の kill で停止してユーザー判断を仰ぎ、後日の再実行で完走 (#1146 コメント)。完走の機会を残しつつ上限で止まる設計にした。コードでの強制は Issue の判断どおり対象外
  - Other candidates: 最初の再 kill で即停止 (#1461 の実績どおりだが完走の機会を捨てる)、上限なし (無限ループの危険)、待機時間を決めて再試行 (根拠となる数値がない)
- **メモリ理由つきの停止通知の `--notification` クラスを `harness-stop` とした** — 理由: `scripts/emit-event.sh` の定義 (ハーネス自身の task-kill 経路を示す文言) に合致する。`skills/auto/SKILL.md` Step 6 の clause (b) が `indeterminate` とするのは理由のない bare な `killed` / `was stopped` で、別物。ログ上は #1477 だけ `indeterminate` で記録されており、その不整合を解消する。`--notification` は `collect-recovery-candidates.sh` の grouping に使われない (grouping は `--cause` のみ) ため、機能上の影響はない
  - Other candidates: `skills/auto/SKILL.md` の clause (b) 付近に新しい clause を足す (スキルの挙動変更になり Issue の範囲外)
- **停止時点のメモリスナップショット取得を best-effort の手順として追加した** — 理由: 4 件のどれにも停止時点のスナップショットがなく、実メモリ不足とハーネス側の誤判定を後から切り分けられない。`free -m` / `memory_pressure` は `skills/auto/SKILL.md` の `allowed-tools` に無く、許可待ちになりうるため、「許可確認なしに取得できる場合」に限定した
  - Other candidates: スナップショット手順を入れない (再発時に同じ調査のやり直しになる)、`allowed-tools` に追加する (スキルの変更で範囲外)
- **`skills/auto/SKILL.md` は変更しない** — 理由: Issue の受入条件はすべて `modules/orchestration-fallbacks.md` で、「コードの変更は含めない」とも明記されている。親セッションが SKILL.md Step 6 から辿る `#external-kill-parent-respawn` の Symptom と Operational Policy に新エントリへのポインタを置くことで到達性を確保する。到達性が不十分と分かった場合は、Step 6 の通知分類 clause へのポインタ追加を別 Issue で扱う
- **`oom-kill-review-full-fanout` (#1457、2026-09-08) は 4 件の外として注記するにとどめた** — 理由: 別 cause slug のため `collect-recovery-candidates.sh` では別グループで、過去のログエントリの書き換えは行わない。今後の記録は `--cause harness-oom-stop` に統一するよう Fallback Steps に明記する (post-merge の観測が grep する slug と一致させるため)

### Uncertainties

- メモリ増設の前後の容量は Issue に記載がなく、モジュールにも書かない (「Sizes before and after were not recorded」と明記する)
- 2026-09 の停止が macOS ホスト、2026-10-03 の停止が ct112 という対応関係は、#1146 のコメント (macOS の `kern.boottime`・圧迫レベル・48 GB) と Issue 本文から読み取ったもの。ホストの移行時期そのものは記録がない
- 公式ドキュメントの引用は WebFetch (要約付き取得) 経由。出所: `https://code.claude.com/docs/en/interactive-mode` の Background bash commands 節 (停止条件・debug log・opt-out)、`https://code.claude.com/docs/en/env-vars` の `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` (v2.1.193 以降)、`https://code.claude.com/docs/en/debug-your-config` (debug log のパス `~/.claude/debug/<session-id>.txt`)。いずれも 2026-10-05 取得。上流 issue (`anthropics/claude-code#78674` Linux・MemFree 判定、`#92228`) の状態は取得時点で open
- 「親セッションの待機が 30 分アイドルの条件を満たしうる」は公式の停止条件からの推論で、`/auto` の待機方式 (背景実行の完了通知待ち) が実際にこの条件に当たるかは未検証。モジュールでは「can meet」「consistent with」と断定を避けている

### 識別子の実在確認 (調査・監査型ではないが、引用する識別子は grep で確認済み)

- 監査・調査型 Issue の判定: no (複数項目を分類する調査ではなく、既存の記録を 1 つのエントリにまとめる文書作成。成果物の根拠として後続処理が読むのは verify command ではなく Issue / ログ)。ただし引用する識別子は確認した
- 確認済み: `_find_known_recoveries_issue` / `_search_recoveries_issue` (`scripts/run-auto-sub.sh`)、`notification_class` (`scripts/emit-event.sh`)、`--write-manual-recovery` (`scripts/run-auto-sub.sh`、`skills/auto/SKILL.md`)、`scripts/detect-external-kill.sh`、`scripts/collect-recovery-candidates.sh` (既定 `THRESHOLD=3`)、`docs/reports/orchestration-recoveries-archive.md` (存在、`cause: harness-oom-stop` は 0 件)、`cause: harness-oom-stop` は `docs/reports/orchestration-recoveries.md` に 4 件 (2026-10-03 03:55 / 2026-09-13 12:21 / 2026-09-10 02:57 / 2026-09-09 08:45 UTC)、`oom-kill-review-full-fanout` は同ファイルの 1 件 (2026-09-08 07:43 UTC)、Issue #1146 / #1093 は open、#1461 / #1477 は closed
- 増設後 batch の事実 (`docs/sessions/1123127-1791088655-2026-10-04/session.md` と `events.jsonl`): `/auto --batch 1490 1491 1497 1496 1493 1492 1495 1494` (8 件)、開始 2026-10-04T04:37:59Z、終了 08:37:29Z、Tier 1/2/3 recovery 0 件、watchdog kill 0 件、`manual_intervention` は #1494 の `label-backfill` の 1 件のみ

### Steering Docs sync candidate check の結果

- [Steering Docs sync candidate] keyword `orchestration-fallbacks.md` skipped: matched 149 files (no discriminating power) — 測定範囲: `grep -rl "orchestration-fallbacks.md" docs/ tests/ scripts/ modules/` (全ファイル種別、`docs/spec/` と `docs/sessions/` の履歴を含む)
- [Steering Docs sync candidate] keyword `external-kill-parent-respawn` skipped: matched 28 files (no discriminating power) — 同じ測定範囲。参考: `docs/spec/`・`docs/sessions/`・`docs/reports/orchestration-recoveries.md` を除く参照元は 10 件 (`docs/structure.md`、`docs/tech.md`、`docs/workflow.md`、`docs/ja/{structure,tech,workflow}.md`、`docs/reports/external-kill-investigation.md`、`modules/orchestration-fallbacks.md`、`scripts/detect-external-kill.sh`、`scripts/run-auto-sub.sh`)。`docs/tech.md` (57 行目) と `docs/workflow.md` (125 行目) の該当段落を読み、respawn の仕組みと `--cause` / `--notification` の記録手順を説明するもので、「respawn は必ず成功する」「蓄積は障害ではない」とは述べていないことを確認した。`docs/structure.md` は `detect-external-kill.sh` の説明 — いずれも変更不要 (推測ではなく確認済み)
- keyword `harness-oom-stop` (新しい anchor 兼 cause slug): matched 4 files。すべて履歴の記録 (`docs/reports/orchestration-recoveries.md`、`docs/sessions/{90128-1788933783-2026-09-18,190537-1790984033-2026-10-03,1123127-1791088655-2026-10-04}/session.md`) で、同期候補なし
- Listing-side sub-check: 発火しない (subcommand の追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構成の変更なし。既存モジュールへのエントリ追加のみ)。`docs/structure.md` の Key Files にある `modules/orchestration-fallbacks.md` の説明はエントリの一覧を持たないため変更不要
- Outbound pointer sync candidate check: 変更ファイルの body が指す先は `skills/auto/SKILL.md` (Step 6 の外部 kill 事前チェックと通知分類)、`scripts/emit-event.sh` (`notification_class` の定義)、`docs/reports/external-kill-investigation.md`。今回の変更でこれらの内容を更新する必要はない (SKILL.md を変更しない理由は上記の Auto-resolved decisions)
- `docs/ja/` translation sync: `docs/translation-workflow.md` あり。Changed Files に top-level の `docs/*.md` が無いため同期対象なし。`modules/` は翻訳対象外

### その他のチェック結果

- 新規テストケース: 新規の分岐ロジックを持つ Implementation Step は無い (文書の追加のみ)。`tests/orchestration-fallbacks.bats` は必須 5 セクションの件数一致と Rationale 内の `#N` 参照を検査するだけで、新エントリを自動的に対象にするため変更不要 (テストファイルを読んで確認済み)
- allowed-tools impact chain check (`modules/*.md` の変更、Case 2): 追加本文 (Entry draft と相互参照 bullet) が参照する `scripts/*.sh` のパスは `scripts/detect-external-kill.sh` の 1 つだけで、説明として挙げるのみ (読み手に新しい呼び出しを求める記述ではない)。このモジュールを読む SKILL.md は `skills/auto/SKILL.md`、`skills/review/SKILL.md`、`skills/verify/SKILL.md` の 3 つ (`grep -l "modules/orchestration-fallbacks.md" skills/*/SKILL.md`)。`allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-external-kill.sh:*` を持つのは `auto` のみ (`review` / `verify` は 0 件) だが、`review` / `verify` はこの script を呼ばないため、ギャップはなく SKILL.md の変更は不要。スナップショット用の `free -m` / `memory_pressure` は scripts/*.sh ではなく、上記のとおり best-effort に限定した
- 数値の測定範囲: 「4 件」は `grep -c "cause: harness-oom-stop" docs/reports/orchestration-recoveries.md` (現行ファイル。archive は 0 件)。「8 件」は `/auto --batch` の対象 Issue 数。「725 サンプル / 60 分 / 2.65 GB / 0.26 GB / 94% / 245 s / 52 MB」は #1146 コメントの実測値の引用で、本 Spec では再計測していない
- Costly / irreversible な Implementation Step: なし (文書編集と軽量なテスト実行のみ)。外部サービスへのログインを要する Step: なし
- 出所 (provenance) は上記 Uncertainties を参照

## Code Retrospective

### Deviations from Design
- なし。Entry draft の事実 (日付・Issue 番号・件数・セッション ID・引用文言) はそのまま転記し、相互参照 bullet 2 件も Spec の原文どおり追加した

### Design Gaps/Ambiguities
- 実行環境に bats が無く (`command -v bats` が空)、`tests/orchestration-fallbacks.bats` と、`modules/orchestration-fallbacks.md` を参照する他 3 つのテスト (`run-auto-sub` / `run-code` / `run-spec`) を実行できなかった。代わりに構造検査を手動で再現した: 必須 5 セクションが各 22 件で一致、Rationale 内の `#N` 参照あり (awk による同等検査)。AC はすべて `file_contains` / `rubric` で bats の `command` AC は無いため、Step 10 の bats-absent 除外と Step 14 の CI 確認の対象外
- 検証済み: `check-forbidden-expressions.sh` と language-convention check (merge-base 6fe36641 との diff) は出力なし・exit 0、`validate-skill-syntax.py skills/` は 0 error。`check-bare-bracket-assertions.sh` の 1016 件の警告は既存の tests/ 由来で、本変更 (tests/ 無変更) とは無関係
- Pre-implementation FAIL 確認: 新規テストの追加なし (N/A)

### Rework
- なし。ただし Issue 本文の checkbox 更新用の一時ファイルを Write ツールでなく Bash リダイレクトで作成してしまった (Notes の規約違反、内容への影響なし・削除済み)

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1500#issuecomment-5987864250

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Entry draft を Spec の原文どおり `modules/orchestration-fallbacks.md` に追加し (`## harness-oom-stop`)、`external-kill-parent-respawn` に相互参照 bullet 2 件を追加した。コード変更・`skills/auto/SKILL.md` の変更はなし (Spec の判断どおり)
- 書き込み前に識別子 (`_find_known_recoveries_issue`、`harness-stop` 等の通知クラス、`THRESHOLD=3`、`detect-external-kill.sh`、archive ファイル、`cause: harness-oom-stop` 4 件) を grep で再確認した

### Deferred Items
- bats 未導入のため `tests/orchestration-fallbacks.bats` ほか 3 テストを実行できず、構造検査 (必須 5 セクションの件数一致・Rationale 内の `#N` 参照) を awk / grep で手動再現した。CI の bats ジョブが push 後の本確認になる
- Post-merge の observation AC (2026-11-02 以降の最初の `/auto` 完了時に `cause: harness-oom-stop` の新規エントリがないこと) は未確認のまま `/verify` に残る

### Notes for Next Phase
- Pre-merge AC 4 件 (file_contains 3 + rubric 4 の組) は Issue 本文でチェック済み。Post-merge の observation AC のみ未チェック
- 2026-11-02 より前に `/verify` が走る場合は観測期間不足で SKIPPED が期待される。期間内に `cause: harness-oom-stop` の新規エントリがあれば FAIL (再発 = 緩和策不足。コード側の施策は別 Issue で扱う)
- push 後の CI (`Run bats tests`) の結果を確認すること: 新エントリは必須 5 セクションの件数一致と Rationale の `#N` 参照を既存テストが自動検査する
