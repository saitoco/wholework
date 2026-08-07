# L3 Session Retrospective: 41961-1785999585

**Date**: 2026-08-06 〜 2026-08-07
**Route**: batch (List mode) — ただし `/auto --batch` ではなく wrapper 個別実行による**手動オーケストレーション**
**Issues processed**: #1186 (M, complete), #1163 (M, complete), #1058 (L, complete), #1078 (M, complete), #1119 (M, complete), #1082 (M, complete), #1075 (L, complete)
**Duration**: 約 17h42m (07:00:13Z → 00:41:52Z、うち約 5h は CI 障害による停滞)

> **注記**: 本セッションは `/auto --batch` を起動せず、`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` を個別に呼び、`/verify` は `Skill()` で直接起動する形で進めた。フェーズごとに結果を確認しながら判断する必要があったため。この形態の副作用は「Limits and gaps」に記載。

## What worked

### 申し送りコメントによる一次情報の伝播

#1058 の code フェーズが、この Issue のスコープ外である経路 (b) (`skills/code/SKILL.md` の Step 順序起因、#1078 の対象) を自分の実行で踏み、main repository の Spec を直接編集して手動 revert が必要になった。この一次情報を #1078 着手前に申し送りコメントとして投稿したところ、**#1078 の code フェーズは同じ位置で自主的に呼び出しを遅延させて回避した**。Comment Consumption が申し送りを読み込んだ結果と見られる。

先行 Issue の実行中に得た観測を、後続 Issue のコメントとして先に投入しておくと triage / code の判断が変わる、という因果が観測できた。#1119 でも同様に実測データ (残留 worktree 43 件、未コミット成果を含むケース) を先に投入し、triage が AC を 2 件追加した。追加された AC4 (未コミット変更の保護) は verify 時点で最も価値が高かった。

### watchdog kill 後の成果保全パターン

PR #1201 の `/review --full` が 2600s の watchdog で kill された (exit 143) が、worktree に**未コミットの修正が 11 ファイル分残っていた**。`modules/orchestration-fallbacks.md` の回復手順は「re-run `/review`」のみを示すため、手順どおりなら失われていた。

実際に取った手順:

1. worktree の `git status` / `git diff` で残留内容を確認
2. 関連 bats 3 ファイル (63 tests) を worktree 内で実行 → 0 failures
3. コミット・push し、残骸 worktree を削除
4. watchdog timeout を延長して `/review` を再実行

再実行の review が **MUST 1 件を含む 10 件を新たに検出**し、うち 1 件は手順 3 でコミットした内容自体の穴 (`reconcile-phase-state.sh` 空出力時に明示 `--pr` でも post-processor が誤発火する反転リスク) だった。時間節約だけでなく品質面でも機能した。

### 実データによる観測条件の検証

post-merge の observation / opportunistic 条件は「次回 X が起きたとき」を待つ設計だが、**リポジトリに残っていた過去の状態が検証材料になるケース**が 2 件あった。

- **#1082**: 残留していた `worktree-code+issue-485` (base に 8 コミット先行、push 未完) に対し merge 済みの completion check を実行し、`commits_found: false` / `worktree_commits_found: true` の分離を確認 → PASS
- **#1050**: CI 障害により `/review` が `PENDING: ... skipping review session` (exit 2) で終了し、fallback スタブでの complete 偽装が起きないことを確認 → PASS

一方 #1119 の「数セッション運用したのち」のように時間経過そのものを要求する条件は SKIPPED とした。条件文が**時間経過**を求めるか**観測可能な状態**を求めるかで扱いが分かれる。

### already-checked AC skip rule (#1186) の効果

同一セッション内で 5 回の `/verify` を実行し、pre-merge AC 計 19 件がすべて SKIPPED となった。旧ルールならすべて再実行され、rubric の再グレーディングコストを払って新規情報ゼロという結果になっていた。

## Limits and gaps

### skill 自己更新の非伝播が `/verify` 自身に発生

