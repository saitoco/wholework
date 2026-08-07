# L3 Session Retrospective: 94570-1786069858

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-07T02:32:13Z
**Session end**: 2026-08-07T08:41:44Z
**Wall-clock**: 06:09:31
**Route mix**: patch: 0, pr: 4, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 7 |
| Throughput | 1.1 issues/hr |
| Tier 1/2/3 recoveries | 0 / 2 / 1 |
| Recovery success rate (tier) | T1: 0 recovered / 0 failed, T2: 1 recovered / 1 failed, T3: 0 recovered / 1 failed |
| Watchdog kills | 1 |
| Max silent window (any phase) | 2520s |
| Phase silent windows > threshold | 5 (review:1, spec:4) |
| Total token usage | input 2050 / output 317871 |
| Concurrent commits detected | 69 |
| Parent session manual interventions | 1 |
| verify FAIL → reopen fix cycles | 0 |
| Retro proposal tiers (1/2/3) | 11 / 1 / 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-pr | 8 |
| merge | 8 |
| review | 8 |
| spec | 10 |
| verify | 23 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | Recovery | Notes |
|---|---|---|---|---|---|
| #1158 (親) | XL/pr | 02:32:13Z – 08:40:39Z | spec 25m → code-pr → review 38m → merge 3m → verify 5m | T1:0/T2:0/T3:0 | Silent 2160s phase=review |
| #1164 | M/pr | 02:58:45Z – 07:16:04Z | spec 21m → code-pr 97m → review 24m → merge 3m → verify 37m | T1:0/T2:0/T3:0 | Silent 1300s phase=spec; 23 concurrent commits |
| #1165 | L/pr | 02:58:45Z – 07:18:17Z | spec 22m → code-pr 74m → review 35m → merge 2m → verify 31m | T1:0/T2:0/T3:0 | Silent 1340s phase=spec; 19 concurrent commits |
| #1166 | M/operate | 02:58:45Z – 07:23:18Z | spec 17m → (code-pr dispatch → operate 実行) → verify 31m | T1:0/T2:1/T3:1 | 両 tier とも failed → manual reconcile-override; 5 concurrent commits |
| #1167 | M/pr | 02:58:45Z – 07:20:11Z | spec 24m → code-pr 148m → review 31m → merge 10m → verify 26m | T1:0/T2:1/T3:0 | T2 recovered; merge フェーズで watchdog kill (600s); 22 concurrent commits |
| #476 / #575 | — | — | verify のみ | — | `/review` の observation scan から dispatch された副次実行 |

### Recovery Events

- [03:37:38Z] Issue #1166 phase=code-pr tier=2 result=failed
- [03:38:19Z] Issue #1166 phase=code-pr tier=3 result=failed (action=skip、`matches_expected != true` で reject)
- [05:51:30Z] Issue #1167 phase=code-pr tier=2 result=recovered

### Manual Interventions

- [06:34:51Z] Issue #1166 recovery_target=code-pr wrapper_exit_code=1 intervention_type=reconcile-override

### Improvement Candidates Surfaced (自動検出)

- Tier 2 recovery in phase=code-pr (count=2, approaching threshold) — review recoveries-auto-fire.threshold
- Tier 3 recovery occurred in phase=code-pr — investigate root cause

## What worked

