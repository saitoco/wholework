# L3 Session Retrospective: 90128-1788933783

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-09-09T06:07:26Z
**Session end**: 2026-09-18T12:45:55Z
**Wall-clock**: 222:38:29
**Route mix**: patch: 1, pr: 6, xl: 0, unknown: 6

### Summary

| Metric | Value |
|---|---|
| Issues processed | 13 |
| Fully closed (phase/done) | N/A (--no-github) |
| phase/verify remaining | N/A (--no-github) |
| Throughput | 0.1 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 1 |
| Recovery success rate (tier) | T1: 0 recovered / 0 failed, T2: 0 recovered / 0 failed, T3: 0 recovered / 1 failed |
| Watchdog kills | 0 |
| Max silent window (any phase) | 4460s |
| Phase silent windows > threshold | 2 (issue:2) |
| Total token usage | input 6690 / output 1520780 |
| Concurrent commits detected | 1 |
| Parent session manual interventions | 4 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 1 |
| Retro proposal tiers (1/2/3) | 7 / 4 / 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 2 |
| code-pr | 12 |
| issue | 14 |
| merge | 14 |
| review | 16 |
| spec | 12 |
| verify | 27 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
| #1325 | ?/? | 2026-09-13T12:48:41Z – 2026-09-13T12:51:41Z | verify 3m | — | T1:0/T2:0/T3:0 | — |
| #1329 | ?/? | 2026-09-13T12:53:33Z – 2026-09-13T12:55:57Z | verify 2m | — | T1:0/T2:0/T3:0 | — |
| #1350 | ?/? | 2026-09-18T12:37:30Z – 2026-09-18T12:39:19Z | verify 1m | — | T1:0/T2:0/T3:0 | — |
| #1351 | ?/? | 2026-09-18T12:40:58Z – 2026-09-18T12:43:18Z | verify 2m | — | T1:0/T2:0/T3:0 | — |
| #1365 | ?/? | 2026-09-09T07:28:00Z – ? | — | — | T1:0/T2:0/T3:0 | — |
| #1369 | ?/? | 2026-09-18T12:44:46Z – 2026-09-18T12:45:55Z | verify 1m | — | T1:0/T2:0/T3:0 | — |
| #1461 | L/pr | 2026-09-10T00:47:13Z – 2026-09-13T03:24:06Z | code-pr 38m → issue 10m → merge 3m → review 3659m → spec 22m → verify 1m | — | T1:0/T2:0/T3:0 | Silent 3460s |
| #1462 | M/pr | 2026-09-09T06:15:19Z – 2026-09-09T08:43:04Z | code-pr 22m → issue 10m → merge 62m → review 27m → spec 18m → verify 3m | — | T1:0/T2:0/T3:1 | Silent 640s phase=issue (within 600s of watchdog limit) |
| #1463 | L/pr | 2026-09-13T03:30:53Z – 2026-09-13T06:12:09Z | code-pr 51m → issue 9m → merge 2m → review 74m → spec 20m → verify 1m | — | T1:0/T2:0/T3:0 | Silent 4460s |
| #1464 | XS/patch | 2026-09-09T06:07:26Z – 2026-09-10T00:44:40Z | code-patch 19m → issue 7m → verify 1m | — | T1:0/T2:0/T3:0 | Silent 1150s |
| #1466 | M/pr | 2026-09-13T06:22:51Z – 2026-09-13T08:12:11Z | code-pr 27m → issue 10m → merge 3m → review 45m → spec 21m → verify 1m | — | T1:0/T2:0/T3:0 | Silent 610s phase=issue (within 600s of watchdog limit) |
| #1468 | M/pr | 2026-09-13T10:07:36Z – 2026-09-13T12:22:56Z | code-pr 37m → issue 7m → merge 3m → review 61m → spec 24m → verify 0m | — | T1:0/T2:0/T3:0 | Silent 2290s |
| #1470 | M/pr | 2026-09-13T08:15:30Z – 2026-09-13T10:04:26Z | code-pr 29m → issue 7m → merge 3m → review 47m → spec 20m → verify 0m | — | T1:0/T2:0/T3:0 | Silent 2810s;1 concurrent commits |

