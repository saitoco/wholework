# L3 Session Retrospective: 16210-1786327272

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-10T02:01:50Z
**Session end**: 2026-08-10T04:07:13Z
**Wall-clock**: 02:05:23
**Route mix**: patch: 1, pr: 0, xl: 0, unknown: 1

### Summary

| Metric | Value |
|---|---|
| Issues processed | 2 |
| Throughput | 1.0 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 1650s |
| Phase silent windows > threshold | 0 |
| Total token usage | input 1317 / output 284768 |
| Concurrent commits detected | 7 |
| Parent session manual interventions | 1 |
| verify FAIL → reopen fix cycles | 0 |
| Retro proposal tiers (1/2/3) | 2 / 0 / 0 |
| Merge conflicts | 0 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
| #1130 | M/patch | 2026-08-10T02:01:50Z – 2026-08-10T03:42:27Z | code-patch 35m → issue 8m → spec 48m → verify 7m | — | T1:0/T2:0/T3:0 | Size M→S;Silent 1650s;7 concurrent commits |
| #1318 | ?/? | 2026-08-10T03:49:24Z – 2026-08-10T03:58:37Z | issue 9m | — | T1:0/T2:0/T3:0 | triage のみ (batch 早期終了) |

### Concurrent Sessions Detected

7 commits from concurrent sessions during the run (#1315, #1301 ×2, #1312 ×2, #1310, and one unattributed).

## セッション範囲の注記

`/auto --batch 1130 1318` として開始したが、**ユーザ判断により #1318 の triage 完了時点で batch を早期終了**した (Mac 再起動のため)。#1318 は `phase/issue` (triaged / Size M / pr route) で保留。batch checkpoint (`remaining: [1318]`) は削除せず残してあり、`/auto --batch --resume` で再開できる。

このセッションで新規起票した #1323 / #1325 / #1326 も batch に一度追加したが、同じ判断で外した。

## What worked

- **post-spec Size 降格が正しく発火した** — #1130 は `/spec` の Changed Files 実測により M → S へ降格され、`Post-spec route demotion/upgrade: M → S, remaining phases re-planned` を経て patch route で完走した
- **`--session-id` の in-band ハンドオフが機能した** — batch 親セッションから `Skill(wholework:verify, args="1130 --session-id=16210-1786327272")` で渡した値が issue-scoped pointer に永続化され、`/verify` 内の各 Bash 呼び出しで `AUTO_EVENTS_LOG` が正しく解決された。並行セッション (`41073-1786325705` 等) が `.tmp/auto-session-current` を上書きする状況下でも誤帰属は起きていない (#1075 の対策どおり)
- **worktree の rebase フォールバックが 2 回とも機能した** — `worktree-merge-push.sh` が `main is checked out here` で ref-fetch を拒否された後、in-place merge → rebase フォールバックへ移行して push まで完了した
- **手動復旧が既知原因の即時適用で済んだ** — spec phase の silent no-op に対し、Tier 3 診断 sub-agent を経ずに既知原因 (`background-notification-wait`) を適用して 1 回のリトライで復旧した

## Findings

- **`background-notification-wait` が spec フェーズで 5 例目の再発を起こし、Tier 2 detector は 5 回とも無反応だった** — `/spec 1130` が「バックグラウンドの bats スイート完了通知…を待ちます」と宣言して exit 0 で終了し、`run-spec.sh` が silent no-op として exit 1 に変換した。空転 20 分。detector が検出しない理由を直接実行で 2 つに切り分けた: (a) `detect-wrapper-anomaly.sh:129` の成功主張フレーズ一覧に待機宣言が含まれない (`--exit-code 0` を渡した probe でも出力が空 → 単独で阻害成立)、(b) `silent-no-op` 分岐全体が `EXIT_CODE == 0` でゲートされているが `/auto` が渡すのは wrapper の exit code で、実運用では常に 1。`docs/reports/orchestration-recoveries.md` に `cause: background-notification-wait` が既に 4 件あり今回で 5 件目。 [Filed: #1323]

- **予防側 #1213 のスコープが code/review 限定で spec フェーズを覆っていなかった** — #994 (code) → #1175 (review) → #1213 (code/review) → 今回 (spec) と phase ごとの個別対応が同じ取りこぼしを繰り返している。#1213 の Purpose は「散文ガイダンスへの遵守依存ではなく構造的に防止する」だった。加えて `run-spec.sh` には `run-code.sh` のような built-in auto-retry が無く、同じ失敗モードでも code phase なら時間コストで済むところが spec phase では phase 全体の失敗になる。 [Resolved directly: #1213 を reopen し、spec スコープ追加・phase 横断での担保・`run-spec.sh` の auto-retry 欠如の 3 点をコメントで記録。fix-cycle fast-path が `/issue`/`/spec` をスキップする点も注意として明記]

- **#1130 が追加した回帰テストに検出力がゼロだった** — 修正前パターン (`` `[^`]+` ``, L67) が working tree に入っていることを `grep` で確認した状態で、追加された bats テストと同一 fixture を実行し 0 error / exit 0 を得た。修正後と同一結果。飲み込まれた verify コメントは「消える」だけでエラーにならないため、正常なコマンドを使う限り差が出ない。fixture のコマンドを未知のものへ変えると修正前 0 error / 修正後 1 error に分かれることを実証した。既存 Pattern 2 のどのサブパターンにも該当しない新しい層 (AC は常時 PASS ではなく、証明される成果物が inert)。 [Filed: #1325]

- **`scripts/check-language-convention.py:41` に同型の欠陥が未修正で残存していた** — `INLINE_CODE_PATTERN = re.compile(r"\`[^\`]*\`")` は #1130 が修正した旧パターンと同じくバッククォート連続長を無視する。L83 で本文ストリップに使われており同じサイレント飲み込みが起きる。#1130 の Spec が「対応する場合は別 Issue」として明示的に繰り延べた項目で、本 run で残存を実測確認した。 [Filed: #1326]

- **私が常時 PASS 規約の参照先を誤引用した** — `modules/verify-patterns.md` §9 と繰り返し書いたが、§9 は "When to Use `rubric` vs hard-pattern" であり同ファイルに常時 PASS の規約は存在しない (`grep -c "常時 PASS"` → 0)。正しい SSoT は `skills/triage/skill-dev-verify-audit.md` § Pattern 2。正しい SSoT を読んだ結果、#1130 の事象が既存サブパターン (#1294 の「既存グリーンテスト」) には該当せず #1315 の被覆表に 1 行足す位置づけであると分類が変わった。 [Resolved directly: #1130 に訂正コメントを投稿し、#1325 の本文にも訂正記録を残した]

- **Timeline 表の Size 列が post-spec 降格を反映していない** — #1130 は Size S で完走したが Timeline は `M/patch` と表示し、run facts JSON の `size: "S"` と食い違う。`M/patch` は Size M なら pr route という規約と表示上矛盾し、読み手に routing バグを疑わせる。#1300 の observation AC は「Size/Route 列と Route mix の集計が矛盾しない」を問うており literal には成立するため、機械判定では決められなかった (reconciliation は ambiguous)。 [Resolved directly: #1300 に実測値と AC 文言の是正案 (「Timeline の Size/Route 列が run facts JSON の size/route と一致する」へ寄せる) をコメントで投稿し、次回 /verify の判断材料とした]

- **再注入された skill 本文がディスク版より古かった** — `/verify` の再呼び出し時に注入された SKILL.md に、ディスク版 (`skills/verify/SKILL.md` L374 / L474) に存在する Step 8b「1b. Record the judgment」と Step 9 の executability marker 段落が欠けていた。ディスク版を確認して従うことで回避し、`verify-executability` marker とイベントを正しく出力した。 [No action: ハーネス側の skill 再注入の挙動であってリポジトリ側の欠陥ではない。実行前にディスク版を確認する既存の運用で回避できている]

- **opportunistic verification が 2 回連続で 13/13 SKIP だった** — `/verify 1285` (別セッション) と `/verify 1130` の両方で候補 13 件が全件 SKIP。ただし候補プールが完全に同一なので、2 回分は独立した観測ではない。 [No action: 母集団が同一で独立観測にならない。隣接する run-fact reconciliation の低収率は #1285 に記録済み]

- **run-fact reconciliation が 5 セッション連続で全件 ambiguous** — 今回は候補 30 件 (2 件は上限で truncate)、判定はすべて ambiguous。通算 150 件で auto-check ゼロ。ただし #1300 の 1 件だけは実測が判断に近づき、AC 文言の是正で機械判定可能になる見込みが立った。 [No action: #1300 へのコメントで具体的な是正案を提示済み。母数としての記録に留める]

- **observation dispatch を 78 件全件繰り越した** — end-of-batch scan が 78 件マッチ (通知コメントは全件投稿済み)。L3 規定では上限 5 件を `/verify` へ dispatch するが、ユーザが再起動のため batch 早期終了を選択したため dispatch をスキップした。 [No action: ユーザ判断による意図的なスキップ。次回の auto-run scan で再マッチする]

- **私が retro-proposals module を経由せず直接起票した** — #1325 / #1326 を `modules/retro-proposals.md` の Processing Steps ではなく手動の duplicate check + freshness check で起票したため、`retro_proposal_classified` イベントが出ず Metrics の Retro proposal tiers が 0/0/0 になっていた。 [Resolved directly: 事後に Tier 1 ×2 を emit し 2/0/0 に補正した]

## Auto Retrospective

### Improvement Proposals

- **`background-notification-wait` が spec フェーズで 5 例目の再発を起こし、Tier 2 detector は 5 回とも無反応だった** — 検出しない理由を (a) 待機宣言フレーズ不在 (b) `EXIT_CODE == 0` ゲート の 2 つに切り分け済み。 [Filed: #1323]
- **#1130 が追加した回帰テストに検出力がゼロだった** — Pattern 2 に「検出力ゼロの成果物を証明する AC」のサブパターンを追加し、あわせて当該テストを是正する。 [Filed: #1325]
- **`scripts/check-language-convention.py:41` に同型の欠陥が未修正で残存していた** — #1130 の横展開。 [Filed: #1326]

## Filed Issues

- #1323
- #1325
- #1326

## Skill Self-Update Propagation Note

Session 中に以下の skill が origin 上で更新されました (比較対象: origin/main)。ローカル main が追従できていない場合、本 session 内の以降の実行や次回セッションが更新前の版を使う可能性があります:

- skills/auto/SKILL.md: (no change)
- skills/code/SKILL.md: (no change)
- skills/spec/SKILL.md: (no change)
- skills/verify/SKILL.md: (no change)
- skills/review/SKILL.md: 0eff0d3c → 691e9d72
- skills/merge/SKILL.md: e2636523 → 691e9d72
- skills/issue/SKILL.md: da663154 → 691e9d72
- skills/audit/SKILL.md: (no change)

3 件はいずれも同一コミット `691e9d72` で、並行セッションによる変更です。本セッションの `/verify` は `skills/verify/SKILL.md` を使用しましたが同ファイルは変更されていないため、伝播ギャップの実害はありません。
