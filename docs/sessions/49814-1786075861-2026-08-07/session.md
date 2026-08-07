# L3 Session Retrospective: 49814-1786075861

**Date**: 2026-08-07
**Route**: batch (List mode) — `/auto --batch 1108 1117 1228 1064 1063 939`
**Issues processed**: #1108 (M) / #1117 (M) / #1228 (L) / #1064 (M) / #1063 (M) / #939 (M) — 6/6 完走、failed 0 / skipped 0
**Duration**: 約 10h05m (04:11:43Z → 14:16:37Z)

> **注記**: 本セッションは `/auto --batch` を skill として起動し、親セッションが List mode の各ステップ (labels 確認 → Size 取得 → blocked-by gate → `run-issue.sh` / `run-auto-sub.sh` 起動 → in-session `/verify`) を手順どおり実行した。batch checkpoint は `35167-1786075877`。

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-07T04:11:43Z
**Session end**: 2026-08-07T14:16:37Z
**Wall-clock**: 10:04:54
**Route mix**: patch: 0, pr: 6, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 47 |
| Fully closed (phase/done) | N/A (--no-github) |
| phase/verify remaining | N/A (--no-github) |
| Throughput | 4.7 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Recovery success rate (tier) | T1: 0 recovered / 0 failed, T2: 0 recovered / 0 failed, T3: 0 recovered / 0 failed |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2650s |
| Phase silent windows > threshold | 4 (issue:2, spec:2) |
| Total token usage | input 9385 / output 871980 |
| Concurrent commits detected | 62 |
| Parent session manual interventions | 1 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Retro proposal tiers (1/2/3) | 1 / 3 / 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-pr | 12 |
| issue | 8 |
| merge | 13 |
| review | 12 |
| spec | 12 |
| verify | 16 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
| #35 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #51 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #56 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #65 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #86 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #122 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #135 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #140 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #144 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #217 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #316 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #319 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #363 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #365 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #436 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #438 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #441 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #461 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #476 | ?/? | 2026-08-07T05:34:15Z – 2026-08-07T05:38:28Z | verify 4m | — | T1:0/T2:0/T3:0 | — |
| #481 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #482 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #489 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #494 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #511 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #541 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #547 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #564 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #575 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #580 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #707 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #781 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #783 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #790 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #917 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #939 | M/pr | 2026-08-07T11:29:43Z – 2026-08-07T14:10:40Z | code-pr 44m → issue 8m → merge 6m → review 14m → spec 29m → verify 2m | — | T1:0/T2:0/T3:0 | Silent 1770s phase=spec (within 600s of watchdog limit);6 concurrent commits |
| #998 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1003 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1051 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1052 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1053 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1063 | M/pr | 2026-08-07T10:32:21Z – 2026-08-07T11:29:16Z | code-pr 18m → merge 3m → review 15m → spec 15m → verify 2m | — | T1:0/T2:0/T3:0 | Silent 1130s;5 concurrent commits |
| #1064 | M/pr | 2026-08-07T09:07:24Z – 2026-08-07T10:31:56Z | code-pr 34m → merge 5m → review 20m → spec 19m → verify 2m | — | T1:0/T2:0/T3:0 | Silent 2030s;9 concurrent commits |
| #1108 | M/pr | 2026-08-07T04:11:43Z – 2026-08-07T05:52:14Z | code-pr 33m → issue 8m → merge 2m → review 24m → spec 22m → verify 5m | — | T1:0/T2:0/T3:0 | Silent 1340s phase=spec (within 600s of watchdog limit);10 concurrent commits |
| #1115 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1117 | M/pr | 2026-08-07T05:56:26Z – 2026-08-07T07:21:15Z | code-pr 37m → issue 10m → merge 3m → review 19m → spec 12m | — | T1:0/T2:0/T3:0 | Silent 640s phase=issue (within 600s of watchdog limit);15 concurrent commits |
| #1220 | ?/? | ? – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1228 | L/pr | 2026-08-07T07:28:48Z – 2026-08-07T14:16:37Z | code-pr 18m → issue 11m → merge 3m → review 43m → spec 15m → verify 312m | — | T1:0/T2:0/T3:0 | Silent 690s phase=issue (within 600s of watchdog limit);17 concurrent commits |


