# L3 Session Retrospective: 74631-1786005349

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-06T08:36:25Z
**Session end**: 2026-08-06T13:50:29Z
**Wall-clock**: 05:14:04
**Route mix**: patch: 3, pr: 1, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 10 |
| Throughput | 1.9 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2070s |
| Phase silent windows > threshold | 2 (review:1, spec:1) |
| Total token usage | input 7562 / output 228908 |
| Concurrent commits detected | 19 |
| Parent session manual interventions | 0 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Retro proposal tiers (1/2/3) | 3 / 0 / 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 6 |
| code-pr | 2 |
| issue | 8 |
| merge | 2 |
| review | 2 |
| spec | 6 |
| verify | 20 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | Recovery | Notes |
|---|---|---|---|---|---|
| #1197 | XS/patch | 08:36:25Z – 09:19:55Z | code-patch 28m → issue 8m → verify 3m | T1:0/T2:0/T3:0 | Silent 1730s; 7 concurrent commits |
| #1162 | M→L/pr | 09:28:04Z – 11:10:01Z | code-pr 32m → issue 7m → merge 3m → review 35m → spec 18m → verify 2m | T1:0/T2:0/T3:0 | Size M→L; Silent 2070s phase=review; 5 concurrent commits |
| #1133 | S/patch | 11:10:48Z – 12:08:30Z | code-patch 28m → issue 4m → spec 21m → verify 2m | T1:0/T2:0/T3:0 | Silent 1250s phase=spec; 3 concurrent commits |
| #1102 | S/patch | 12:09:17Z – 13:18:21Z | code-patch 35m → issue 6m → spec 18m → verify 6m | T1:0/T2:0/T3:0 | Silent 1500s; 4 concurrent commits; **code_retry_fire 1 (silent no-op)** |
| #514 | —/— | 13:30:33Z – 13:33:40Z | verify 3m | T1:0/T2:0/T3:0 | observation dispatch |
| #520 | —/— | 13:34:50Z – 13:40:02Z | verify 5m | T1:0/T2:0/T3:0 | observation dispatch |
| #562 | —/— | 13:41:18Z – 13:43:49Z | verify 2m | T1:0/T2:0/T3:0 | observation dispatch |
| #589 | —/— | 13:44:17Z – 13:45:33Z | verify 1m | T1:0/T2:0/T3:0 | observation dispatch |
| #590 | —/— | 13:45:33Z – 13:46:40Z | verify 1m | T1:0/T2:0/T3:0 | observation dispatch |
| #1188 | —/— | 09:04:36Z – 09:08:18Z | verify 3m | T1:0/T2:0/T3:0 | 別セッション由来の in-session verify |

### Token Usage Aggregate

| Issue | Input | Output | Total |
|---|---|---|---|
| #1102 | 154 | 29571 | 29725 |
| #1133 | 158 | 24429 | 24587 |
| #1162 | 2083 | 135438 | 137521 |
| #1197 | 5167 | 39470 | 44637 |

### Concurrent Sessions Detected

19 件。並行していた他セッションの作業対象: #1152 / #1188 / #1191 / #1201 / #1078 / #1205。

### Retro Proposal Tier Breakdown

- Tier 1: 3 / Tier 2: 0 / Tier 3: 0 (filter hit rate 0%)

## What worked

- **バッチ 4/4 完走、Tier 1/2/3 recovery ゼロ、watchdog kill ゼロ**。`docs/reports/orchestration-recoveries.md` への新規エントリもゼロで、orchestration 側の手当ては一度も要らなかった。
- **#1102 の silent no-op が完全自動で復旧した**。`run-code.sh` の exit-0 reconcile ガード (#520 の成果物) が `commits_found:false` を検出し、`auto-retry-on-fail` が 2 回目を起動して成功。`modules/orchestration-fallbacks.md#code-patch-silent-no-op` のカタログどおりの経路で、2 回目起動時には 1 回目が残した stale worktree / branch も自動クリーンアップされた。親セッションの介入は不要だった。
- **#1162 が追加した session フィルタが本番で機能した**。バッチ末尾の observation scan で 58 件がマッチし、`filter-session-verified-issues.sh` が in-session verify 済みの #1133 / #1162 を除外して 56 件に絞った。着地当日に自身の機能が効いている。
- **跨り Issue の Spec-as-memory が回帰を防いだ**。#1133 の Spec Notes が「前身 Issue #687 の Spec Notes が記録する通り」として `grep -c ... || _failed=0` イディオムの維持を指示し、Code Retrospective が遵守を明記。#687 → #1133 の知識伝達が完結した (#562 の observation 評価で確認)。
- **AC 監査の二重チェックが一致した**。バッチ投入前に人手で修正した #1102 の AC 欠陥 2 件 (常時 PASS の `grep` パターン / patch route × `gh pr checks` 不整合) を、`/issue` の非対話実行が独立に同じ 2 件として検出した。

