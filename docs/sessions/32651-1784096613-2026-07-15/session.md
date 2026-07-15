# L3 Session Retrospective: 32651-1784096613

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-07-15T06:24:32Z
**Session end**: 2026-07-15T13:09:11Z
**Wall-clock**: 06:44:39
**Route mix**: patch: 3, pr: 6, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 13 |
| Fully closed (phase/done) | N/A (--no-github) |
| phase/verify remaining | N/A (--no-github) |
| Throughput | 1.9 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 1820s |
| Phase silent windows > threshold | 1 (spec:1) |
| Total token usage | input 15935 / output 227857 |
| Concurrent commits detected | 0 |
| Parent session manual interventions | 5 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 3 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 4 |
| code-pr | 5 |
| issue | 10 |
| merge | 6 |
| review | 7 |
| spec | 14 |
| verify | 19 |

## What worked

- Batch List mode (`--batch 1017 1010 1009 994 993`) processed 5 explicitly-listed Issues sequentially, with the user adding #993 mid-turn via `/auto --batch` remaining-list semantics honored correctly.
- The external-kill pre-check recovery playbook (established in prior sessions, see `[[project_external_kill_pattern]]`) was applied 5 times this session, each time correctly diagnosing via `detect-external-kill.sh` (isolating the relevant phase's log segment to avoid false negatives from earlier phases' "Exit code:" trailers) and respawning `run-auto-sub.sh` without any lost work, thanks to label-as-SSoT + milestone resume (`skip-to-review` action correctly triggered twice for #1017 and #1009 after code-pr/PR-already-exists was detected).
- The Event-based observation scan (`observation-trigger.sh --event auto-run`) correctly surfaced 10 Issues with pending observation-type ACs; per `AUTONOMY_TIER=L3`, all 8 not already in `BATCH_LIST` were dispatched to `/verify` sequentially. Two of them (#981, #1015) had their observation conditions genuinely satisfied by this session's own activity and were confirmed PASS with concrete evidence rather than deferred again — a case where the observation mechanism's design (defer until a real occurrence, then verify against it) worked exactly as intended.
- Recovery Candidates Tail Check (`recoveries-auto-fire`) correctly did NOT re-file a duplicate Issue for the accumulating `manual-recovery-respawn` entries, since #1017's fix (matching known symptom Issues) had already tagged them `起票済み #1014` — confirmed this specific fix works in production during this same session that exercised it 5 more times.

## Findings

- 外部kill切り分け実験 (ユーザー発案、セッション/ターミナル再起動 + Fable→Sonnet 切替) の結果、若いセッションでも 5 issue 中 4 issue で計 5 回 kill が発生し、頻度は減らなかった。H-a (長命セッションのタスク reaper) のセッション長依存説は棄却方向。`docs/reports/external-kill-investigation.md` に詳細記録済み、`[[project_external_kill_pattern]]` メモリも更新済み。[Resolved directly: 実験結果を investigation report とメモリに記録]
- `scripts/run-auto-sub.sh --write-manual-recovery` の `EXIT_CODE` 引数が、skill文書 (`skills/auto/SKILL.md`) の "unknown if it could not be observed" という指示に反し、実装側 (`_validate_recovery_args`) では数値のみ許容し `unknown` を拒否する (exit 1) 仕様不一致を発見。今回は引数省略で回避したが、文書と実装のどちらかを修正すべき恒久対応が必要。[Filed: #1020]
- Observation-type AC (`verify-type: observation event=auto-run`) のうち、project-config 依存の条件 (例: `always-pr: true` が本リポジトリで未設定) は原理的に永続的に観察不能であるにもかかわらず、`auto-run` イベントは「任意の /auto 完走」という広いスコープで無条件に再発火し、Issue #797 では 30件超の無意味な再通知コメントが3週間にわたり蓄積していた。Tier 2 (convention/recurring pattern) と判定し、Issue 起票はせず Spec retrospective への記録のみとした (同種のパターンは #839, #841, #843, #984, #995 でも観測)。[No action: Tier 2 判定によりメモリ/Specへの記録のみで十分と判断、opportunistic-search.sh の既存 --context-file ゲート機構を参考にした将来の改善余地は #797 の Spec に記録済み]

## Auto Retrospective

### Improvement Proposals

- `skills/auto/SKILL.md` の外部kill pre-check手順が `EXIT_CODE=unknown` を渡す指示になっているが、`scripts/run-auto-sub.sh` の `_validate_recovery_args` はこれを拒否する。ドキュメントと実装のどちらかを修正すべき — 案: `_validate_recovery_args` の exit_code 検証を `^([0-9]+|unknown)$` に緩和するか、SKILL.md 側の記述を「未観測時は引数省略」に統一する

## Filed Issues

- #1020

## Skill Self-Update Propagation Note

Session 中に以下の skill が更新されました (本 session には未適用、次 session から反映):
- skills/auto/SKILL.md: (no change)
- skills/code/SKILL.md: 4198c6d56ee2391e7b95ba2eb95293eb9582d3be → 598f1b5f1d44a379dd113ce4e2aed0fd6d46d02d
- skills/spec/SKILL.md: (no change)
- skills/verify/SKILL.md: (no change)
- skills/review/SKILL.md: (no change)
- skills/merge/SKILL.md: (no change)
- skills/issue/SKILL.md: (no change)
- skills/audit/SKILL.md: (no change)
