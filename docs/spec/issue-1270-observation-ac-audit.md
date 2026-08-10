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

- saito / MEMBER / first-class / 前回 `/verify 1270` の Acceptance Test Results (Pre-merge AC1 UNCERTAIN、Post-merge 3件 SKIPPED=未発火) / https://github.com/saitoco/wholework/issues/1270#issuecomment-5228569610
- saito / MEMBER / first-class / observation event `auto-run` 発火 (1回目、2026-08-09T01:55:37Z) — `/verify 1270` 実行依頼 / https://github.com/saitoco/wholework/issues/1270#issuecomment-5229262441
- saito / MEMBER / first-class / Pre-merge AC 1 の UNCERTAIN 解消 (baseline 単位を「率」から「候補母集団の実数」へ変更、AC1/Post-merge AC8 双方を修正) / https://github.com/saitoco/wholework/issues/1270#issuecomment-5229448151
- saito / MEMBER / first-class / observation event `auto-run` 発火 (2回目、2026-08-10T03:02:58Z) — `/verify 1270` 実行依頼 / https://github.com/saitoco/wholework/issues/1270#issuecomment-5235407991

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- 親の Notes「実行順序の制約」は明快で、baseline を fan-out 前に取る必要性が正しく記述されていた。にもかかわらず `/auto` の XL route がその順序を実行できないため、親セッションの手作業に依存した。**AC の記述品質ではなく実行経路側の欠落**である。
- Pre-merge AC 1 の分母・分子の定義が内部矛盾していた (下記 verify 節)。`/issue` triage の AC 監査は「常時 PASS」パターンを検出するが、この種の「定義が構造的に充足不能」なパターンは検出対象外である。

#### spec

- 親 Spec は存在しなかった (XL route は親の spec フェーズを持たない)。本ファイルは Step 4a で新規作成したもの。

#### code

- 親の実装 (baseline 計測・集約レポート統合) は `/code` を経ず親セッションが直接実施した。XL route に親の実装フェーズが無いため。

#### review

- 親側の成果物は `/review` を経ていない。sub-issue 側では 3 本とも `/review` が実質的な検出をしており、特に #1274 で分類 A → D の再分類 2 件を引き出している。

#### merge

- 親には PR が無い。sub-issue 3 本が並列で main を進めたため `concurrent_commit_detected` が 26 件検出されたが、全件ハンドリング済み。

#### verify

- Pre-merge 4 件が PASS、1 件が UNCERTAIN。Post-merge 3 件は `auto-run` 未発火のため SKIPPED。
- **UNCERTAIN の内容**: AC 1 は分母を「1 回の dispatch で候補に挙がった observation AC 行数」(= 85)、分子を「そのうち SKIPPED を返した行数」と定義するが、`observation-dispatch-threshold` (既定 5) により 1 回の実行で SKIPPED/PASS が確定するのは最大 5 行であり、**分母 85 に対する分子は構造上 5 が上限**になる。率として意味をなさないため分子を記録していない。FAIL ではなく UNCERTAIN としたのは、実装側に修正すべきものが無く、FAIL 判定に伴う reopen と `phase/*` ラベル削除が状態を失うだけで問題を解決しないため。同じ「率」を使う Post-merge 8 も同じ不整合を抱えているので、AC 1 だけの修正では片手落ちになる。

### Improvement Proposals

