# L3 Session Retrospective: 33233-1786023637

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-06T13:41:35Z
**Session end**: 2026-08-07T04:14:56Z
**Wall-clock**: 14:33:21
**Route mix**: patch: 2, pr: 2, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 5 |
| Fully closed (phase/done) | 1 (#1210) |
| phase/verify remaining | 3 (#1209 / #1212 / #1213 — observation AC 待ち) |
| Throughput | 0.3 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 2 |
| Recovery success rate (tier) | T1: 0 recovered / 0 failed, T2: 0 recovered / 0 failed, T3: 0 recovered / 2 failed |
| Watchdog kills | 1 |
| Max silent window (any phase) | 3030s |
| Phase silent windows > threshold | 5 (review:2, spec:3) |
| Total token usage | input 13346 / output 251217 |
| Concurrent commits detected | 33 |
| Parent session manual interventions | 2 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Retro proposal tiers (1/2/3) | 2 / 1 / 5 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 4 |
| code-pr | 4 |
| merge | 6 |
| review | 4 |
| spec | 8 |
| verify | 11 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
| #1200 | ?/? | 2026-08-06T14:03:59Z – 2026-08-06T14:07:45Z | verify 3m | — | T1:0/T2:0/T3:0 | 前セッションからの繰り越し verify |
| #1209 | S/patch | 2026-08-06T14:55:38Z – 2026-08-06T15:50:48Z | code-patch 29m → spec 20m → verify 4m | — | T1:0/T2:0/T3:0 | Silent 1240s phase=spec;3 concurrent commits |
| #1210 | S/patch | 2026-08-06T13:41:37Z – 2026-08-07T04:14:56Z | code-patch 42m → spec 19m → verify 3m ×2 | — | T1:0/T2:0/T3:0 | Silent 2550s;1 concurrent commits;verify 2 回 (observation AC 充足) |
| #1212 | M/pr | 2026-08-06T23:46:09Z – 2026-08-07T02:01:24Z | code-pr 28m → merge 23m → review 51m → spec 27m → verify 3m | #1222 | T1:0/T2:0/T3:1 | Size M→L;Silent 3030s phase=review;17 concurrent commits;手動 recovery |
| #1213 | M/pr | 2026-08-07T02:02:04Z – 2026-08-07T04:04:52Z | code-pr 29m → merge 23m → review 36m → spec 30m → verify 2m | #1225 | T1:0/T2:0/T3:1 | Size M→L;Silent 2050s phase=review;12 concurrent commits;手動 recovery;spec watchdog kill |

### Token Usage Aggregate

| Issue | Input tokens | Output tokens | Total |
|---|---|---|---|
| #1209 | 174 | 32219 | 32393 |
| #1210 | 194 | 36882 | 37076 |
| #1212 | 12694 | 127142 | 139836 |
| #1213 | 284 | 54974 | 55258 |

### Recovery Events

- [2026-08-07T01:36:49Z] Issue #1212 phase=merge tier=3 result=failed
- [2026-08-07T03:39:54Z] Issue #1213 phase=merge tier=3 result=failed

両方とも Tier 3 sub-agent が `action=abort` を返した。これは**失敗ではなく正しい判断** — `run-merge.sh` が意図的に merge をブロックした状況であり、機械的リトライではなく人間/オーケストレータの判断が必要と正しく識別している。Metrics 上は `result=failed` として記録されるが、実態は「Tier 3 が対象外と判定して安全に停止した」ケース。

### Skill Self-Update Propagation

本セッション中に 8 skill 中 **7 skill** が変更された (本セッションの #1210/#1212/#1213 + 並行セッションの Issue 群による):

| Skill | Session start | Session end |
|---|---|---|
| auto | `d65f6f83` | `12339eec` |
| code | `ff5f9605` | `38663cb3` |
| spec | `ff5f9605` | `ac2af751` |
| verify | `7c6c0437` | `9a8b3c55` |
| review | `9dc07088` | `38663cb3` |
| issue | `8e317b92` | `9a8b3c55` |
| audit | `0028ad27` | `12339eec` |

merge のみ不変。self-hosting プロジェクトとして skill 群が高頻度で自己更新されており、`session=next` 修飾子付き observation AC の前提 (skill self-update の伝播) がバッチ内で成立しうる環境になっている (実際 #1210 の AC がそれで充足した)。

## What worked

- **merge gate (`review_incomplete_fallback`) が 2 回とも work loss を防いだ**。#1212 / #1213 の両方で `/review` が Step 12.2 (コミット・push) 到達前に silent no-op で終了し、review worktree に MUST/SHOULD 修正が未コミットで残っていた。gate がなければ修正を欠いた PR がマージされていた。#1212 の MUST は実質的なバグ修正 (`skills/code/SKILL.md` Step 10 の CI AC 除外が checkbox-flip ループから除外しておらず未検証条件が `[x]` になる漏れ)、#1213 の SHOULD は根本原因の一段深い層 (`modules/test-runner.md` の 120s 固定 timeout) の特定だった
- **Tier 3 recovery sub-agent が 2 回とも正しく abort した**。「これは説明不能な異常ではなく、`run-merge.sh` が意図的にブロックした状況であり人間の判断が必要」と rationale を明示。機械的リトライで解けない事象を正しく識別している
- **#1185 が導入した triage AC 監査 → `/spec` 自動解決の予防系連鎖が 3 回機能**。#1209 (起票時の前提の誤りを検出しスコープを Pattern 7 新設 → Pattern 2 拡張へ修正)、#1212 (AC4 が pr route なのに patch route 形式を使っており、本 Issue の是正対象である欠陥 A を体現していたのを修正)、いずれも監査コメントを `/spec` が first-class input として consume して判断している
- **`post-fallback-review-summary.sh` + `reconcile-phase-state.sh` + merge gate の 3 段構成が機能**。fallback がサマリを代替投稿して完了シグナルを復旧しつつ `review_incomplete_fallback=true` マーカーを残し、gate がそれを検出してブロックする。「見かけ上の完了」と「実際の完了」を区別できている
- **`worktree-merge-push.sh` の rebase fallback が自動発火して成功**。#1210 iteration 2 の retrospective push で base が前進していたが、ancestry チェック → worktree rebase → FF merge が自動で通った

## Findings

- **同一失敗モード (再呼び出し保証のない実行サーフェスでの background task 完了通知待ち) が review フェーズで 2 連続再発した**。#1212 (「フルテストスイートをバックグラウンドで実行中です。完了通知を待ってコミット・push (Step 12.2) に進みます」) と #1213 (「バックグラウンドタスクの完了通知を待ちます。」)。`run-review.sh` は `claude -p --non-interactive` を使うため通知は永久に届かない。#994 が追加したガードは `skills/code/SKILL.md` 限定で `skills/review/SKILL.md` には存在しなかった [Resolved directly: #1213 が着地し code/review 両方の分岐非依存な位置にガードを配置。実測 2 件を #1213 にコメント記録し、`docs/reports/orchestration-recoveries.md` に `cause=background-notification-wait` で 2 件記録]
- **前景実行のガードだけでは物理的に守れない指示だった**。`modules/test-runner.md` Step 2 が `timeout: 120 seconds` を固定値で指示しており、フルスイート (実測 ~407s) は前景で回しても 120 秒で打ち切られる。この制約がエージェントを `run_in_background: true` へ逃がす圧力になっていた。#1213 の review フェーズがこれを特定し、caller-supplied timeout + 明示 `timeout: 600000` 要件として修正した [Resolved directly: #1213 の PR #1225 に含めて着地 (`modules/test-runner.md` / `skills/review/SKILL.md` / bats 4 件)]
- **`post-fallback-review-summary.sh` は完了シグナルは復旧するが作業は復旧しない**。review worktree に未コミット変更が残っていても検出せず、「Review Response Summary を代替投稿した」とだけ報告する。gate のメッセージも「MUST 指摘が未解消の**可能性**」という推測形に留まる。fallback 投稿前に `git status --porcelain` を確認すれば 4 ファイルの未コミット変更を事実として提示できた [Resolved directly: #1213 に方針 3 として提案コメントを投稿]
- **pr route の Step 10 と `github_check "gh pr checks"` AC の関係が SKILL.md に未明文化**。Step 10 (Verify Command Consistency) は PR 作成 (Step 11) より前に実行されるため、pr route では PR が存在せず AC が判定不能 (UNCERTAIN) になる。#1212 が patch route 側 (`branch-scoped CI AC exclusion`) を明文化した対称ケースだが、pr route 側は未対応。#1213 の code フェーズは AC4 のチェックボックスを未チェックのまま残して `/review` に委ねる運用で回避した [Filed: #1229]
- **observation AC は「証拠の成立」と「event の発火」が独立しており、バッチ内で条件が揃っても自動では拾われない**。#1210 の AC 8 は #1209 の code フェーズ (同一バッチ内の次の Issue) で事実として充足したが、`observation-trigger.sh --event auto-run` が未発火のため iteration 1 では SKIPPED。さらに `/auto` List mode は `BATCH_LIST` に含まれる Issue を dispatch 対象から除外するため、バッチ完了時の observation scan 後も自動再 verify されない。今回は親セッションが明示的に `/verify 1210` を再実行して `phase/done` まで到達させた [No action: 隣接する #1118 (observation AC の実行文脈条件宣言) のスコープと重なるため、Spec の Verify Retrospective に記録するに留める]
- **AC の形式的欠陥が同一 Issue の再 verify で結果を変えた**。#1210 の AC 7 (`--commit=$(git rev-parse HEAD)`) は iteration 1 では worktree HEAD がたまたま push 済みコミットに一致して PASS したが、iteration 2 では `append-consumed-comments-section.sh` が worktree にコミットを作ったため HEAD が変わり、run が存在せず評価不能になった。代替検証 (現行 main の完了済み run 3 件すべて success) で PASS と判定した [No action: #1212 が本セッションで着地し推奨形が `--branch=main --limit=1` へ是正済み。以後の Issue では発生しない]
- **`.tmp/auto-session-current` が並行セッションに上書きされ、in-session `Skill()` 経由の `/verify` イベントが誤った session_id で記録された**。PGID pointer は Bash tool 呼び出しごとに PGID が変わるためヒットせず、`auto-session-current` へのフォールバックが常用される。以降の emit では PGID pointer を明示的に書いて補正した [No action: 既存 #1075 に本日 (2026-08-06) 双方向誤帰属の実測と原因分析を記録済み。今回は同一パターンの再現であり追記不要]
- **`/spec` の watchdog kill (1800s) が実害なく着地した**。#1213 の spec フェーズが 1800 秒無出力で kill されたが、`## Design Complete` コメント投稿・Spec 作成・push・Size 再評価 (M → L) はすべて kill 前に完了していた。作業完了後にターンを終える直前で kill された形 [No action: 実害なし。silent window の長さ自体は Metrics に記録済み (spec 3 件が閾値超過)]
- **Metrics の `Tier 1/2/3 recoveries` が Tier 3 の abort を `failed` として計上する**。実態は「Tier 3 が対象外と正しく判定して安全に停止した」ケースであり、復旧失敗ではない。Recovery success rate の指標として誤読を招きうる [No action: Metrics セクション冒頭の Known structural gaps (#875) が同種の限界を既に明示しており、本セッションの Recovery Events 節に実態を注記した]

## Auto Retrospective

### Improvement Proposals

- **pr route の Step 10 と `github_check "gh pr checks"` AC の関係が SKILL.md に未明文化**。Step 10 (Verify Command Consistency) は PR 作成 (Step 11) より前に実行されるため、pr route では PR が存在せず AC が判定不能 (UNCERTAIN) になる。#1212 が patch route 側 (`branch-scoped CI AC exclusion`) を明文化した対称ケースだが、pr route 側は未対応。#1213 の code フェーズは AC4 のチェックボックスを未チェックのまま残して `/review` に委ねる運用で回避した

## Filed Issues

- #1229 — code: Step 10 の CI 検証 AC 除外を pr route にも明文化する
