# L3 Session Retrospective: 56516-1785934632

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-05T12:59:55Z
**Session end**: 2026-08-05T17:30:09Z
**Wall-clock**: 04:30:14
**Route mix**: patch: 0, pr: 3, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 3 |
| Throughput | 0.7 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 1 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2430s |
| Phase silent windows > threshold | 2 (review:1, spec:1) |
| Total token usage | input 5710 / output 286615 |
| Concurrent commits detected | 5 |
| Parent session manual interventions | 0 (実際は 2 — 誤帰属、Findings 参照) |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 2 |
| code-pr | 4 |
| merge | 6 |
| review | 4 |
| spec | 6 |

## What worked

- **recovery 削減 3 件がすべて着地**: #1179 (`recoveries-auto-fire` の既定 opt-out)、#1181 (manual recovery 記録先の集約、−1257 行)、#1180 (fallback catalog 2 エントリ + 検出器 2 パターンの退避) がいずれも merge され、verify も全 AC PASS。
- **#1179 の効果が同一セッション内で 3 回連続して確認できた**: 各 `/verify` の Step 15 で `manual-recovery-review-rerun` が閾値 3 に達していたにもかかわらず、`RECOVERIES_AUTO_FIRE_ENABLED=false` により自動起票が発生せず Recommend 出力のみに留まった。従来設定なら 3 件の Issue が生成されていた場面。
- **#1181 の実装をクリーンに実測できた**: #1180 の merge 後に `--write-manual-recovery` を実行し、Spec のコミットハッシュ・ファイルハッシュとも無変更、deferred stash ファイルも生成されず、記録先が `docs/reports/orchestration-recoveries.md` 1 ファイルのみであることを確認。
- **Tier 3 recovery が 1 回機能した**: #1181 の review phase で `action=retry` により回復し、そのまま完走した。
- **`/merge` の pre-merge AC gate が設計どおり停止した**: 2 件とも「未チェック AC がある状態で非対話モードでは自動承認しない」というポリシーを守り、`decision=blocked` マーカーを残して人手判断に委ねた。バグではなく設計どおりの動作。
- **新規 Issue 起票ゼロで 5 件の実測を既存 Issue に集約できた**: 本セッションで得た知見はすべて #1083 / #1141 / #1146 / #1075 への追記で吸収し、open Issue 数は 83 → 80 に純減した。

## Findings

