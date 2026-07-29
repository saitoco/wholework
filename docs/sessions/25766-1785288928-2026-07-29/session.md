# L3 Session Retrospective: 25766-1785288928

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-07-29T01:36:04Z
**Session end**: 2026-07-29T07:26:18Z
**Wall-clock**: 05:50:14
**Route mix**: patch: 0, pr: 7, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 3 |
| Fully closed (phase/done) | 0 (3 件とも phase/verify で manual AC 待ち) |
| phase/verify remaining | 3 |
| Throughput | 0.5 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 (実際は Tier 3 が 2 回発火。Findings 参照) |
| Watchdog kills | 6 |
| Max silent window (any phase) | 2680s |
| Phase silent windows > threshold | 0 |
| Total token usage | input 714 / output 147443 |
| Concurrent commits detected | 17 |
| Parent session manual interventions | 0 (実際は 3 回。Findings 参照) |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 1 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-pr | 5 |
| issue | 6 |
| merge | 6 |
| review | 9 |
| spec | 6 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
| #1059 | M/pr | 2026-07-29T01:36:04Z – 2026-07-29T03:15:30Z | code-pr 44m → issue 7m → merge 3m → review 16m → spec 25m | #1068 | 外部 kill ×1 (spec 後) | Silent 2680s;10 concurrent commits |
| #1060 | L/pr | 2026-07-29T03:26:24Z – 2026-07-29T05:01:20Z | code-pr 16m → issue 8m → merge 3m → review 52m → spec 14m | #1079 | 外部 kill ×1 (review Tier 3 retry 中) | Silent 1490s;6 concurrent commits |
| #1061 | L/pr | 2026-07-29T05:10:32Z – 2026-07-29T07:26:18Z | issue 7m → merge 2m → review 67m → spec 16m | #1090 | 外部 kill ×3 (code 直前 / review ×2) | Silent 1170s;1 concurrent commits |

### Concurrent Sessions Detected