- **4 並列の sub-issue 実行が競合なく完走した**。`auto-max-concurrent` 既定 5 の範囲内で 4 本を並列起動し、worktree 競合・push 競合・merge conflict はいずれも 0 件。`concurrent_commit_detected` は 69 件記録されたが、すべて検知イベントであり実害には至っていない。
- **Tier 2 fallback catalog が #1167 で自動復旧した**。code-pr フェーズで既知パターンにマッチし、PR #1237 作成まで無介入で継続。`apply-fallback.sh` が recovery ログを直接コミットしており二重記録もなかった。
- **Tier 1 (reconcile-first) の設計が #1166 で正しく機能した**。wrapper は exit 1 だったが `reconcile-phase-state.sh code-patch --check-completion` が `matches_expected: true` を返し、機能的には成功していたことを機械的に確認できた。「wrapper の exit code より観測可能な状態を信じる」という checkpoint-as-hint の原則が実証された。
- **fan-out レビューの corroboration**。親 PR #1249 で review-spec + review-bug×2 の 3 finder が独立に同じ 2 箇所 (line 84 の一括マッチ確認 claim、D3 テーブルの AC 行数 24 vs 22) を指摘し、adversarial verify で 3/4 が CONFIRMED。rubric AC が PASS 判定した記述の不正確さを review 側が捕捉した。
- **observation AC の 2 段階評価が機能した**。1 回目の verify で全 sub-issue が SKIPPED (waiting for event) → `observation-trigger.sh --event auto-run` を発火 → 2 回目の verify で全件 PASS → `phase/done`。observation 型 AC が「イベント発火を待って自動評価される」という設計どおりの挙動を、同一セッション内で端から端まで観測できた。
- **成果**: Manual Waiting Count が baseline と同一母集団 (`phase/verify` ラベル、created ≥ 2026-05-07) で **79 件 → 18 件 (−61)**。sub-issue 5 本 + 親の計 6 Issue がすべて `phase/done` + CLOSED に到達。

## Findings

- **`scripts/run-auto-sub.sh` の sub-issue route 判定が Spec 由来の operate route を honor しない** — `skills/auto/SKILL.md` の単一 Issue 経路には Step 3a「Operate route demotion」があるのに、`run-auto-sub.sh` の post-spec 再判定は Size 軸しか見ない (`grep -n "operate" scripts/run-auto-sub.sh` は 0 件)。#1166 は `/spec` が `ROUTE=operate` と判定したにもかかわらず `code-pr` で dispatch され、PR 不在のため completion check が失敗 → Tier 2 (anchor マッチ・handler 失敗) → Tier 3 (`action=skip` を reject) と空振りして exit 1。実際には `/code` の operate 分岐は正常完走しており `code-patch` の completion check は `matches_expected: true` を返す。バッチ/XL 経路で operate route Issue を扱う限り再発する。 [Filed: #1240]

- **`/auto` の XL route に親 Issue の実装フェーズが存在しない** — XL route は「sub-issue 実行 → 親ラベル集約 → sub-issue verify → 親 close flow」で構成され、親自身の `/code` を回す経路を持たない。しかし親 #1158 の Pre-merge AC 5 件は全て `rubric` 型で、rubric grader は Issue コメントや Spec を参照できないため、親自身が成果物ファイル (`docs/reports/manual-ac-retype-summary.md`) を持たざるを得なかった。本セッションでは親セッションが Step 4d の後に `run-code.sh 1158 --pr` → `run-review.sh 1249 --full` → `run-merge.sh 1249` → `/verify 1158` を手動挿入して pr route 相当を完走させた。 [Filed: #1241]

