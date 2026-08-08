# L3 Session Retrospective: 23043-1786197225

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-08T13:54:21Z
**Session end**: 2026-08-08T22:28:11Z
**Wall-clock**: 08:33:50
**Route mix**: patch: 3, pr: 3, xl: 0, unknown: 1

### Summary

| Metric | Value |
|---|---|
| Issues processed | 7 |
| Fully closed (phase/done) | 2 |
| phase/verify remaining | 5 |
| Throughput | 0.8 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2720s |
| Phase silent windows > threshold | 3 (issue:1, spec:2) |
| Total token usage | input 45445 / output 945576 |
| Concurrent commits detected | 19 |
| Parent session manual interventions | 0 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Retro proposal tiers (1/2/3) | 4 / 6 / 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 6 |
| code-pr | 6 |
| issue | 12 |
| merge | 6 |
| review | 6 |
| spec | 12 |
| verify | 16 |

Sub-Issue Completion Timeline は生成表をそのまま転記していない。同表の `Size/Route` 列と `PR` 列に誤りがあることを本セッションで検出したため (Findings 参照、[Filed: #1300])、実態に基づく内訳を以下に置く:

| Issue | 実 Size/Route | 実 PR | 主なフェーズ |
|---|---|---|---|
| #1256 | XS/patch (`/spec` が M→XS 降格) | なし | issue → spec → code-patch → verify ×2 |
| #1266 | S/patch | なし | issue → spec → code-patch → verify |
| #1279 | M/pr | #1286 | issue → spec → code-pr → review → merge → verify |
| #1257 | M/pr | #1291 | issue → spec → code-pr → review → merge → verify |
| #1287 | S/patch | なし | issue → spec → code-patch → verify |
| #1289 | M/pr | #1299 | issue → spec → code-pr → review → merge → verify |
| #476 | — (in-session `/verify` dispatch のみ) | — | verify のみ (#1257 の review フェーズ中に dispatch) |

## What worked

- **検出 → 修正 → 実データ検証が同一セッション内で閉じた**: 測定系の 3 件 (#1279 / #1287 / #1289) は、いずれも「本セッション自身のイベントログ」を題材に修正の効果を実測できた。#1279 は `Issues processed` が 6 → 3 (候補 Issue 3 件の除外)、#1287 は `collect-run-facts.sh` の列挙から同じ 3 件が消え処理実績セットと完全一致、#1289 は `Route mix` が `patch: 2, pr: 4` 相当 → `patch: 3, pr: 3` へ是正された。検出元セッションが検証環境そのものになるため、observation AC の発火を待たずに効果を確定できた

- **#1256 が「実発火を確認したうえで」close された**: 自己 PR への `REQUEST_CHANGES` 422 フォールバックは #945 → #1102 → #1256 と 3 世代続いた系統で、#1102 は修正が一度も発火しないまま close されていた (それが #1256 の起票理由)。本セッションでは #1257 / PR #1291 で MUST 指摘 1 件が発生して条件が成立し、review body 先頭のフォールバック固有注記で発火を確認したうえで post-merge observation を PASS 判定して close した。同じ失敗形の再現を構造的に避けられている

- **前 Issue の verify 結果が後続 Issue の AC 品質に直結した**: `/triage` が #1279 の AC4 に常時 PASS を指摘 → `/issue` が独立に同じ指摘 → `/spec` が `bats --filter 'candidate Issues are excluded'` へ具体化して Issue 本文も同期。指摘が 3 フェーズを跨いで消化された

- **`/review` がパーサ系変更の実バグを捕捉した**: #1257 の MUST 指摘 1 件は Spec の Implementation Steps 由来のアルゴリズム欠陥 (フェンス追跡を追加行のみでカウントしたため、既存フェンス内の 1 行編集を誤判定) を、スクリプト自身の docstring 例に対して再現させて指摘した。修正後の bats ケース 7 が回帰保護になっている

- **#1202 の全文検索ガードが実際に誤ヒットを防いだ**: `/verify 1266` の Step 2 で `gh pr list --search "closes #1266"` が PR #1090 を返したが、`gh-extract-issue-from-pr.sh` による実参照確認で `closes #1061` と判明し正しく除外された

## Findings

- **AC の常時 PASS が本セッションの支配的な欠陥クラスだった。根因は監査パターン文書の被覆漏れ**: `/triage` と `/verify` を通じて 7 件の不備を検出した — #1283 (always-FAIL 1 件)、#1273 (always-PASS 5 件)、#1279 (always-PASS 1 件)。さらに #1287 でも `command "bats tests/run-fact-matching.bats"` (既存ファイル) が常時 PASS だった。当初これを「`/issue` の処置が Issue 間で一貫しない」と捉えたが、`skills/triage/skill-dev-verify-audit.md` Pattern 2 を精読したところ `command` 型のサブパターンが「スクリプトが informational 専用で常に exit 0」というケースしか扱っておらず、「AC 本文は新規テスト追加を主張しているが、コマンドは変更前から green な既存スイートを走らせるだけ」という形が被覆されていないことが判明した。#1279 で `/issue` が気づいたのはパターン文書の要求を超えた判断であり再現性がない。同文書は `/triage` Step 7 と `/issue` Step 15 の 2 skill が読む共有面である [Filed: #1294]

- **#1289 の修正が同一スクリプト内で不完全だった**: `get-auto-session-report.sh` には `sub_start` の `size` から route を導出する箇所が 2 つあり (`ROUTE_MIX` と Sub-Issue Completion Timeline 行生成 `:341-342`)、#1289 は前者のみを修正した。結果として同じレポート内で `Route mix` は `patch: 3, pr: 3` と正しく報告する一方、Timeline 表は #1256 を `M/pr` と表示し両者が矛盾する。#1289 の Spec は `ROUTE_MIX` を対象と明記しており Timeline は Changed Files にもテストにも含まれていなかった。あわせて同表の `PR` 列が `gh pr list --search` の `.[0]` を実 `closes` 参照の確認なしに採用しており、7 行中 3 行で誤った PR 番号を報告していた (#1256/#1266 は patch route で PR なしなのに `#1299`、#1279 は実際は #1286)。これは #1202 が `/verify` Step 2 で修正したのと同一パターンで、参照実装 (`gh-extract-issue-from-pr.sh`) が同一リポジトリ内にある [Filed: #1300]

- **`code_retry_fire` がどの永続 SSoT にも到達しない**: #1266 の code フェーズは silent no-op によるリトライで 2 回走った (15:18:25Z にリトライ発火、約 14 分消費) が、この事実は Spec の Code Retrospective (`Rework: N/A`) にも `docs/reports/orchestration-recoveries.md` (#1266 の grep ヒット 0) にも記録されていない。唯一の記録は gitignore 対象の `.tmp/auto-events.jsonl` のみ。リトライは fresh context で起動するため、2 回目が書く Code Retrospective が 1 回目の失敗を観測できないのは構造的な帰結であり、code フェーズの記述漏れではない。なお #869 の post-merge observation AC (「次回 silent no-op が観測された session で `code_retry_fire` イベントが記録される」) は本イベントで満たされうる [No action: #1266 の Verify Retrospective に Tier 2 として記録。耐久記録先を持たせる提案が再度出た場合は #1279 と同じ「測定 SSoT の欠落」系統として Tier 1 を検討]

- **`/code` の Code Retrospective に事実誤認があり、verify で訂正した**: #1266 の Design Gaps は「`phase/ready` 付与と `phase/code` 遷移が同一タイムスタンプ (15:04:31Z)」と記録していたが、実測のラベルイベントは 14:59:01Z と 15:04:31Z で 5 分 30 秒離れている。`reconcile-phase-state.sh` の `_precondition_code_common` が `matches_expected: false` を返す分岐は (1) `phase/ready` 不在、(2) Spec 不在かつ Size ≠ XS の 2 つのみで、precondition check は Step 3 (`:165`)・ラベル遷移は Step 4 (`:187`) の順序であり wrapper スクリプトはラベルを触らない (grep ヒット 0) ため、分岐 1 は構造的に成立不能で発火したのは分岐 2 (Spec 不在) だった。Spec 自体は実装時点では読めていたため、fresh worktree の base ref と `/spec` の push 伝播のタイミングによる時間窓が疑われるが機構は未確定 [Resolved directly: #1266 の Issue コメントと Verify Retrospective に訂正を記録]

- **spec フェーズの watchdog timeout が 2 セッション連続で限界に接近している (前セッションの「再発時に判断」トリガーが発火)**: `WATCHDOG_TIMEOUT_SPEC_DEFAULT` は 1800s。本セッションの spec silent window は #1257 が 1690s、#1289 が 1790s で、後者は kill 閾値まで **10 秒**だった (レポートの Notes 列も 3 件を "within 600s of watchdog limit" と警告)。前セッション (`83694-1786088052`) では spec の閾値超過 3 回・最大 4070s・kill 1 回を記録し、「kill 1 回で完走しており判断にはデータ不足。再発時に判断」として保留していた。2 セッション合計で 5 回の超過・1 回の kill・10 秒の余裕という状況は、その保留条件を満たす。`.wholework.yml` は既に code (7200s) と review (5400s) を明示的に延長しており、spec だけが既定値のままである [Filed: #1301]

- **batch が retro Issue をほぼ 1:1 で生成し、構造的に終端しない**: 処理 7 件に対し、本 batch 中に起票された retro Issue は 8 件 (#1285 / #1287 / #1288 / #1289 / #1292 / #1293 / #1294 / #1300)。うち #1287 は `/code` フェーズ、#1285 / #1288 / #1292 / #1293 は `/review` フェーズ中の入れ子 dispatch (#476 経由を含む)、#1289 / #1294 / #1300 は `/verify` および L3 retrospective 由来である。「batch 中に発生した retro Issue は remaining に自動追加」の慣例をそのまま適用すると消化と生成が釣り合い batch が終わらない。ユーザーに提示し、#1289 まで消化して終了・残りは次セッションという判断を得た [No action: 運用判断としてユーザーが決定。慣例自体の見直しが必要になった場合は別途起票]

- **`session=next` ゲートが script 変更にも機械的に付与される**: #1289 の post-merge observation AC に `session=next` が付いたが、変更対象は `scripts/get-auto-session-report.sh` であり skill 自己更新の伝播待ちは本来不要 (実際、マージ後の main に対して即座に効果を実測できた)。Background が SKILL.md を参照していたことによるスコープゲートの検出結果で、保守側に倒れた形 [No action: 実害は「不要に 1 セッション待つ」のみで、fail-safe 方向の誤りのため許容。同型が頻発した場合に判断]

## Auto Retrospective

### Improvement Proposals

- **`skill-dev-verify-audit.md` Pattern 2 に「既存のグリーンなテストスイートを走らせるだけの `command` 型 AC」のサブパターンが欠けている** — 本セッション内で 3 件観測 (#1273 / #1279 / #1287)。検出は機械的に可能 (実装前の main に対してコマンドを実行し、既に exit 0 かつ AC 本文が新規カバレッジ追加を主張していれば flag)。対象文書は `/triage` Step 7 と `/issue` Step 15 の 2 skill が読む共有面

- **`get-auto-session-report.sh` Timeline 表の `Size/Route` 陳腐化と `PR` 列の無検証全文検索** — #1289 の修正漏れ (同一スクリプト内の 2 消費箇所のうち 1 つのみ修正) と、#1202 が `/verify` で修正済みのパターンの未適用。7 行中 3 行で PR 番号が誤り

- **spec フェーズの watchdog timeout を `.wholework.yml` で延長する** — 2 セッションで 5 回の閾値超過、1 回の kill、今回は残り 10 秒。code / review は既に延長済みで spec のみ既定値

## Filed Issues

- #1294 — skill-dev-verify-audit: Pattern 2 に既存グリーンテストを走らせるだけの command 型 AC を追加
- #1300 — get-auto-session-report: Timeline 表の Size/Route 陳腐化と PR 列の無検証全文検索を修正
- #1301 — auto: spec フェーズの watchdog timeout を延長する

## Deferred to next session

本 batch 中に入れ子フェーズが起票し、未処理のまま残した retro Issue:

- #1285 — opportunistic-verify: run-fact トークン事前フィルタが判定可能な候補を落とさないようにする
- #1288 — doc/audit: ドキュメント走査の除外パターン重複定義を共通 SSoT に集約
- #1292 — test: bats の否定アサーションが set -e 下で無効化される落とし穴を共有モジュールに明文化
- #1293 — observation-trigger: keyword= ゲートの非パス様値への部分一致を単語境界マッチに改善