17 件の並行 commit を検出 (#1051, #1056, #1062, #1066, #1069, #1074)。並行セッションが同一 main を進めたため、`/verify 1059` の worktree FF merge が失敗し手動 rebase が必要になった (Findings 参照)。

## What worked

- **外部 kill からの respawn 復旧**: 5 回の外部 kill すべてから復旧し、3 Issue とも merge まで到達した。`phase/*` ラベル (SSoT) と `code_phase_milestone` チェックポイントの組み合わせにより、respawn 時に `skip-to-review` / `push-and-pr` へ正しく分岐できた。特に #1060 の 2 回目 respawn は `[resume] observed milestone: post-PR-create` → `[resume] action: skip-to-review` で code フェーズを正しくスキップしている。
- **`post-fallback-review-summary.sh` の fallback**: #1061 の review が silent no-op で終了した際、先行 review (AC 検証結果 10 件 + Code Review) の存在を正しく検出して Response Summary のみを補完した。review の実体は失われず、`reconcile-phase-state.sh` の completion check も `matches_expected: true` に回復した。fail-open ではなく正しい部分復旧として機能している。
- **`/review` の finder 品質**: #1060 で pipefail による fail-open と `>` を含む HTML コメント除去失敗の 2 件、#1061 で常時 PASS の bats assert を検出した。いずれも AC 検証では原理的に捕捉できない欠陥であり、review の付加価値が明確に出た。
- **AC verify command 監査 (PASS 側)**: `/issue` が #1059 の `grep` 常時 PASS と #1061 の `grep "always-pr"` 常時 PASS をいずれも検出し `rubric` / より固有のパターンへ差し替えた。
- **並行セッションとの起票重複回避**: 本セッションの findings のうち 3 件 (session_id 誤帰属、worktree-merge-push の rebase fallback、detect-external-kill の phase スコープ) は、並行セッションが #1075 / #1076 / #1093 として先に起票していた。dedup チェックが機能し重複起票を回避できた。

## Findings

- **1 セッションで外部 kill が 5 回発生し、wall-clock 5h50m / throughput 0.5 issues/hr まで低下した**。内訳: #1059 spec 直後 ×1、#1060 review (Tier 3 retry 中) ×1、#1061 code commit 直前 ×1・review ×2。いずれも wrapper が自身の EXIT trap を通らずプロセスグループごと停止しており、`docs/reports/orchestration-recoveries.md` の既知パターンと一致する。復旧そのものは全件成功したが、5 回の respawn が所要時間の大半を占めた。[No action: 根本原因は未特定のまま (通算 30 回目)。個別の復旧経路は #1070 / #1081 / #1093 でカバー済みで、構造的対策としては #483 (forked-session orchestration の単一セッション実行への移行) が起票済み]
- **`/review` が bats をバックグラウンド実行して通知待ちのままターンを終える silent no-op を起こす**。#1061 の 3 回目 review で「bats のバックグラウンド実行完了を待ちます (通知が届き次第、続行します)。」を最後に出力してセッションが終了し、`run-review.sh` が「claude exited 0 but review phase did not complete (silent no-op)」を検出した。headless (`claude -p`) 実行では完了通知が届かないため、この待機は必ず無期限になる。fallback で復旧はしたが、Response Summary が自動生成の定型文に置き換わり review の締めくくり情報が失われる。[Filed: #1097]
- **Tier 3 recovery が 2 回発火したのに Metrics の「Tier 1/2/3 recoveries」が 0/0/0 のまま**。#1060 と #1061 の review フェーズで `[spawn-recovery] action=retry: re-invoking run-review.sh` がログに出ているが、`events.jsonl` に `recovery` event が 1 件も記録されていない (event 種別一覧に `recovery` が存在しない)。両方とも retry 自体が外部 kill されたため、成功時のみ emit する実装になっている可能性がある。いずれにせよ「発火した recovery の回数」が観測できず、`recoveries-auto-fire` の threshold 判定にも影響する。[Filed: #1098]
- **`observation-trigger.sh` が副作用 (advisory コメント投稿) を持つのに冪等でない**。親セッションが出力形式を確認するため同スクリプトを 3 回実行し、11 件の Issue に同一の advisory コメントが 3 通ずつ投稿された。呼び出し側の運用ミスではあるが、同一 event・同一 Issue に対する直近のコメントが既に存在する場合は再投稿しない dedup ガードがあれば、この種のノイズは構造的に防げる。[Filed: #1099]
- **`run-code.sh` が route を問わず既存 worktree を無条件 force remove するため、pr route の外部 kill respawn で未コミットの完成済み実装が失われる**。#1061 では実装 9 ファイル (Spec の Changed Files と完全一致、全 1266 テスト PASS) が未コミットのまま残っており、そのまま respawn すれば全損する状態だった。`modules/worktree-lifecycle.md` の Entry セクションには「reuse vs. discard」の判断手順があるが、`run-code.sh` は wrapper 層でその手前に削除してしまう。[Resolved directly: #1081 (patch route + 未 push コミット) に、route 非依存かつ未コミットケースも同じ経路であることをスコープ拡張コメントとして投稿した]
- **Metrics の「Parent session manual interventions」が実際の 3 回に対して 0 と表示される**。本セッションでは `--write-manual-recovery` を 3 回呼び出し (#1059 spec/respawn、#1060 review/respawn、#1061 code-pr/push-only + review/review-rerun の計 4 回) いずれも `orchestration-recoveries.md` への追記は成功しているが、`manual_intervention` event が集計に反映されていない。[No action: #1049 (`run-auto-sub.sh --write-manual-recovery の manual_intervention event under-counting 調査`) で起票済み]
- **並行セッションが main を進めた結果、`/verify 1059` の worktree FF merge が失敗し手動 rebase が必要になった**。`worktree-merge-push.sh` は「main が current branch として checkout されている」経路で in-place `git merge --ff-only` に落ちるが、diverge している場合はそこで abort し、`modules/orchestration-fallbacks.md#ff-only-merge-fallback` の step 3-5 (worktree 内 rebase) へ進まない。[No action: #1076 (`worktree-merge-push: base が current branch の経路にも rebase fallback を追加`) として並行セッションが起票済み]
- **in-session `Skill()` から emit した event が並行セッションの session_id に誤帰属した**。`restore_auto_session_pointer()` が読む `.tmp/auto-session-current` は PGID 非依存のため、並行 `/auto` セッションに上書きされる。本セッションの `/verify` 3 回分の event は別セッション ID で記録されている可能性が高い。[No action: #1075 (`auto/verify: in-session /verify の event が並行セッションの session_id に誤帰属するのを防ぐ`) として並行セッションが起票済み]
- **`detect-external-kill.sh` が multi-phase wrapper のログで誤判定する**。#1060 の review 外部 kill に対して `no-match` を返した。判定に使う「`Exit code:` トレーラ不在」が内側の `run-spec.sh` バナーにマッチし、「`wrapper_exit` event 不在」が Tier 3 retry 前の 1 回目 review の記録にマッチしたため。[No action: #1093 (`auto: detect-external-kill.sh の判定を連結ログでも phase 単位にスコープする`) として並行セッションが起票済み]

## Auto Retrospective

### Improvement Proposals

- **`/review` が bats をバックグラウンド実行して通知待ちのままターンを終える silent no-op を起こす**。#1061 の 3 回目 review で「bats のバックグラウンド実行完了を待ちます (通知が届き次第、続行します)。」を最後に出力してセッションが終了し、`run-review.sh` が「claude exited 0 but review phase did not complete (silent no-op)」を検出した。headless (`claude -p`) 実行では完了通知が届かないため、この待機は必ず無期限になる。fallback で復旧はしたが、Response Summary が自動生成の定型文に置き換わり review の締めくくり情報が失われる。
- **Tier 3 recovery が 2 回発火したのに Metrics の「Tier 1/2/3 recoveries」が 0/0/0 のまま**。#1060 と #1061 の review フェーズで `[spawn-recovery] action=retry: re-invoking run-review.sh` がログに出ているが、`events.jsonl` に `recovery` event が 1 件も記録されていない (event 種別一覧に `recovery` が存在しない)。両方とも retry 自体が外部 kill されたため、成功時のみ emit する実装になっている可能性がある。いずれにせよ「発火した recovery の回数」が観測できず、`recoveries-auto-fire` の threshold 判定にも影響する。
- **`observation-trigger.sh` が副作用 (advisory コメント投稿) を持つのに冪等でない**。親セッションが出力形式を確認するため同スクリプトを 3 回実行し、11 件の Issue に同一の advisory コメントが 3 通ずつ投稿された。呼び出し側の運用ミスではあるが、同一 event・同一 Issue に対する直近のコメントが既に存在する場合は再投稿しない dedup ガードがあれば、この種のノイズは構造的に防げる。

## Filed Issues

- #1097
- #1098
- #1099

## Skill Self-Update Propagation Note

Session 中に以下の skill が更新されました (本 session には未適用、次 session から反映):

- skills/auto/SKILL.md: (no change)
- skills/code/SKILL.md: b4769535297664397f2b6ac3354bca8e6049dfbf → 7d5a855d
- skills/spec/SKILL.md: 8183695567bdfe700ce1f0e72ca6e87596a7e913 → 7d5a855d
- skills/verify/SKILL.md: b64648a3204e38697d328fae6b89466d44af9d7a → 1558c82e
- skills/review/SKILL.md: 420c5f786c5277d32aa7b07ef173ab7029f05c41 → 0af6361a
- skills/merge/SKILL.md: f760c77df7196d71117e3571337aef3b189e54a2 → 0af6361a
- skills/issue/SKILL.md: 0e932af963870c8e2337b73feb159f18b0306e9d → 7d5a855d
- skills/audit/SKILL.md: (no change)

`skills/verify/SKILL.md` (#1059) と `skills/review/SKILL.md` / `skills/merge/SKILL.md` (#1059, #1060) は本 session 自身が処理した Issue によって更新されている。本 session の後続フェーズは更新前の版で動作しているため、manual preview AC の扱い (#1059) と pre-merge AC ゲート (#1060) は本 session 内では適用されていない。