## Findings

- **patch route の CI 検証 AC が実装コミットの run 不在と HEAD 依存で誤判定する**: `modules/verify-classifier.md:161` が正準形とする `github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) ..."` に 2 つの独立した欠陥がある。(A) `$(git rev-parse HEAD)` は verify 実行時に評価されるため並行セッション下では無関係なコミットを指しうる (#1133 で記録済み、本セッションで 2 回目の観測)。(B) GitHub Actions は push 先頭コミットにのみ run を作るため、`closes #N` を含む実装コミットには run が存在しない — #1102 の `a1bb7d68` は `gh run list --commit=` が空を返し、run が付いたのは同一 push 末尾の `5aa41ecc` だった。欠陥 B は #1133 が提示した対処方向 (`git log --grep "closes #N"` で SHA 解決) を否定する。加えて `--commit` の有無が `modules/verify-classifier.md` / `skills/issue/SKILL.md:786` / `skills/verify/SKILL.md:224` / `modules/verify-patterns.md:39` の 4 箇所で割れている。 [Filed: #1212]

- **`--non-interactive` 実行で background task の完了通知待ちが再発した (#994 のガードが着地後に破られた)**: #1102 の code phase 1 回目が `bats tests/` をバックグラウンド起動して「完了通知を待つ」とターンを終了し、headless `claude -p` に次のターンが無いため exit 0 で silent no-op になった。`skills/code/SKILL.md:353` が `--non-interactive` では foreground 実行を明示的に指示しており (#994 で追加)、`scripts/run-code.sh:230` は `--non-interactive` を渡しているため適用条件は満たされていた。コスト: 約 25 分の空転 + auto-retry 枠 1/3 消費。現在の指示は Step 8 のテスト実行節で「追加のテストファイルが変更対象を参照している場合」という先行分岐の下にネストしており、その分岐に入らない経路からは視界に入りにくい。 [Filed: #1213]

- **`/code` が retrospective に事実と異なる precondition 診断を書き込んだ (#1053 に続き 2 回目)**: #1102 の Spec の `## Notes > ### Auto-Resolve Log` と `## Phase Handoff > ### Notes for Next Phase` の 2 箇所に「`/code` 開始時点で `phase/ready` が不在」「過去の `/code` 実行が中断したレジューム状態」と記録されたが、GitHub timeline では `phase/ready` は 12:32:09Z〜12:37:17Z の全区間で present で、`/code` 開始 (12:35:40Z) 時点でも存在していた。`phase/code` のラベル付けは timeline 全体で 1 回のみで、示唆された過去の中断実行は存在しない。`skills/code/SKILL.md` の Step 順序自体は正しく、retrospective 執筆時点 (13:10Z) の再観測をフェーズ開始時点の状態として遡及記述した可能性が高い。 [No action: 既存 open Issue #1112 が同一現象を扱っており、2 回目の再発として実測を同 Issue にコメント済み]

- **observation dispatch 1 ラウンドで 5 件中 3 件が前提不成立だった**: cap いっぱいの 5 件を dispatch した結果、#514 PASS / #520 PASS / #562 UNCERTAIN / #589 SKIPPED / #590 SKIPPED。解決不能の原因は 3 類型に分かれる — (1) 実行文脈不一致 (#589/#590 は XL Issue を要求、本バッチの Size は XS/L/S/S)、(2) 発火イベントの誤指定 (#590 の `/audit progress` は `/auto` から呼ばれないため `event=auto-run` では永久に前提が揃わない)、(3) 判定軸が測定不能 (#562 の「減っている」、#590 の「明らかに効率的」)。加えて #514 は判別力のない証拠で PASS した (post-merge manual AC 専用の Implementation Step が存在しないケースで判定したため、元の再現パターンを再現していない)。 [No action: 既存 open Issue #1118 が扱う論点であり、3 類型の切り分けと判別力の弱い PASS の観察を同 Issue にコメント済み]

- **バッチ順序により「修正する側」が「効果を観測する側」より後に処理された**: `/auto --batch 1197 1162 1133 1102` で `scripts/run-merge.sh` を修正する #1133 は、その効果を観測できる唯一の pr route Issue (#1162) より後に処理された。#1162 の merge phase が 11:06:46Z に emit した `test_result` は `passed:1452 / failed:1` で、参照先 CI run 31093146797 は全 job SUCCESS — 修正着地 (`d8556192`, 12:02:19Z) の 56 分前に本バグの実発生を捕捉した形になった。結果的にバグの実証データは得られたが、#1133 の post-merge observation は 1 バッチ分の待ちが発生している。 [Resolved directly: #1133 に実測と SKIPPED 判定の根拠をコメント投稿]

- **run-fact reconciliation がラベル遷移をせず「全 AC チェック済みだが phase/verify」状態を作る**: `apply-run-fact-match.sh` が #1140 / #1136 の AC を auto-check した結果、両 Issue は未チェック AC ゼロになったが `phase/verify` に留まっている。`modules/run-fact-matching.md` はラベル遷移に言及しておらず、checkbox + audit コメントで責務を終える設計。この状態は `/audit stats --retention` の phase/verify 滞留メトリクスに残り続ける。 [No action: モジュールの設計どおりの挙動であり、後続の `/verify N` で解消される。単発観測のため起票せず記録に留める]

- **retro proposal の filter hit rate 0% は重複抑止分を数えていない**: 本セッションの Tier 分類は 1/2/3 = 3/0/0 で filter hit rate 0% だが、Tier 1 の 3 件のうち 1 件は step 9 の重複チェックで既存 #1112 に吸収され Issue を作っていない (action=spec_only)。実際に起票されたのは 2 件。`modules/retro-proposals.md` の hit rate は Tier 2/3 のみを分子に取るため、重複抑止による削減が #1159 の目的 (retro/verify の過剰起票抑制) に効いていても指標に現れない。 [No action: 指標定義の解釈上の注意であり、#1159 の目的自体は達成されている。単発観測のため起票せず記録に留める]

- **silent window が watchdog 上限に接近する phase が 2 件あった**: review 2070s (#1162)、spec 1250s (#1133)。いずれも `.wholework.yml` で引き上げ済みの設定値 (`watchdog-timeout-review-seconds: 5400`, code 7200) の範囲内で完走したが、既定値のままなら kill されていた水準。 [No action: 設定値の引き上げ (#1201 由来の 5400s、d1df1e48 の 7200s) が既に効いており、追加対応は不要]

## Auto Retrospective

### Improvement Proposals

- **patch route の CI 検証 AC が実装コミットの run 不在と HEAD 依存で誤判定する**: `modules/verify-classifier.md:161` が正準形とする `github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) ..."` に 2 つの独立した欠陥がある。(A) `$(git rev-parse HEAD)` は verify 実行時に評価されるため並行セッション下では無関係なコミットを指しうる (#1133 で記録済み、本セッションで 2 回目の観測)。(B) GitHub Actions は push 先頭コミットにのみ run を作るため、`closes #N` を含む実装コミットには run が存在しない — #1102 の `a1bb7d68` は `gh run list --commit=` が空を返し、run が付いたのは同一 push 末尾の `5aa41ecc` だった。欠陥 B は #1133 が提示した対処方向 (`git log --grep "closes #N"` で SHA 解決) を否定する。加えて `--commit` の有無が `modules/verify-classifier.md` / `skills/issue/SKILL.md:786` / `skills/verify/SKILL.md:224` / `modules/verify-patterns.md:39` の 4 箇所で割れている。 [Filed: #1212]

- **`--non-interactive` 実行で background task の完了通知待ちが再発した (#994 のガードが着地後に破られた)**: #1102 の code phase 1 回目が `bats tests/` をバックグラウンド起動して「完了通知を待つ」とターンを終了し、headless `claude -p` に次のターンが無いため exit 0 で silent no-op になった。`skills/code/SKILL.md:353` が `--non-interactive` では foreground 実行を明示的に指示しており (#994 で追加)、`scripts/run-code.sh:230` は `--non-interactive` を渡しているため適用条件は満たされていた。コスト: 約 25 分の空転 + auto-retry 枠 1/3 消費。現在の指示は Step 8 のテスト実行節で「追加のテストファイルが変更対象を参照している場合」という先行分岐の下にネストしており、その分岐に入らない経路からは視界に入りにくい。 [Filed: #1213]

## Filed Issues

- #1212
- #1213