本セッション中に `skills/verify/SKILL.md` を #1186 で変更したが、**セッションにロードされている SKILL.md は変更前のスナップショット**のままだった (Step 5 に already-checked skip rule なし、Step 6 に旧文言 "Re-verify even if already checked" が残存)。リポジトリ上の実ファイル (L210) を SSoT として手動適用した。

`session=next` 属性 (#1168) が対象とする現象が、その属性を実装している `/verify` 自身にも同じ形で起きた。skill を変更する Issue を複数連続で処理する場合、変更後の skill が効くのは次セッション以降である点を運用上の前提にする必要がある。

### opportunistic verification の誤判定 (#129)

`/review 1218` の Opportunistic Verification が #129 の条件「残留 worktree が蓄積せず、再試行時に競合しない」を PASS と判定し `phase/done` へ遷移させたが、実測では 47 件が残留していた。親セッションが検出して uncheck・`phase/verify` へ差し戻し、訂正コメントを投稿。

原因は判定範囲のミスマッチ。`/review` セッションは自分の worktree を 1 つ作って 1 つ消しただけで、リポジトリ全体の残留数は数えていない。**単一セッションの後始末成功を、リポジトリ全体の状態の PASS と読み替えた**。誤 PASS は「検証されていない条件を検証済みとして閉じる」失敗モードを持つため、Pattern 6 (常時 UNCERTAIN) より実害が重い。→ #1223 として起票。

### 手動オーケストレーションでの session_id 誤帰属

`/auto` Step 1 の session 初期化を経なかったため、in-session `/verify` の event 5 件がすべて**並行セッションの ID** に誤帰属した (`63129-...` → `16353-...` → `89790-...` と時系列で 3 回変化)。`restore_auto_session_pointer` が最終段の `.tmp/auto-session-current` にフォールバックし、他セッションが上書きした値を拾っていた。

誤帰属の境界は明確に分かれた:

- **wrapper 経由の event は生存** — wrapper 呼び出しの直前に同じ Bash 呼び出し内で PGID ポインタを書いていたため、同一 PGID で解決できた
- **親セッションの in-session emit は欠損** — 別の Bash 呼び出し = 別 PGID のため解決できず `current` へフォールバック

→ #1224 として起票。

### CI プラットフォーム障害への対処手順がない

2026-08-06 18:21Z 以降、GitHub Actions が新規 workflow run を一切生成しない状態が約 5 時間続いた。`macOS shell compatibility` job が 1h17m / 1h31m でタイムアウト fail、`gh run cancel` は HTTP 502、rerun / PR close-reopen / 空コミット push のいずれも新規 run をトリガーできなかった。workflow 定義は 3 件とも `active`、API の読み取りと push は正常に通っていた。

`run-review.sh` は CI が confirmed state に達しないと exit 2 で review セッションをスキップする設計 (#1050 の意図どおり) のため、この間フェーズを進められなかった。復旧後は bats 3m5s / macOS 5s と通常の実行時間に戻り、再実行で完走。

`modules/orchestration-fallbacks.md` は「CI プラットフォーム側の障害で confirmed state に到達しない」ケースを扱っていない。ただし新規パターン追加は #1122 の補償層モラトリアム対象のため、起票は見送った。

### external kill の再発

`run-issue.sh 1119` の初回実行が出力 9 行 (開始バナーのみ)・終端バナーなしで終了し、triage が実質実行されていなかった。exit code は 0 と報告された。

`run_with_retry_on_kill` の Branch A は exit 137/143 以外を即 return するため、「exit 0 だが出力ゼロ」は retry 対象にならない。wrapper が `print_end_banner` にも `reconcile-phase-state --check-completion` にも到達しておらず、wrapper 自身の安全網も働かなかった。親セッション側では**終端バナーの不在**が決定的な検出シグナルだった (exit code は信用できない)。→ #1146 に観測データとして追記。

### 未解明: `collect-recovery-candidates.sh` の結果不整合

同一コマンドで前回 2 件 (`manual-recovery-respawn 21` / `code-pr-tier3-recovery 6`) → 今回 0 件を返した。`--issues-json` を外しても 0 件で、dedup は候補を減らすだけなので論理的に説明がつかない。`docs/reports/orchestration-recoveries.md` は両実行の間で変化していない (最終変更 17:26 JST)。#1152 がこのスクリプトの除外判定を同日変更しているが、関連は未確認。**未起票**。

## Improvement candidates

| 候補 | 扱い |
|---|---|
| AC verify command 監査に「常時 PASS」パターンを追加 | #1209 として起票 |
| opportunistic-verify のセッション単独観測範囲外の PASS 誤判定 | #1223 として起票 |
| `/auto` を経ない実行での session_id 誤帰属 | #1224 として起票 |
| `WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2600` の再校正 | #939 に実測データを追記 (Tier 2) |
| worktree に未コミット成果が残るケースの回復手順 | #1122 に追記 (モラトリアム対象、Tier 2) |
| `gh-pr-review.sh` の severity 欠落によるサイレント `COMMENT` 降格 | #1102 に追記 (Tier 2) |
| skill 自己変更 Issue の post-merge AC の verify-type 選択基準 | #1072 に追記 (Tier 2) |
| `collect-recovery-candidates.sh` の結果不整合 | **未起票** — 再現条件が特定できていない |

## Metrics

`get-auto-session-report.sh 41961-1785999585 --metrics-only` の出力より抜粋。**session_id 誤帰属により不完全**である点に注意。

| Metric | Value | 実態との一致 |
|---|---|---|
| Session start / end | 2026-08-06T07:00:13Z → 2026-08-07T00:41:52Z | 一致 |
| Wall-clock | 17:41:39 | 一致 |
| Watchdog kills | 1 | 一致 (PR #1201 review) |
| Max silent window (any phase) | 4110s | 一致 |
| Phase silent windows > threshold | 4 (review:3, spec:1) | 一致 |
| Parent session manual interventions | 2 | 一致 |
| Route mix | patch: 0, pr: 0, xl: 0 | **不一致** (実際は pr route 7 件) |
| Issues processed | 10 | **不一致** (バッチ対象 7 件 + opportunistic 対象 4 件) |
| Retro proposal tiers (1/2/3) | 1 / 0 / 0 | **不一致** (Tier 1 は 3 件) |
| Concurrent Sessions Detected | (none detected) | **不一致** (並行セッションが `current` を 3 回上書き) |

wrapper が emit する metric (watchdog / silent window / manual intervention) は正しく、親セッションが直接 emit する metric (route mix / retro proposal tier) が欠落するという分布になっている。

## Housekeeping

セッション終了時に `scripts/reclaim-stale-worktrees.sh --apply` を初回実行 (#1119 で追加したもの)。

| 分類 | 件数 | 扱い |
|---|---|---|
| 回収 (worktree + branch) | 33 | 削除 |
| 未コミット変更あり | 6 | 保護 (`review+pr-1160` の 8 ファイル等) |
| branch tip が merged PR head と不一致 | 30 | ブランチのみ残置 |
| 命名規約外 | 9 | 保留 |

worktree 総数は 47 → 11 に減少。保護された 6 件は #1201 と同型の「回収すべき成果」を含む可能性があり、個別判断が必要 (#1122 に記録)。

## Filed Issues

- **#1209** — triage: AC verify command 監査に「常時 PASS」パターンを追加
- **#1220** — (review 経由で自動起票) `keyword=workflow` ゲートがファイル名の部分一致で誤発火する
- **#1223** — opportunistic-verify: セッション単独で観測できない条件の PASS 誤判定を防ぐ
- **#1224** — event-emission: `/auto` を経ない実行での session_id 誤帰属を防ぐ

## Corrections

- **#129** — Opportunistic Verification による誤 PASS 判定を取り消し。checkbox を uncheck し `phase/done` → `phase/verify` へ差し戻し、実測データ付きの訂正コメントを投稿 (issuecomment-5210156886)