- **監査・実査レポートに書く具体的な参照 (関数名・ファイルパス・節名・設定キー) は、記述前に `grep` / `Read` で実在確認する工程を Implementation Steps に明示すべき**。3 本の sub-issue のうち **2 本で同型の欠陥が独立に発生**した。#1274 は分類 A の判定根拠に #1181 で削除済みの関数 (`_write_tier2_recovery_to_spec()` / `_write_manual_recovery_to_spec()`) を引用しており `/review` が D へ再分類させた。#1276 は Spec 本文に実在しないパス (`.tmp/auto-checkpoint-*.json`) と実在しない節名を書き、レポートへ転記されてから `/review` が検出した。いずれも「実装コードから正確な文字列を確認せず記憶・推測で転記した」ことが原因である。#1274 は同じセッション内で #762 の参照先消滅を正しく検出していたため、パターンを知らなかったのではなく**適用にムラがあった**。この種のレポートは「将来 `/verify` が参照する判定根拠」になるため、誤った参照は後続の判定を誤らせる。並列 sub-agent へ実査を委任する構成では、既存ドキュメントの記述の存在だけで判断が確定しやすい点も要因と見られる。
- **AC の verify 定義が構造的に充足不能なパターンを `/issue` triage の AC 監査が検出できない**。本 Issue の Pre-merge AC 1 は分母と分子の定義が 1 回の dispatch では両立せず、実装をどう進めても充足できなかった。triage の AC 監査は「実装前から真になる」常時 PASS パターンを検出するが、「定義自体が矛盾している」パターンは対象外である。#1278 の verify retrospective でも同種の指摘 (「常時 UNCERTAIN」になる verify command を監査が通過した) を **#1251 へ追記済み**であり、本件も同じ系統。**#1251 のスコープ内**として追記するのが適切で、新規起票はしない。
- **`/auto` の XL route に親 Issue の実装フェーズが存在しない**。既存 **#1241** が扱っており、本セッションの観測 (2 例目、かつ fan-out **前**の親作業を要する新しい型) は **#1241 へコメントで追記済み**。新規起票はしない。

### Re-run (2026-08-10) — Post-merge AC 解決

前回 `/verify` (2026-08-08T22:49) 時点では Post-merge 3 件とも `auto-run` 未発火で SKIPPED だった。以降、`auto-run` イベントが 2 回発火 (2026-08-09T01:55 / 2026-08-10T03:02) し、本再実行で 3 件とも PASS と判定できた。

- **Post-merge 6**: observation waiting 90 Issue (baseline 107 から -17)
- **Post-merge 7**: observation -17 / manual +14 が集約レポートの D5+E15=20 の見立てと方向・概算規模で一致 (Issue 単位集計のため AC 行単位の 20/15 とは厳密一致しない)
- **Post-merge 8**: 候補母集団 71 Issue / 74 AC 行 (baseline 82 Issue / 85 AC 行を下回る)

3 件とも `session=next` 付きだったが、実際には skill 挙動観測ではなくリポジトリ/GitHub 状態の数値観測だったため、`skills/verify/SKILL.md` Step 8c の `session=next` 既定 (skill self-update propagation 待ちとして SKIPPED) をそのまま適用せず、「変更 (D/E処理・集約レポート) が本セッション開始前に着地済みか」で判定した。詳細は Improvement Proposals を参照。

#### Improvement Proposals (追加分)

- **`session=next` の Step 8c 既定判定が、skill 挙動観測以外の observation 条件には合わない**。`modules/verify-classifier.md` は `session=next` を「変更した skill 自身の挙動を新セッションで観察する」用途に限定して定義しているが、`skills/verify/SKILL.md` Step 8c の判定手順は「evidence が the changed skill step actually ran in the observed `/auto` execution を示すか」という skill 挙動判定の文言を、`session=next` を持つ条件全般に一律適用する書き方になっている。本 Issue の Post-merge 3 件は skill ファイル変更ではなく GitHub 状態の数値観測であり、この文言をそのまま適用すると本来評価可能な条件まで機械的に SKIPPED になってしまう。今回は Claude の判断で「対象の変更が本セッション開始前に着地済みか」に読み替えて評価したが、この読み替えが正しい一般化かは Step 8c 本文からは自明でない。`session=next` を持つ条件が (a) skill 挙動観測型か (b) 非skill挙動 (数値・状態) 観測型かで Step 8c の判定分岐を明示的に分けるか、あるいは `/issue` 側で非skill挙動条件に `session=next` を付けないよう誘導するかの整理が必要。単発観測のため、再発 (次に `session=next` を持つ数値観測型 AC が発生した回) を確認してから起票を判断する。