### Token Usage Aggregate

| Issue | Input tokens | Output tokens | Total |
|---|---|---|---|
| #939 | 1657 | 259595 | 261252 |
| #1063 | 512 | 122845 | 123357 |
| #1064 | 790 | 170399 | 171189 |
| #1108 | 444 | 90276 | 90720 |
| #1117 | 486 | 74048 | 74534 |
| #1228 | 5496 | 154817 | 160313 |

### Recovery Events

(no recovery events)

### Verify Phase Residuals

(--no-github mode: cannot detect phase/verify residuals via live label lookup. Re-run without --no-github to populate this section.)

### Concurrent Sessions Detected

- [2026-08-07T05:17:41Z] phase=code-pr sha=0ae13335 → #476 (author=Toshihiro Saito)
- [2026-08-07T05:17:41Z] phase=code-pr sha=fbb63d51 → #1165 (author=Toshihiro Saito)
- [2026-08-07T05:17:41Z] phase=code-pr sha=d6dc0e53 → #1165 (author=Toshihiro Saito)
- [2026-08-07T05:17:41Z] phase=code-pr sha=0305bbb7 → #575 (author=Toshihiro Saito)
- [2026-08-07T05:17:41Z] phase=code-pr sha=924d4b3d → #575 (author=Toshihiro Saito)
- [2026-08-07T05:42:38Z] phase=review sha=82ac9737 → #1234 (author=Toshihiro Saito)
- [2026-08-07T05:42:38Z] phase=review sha=cb47927f → #476 (author=Toshihiro Saito)
- [2026-08-07T05:42:38Z] phase=review sha=049a58de → #476 (author=Toshihiro Saito)
- [2026-08-07T05:42:38Z] phase=review sha=0b590f46 → #1164 (author=Toshihiro Saito)
- [2026-08-07T05:42:38Z] phase=review sha=f82afe7a → #1164 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=c902d8c6 → #1167 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=a87bde7a → #1166 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=391ee39d → #1165 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=f2047886 → #1164 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=a8217590 → #1158 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=3d33d983 → #1166 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=45ebc3f1 → #1167 (author=Toshihiro Saito)
- [2026-08-07T06:58:21Z] phase=code-pr sha=533a84bb → #1167 (author=Toshihiro Saito)
- [2026-08-07T07:17:29Z] phase=review sha=55af0dea → #1164 (author=Toshihiro Saito)
- [2026-08-07T07:17:29Z] phase=review sha=9b9f294e → #1164 (author=Toshihiro Saito)
- [2026-08-07T07:17:29Z] phase=review sha=dda541a1 → #476 (author=Toshihiro Saito)
- [2026-08-07T07:17:29Z] phase=review sha=c3d2a60a → #476 (author=Toshihiro Saito)
- [2026-08-07T07:21:14Z] phase=merge sha=e144a494 → #1167 (author=Toshihiro Saito)
- [2026-08-07T07:21:14Z] phase=merge sha=d9f1ae04 → #1167 (author=Toshihiro Saito)
- [2026-08-07T07:21:14Z] phase=merge sha=cbcefee8 → #1165 (author=Toshihiro Saito)
- [2026-08-07T08:15:30Z] phase=code-pr sha=35b38a42 → #1224 (author=Toshihiro Saito)
- [2026-08-07T08:15:30Z] phase=code-pr sha=f79bd887 → #1224 (author=Toshihiro Saito)
- [2026-08-07T08:15:30Z] phase=code-pr sha=63d2630e → #1236 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=867b8396 → #1213 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=d64dd230 → #1213 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=e28c0d64 → #575 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=8117d83a → #575 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=fb4cf460 author=Toshihiro Saito
- [2026-08-07T08:58:40Z] phase=review sha=3944c81a → #1158 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=b3c3dc93 → #575 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=a68fe2b7 → #575 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=4446d479 → #1221 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=d3daa8e5 → #1158 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=9ed103ca → #1158 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=61e39964 → #1158 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=331428ee → #575 (author=Toshihiro Saito)
- [2026-08-07T08:58:40Z] phase=review sha=d19d66b4 → #1224 (author=Toshihiro Saito)
- [2026-08-07T10:01:30Z] phase=code-pr sha=2705b231 → #1221 (author=Toshihiro Saito)
- [2026-08-07T10:01:30Z] phase=code-pr sha=20a184a3 → #1221 (author=Toshihiro Saito)
- [2026-08-07T10:01:30Z] phase=code-pr sha=84bfb1fe → #1221 (author=Toshihiro Saito)
- [2026-08-07T10:01:30Z] phase=code-pr sha=08d894a2 → #476 (author=Toshihiro Saito)
- [2026-08-07T10:21:38Z] phase=review sha=671455cc → #476 (author=Toshihiro Saito)
- [2026-08-07T10:21:38Z] phase=review sha=742584c7 → #476 (author=Toshihiro Saito)
- [2026-08-07T10:21:38Z] phase=review sha=905c6e1b → #575 (author=Toshihiro Saito)
- [2026-08-07T10:27:22Z] phase=merge sha=14c25dc0 → #1236 (author=Toshihiro Saito)
- [2026-08-07T10:27:22Z] phase=merge sha=5c676042 → #1236 (author=Toshihiro Saito)
- [2026-08-07T11:06:45Z] phase=code-pr sha=d06cdde3 → #476 (author=Toshihiro Saito)
- [2026-08-07T11:06:45Z] phase=code-pr sha=430027da → #476 (author=Toshihiro Saito)
- [2026-08-07T11:22:33Z] phase=review sha=5b644c45 → #1220 (author=Toshihiro Saito)
- [2026-08-07T11:22:33Z] phase=review sha=3bf5ea47 → #1220 (author=Toshihiro Saito)
- [2026-08-07T11:22:33Z] phase=review sha=94794f92 → #1220 (author=Toshihiro Saito)
- [2026-08-07T12:53:25Z] phase=code-pr sha=15d796f3 → #1234 (author=Toshihiro Saito)
- [2026-08-07T12:53:25Z] phase=code-pr sha=a915e731 → #1234 (author=Toshihiro Saito)
- [2026-08-07T12:53:25Z] phase=code-pr sha=9004ae05 → #1234 (author=Toshihiro Saito)
- [2026-08-07T12:53:25Z] phase=code-pr sha=fd64d066 → #1227 (author=Toshihiro Saito)
- [2026-08-07T12:53:25Z] phase=code-pr sha=7a123864 → #1227 (author=Toshihiro Saito)
- [2026-08-07T12:53:25Z] phase=code-pr sha=27129dd1 → #476 (author=Toshihiro Saito)