- **`opportunistic-search.sh` / `scan-pending-ac.sh` の母集団が `--state closed` 固定で、走査スコープも不一致** — (1) OPEN + `phase/verify` の Issue がどちらの自動評価経路にも乗らない (#490 / #465 が実例、`docs/stats/2026-08-05.md` Section 7 も CLOSED 165 / OPEN 2 と記録)。(2) `opportunistic-search.sh:222` はセクション非依存に `^- \[ \]` を grep する一方 `scan-pending-ac.sh:127` は `### Post-merge` にスコープしており、コードフェンス内のサンプル AC を実 AC と誤認する (#491 が実例)。 [Filed: #1242]

- **`config=` 条件ゲートが boolean 専用で enum 設定キーを表現できない** — `modules/observation-trigger.md` § Condition Check Gate は `config=<key>` の値が `"true"` の場合のみマッチする実装。#1165 では `auto-stop-at` (enum) をゲートに使えず、#783 を再型付けではなく retire に倒す決め手になった。 [Filed: #1243]

- **#1158 の sub-issue 分割から区分 C 相当の 3 AC 行 (#708 条件1・2 / #719 条件1) がこぼれ落ちた** — #1163 の Phase Handoff が「#1167 の領域」と記録したが、#1167 の Issue 本文は #1066 / #1060 のみを挙げていた。`grep -rl "#708" docs/spec/` は 4 ファイルにヒットし、#1163 と #1167 の 2 つの独立した Spec retrospective が同じ欠落を記録している。親 Issue が解消しようとしている滞留が、分割作業自体の副産物として新たに 3 行残った。 [Filed: #1245]

- **AC が「評価者が判定に必要とする情報」を AC 自身に含めていない (2 形態・4 Issue)** — (1) rubric の可視範囲: `modules/verify-executor.md:85` は grader の入力を「Issue 本文 + git diff + rubric text が明示的に名指ししたファイル」と定めるが、#1158 の rubric AC 5 件はファイルを名指ししておらず一次証拠が不可視だった。(2) 数値 AC の母集団定義: #1164 / #1165 / #1158 の observation AC が「移行前 (79 件) から減少」と絶対数のみを書いており、baseline の母集団定義 (90 日窓 / 167 件) は `docs/stats/2026-08-05.md` § 訂正 1 を辿らないと復元できない。全期間スキャンだと 123 件となり「増加している」と誤判定しうる。対照的に #1167 の AC は対象 Issue を個別に名指ししており母集団定義なしで一意判定できた。 [Filed: #1251]

- **operate route + observation AC で close deadlock が実在した (#1166)** — operate route は `closes #N` コミットを持たないため CLOSE 契機が `/verify` の全 AC 充足のみ。一方 `opportunistic-search.sh` の母集団は closed 限定なので、OPEN のままの #1166 は `auto-run` のマッチ集合 (83 件) から構造的に除外され通知が届かない。「close されないと通知母集団に入らない → 通知が来ないと observation AC が評価されない → AC が評価されないと close されない」という閉路。親セッションがスキャナ欠陥の補正として同一形式の通知を経緯付きで手動投稿して打開した。 [No action: 真因は #1242 の母集団 closed 限定であり、そちらの修正で閉路自体が消える。deadlock として独立起票する価値はない]

- **XL 親の observation AC は親 PR マージ後に observation-trigger の再実行を要する** — `/auto` の XL route は observation scan を Step 5 (全フェーズ完了後) に 1 回だけ実行するが、親自身の PR マージがその scan より後に来る構成では、scan 時点で親はまだ OPEN (母集団外) のため親の observation AC が永久に未発火になる。本セッションでは親マージ後に再実行して解消 (24h 冪等性ガードにより既通知 83 件はスキップ、#1158 のみ新規通知)。 [No action: #1241 で親 code フェーズが Step 4d〜4c 間に入れば、親 PR は Step 5 の scan より前にマージされるため自然に解消する]

- **#1167 の merge フェーズで watchdog kill が発生したが work loss はなかった** — 06:33:07Z、`phase=merge pr=1237 silent_window_sec=600 timeout_setting=600`。しかし PR #1237 はマージ済み、Issue は CLOSED + `phase/verify` へ遷移済みで、`run-auto-sub.sh` の exit code も 0。実質的な作業は kill 前に完了しており、silent window は後処理中に発生したと見られる。 [No action: work loss ゼロの単発事象。`watchdog-timeout-merge-seconds` の既定 600s を変更する根拠としては弱く、再発時に再評価する]

- **run-fact JSON が #1166 を `route: pr` と記録している (実際は operate)** — `collect-run-facts.sh` は phase イベント名から route を導出するため、`run-auto-sub.sh` が `code-pr` を emit した #1166 は operate として記録されない。`modules/run-fact-matching.md` は「`route` は operate と patch を区別する唯一のシグナル」と位置づけているため、この誤記録は run-fact マッチングの判定精度に直接影響する。 [No action: #1240 の dispatch 修正で `run-auto-sub.sh` が `code-patch` を emit すれば route 導出も自動的に正しくなる。独立した修正対象ではない]

- **retro proposal の filter hit rate が 8% (Tier 1: 11 / Tier 2: 1 / Tier 3: 0)** — `modules/retro-proposals.md` は #1159 の分析を受けて「判断が難しい場合の既定を Tier 2 へ倒す」方針に変更したが、本セッションの実測では 12 件中 11 件が Tier 1 判定だった。ただし本セッションの Tier 1 判定はいずれも positive-evidence gate の signal (a) multi-file ripple / (b) 再発性の機械的確認 / (c) SSoT ripple のいずれかを実際に満たしており、既定への fall-through ではない。 [No action: #1159 が既にレート監視の post-merge AC を持っており、単一セッションの実測値で追加の起票をする段階ではない]

- **並列度 4 で concurrent_commit_detected が 69 件記録された** — 内訳は #1164:23 / #1167:22 / #1165:19 / #1166:5。本セッションの 4 並列に加え、他セッション (#1210 / #1213 / #1223 / #1224 / #1108 / #1150 / #1117 等) のコミットも検知している。merge conflict は 0 件、work loss も 0 件。 [No action: 検知のみで実害なし。並列度の抑制や検知閾値の変更を要する状況ではない]

## Auto Retrospective

### Improvement Proposals

- **`scripts/run-auto-sub.sh` の sub-issue route 判定が Spec 由来の operate route を honor しない** — `skills/auto/SKILL.md` の単一 Issue 経路には Step 3a「Operate route demotion」があるのに、`run-auto-sub.sh` の post-spec 再判定は Size 軸しか見ない。#1166 が実例で、機能的には成功しているのに wrapper は exit 1 で終わる。バッチ/XL 経路で operate route Issue を扱う限り再発する構造的欠陥。
- **`/auto` の XL route に親 Issue の実装フェーズが存在しない** — 親が rubric 型の横断 AC を持つ場合、rubric grader の可視範囲の都合で親自身が成果物ファイルを持たざるを得ないが、XL route はその実装フェーズを回す経路を持たない。
- **`opportunistic-search.sh` / `scan-pending-ac.sh` の母集団が closed 限定で、走査スコープも不一致** — OPEN + `phase/verify` の Issue を構造的に取りこぼし、コードフェンス内のサンプル AC を実 AC と誤認する。
- **`config=` 条件ゲートが boolean 専用で enum 設定キーを表現できない** — enum キーに依存する observation AC を retire せざるを得なくなる。
- **#1158 の sub-issue 分割から区分 C 相当の 3 AC 行 (#708 条件1・2 / #719 条件1) がこぼれ落ちた** — 親 Issue が解消しようとしている滞留が、分割作業自体の副産物として新たに残った。
- **AC が「評価者が判定に必要とする情報」を AC 自身に含めていない** — rubric の参照ファイル明示と、数値 AC の母集団定義の 2 形態。

## Filed Issues

- #1240
- #1241
- #1242
- #1243
- #1245
- #1251

## Skill Self-Update Propagation Note

Session 中に以下の skill が origin 上で更新されました (比較対象: origin/main)。ローカル main が追従できていない場合、本 session 内の以降の実行や次回セッションが更新前の版を使う可能性があります:

- skills/auto/SKILL.md: 12339eec → f79bd887
- skills/code/SKILL.md: 9a8b3c55 → 38663cb3
- skills/spec/SKILL.md: (no change)
- skills/verify/SKILL.md: (no change)
- skills/review/SKILL.md: 9dc07088 → 38663cb3
- skills/merge/SKILL.md: (no change)
- skills/issue/SKILL.md: 9a8b3c55 → 96d26cd0
- skills/audit/SKILL.md: 12339eec → f79bd887

本セッションは並行して走っていた他セッション (#1210 / #1213 / #1223 / #1224 等) の着地を継続的に取り込んでおり (`git fetch` + rebase を各フェーズ境界で実施)、`run-*.sh` 経由のサブプロセスは起動時点の main を読む。`/verify` のみ wrapper を持たず会話単位でキャッシュされるため、session 開始時点の版で全 6 回の verify を実行している (`skills/verify/SKILL.md` は今回 no change だったため実害なし)。