- **pre-merge AC に `command` 型 verify command を置くと `/merge` を構造的にブロックする**。`/review` は safe mode で `command` を実行しないため UNCERTAIN のまま未チェックで残り、pre-merge AC gate が非対話モードで merge を止める。本セッションの 3 件中 2 件 (#1181 / #1180) が同一原因で merge に失敗し、いずれも親セッションの手動介入 (実質検証 → チェックボックス更新 → `run-merge.sh` 再実行) を要した。加えて `check-translation-sync.sh` は `--fail-if-outdated` なしでは常に exit 0 を返すため、判別力のない「常時 PASS な verify command」でもあった (3 件とも同じものを使用)。`/triage` の AC 監査 Pattern 2 は文字列存在ベースの常時 PASS のみを扱い、exit code 設計に起因するものは検出対象外。 [No action: #1083 に「実測による補正」セクションと AC 2 件を追記済み。補正 1 = 症状は「静かな無効化」ではなく「毎回 merge を止める」、補正 2 = PASS 側にも未捕捉パターンがある]
- **`manual_intervention` event が並行セッションの `session_id` に誤帰属した**。`--write-manual-recovery` を単独の Bash 呼び出しで実行したため PGID ポインタが存在せず、`.tmp/auto-session-current` にフォールバックした結果、同時刻に走っていた別セッション (`65022-1785935372`) の ID で記録された。実際には 2 回発生した親セッション手動介入が Metrics 上は 0 と表示されている。#1075 の当初分析は「誤帰属は in-session emit 経路にのみ現れる」としていたが、**`run-auto-sub.sh` のサブコマンド呼び出しでも起きる**ことが判明した (`skills/auto/SKILL.md` Step 6 の Manual recovery hand-off に pointer 再生成の指示がないため)。 [No action: #1075 に「実測 2」セクション、影響範囲の追記、対応方針 案 D、AC 1 件を追記済み]
- **worktree セッション内では `source` 経由のシェル関数呼び出しとコマンド置換を含む verify command が実行できない**。`/verify` Step 11 の `phase_complete` emit (`source emit-event.sh` → `emit_event`) と、#1181 の AC 8 (`bats --jobs $(nproc ...)`) がいずれも worktree isolation guard にブロックされた。前者は Worktree Exit 後に実行、後者は `--jobs 18` へ分解して回避した。`/verify` は Step 3 で必ず worktree に入る設計のため構造的な制約。 [No action: #1141 に事例 2 として追記済み (AC 1 件も追加)]
- **同一リポジトリで claude CLI セッションが 3 本並行していた**。`ps` + `lsof` で cwd を確認 (うち 1 本が `/auto --batch 1169 1140`)、`git worktree list` にも他セッションの `review+pr-1182 (locked)` が同時に存在。この並行度は既存のどのイベントにも記録されておらず、事後に `events.jsonl` を突合しても復元できない。external kill の最有力仮説 (並行セッション × harness 変化) の検証にとって欠けている観測軸。 [No action: #1146 の「支持する観察」に実測を追記し、「補助計測: 並行度スナップショットのイベント化」を Arm 4a の実行手順に組み込み済み]
- **起票時の分析が軸不足だった (#1180)**。「19 エントリ中 17 件が発火実績ゼロ」を根拠に退避を提案したが、spec が「live 参照元の有無」を第 2 軸に追加した結果、実退避は 2 エントリに留まった。発火実績がなくても `skills/` や `docs/` から手順の SSoT として参照されているエントリは削除すると参照が壊れる。当初 AC に「手順書用エントリの参照可能性」を含めていたおかげで観点が spec に引き継がれた。 [Resolved directly: #1180 の Verify Retrospective に記録。判断としては spec 側が正しく、起票時の分析の粗さを認識に留める]
- **merge 直後に `git pull` せず `--write-manual-recovery` を実行すると旧版スクリプトが動く**。#1181 で発生し、撤去済みのはずの Spec 書き込みと deferred flush が走った (記録内容自体は正しいため削除せず注記を追加)。#1180 では pull してから実行し回避、結果として #1181 実装のクリーンな初回検証になった。 [Resolved directly: #1181 の Spec に経緯を注記し、#1180 では pull を先行させて回避]
- **`docs/reports/*.md` を新規追加する documentation-only PR が CLAUDE.md の言語規約チェックの対象外**。#1180 のアーカイブファイルが英語本文に日本語セクション混在・全角括弧混入の状態で review に到達し、人手の読解でのみ検出された。`check-forbidden-expressions.sh` は固定の deprecated 用語リストのみを見る。 [No action: 既存 checker の拡張範囲であり #1180 のスコープ外。retro-proposals で Tier 3 と分類 (変更対象 1 ファイル、提案自体がスコープ外と明記)]

## Auto Retrospective

### Improvement Proposals

N/A — 上記 Findings はすべて既存 Issue (#1083 / #1075 / #1141 / #1146) への追記、または本セッション内での直接解決で処理済み。新規起票なし。

`retro-proposals` の Tier 分類結果: Tier 1 が 1 件 (`command` 型 Pre-merge AC の構造的検証不能) 得られたが、duplicate check で #1083 と実質同一と判明したため起票せず実測の追記に切り替えた。Tier 3 が 1 件 (`docs/reports` 言語規約チェック不在)。`Tier classification: 1 Tier 1 / 0 Tier 2 / 1 Tier 3 (filter hit rate 50%)`

## Skill Self-Update Propagation Note

Session 中に以下の skill が更新されました (本 session には未適用、次 session から反映):

- skills/auto/SKILL.md: 74cc8f57 → 9ba018e9
- skills/verify/SKILL.md: 232f0837 → 9ba018e9
- skills/code/SKILL.md: (no change)
- skills/spec/SKILL.md: (no change)
- skills/review/SKILL.md: (no change)
- skills/merge/SKILL.md: (no change)
- skills/issue/SKILL.md: (no change)
- skills/audit/SKILL.md: (no change)

いずれも #1181 の実装 (recovery 記録先の集約) による更新。`skills/auto/SKILL.md` は Step 4a の Tier 2/3 記録タイミング記述、`skills/verify/SKILL.md` は Step 12 の Tier 2/3/Manual recovery 判定基準の記述が対象。本セッションの `/auto` および各 `/verify` は更新前の版で実行されている。