### Improvement Candidates Surfaced

(none — no Tier 3 recoveries or Tier 2 approaching recoveries-auto-fire threshold)

### Retro Proposal Tier Breakdown

- Tier 1: 1
- Tier 2: 3
- Tier 3: 0

Filter hit rate: 75% (3+0/4)
### Metrics の精度に関する注記

- **Issues processed 47 は実態 6 と乖離している**。バッチ末尾の `observation-trigger.sh --event auto-run` が 20 件の Issue にコメントを投稿し、それらの emit が同一 `session_id` に載るため。実データ (Duration / Phase breakdown / Token Usage) を持つのは #939 / #1063 / #1064 / #1108 / #1117 / #1228 の 6 件のみで、他 41 件は全カラムが `?` / `—`
- **#1228 の `verify 312m`** は `/verify` を 2 回実行したため (1 回目 09:00 頃は post-merge AC が未発火で SKIPPED、2 回目 14:16 は observation scan 後に PASS 確定)。連続した滞留ではない
- **#1117 の verify フェーズが Metrics に現れない** — 親セッションが `persist_auto_session_pointer` を省略したため `phase_complete` が並行セッション `3340-1786079730` に誤帰属した (Findings 参照)

## What worked

### Issue 間の依存が実際に解けていく連鎖が観測できた

本バッチの最大の成果は、事前に設定した blocked-by が実運用で機能し、**後続 Issue が先行 Issue の成果を証拠として使う**連鎖が成立したことである。

