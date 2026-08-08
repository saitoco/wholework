# Issue #1270: verify: 再型付けした observation AC 57 行を「発火時に判定可能か」で実査し判定不能分を retire

XL route のため実装は 3 本の sub-issue が担当した。本ファイルは親側の Auto Retrospective を記録する。集約結果は `docs/reports/observation-ac-audit-summary.md` を参照。

## Auto Retrospective

### Execution Summary

| # | Title | Route | Result | Notes |
|---|-------|-------|--------|-------|
| #1274 | #1163 由来の observation AC 29 行を実査 | pr (Size L) | SUCCESS | PR #1297。`/review` 指摘で #761 / #822 を A → D へ再分類 |
| #1275 | #1164 由来の observation AC 12 行を実査 | pr (Size M) | SUCCESS | PR #1296。merge フェーズで wrapper-retry-on-kill が発動 (自動回復) |
| #1276 | #1165 由来の observation AC 16 行を実査 | pr (Size L) | SUCCESS | PR #1295。#1242 着地により母集団前提の訂正あり |

3 本とも exit 0、依存関係なし (1 レベル並列)、skip 発生なし。

分類結果 (57 行): A 29 / B 8 / C 0 / D 5 / E 15。

### Parallel Execution Issues

- **`concurrent_commit_detected` 26 件** — 3 本が同時に main を進めたことによる検出。全件がハンドリングされ、失敗・取りこぼしはなかった。内訳は code-pr 6 / review 17 / merge 3。#1274 の review フェーズで 12 件が同時刻に検出されており、他 2 本の着地が集中したタイミングと一致する
- **wrapper-retry-on-kill (#1275, merge フェーズ)** — `run-merge.sh` が early-kill window 内に exit 0 で終了し、`retry-on-kill.sh` が自動再試行して成功。`docs/reports/orchestration-recoveries.md` に記録済み (2026-08-08 22:08 UTC)。Improvement Candidate は「未起票」のまま
- **`worktree-merge-push.sh` の rebase fallback** — 親セッション側の Spec/レポート push で 1 回発動。並行して sub-issue が main を進めていたため。設計どおりの経路

### Improvement Proposals

- **`/auto` の XL route に親 Issue の実装フェーズが存在しない**。本 Issue の親 Pre-merge AC 1 (baseline 計測) は「3 sub-issue の着手**前**に完了させること」が Notes で必須とされていたが、XL route は `get-sub-issue-graph.sh` → sub-issue 並列実行 → Step 4c close flow という経路で、親自身の実装を走らせる段階を持たない。そのため `/auto 1270` をそのまま起動すると baseline 未計測のまま fan-out し、retire 開始時点で母集団が変化して baseline が再取得不能になる。本セッションでは親セッションが手作業で baseline を計測・commit してから fan-out した (`docs/reports/observation-ac-audit-summary.md`、commit `d563246e`)。集約レポートへの結果統合 (親 Pre-merge AC 3/4/5) も同様に手作業で行っている。**同じ欠落は `/auto 1158` (session `94570-1786069858`) でも診断済みであり、2 回目の観測**である。sub-issue 側にプロース (「baseline が無ければ待つ」) を書くだけでは防げない — fan-out 内の sub-issue は実質「待つ」ことができず、停止するか無視して進むかのいずれかになる。対処の方向は (a) 親の実装フェーズを XL route に追加する、(b) 親の前提作業を level 0 の sub-issue として依存グラフに載せる、のいずれか。
- **`/issue` triage が sub-issue 間で実行前提の注記を揃えない**。親 #1270 の「実行順序の制約」を本文へ反映したのは #1274 のみで、#1275 / #1276 には入らなかった (triage 実行は 3 本並列)。同じ親を持つ sub-issue 群に対して親由来の制約を反映する場合、反映されたか否かが sub-issue ごとに揺れる。本セッションでは親セッションが #1275 / #1276 へ手作業で追記した。単発観測のため再発を確認してから起票を判断する。

### 結果側の所見 (proposal ではない)

- **observation waiting の 20 行減少のうち、純減は 5 行 (25%) のみ**で、15 行 (75%) は `manual` への型間移動だった。#1158 は「manual には発火契機がない」という前提で 57 行を observation へ移したが、本実査で 15 行が `manual` へ戻された。移動の方向自体が逆だった行が一定数あったことになる
- **E のうち capability 待ちは 0 行**だった。3 本の sub-issue が独立に「`.wholework.yml` の capability 不足が理由の差し戻しは無い」と結論している。装備待ちのケースは observation ではなく `manual` バケツ側に存在すると見られ、#1278 の実測がその母集団を扱う

## Consumed Comments
No new comments since last phase.