### Token Usage Aggregate

| Issue | Input tokens | Output tokens | Total |
|---|---|---|---|
| #1461 | 1124 | 326394 | 327518 |
| #1462 | 626 | 161992 | 162618 |
| #1463 | 1980 | 288417 | 290397 |
| #1464 | 236 | 50063 | 50299 |
| #1466 | 934 | 232890 | 233824 |
| #1468 | 808 | 222202 | 223010 |
| #1470 | 982 | 238822 | 239804 |

### Recovery Events

- [2026-09-09T07:38:52Z] Issue #1462 phase=merge tier=3 result=failed

### Verify Phase Residuals

(--no-github mode: cannot detect phase/verify residuals via live label lookup. Re-run without --no-github to populate this section.)

### Concurrent Sessions Detected

- [2026-09-13T09:59:30Z] phase=review sha=550ffc3b → #1365 (author=Toshihiro Saito)

### Improvement Candidates Surfaced

- Tier 3 recovery occurred in phase=merge — investigate root cause

### Retro Proposal Tier Breakdown

- Tier 1: 7
- Tier 2: 4
- Tier 3: 0

Filter hit rate: 36% (4+0/11)

## What worked

- **Until mode が上限到達ではなく収束で終了した。** Round 1 (4 件) → Round 2 (3 件、Round 1 の retro proposals) → Round 3 でクエリ 0 件。`--max-rounds 3` の安全弁は使われず、対象が尽きての正常終了。
- **round-ordering の cluster 判定が競合を防いだ。** Round 2 の #1466 と #1470 は両方が `skills/review/SKILL.md` を編集するため同一 cluster として隣接処理し、直列マージで競合を回避した。
- **phase ラベルを SSoT とした respawn が 5 回の外部 kill すべてで作業を保全した。** #1462 (spec 完了直後)、#1461 (review ×2)、#1468 (review ×2) のいずれも `skip-to-review` / `phase/ready` からの再開で spec / code の再実行は発生していない。
- **merge gate が pre-merge AC 未チェックで正しく停止した** (#1462)。CI は 15/15 緑だったが Issue 本文のチェックボックスが未更新だったため停止し、override も要求された。
- **AC 監査 → 修正 → 検証シグナル復活のループが機能した。** #1466 の AC2 は起票直後の `/triage` 監査で常時 PASS (Pattern 2) として検出され、修正後は「実装前 0 件マッチ → 実装後 1 件マッチ」となり安全網として復活した。
- **opportunistic AC が設計どおり自動解決した。** #1461 の AC (worktree route の `/spec` `/code` `/review` で emission が成功することを観察) は、#1466/#1470/#1468 の `/code` フェーズ Step 14 が PASS 判定し `phase/done` へ遷移させた。

## Findings

- **#1462 の gate 修正が、握り潰されていた既存の恒久的 CI 失敗を 2 層露出させた。** (1) `tests/resolve-preview-env.bats` の `file_mode` が GNU stat で誤値を返し Linux CI で 100% 失敗 (#1429 由来)、(2) `tests/check-bare-bracket-assertions.bats` の heredoc 内 fixture を bats 1.10 が実テストとして計上し並列ステップが常時 exit 1。後者がある限り `set -o pipefail` 追加だけで全 PR の bats ジョブが恒久的に赤になるため、両方の修正が AC4 達成の必要条件だった。 [Resolved directly: 両方を PR #1465 で修正し、Spec の Changed Files / Deviations に Scope 逸脱と根本原因を記録した]
- **`/review` の CI 失敗診断が、決定的な既存失敗を「環境依存フレーク」と誤判定した。** その誤診断が「Pre-existing failure exception の汎用化」提案の根拠になっており、実装されていれば本 PR は gate が赤のままマージされ Issue の目的と正反対の結果になっていた。また並列ステップの `Executed N instead of expected M` を分類入力に含めていない。 [Filed: #1466]
- **stale skill body 検出が行数不変の変更を取りこぼした。** #1461 の `emit-verify-event.sh` → `emit-skill-event.sh` リネームは行数を変えないため 996 = 996 で一致し、検出をすり抜けた。本セッションは #1461 マージ以降 4 回の verify で一貫して stale な本文を実行し、毎回 `exit 127` に気付いて読み替えて進行していた。 [Filed: #1468]
- **`/review` の Edge Case Pre-check が実行コンテキスト (CWD) の軸を持たない。** 入力内容の 5 軸のみをカバーし手順 3(3) が実行場所を repository root に固定しているため、CWD 依存バグは何度実行しても再現しない。#1463 で実際に取りこぼし、review-bug の diff 読解が発見した。 [Filed: #1470]
- **検出力ゼロ AC の監査が `/issue` 実行時点では原理的に判定できない。** Detection approach (b)(c) がフィクスチャの中身の検討を要求するが、`/issue` は実装前に走るためフィクスチャが存在せず (d)「判定が難しい場合は素通し」が常に適用される。本セッションの `/issue` 7 回・該当形 AC 3 件 (#1463) に対し指摘 0 件。 [Filed: #1474]
- **merge phase auto-retry の deferral 解除条件が「インシデント件数」のみで、回避可能性を区別していない。** #1462 で初の merge-phase silent no-op が発生し条件は形式上満たされたが、真因は pre-merge AC 未チェックによる gate の正常停止であり auto-retry では回避できなかった。件数だけを根拠にすると不可逆操作へのリトライ機構を誤った理由で実装するリスクがある。 [Filed: #1475]
- **定量的改善を問う observation AC にベースラインと最小サンプル数がなく、実装が機能していても PASS にできない。** #1350 は evidence source が実際に #1329 の PASS を生んだにもかかわらず、後半節「UNCERTAIN/SKIPPED 率が改善する」のベースライン不在で UNCERTAIN に留まった。 [Filed: #1480]
- **observation AC の event 種別が実際のトリガと一致しない場合がある。** #1351 は `event=auto-run` だが待っている事象は人手による `/loop` 起動であり、ユーザーが起動するまで `/auto` のたびに SKIPPED され続ける。#1480 にコメントとして追記し、observation AC が構造的に解決しない 3 つの型 (判定フェーズの不整合 / 測定基準の欠落 / event 種別の不一致) を整理した。 [Filed: #1480]
- **外部 kill が 5 回発生したが、いずれも claude 自身のメモリ消費とは対応していなかった。** 実測 (725 サンプル / 約 60 分) で claude 合計 RSS ピーク 2.65GB / 48GB、`review --full` の fan-out 増分 0.26GB、macOS 圧迫レベルは 94% のサンプルで正常。`Pages free` 52MB でも完走しており、設定も並行度も変えずに 3 回目で成功した。kill は確率的・一過性で、**再試行が最も有効な対処**と確認した。 [Resolved directly: #1146 にコメントとして計測結果と uptime 分布 (kill: 3.3〜4.1 日 / 完走: 6.2〜6.6 日) を記録し、Arm 4a の結論が成立しなくなること・expiry 条件が否定されることを明記した]
- **`detect-external-kill.sh` が連結ログで偽陰性を起こした。** `run-auto-sub.sh` のログに内側 `run-spec.sh` の `Exit code: 0` トレーラが残るため、#1461 の kill 2 件を `no-match` と判定した。Icebox #1093 が扱う事象そのものの実観測。 [No action: Icebox #1093 として既に凍結管理されており、本観測は #1146 のコメントで再評価トリガーとして記録済み]
- **`manual-recovery-respawn/harness-oom-stop` が threshold 3 に到達した。** `recoveries-auto-fire.enabled: false` のため自動起票はされず推奨出力に留まった。 [No action: `.wholework.yml` で opt-out 済み (#1179)。本セッションの 5 件はすべて同一原因 (ハーネスの OOM stop) で、#1146 に集約記録済み]

## Auto Retrospective

### Improvement Proposals

- **`/review` の CI 失敗診断が、決定的な既存失敗を「環境依存フレーク」と誤判定した。** その誤診断が「Pre-existing failure exception の汎用化」提案の根拠になっており、実装されていれば gate が赤のままマージされ Issue の目的と正反対の結果になっていた。また並列ステップの `Executed N instead of expected M` を分類入力に含めていない。
- **stale skill body 検出が行数不変の変更を取りこぼした。** 行数のみの比較では、リネームのように行数を変えない変更をすり抜ける。
- **`/review` の Edge Case Pre-check が実行コンテキスト (CWD) の軸を持たない。** 入力内容の 5 軸のみをカバーし実行場所が repository root 固定のため、CWD 依存バグを構造的に検出できない。
- **検出力ゼロ AC の監査が `/issue` 実行時点では原理的に判定できない。** フィクスチャ未存在のため Detection approach (b)(c) が評価不能で (d) の素通しが常に適用される。
- **merge phase auto-retry の deferral 解除条件が「インシデント件数」のみで、回避可能性を区別していない。**
- **定量的改善を問う observation AC にベースラインと最小サンプル数がなく、実装が機能していても PASS にできない。**
- **observation AC の event 種別が実際のトリガと一致しない場合がある。**

## Filed Issues

| Issue | Title | State |
|---|---|---|
| #1466 | review: CI 失敗診断が決定的な既存失敗をフレークと誤判定し件数不一致シグナルを見落とす | CLOSED (本セッション内でマージ) |
| #1468 | verify: stale skill body 検出が行数不変の変更を取りこぼす (内容ハッシュ併用) | CLOSED (本セッション内でマージ) |
| #1470 | review: Edge Case Pre-check が実行コンテキスト (CWD) の軸を持たず CWD 依存バグを検出できない | CLOSED (本セッション内でマージ) |
| #1474 | triage: 検出力ゼロ AC の監査が /issue 時点ではフィクスチャ未存在で判定不能 | OPEN |
| #1475 | orchestration: merge phase auto-retry の deferral 解除条件に回避可能性の判定を加える | OPEN |
| #1480 | verify: 定量的改善を問う observation AC にベースラインと最小サンプル数の明記を必須化する | OPEN |

## Skill Self-Update Propagation Note

セッション開始時に記録した 8 skill のハッシュを `origin/main` と比較した結果、**6 skill が本セッション中に変更された**。本セッション自身が自己改変したフレームワーク上で走っていたことになるため、Metrics の一部 (特に review フェーズの挙動) はセッション前半と後半で同一条件ではない。

| Skill | セッション開始時 | 現在 (origin/main) | 変更した Issue |
|---|---|---|---|
| `skills/auto/SKILL.md` | `2ec4a8f9` | `37b19a1c` | #1461, #1463 |
| `skills/code/SKILL.md` | `2ec4a8f9` | `c2a49cc2` | #1461 |
| `skills/spec/SKILL.md` | `dfdf5035` | `c2a49cc2` | #1461, #1464 |
| `skills/verify/SKILL.md` | `a9637dc4` | `f0ef6822` | #1461, #1463, #1468 |
| `skills/review/SKILL.md` | `b54923f9` | `5851148e` | #1461, #1466, #1470 |
| `skills/merge/SKILL.md` | `8eebe495` | `8eebe495` | (変更なし) |
| `skills/issue/SKILL.md` | `c85c44da` | `c2a49cc2` | #1461 |
| `skills/audit/SKILL.md` | `64df1bab` | `64df1bab` | (変更なし) |

伝播上の注意点:

- **`skills/verify/SKILL.md` の更新が本セッションには伝播しなかった** — `/verify` は wrapper を持たず会話セッション単位で本文がキャッシュされるため、#1461 のリネームを含む更新を最後まで読み込めず `exit 127` を手動で読み替え続けた (#1468 の起票根拠そのもの)。#1468 の内容ハッシュ併用はマージ済みだが、その効果を確認できるのは次の会話セッション以降。
- **`skills/review/SKILL.md` は Round 2 の途中で 2 回更新された** (#1466 → #1470)。`/review` は wrapper 経由で毎回新しいコンテキストに読み込まれるため、Round 2 後半の review は前半とは異なる本文で実行されている。