```
#1108 (案 A: run-auto-sub.sh の spec dispatch に Size XS ゲートを追加)
   └─ dispatch チェーンの構造を保持
#1228 (案 ii: run-spec.sh / run-issue.sh 側で直接 emit)
   ├─ #1108 の XS ゲート・ログ文言・--opus 受け渡しを一切壊さず実装
   ├─ spec / issue phase の wrapper_exit / token_usage を 0 件 → 実測可能に
   ├─ #939 の blocker を解除
   └─ #1064 のレポート再評価トリガーの前提を一部充足
#939 (AC の実測範囲を --fable → --fable または --opus に拡張)
   └─ #1228 が Size L で通した --opus spec の実測 (max silent 900s / 閾値 1800s) で PASS
```

triage 時に #1228 へ投稿した申し送りコメント (案 i を採る場合の 3 制約) が Comment Consumption 経由で spec に届き、**spec は案 ii を選んで 3 制約すべてを回避した**。先行 Issue の成果を壊さない方針選択が L0 経由の情報伝播で成立している。

### #939 の 2 回 FAIL していた構造的デッドロックが専用試行ゼロで解けた

#939 は「AC が `--fable` 実行の実測を要求するが、`docs/tech.md` の『無認可の試行実行で証拠を捏造しない』方針により実測が得られない」という衝突で 2 回 FAIL していた。過去の改善提案は 2 件とも「実測が得られない前提で verify 側の判定を緩める」方向 (escape hatch / ガイドライン追加) だったが、実際に効いたのは **第 3 の経路 = 証拠源の拡張**だった。

`/issue` refinement が蓄積コメント 3 件を入力として AC1/AC2 の範囲を `--opus` へ広げ、同一バッチの #1228 (Size L) が通常の backlog 消化の副産物として証拠を供給した。**専用の試行実行を一切行っていない**。

### merge 直後の明示的な base 同期が `session=next` 要件を満たした

#1228 の merge 完了直後に `git fetch origin main` + `git merge --ff-only origin/main` を挟むことで、後続の #1064 / #1063 / #939 の spec / issue phase が新版 `run-spec.sh` / `run-issue.sh` で実行された。これにより #1228 の post-merge AC (`observation event=auto-run session=next`) が**同一バッチ内で確定**した。

`run-*.sh` は新プロセスでディスクから読み直すため、`session=next` は会話セッションを跨ぐ必要がない ([[project_triage_audit_gap]] の解釈)。#1206 が検出機構を入れた「ローカル main 未追従で skill が巻き戻る」経路を、明示的な同期で先回りして塞いだ形。

### #1076 の rebase fallback が 5 回すべて自動復旧した

`worktree-merge-push.sh` の `ff-only-merge-fallback` が 5 回発火 (各 verify の Worktree Exit 時)。並行セッションが 3-4 本稼働して base が頻繁に進むため FF が失敗するが、すべて ancestry 確認 → worktree rebase → FF → push で自動復旧した。#1076 が本バッチ前に着地していなければ手動 rebase を 5 回要していた。

### #1186 のチェック済み AC スキップ規則の効果を定量できた

pre-merge AC は 6 Issue で計 39 件あり、すべて `/review` フェーズでチェック済みのため SKIPPED になった。効果が最大化したのは #1228 で、**8 件中 4 件が `command "bats ..."` 型** (`auto-sub-observability` / `run-auto-sub` / `run-spec` / `run-issue`) だったため、旧規則なら bats 4 スイートを再実行していた。

### external kill からの復旧が手順どおり成立した

#939 の merge phase が external kill を受けた際、Step 6 の external kill pre-check → `detect-external-kill.sh` による機械的確認 → respawn → `--write-manual-recovery ... --cause` の記録、という手順が一度も逸脱せずに回った。respawn は 6 分 54 秒で完走し CI bats 1560/0。

## Findings

