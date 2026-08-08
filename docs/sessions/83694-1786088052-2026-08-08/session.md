# L3 Session Retrospective: 83694-1786088052

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-07T07:34:53Z
**Session end**: 2026-08-08T08:21:32Z
**Wall-clock**: 24:46:39
**Route mix**: patch: 0, pr: 5, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 48 (**inflated — actual 4**; see Findings) |
| Throughput | 1.9 issues/hr (**inflated by the same cause**) |
| Tier 1/2/3 recoveries | 0 / 0 / 1 |
| Recovery success rate (tier) | T3: 0 recovered / 1 failed |
| Watchdog kills | 1 |
| Max silent window (any phase) | 4070s |
| Phase silent windows > threshold | 4 (issue:1, spec:3) |
| Total token usage | input 13307 / output 903726 |
| Concurrent commits detected | 56 |
| Parent session manual interventions | 0 (**under-counted** — two real interventions were not recorded via `--write-manual-recovery`) |
| verify FAIL → reopen fix cycles | 0 |
| Retro proposal tiers (1/2/3) | 5 / 5 / 5 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-pr | 8 |
| issue | 9 |
| merge | 8 |
| review | 9 |
| spec | 8 |
| verify | 10 |

Sub-Issue Completion Timeline is omitted here: the generated table contained 48 rows, 43 of which are spurious (all fields `?`) for the reason recorded in Findings.

## What worked

- **`--batch` の直列処理が Issue 間の依存を正しく扱った**: #1239 と #1242 は同じ `scripts/opportunistic-search.sh` の match loop を書き換えるため、並行させれば確実に衝突した。List mode が各 Issue を merge まで完了させてから次へ進むため、#1242 の `/issue` フェーズは #1239 着地後のコードを見て行番号ドリフト (`:202`→`:291` 等) を自動修正できた
- **中断が 2 回発生したが、いずれも作業損失ゼロ**: 月次支出上限 (#1239 review フェーズ) と週次上限 (#1242 issue フェーズ) で `claude -p` が停止したが、両方とも `phase/*` ラベル未遷移の境界で止まったため再実行でやり直しが発生しなかった。#1239 では `run-auto-sub.sh` の resume preamble が `post-PR-create` milestone を観測して `skip-to-review` を選び、code フェーズを正しくスキップした
- **triage の非破壊監査 → 後続フェーズでの修正という連携が機能した**: `/triage` が常時 PASS を指摘した AC 群 (#1243/#1242/#1241/#1240/#1233/#1229) のうち、#1242 では `/issue` フェーズが 4 件すべてを適切な verify command 形式へ強化した
- **前 Issue の verify 結果が次 Issue の AC 品質に直結した**: `/verify 1239` で実測した「13→13 (削減ゼロ)」と原因分析を #1238 にコメント投稿したところ、`/issue 1238` がそれを第二ベースラインとして AC3 に組み込んだ

## Findings

- **`get-auto-session-report.sh` の Issue 列挙が `opportunistic_verify_result` イベントで汚染される**: 本セッションで実際に処理した Issue は 4 件 (#1236/#1239/#1238/#1242) だが、Metrics は「Issues processed: 48」と報告した。イベント中の distinct issue 番号は 48 件ある一方、`sub_start`/`phase_*` イベントに現れるのは 5 件 (#575 + 処理 4 件) のみで、差分 43 件はすべて #1236 が本セッション中に導入した `opportunistic_verify_result` イベント (候補 Issue 番号を `EMIT_ISSUE_NUMBER` に持つ) に由来する。Throughput (1.9 issues/hr) も同じ理由で約 12 倍に膨らみ、Sub-Issue Completion Timeline には全フィールドが `?` の行が 43 行生成された。L3 retrospective と `/audit auto-session` の双方が消費する測定 SSoT が壊れている [Filed: #1279]

- **run-fact AC match で `satisfied` 誤判定を 1 件出し、L0 書き込み後に自力で訂正した**: #917 AC #3 を `collect-run-facts.sh` の集約出力 (`recovery_tiers: [3]`, `manual_intervention: 0`) だけで判定し auto-check したが、生イベントは `phase=review` / `result=failed` であり、かつ親セッションは実際に手動再開を行っていた。3 点すべてが条件と食い違う。`modules/run-fact-matching.md` の fail-safe 基準に照らせば「手動 salvage が不要」は facts JSON で判定不能のため `ambiguous` が正しかった。チェックボックスを戻し訂正コメントを投稿済み (#917)。集約フィールドは生イベントの `phase`/`result` を潰すため、recovery 系 AC の判定には集約値だけを使ってはならない [Resolved directly: #917 の checkbox を uncheck し訂正コメントを投稿]

- **`manual_intervention` メトリクスが実態を反映しない**: 本セッションでは 2 回の実質的な手動介入 (支出上限後の `run-auto-sub.sh 1239` 再実行、週次上限後の `run-issue.sh 1242` 再実行) があったが、いずれも `--write-manual-recovery` を呼ばなかったため `manual_intervention=0` と記録された。上記の誤判定はこの値を「手動介入なし」の根拠に使ったことが一因。外部要因による停止からの単純な再実行を manual recovery として記録すべきかは設計判断の余地があるが、少なくとも現状のメトリクスは「親セッションが介入した回数」ではなく「`--write-manual-recovery` が呼ばれた回数」である [No action: 上記 Filed 項目と #1181 の記録方針の範囲で扱う。単独の起票は見送り]

- **#1239 は単独では効果ゼロで、#1238 との組み合わせで初めて機能した**: merge 直後の実測は 13→13。skill 名フィルタとトークン照合が同じ語彙空間を共有するため、該当 skill のフェーズを実行したセッションでは fact-token ゲートが定義上 1 件も除外できない構造だった。#1238 が bare phase 名を除去して解消 (13→0)。batch の実行順 (1239 が先、1238 が後) と post-merge AC の依存方向が逆だったが、observation AC は次回 `/auto` で自動再評価されるため実害はなかった [No action: #1239/#1238 の Issue コメントと Spec、および modules/run-fact-matching.md に SSoT として記録済み]

- **spec フェーズの silent window が閾値超過 3 回、最大 4070s**: `watchdog_kill` は #1238 の spec フェーズで 1 回発生 (silent_window 1800s = timeout 1800s)。`.wholework.yml` は `watchdog-timeout-code-seconds: 7200` を設定済みだが spec フェーズ向けの延長設定はない。今回は kill 後も spec が完走したため実害なし [No action: kill 1 回で完走しており、spec 向け timeout 延長の必要性を判断するにはデータ不足。再発時に判断]

## Auto Retrospective

### Improvement Proposals

- **`get-auto-session-report.sh` の Issue 列挙が `opportunistic_verify_result` イベントで汚染される**: 本セッションで実際に処理した Issue は 4 件 (#1236/#1239/#1238/#1242) だが、Metrics は「Issues processed: 48」と報告した。イベント中の distinct issue 番号は 48 件ある一方、`sub_start`/`phase_*` イベントに現れるのは 5 件 (#575 + 処理 4 件) のみで、差分 43 件はすべて #1236 が本セッション中に導入した `opportunistic_verify_result` イベント (候補 Issue 番号を `EMIT_ISSUE_NUMBER` に持つ) に由来する。Throughput (1.9 issues/hr) も同じ理由で約 12 倍に膨らみ、Sub-Issue Completion Timeline には全フィールドが `?` の行が 43 行生成された。L3 retrospective と `/audit auto-session` の双方が消費する測定 SSoT が壊れている

## Filed Issues

- #1279
