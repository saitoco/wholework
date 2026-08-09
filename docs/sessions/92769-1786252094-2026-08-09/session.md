# L3 Session Retrospective: 92769-1786252094

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.
> - `Phase silent windows > threshold` の閾値は `.wholework.yml` の phase timeout override を読まないため過大計上されている (本セッションで検出、[Filed: #1312])。spec:1 の内訳は #1301 の 1310s で、実際の上限 2340s に対しては 1030s の余裕がある。

**Session start**: 2026-08-09T05:08:54Z
**Session end**: 2026-08-09T10:17:18Z
**Wall-clock**: 05:08:24
**Route mix**: patch: 2, pr: 2, xl: 0, unknown: 1

### Summary

| Metric | Value |
|---|---|
| Issues processed | 5 |
| Fully closed (phase/done) | 1 |
| phase/verify remaining | 4 |
| Throughput | 1.0 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2340s |
| Phase silent windows > threshold | 3 (issue:2, spec:1) — 上記キャベアト参照 |
| Total token usage | input 12195 / output 743266 |
| Concurrent commits detected | 13 |
| Parent session manual interventions | 0 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Retro proposal tiers (1/2/3) | 2 / 0 / 2 |
| Merge conflicts | 0 |

### Sub-Issue Completion Timeline

本セッションで #1300 が修正したため、Timeline 表の `Size/Route` 列と `PR` 列は実態と一致している (前セッションは 7 行中 3 行の PR 列が誤りだった)。

| Issue | Size/Route | PR | 主なフェーズ |
|---|---|---|---|
| #1301 | S/patch | — | issue → spec → code-patch → verify |
| #1294 | S/patch | — | issue → spec → code-patch → verify ×2 |
| #1300 | M/pr | #1311 | issue → spec → code-pr → review → merge → verify |
| #1293 | M/pr | #1314 | issue → spec → code-pr → review → merge → verify |
| #476 | — (in-session `/verify` dispatch のみ) | — | verify のみ |

## What worked

- **同一 batch 内で「機構の改善 → その機構による検出 → 検出結果の修正 → 修正の検証」が閉じた**: #1294 (AC 監査 Pattern 2 のサブパターン追加) の着地後、#1300 では回帰保護と明示された `command "bats ..."` が除外条件 (d) により正しく**指摘されず**、#1293 では新規カバレッジを主張する同型 AC が正しく**指摘された**。指摘を受けた `/spec 1293` は AC3 を `bats --filter 'CLI flag token' ...` へ絞り込み (#1294 が Fix options 第 1 項に記載した手段)、`/verify 1293` でこの filter が実テスト 2 件にマッチし両方 PASS することを実測した。誤検出・検出漏れのいずれも起きていない

- **`/issue` フェーズが Issue タイトルが示唆する実装方式を実測で反証した**: #1293 のタイトルは「単語境界マッチに改善」だったが、`/issue` が `echo "--workflow=test.yml" | grep -qiw "workflow"` を実機実行して一致することを確認し、当該方式では対象ケースが解消しないことを示した (`-` と `=` がいずれも非単語文字であるため)。AC1/AC2 が outcome-based (rubric ベース) で手段を固定していなかったため AC の書き換えは不要で、`/spec` は別方式 (#1220 のトークン除去を CLI フラグ構文へ拡張) を採用できた。**タイトルが特定方式を示唆していても、AC が手段を固定していなければ設計の再検討が阻害されない**という事例

- **測定系の修正が実データで即座に検証できた**: #1300 の着地後、本セッション自身の Timeline 表が #1294 = `S/patch` / PR `—`、#1300 = `M/pr` / PR `#1311`、#1301 = `S/patch` / PR `—` を報告し、3 行すべてが実態と一致した。前セッションから続く「検出元セッションが検証環境そのものになる」パターンが 4 件目 (#1279 / #1287 / #1289 / #1300) として機能した

- **前セッションの `/issue` 由来の改善が起票側の想定漏れを補正した**: #1300 の AC5 は起票時「post-spec で Size が**降格**した Issue」のフィクスチャのみを要求していたが、`/issue` が実測で #1292 の **S→M 昇格**でも同じ誤りが出ることを示し、AC を両方向へ拡張した。起票者 (`/verify 1289` の L3 retrospective) が観測できた実例が降格側だけだったための片側バイアスを、後段フェーズが補正している

- **並行セッションとの分担が機能した**: 前セッションが次セッション送りにした 4 件のうち #1285 / #1288 / #1292 は並行セッションが完走させており、本 batch は残る 4 件に集中できた。`gh issue list` による着手前の state 確認で重複作業を回避

## Findings

- **レポートの silent-window at-risk 警告閾値が `.wholework.yml` の phase timeout override を読まない**: `scripts/get-auto-session-report.sh:26` は `SILENT_THRESHOLD_SPEC=$(( ${WATCHDOG_TIMEOUT_SPEC_DEFAULT:-1800} - SILENT_MARGIN ))` のようにグローバル既定値からのみ閾値を計算しており、実際に kill を行う `run-*.sh` が使う `load_watchdog_timeout()` (config を解決する) と別経路になっている。本セッションでは #1301 が設定した `watchdog-timeout-spec-seconds: 2340` に対し 1310s の silent window (余裕 1030s) が `within 600s of watchdog limit` として警告された。この repo は code (7200s / 既定 4680s) も override しており同じ乖離が生じる。同一スクリプトの測定精度欠陥としては #1279 / #1289 / #1300 に続く 4 件目 [Filed: #1312]

- **#1301 の post-merge observation AC が上記の欠陥により恒久的に達成不能になっている**: 条件は「`within 600s of watchdog limit` の警告が spec 行に出ないことを観察する」だが、警告閾値が override を読まない限り spec の silent window が 1200s を超えるたびに警告が出続ける。本セッションの watchdog kill は 0 件で #1301 の目的 (kill 抑制) 自体は達成されており、壊れているのは確認手段のほうである。将来の `/verify 1301` が FAIL と誤判定して fix-cycle を発火させないよう、Issue コメントに申し送りを記録し `#1301 blocked-by #1312` を GraphQL で設定した [Resolved directly: #1301 にコメント投稿 + blocked-by 設定]

- **起票者自身の AC にも常時 PASS が混入していた**: #1301 の AC は `/verify 1289` の L3 retrospective が起草したもので、同じ前セッションでは他 Issue の always-PASS を 7 件指摘していた。それにもかかわらず AC4 (`load_watchdog_timeout()` の解決経路で読まれることの確認) が常時 PASS であり、`/issue` Step 15 に検出された。根因が個々の実行者の注意深さではなく監査パターンの被覆範囲にあるという #1294 の見立てを補強する実例 [No action: #1301 の Verify Retrospective に Tier 3 として記録。#1294 で対処済み]

- **AC 監査の指摘が保守側に倒れる場合がある**: `/issue 1301` は「AC3 の rubric が Spec ファイルの内容を根拠にしており、`modules/verify-executor.md` の grader 入力仕様上 Spec が渡らないため恒久 UNCERTAIN/FAIL になりうる」と指摘した。仕様上は正しいが、同型の rubric は前セッションで 3 件 (#1279 AC2/AC3、#1289 AC3) がいずれも PASS しており、Spec ファイルが同一ブランチの git diff に含まれるため実際には grader が参照できていたと考えられる。`/spec` が従った修正 (記録先を config コメントへ移動) は結果的により堅牢だった。関連する既存 open Issue として **#1251** (rubric の参照ファイルを AC に含める規約) がある [No action: #1301 の Verify Retrospective に Tier 3 として記録。受け皿は #1251]

- **observation-trigger の一括発火が harness の 2 分 timeout に収まらない**: 81 件のマッチに対してコメント投稿を行う `observation-trigger.sh --event auto-run` が foreground 実行で exit 143 (SIGTERM) となった。冪等性ガード (24h) があるためバックグラウンド再実行で完了したが、マッチ件数が増えるほど foreground 実行は成立しなくなる [No action: バックグラウンド実行で回避可能。マッチ件数は `phase/verify` 滞留数に比例するため、滞留の解消 (#1270-#1276 系) が進めば自然に緩和する。再発が運用の妨げになる場合に起票判断]

## Auto Retrospective

### Improvement Proposals

- **silent-window at-risk 警告閾値を watchdog の実解決経路 (`load_watchdog_timeout()`) に揃える** — 警告基準と実 kill 基準の乖離。#1301 の post-merge AC を直接ブロックしている

## Filed Issues

- #1312 — get-auto-session-report: silent-window 警告閾値を watchdog の実解決経路に揃える

## Fully closed this session

- **#1294** — post-merge observation を PASS 判定し `phase/done` へ遷移。#1293 での検出と #1300 での非検出の両方を証拠として確認済み