- **external kill が新規条件 3 軸で再現した**。#939 の merge phase (13:07:44Z 開始) が最終出力から約 3 分後に停止。`detect-external-kill.sh` が `external-kill` シグネチャ (開始バナーあり / 終端バナーなし / `Exit code:` トレーラなし / `wrapper_exit` イベントなし) を機械的に確認。merge phase の watchdog 閾値 600s に到達していないため watchdog kill ではなく、CI 待機も完了済み (9/9 passed) で #1214 型の CI 障害でもない。既存記録に対する新規条件は (1) ホスト uptime **~70h** (報告書の上限 ~60h 超)、(2) phase=**merge** (既存は code / review / issue)、(3) load avg 4.52 の並行下。ただし 1 件では 7 月の発生率 (2 週間で 30+ 件) との頻度差を説明できず、AC 5 の「目安 2 週間以上」にも未達 [No action: #1146 に観測データを追記済み (issuecomment-5218189467)。expiry criterion の再修正 (2) が定める backstop 2026-09-07 までの追加観測を継続する方針を維持]

- **harness-stop と external-signal を通知文言から判別できなかった**。停止時の通知は `<status>killed</status>` / `Background command "..." was stopped` で、正常時の `<status>completed</status>` / `completed (exit code 0)` と異なり**数値の exit code を含まない**。`detect-external-kill.sh` に `--exit-code unknown` を渡すしかなく、その場合の判定 (トレーラとイベントの両方の不在) は harness がプロセスグループを終了させたケースでも同一の結果になる。判別に使えそうな追加軸として (1) 通知に数値 exit code が含まれるか、(2) 停止までの経過時間 vs watchdog 閾値、(3) `run_in_background` で起動したタスクか、の 3 つを観測した [No action: #1153 に通知文言と判別軸 3 案を追記済み (issuecomment-5218189694)。同 Issue のスコープを「文言の記録」から「判別ロジック」へ広げるかは判断が必要]

- **`modules/detect-config-markers.md` の watchdog phase default が実装と 3 phase で乖離していた**。表の記載は code 1800 / review 2000 / issue 600 だが、`scripts/watchdog-defaults.sh` の実装値は 4680 / 5400 / 1200 (2.0〜2.7 倍)。#628 (issue 600→1200)、Sonnet 5 recalibration (code/review 1.3x)、#939 (review 2600→5400) の 3 回の変更が伝播していない。実害として、親セッションが #1108 の issue phase で silent 480s を観測した際に「あと 120s で kill 圏」と**誤った危険判断をユーザーに報告した** (実際の閾値は 1200s で余裕 720s)。同バッチの #1228 issue phase は silent 660s で完走しており、記載どおり 600s なら kill されていた水準 [Filed: #1265]

- **`/verify 1117` の `phase_complete` が並行セッションに誤帰属した**。親セッションが Step 1 の `persist_auto_session_pointer` を省略したため、`restore_auto_session_pointer 1117` が issue-scoped ポインタを見つけられず `.tmp/auto-session-current` にフォールバックし、並行セッションが上書きした `3340-1786079730` を拾った。#1224 の失敗モードがそのまま再現した形だが、原因は skill の欠陥ではなく親セッションの手順漏れ。`phase_start` も未 emit のため、#1117 の verify フェーズは本セッションの Metrics からほぼ欠落している [Resolved directly: 残り 4 Issue (#1228/#1064/#1063/#939) と #1117 の issue-scoped ポインタを事前に一括作成し、以降の verify はすべて正しく帰属した。誤帰属した 1 イベントは session `41961-1785999585` の前例に倣いログを改変せず、本節と Metrics の注記で開示]

- **`/code` の precondition 診断の事実誤認が 3 回目**。#1108 の Auto-Resolve Log が「`phase/ready` が不在なのは先行する `/code` 実行が中断したため」と記録したが、timeline では `phase/code` の付与は 1 回のみで中断実行は存在しない。記録されたラベルリスト (`triaged, phase/code, retro/verify`) から、`/code` が**自身のラベル遷移後の状態を読んで** precondition を判定していることが読み取れ、#1102 の分析 (retrospective 執筆時点の再観測を遡及記述) より一段踏み込んだ機序が特定できた [No action: #1112 に 3 回目の実測をコメント済み (issuecomment-5213033471)]

- **post-merge AC の充足条件が Size に依存する Issue 群は、バッチ順序の設計対象になりうる**。#1064 AC7 (「L size Issue で `run-spec.sh --opus` が判定後の effort で起動」) と #1063 AC9 (「`/review --full` で review-bug/review-spec が frontmatter の effort で起動」) は、どちらも Size L の Issue が**着地後に** `/auto` を通ることを要求する。本バッチで L だったのは #1228 のみで両 Issue より前に処理されたため、2 件が同時に保留された。Size L の Issue を後ろに配置すれば両方解決できた [No action: #1064 / #1063 の Verify Retrospective にそれぞれ記録済み。#1118 / #1172 (observation AC の実行文脈条件) の隣接領域だが opportunistic 型かつ単発観測のため起票せず]

- **「維持」verdict を出す Issue の post-merge AC は判別力を持ちにくい**。#1064 は verdict が「維持」でコード変更ゼロだったため、AC7 は判定の前後で同一の結果を返す構造になっていた (`skills/triage/skill-dev-verify-audit.md` Pattern 2 の系)。判定そのものが観測可能な形 — 本 Issue の場合はレポートの再評価トリガー条件 (「`--opus` の実サンプルが蓄積したら」) の充足確認 — にする方が実効的 [No action: #1064 の Verify Retrospective に記録済み。#1209 (Pattern 2 の対象拡張) の隣接ケースだが「観測対象の選び方」の問題であり単発観測のため起票せず]

- **AC 文言の正確な読み取りが PASS / FAIL 双方の誤判定を防いだ**。#1063 の AC8 を truncate された表示から「Sonnet sub-agent に設定**しない**理由が記録されている」と読み違え、`agents/review-light.md` に `effort: high` があることと矛盾すると一度判断した。Spec を読んで実際の文言が「設定する**か否かの判断とその根拠**」であることを確認し解消した。already-checked スキップ規則で機械的に SKIP していれば疑いを持つ機会もなく、疑った時点で Spec を読まずに FAIL としていれば誤判定だった。session `11623-1785999585` の AC 10 誤 PASS (出力の変化を解釈に合わせて読み、AC 文言と突き合わせなかった) の裏返しのケース [No action: #1063 の Verify Retrospective に記録済み]

- **案 ii 採用の代償としてコード重複が発生した**。#1228 は `run-spec.sh` と `run-issue.sh` に同型の emit コードを追加したため、`emit-event.sh` への `emit_token_usage_from_file` 抽出が Deferred Items に残った。案 i (`run_phase_with_recovery()` 経由への統一) なら発生しなかったコスト [No action: 重複は 2 箇所に限定。3 箇所目の消費者が現れた時点が抽出の判断点 ([[project_skill_consolidation_trigger]] の基準)。#1228 の Verify Retrospective に記録済み]

- **`--opus` (Size L) の telemetry サンプルは依然ゼロ**。#1228 が spec / issue phase の emit を有効化し本バッチで spec 7 件 / issue 5 件が記録されたが、**すべて Sonnet パス**である。#1064 のレポートが再評価トリガーとして要求する `--opus` サンプルは、Size L の Issue が着地後に `/auto` を通るまで得られない — AC7 と同一条件 [No action: #1064 の Verify Retrospective に記録済み]

## Auto Retrospective

### Improvement Proposals

- `modules/detect-config-markers.md` の Marker Definition Table における watchdog phase default が `scripts/watchdog-defaults.sh` の実装値と 3 phase で乖離しており (code 1800 vs 4680 / review 2000 vs 5400 / issue 600 vs 1200)、親セッションの kill リスク判断を実際に誤らせた。#628 / Sonnet 5 recalibration / #939 の 3 回の変更が伝播していない。値の修正だけでは再発するため、SSoT 参照化またはテストによる固定が必要

## Filed Issues

- **#1265** — detect-config-markers: watchdog phase default の記載値を watchdog-defaults.sh と一致させる

## Housekeeping

- batch checkpoint `35167-1786075877` を削除済み
- verify worktree 7 件 (#1108 / #1117 / #1228 ×2 / #1064 / #1063 / #939) はすべて Worktree Exit → `worktree-merge-push.sh` → cleanup を完走し、残骸なし
- 本セッション中に別セッションが #1226 / #1227 (本セッションで起票した 2 件) の issue / spec phase を処理していることを events log で確認 (`token_usage` phase=spec で #1226 98,008 tokens / #1227 46,913 tokens)
