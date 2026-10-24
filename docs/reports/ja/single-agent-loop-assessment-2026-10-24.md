# 単一 agent loop の観点からのアーキテクチャ評価 (2026-10-24)

**Report date**: 2026-10-24
**Scope**: Claude Blog の記事「Building agents: When to fold subagents into your main agent loop」(2026-10-22) の観点から、wholework の agent 構成 (フェーズ別プロセス、フェーズ内 sub-agent、`/auto` のオーケストレーションと回復層) を見直す余地を評価する
**Method**: 記事の判定基準と wholework の境界の突き合わせ。`docs/sessions/*/events.jsonl` (2026-06-20〜2026-10-16、80 セッション、484 Issue、20,781 イベント) の集計。skills・modules・既存レポート・Spec の調査
**発端**: 上記記事を読んだうえでの、アーキテクチャ改定の余地の検討依頼
**Source**: https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop

## Summary

改定の余地は大きい。ただし「subagent を畳め」をそのまま当てはめるのではなく、**「フェーズ = GitHub の状態遷移」と「フェーズ = 新しい context window (`claude -p` プロセス)」が同一視されている点を切り離す**のが要点である。ラベル・Spec・PR・レビューは成果物と checkpoint として残し、それを運ぶためのプロセス境界を減らす。

記事は「問題の種類ではなく context で分割せよ」と述べる。wholework は Issue の中をフェーズ (問題の種類) で分割し、Issue をまたぐ親が全体を握っている。context の自然な単位は Issue のほうである。

既存の議論との違い: #598 (in-session 移行) は「sub-agent を **どこで** 動かすか」(`claude -p` から in-session の非同期 sub-agent へ) を問う。今回の記事が示すのは「sub-agent を **いくつ** 持つか」という別の軸である。#1382 は #598 の凍結継続を external kill を軸に判断しており、この軸はまだ評価されていない。

推奨は次の順序である。

1. task-completion eval の整備
2. `/merge` のスクリプト化と `/review` 内の sub-agent 統合
3. spec と code の統合実験
4. 保てれば Issue 単位の単一 loop に進む

## 1. 記事の要点 (wholework に関係する部分)

- **subagent を残すべき条件**は 3 つ。(1) 単一 loop で context の肥大による性能低下が測定できる、(2) 破棄できる新しい context で並列処理したい、(3) ツール選択に失敗する、または system prompt 内の指示が矛盾している
- **分割の仕方**: 分割するなら context で分ける。周囲にほとんど依存しない作業を渡し、コンパクトな結果を返させる。良い候補は独立した調査経路、きれいな interface を持つ部品、ブラックボックス検証。問題の種類で分けると「伝言ゲーム」になり、引き継ぎのたびに精度が落ちる
- **単一 loop の設計**
  - 計画を書くモデルがそのまま実行も担い、途中で計画を変えられる
  - 手順は skills に、ハードな制約 (バリデーション、承認ゲート) はツールに移す
  - 機械的な部分は loop が呼ぶツールの中のコードで処理する
  - 「ルールのカタログから計画を書き換えるコードのステップ」は不要になる
- **移行の方法**
  - まず小さな end-to-end eval を作る (10 件のゴールデン例で十分)
  - 1 つずつ統合し、最終スコアだけでなく結果が反転したタスクを確認する
  - 各タスクを複数回実行する。記事の事例では、破綻は 2 回に 1 回しか出なかった
- **失敗パターン**: context の受け渡しによる欠落、subagent の乱立、フランケンプロンプト (各自が一文ずつ足して矛盾する)、局所的すぎる eval、レイテンシ

## 2. 既存の判断との関係

| 既存の判断 | 内容 | 本レポートとの関係 |
|---|---|---|
| `docs/reports/ja/project-structural-review-2026-07-31.md` | 構造問題の中心を「L1/L2 境界の spawn-and-block 実行モデル」と診断した。補償層 (回復・検出系) が scripts の 30〜35% を占めると指摘 | 同じ境界を、記事の「境界の数」の観点から見直す |
| #598 / #1382 (2026-08-18) | #598 は `/auto` 子フェーズの in-session 移行。#1382 は (1) H-a 未確定、(2) respawn 補償層が 17/17 で機能中、を理由に凍結継続とした | #1382 は、#598 の動機を「external kill 回避」と「それ以外」(spawn-and-block のオーバーヘッド、文脈保持、フェーズ間の受け渡し) に分けた。そのうえで前者で判断している。記事は後者を評価する材料になる |
| `docs/reports/ja/phase-duration-analysis-2026-08-10.md` | LLM フェーズの時間増は出力トークン増が直接の原因で、出力の 9 割以上は調査と思考。merge は指示量が増えても時間は増えなかった | フェーズごとに context が新しくなるため、同じ調査が繰り返されている可能性がある (仮説。eval で測る) |
| `docs/tech.md` § fork context vs main context | fork の根拠は「独立性と安全性」。1M context GA 以降、容量の動機はほぼ消えたと明記している | 記事の条件 1 (context 肥大) は、wholework ではすでに弱い根拠であることと整合する |

#598 と選択肢 C (後述) は直交する。#598 はフェーズ別の分割を保ったまま、実行面を変える案である。記事の段階でいえば「subagent をツールとして呼ぶ」にとどまり、記事が挙げる残存失敗 (要約での欠落、入れ子 loop の遅延、専門ごとのプロンプト) が残る。C は境界の数そのものを減らす案で、実行面は `claude -p` でも in-session でもよい。

## 3. 記事の判定基準を wholework に当てる

記事が「よく見る設計」として挙げる構成は、ほぼそのまま wholework に対応する。

| 記事の例 | wholework |
|---|---|
| 意図分類器 | `/triage` (Type/Size/Priority/Value) |
| 固定の多段パイプライン | issue→spec→code→review→merge→verify |
| ユーザーセグメント別の振り分け | Size バケット (XS〜XL) |
| 別々の分岐 | patch / pr / operate ルート |
| 上に載るオーケストレーター | `/auto` + `run-auto-sub.sh` |

ただし wholework では、この構造の一部はモデルのための足場ではない。人間と GitHub のためのガバナンスの記録であり、製品そのものである (`docs/product.md` の「governance-and-verification harness」)。そこで境界ごとに「誰のための境界か」で判定した。

| 境界 | 分割の軸 | 判定 |
|---|---|---|
| code → review | 生成と検証 | **残す**。記事が推奨する generator-verifier (ブラックボックス検証) |
| XL / batch での Issue 並列 | 独立した作業 | **残す**。条件 2 |
| `frontend-visual-review` | 画像で context が膨らむ | **残す**。条件 1 |
| spec → code | 計画と実行 | **一番の統合候補**。「計画を書くモデルが実行も担う」がそのまま当てはまる |
| issue → spec | 要件と設計 | 統合候補。`/auto` では常に連続で呼ばれ、同じデータを扱う |
| review → merge | 機械的な処理 | LLM フェーズをやめ、ツール (スクリプト) にする |
| `/review` 内の review-spec / review-bug / review-light | 問題の種類 | 統合候補。review プロセス自体がすでに code から独立している |
| `/issue` の issue-scope / risk / precedent | 観点 | 統合候補。非対話モード (`run-issue.sh`) では実行されていない |
| `/auto` の回復 (Tier 1〜3 + `modules/orchestration-fallbacks.md`) | ルールカタログ | 記事の「ルールのカタログから計画を書き換えるコードのステップ」に当たる |

統合がうまくいきそうな材料も、すでにある。

- **XS はすでに spec を省いている**。`/code` が計画と実装を 1 つの loop でこなしている (`skills/auto/SKILL.md` Step 3)
- **`/review` の Sub-agent Result Fallback**は、sub-agent の結果が取れなければ orchestrator が自分でレビューする経路である。統合版に当たるものがすでに動いている

## 4. 実データで見るプロセス境界のコスト

`docs/sessions/*/events.jsonl` の集計である。対象はセッション retrospective がコミットされた分のみで、同じ Issue の再実行を含む。所要時間は同じ `(session_id, issue, phase)` の最後の `phase_start` から `phase_complete` までで算出した。

### 4.1 所要時間と出力量

| phase | n | 所要時間の中央値 | 出力トークンの中央値 |
|---|---|---|---|
| spec | 303 | 17.4 分 | 90,664 |
| code-pr | 172 | 26.4 分 | 36,631 |
| review | 187 | 18.5 分 | 37,853 |
| code-patch | 161 | 18.3 分 | 23,589 |
| issue | 306 | 7.5 分 | 28,882 |
| merge | 186 | 3.4 分 | 4,222 |
| verify | 400 | 1.9 分 | (親セッション内のため記録なし) |

M ルートでは、中央値の合計が約 68 分になる。その間に `claude -p` が 4 回 (spec、code、review、merge) 起動する。

### 4.2 境界に起因する障害

| 指標 | 値 | 備考 |
|---|---|---|
| watchdog kill | 13 件 | 記録上は 19 件。うち 6 件 (2026-07-29、#1060、timeout 2〜10 秒) は bats テストによる偽イベント (#1136) なので除外した。内訳は code-pr 5、merge 4、spec 3、review 1 |
| 手動介入 (`manual_intervention`) | 57 件 | うち respawn 系が 34 件。多い順に review 14、spec 9、code-pr 4 |
| Tier 回復 (`recovery`) | 27 件 | うち 11 件失敗。merge は 6 件中 5 件失敗 |
| code の silent no-op による自動リトライ | 91 回 (49 Issue) | code フェーズ 333 回に対して。プロセスは正常終了したのに成果がない状態 |

merge は出力トークンの中央値が 4,222 しかない。それでも独立プロセスとして、watchdog kill 4 件と回復失敗 5 件を抱えている。

### 4.3 維持にかかる工数

- `docs/spec/` 899 件のうち約 180 件 (約 2 割) が、ファイル名に watchdog / recovery / fallback / handoff / retry / wrapper / notification などを含む。キーワードで拾っただけの粗い推定である
- 2026-07-31 の構造診断は、回復・検出系スクリプトを約 4,000 行 (scripts 全体の 30〜35%)、リトライ・回復機構を 15 系統と数えている
- `modules/orchestration-fallbacks.md` は 915 行、`skills/auto/SKILL.md` は 1,523 行ある

### 4.4 記事の「伝言ゲーム」に当たる事例

- **#951 (`modules/costly-step-protocol.md`)**: `/spec` が事前承認した手順を、`/code` が独自に考え直して保留した。それでも AC は実行済みの書き方のまま残った (#903、#939 で再発)
- **`/review` Step 10 の結果受け渡し機構**: 名前なしでの起動、result file を 2 つ目の受け渡し経路にすること、Sub-agent Result Fallback、TaskStop が積み重なっている (#1478 / #1481 / #1518 / #1522)
- **headless では次のターンがない**: `claude -p` には次のターンがないため、background 完了通知を待つ処理が成り立たない (`modules/execution-context.md` § Re-invocation Guarantee)。silent no-op の主因クラスでもある (2026-07-31 構造診断 §1)

## 5. 記事がそのまま当てはまらない点

- **対象の違い**: 記事は Claude Platform 上の顧客向けエンタープライズ agent を想定している。wholework は Claude Code を OAuth 認証で動かしており、task budgets は使えない (`docs/reports/task-budgets-spike.md`)
- **肥大化の原因の違い**: 単一保守者なので、Conway の法則は直接は効かない。代わりに「retro → 改善提案 → SKILL.md に一文追加」というループが、フランケンプロンプトと同じ形の肥大を生んでいる。Distributable-first 原則は、改善を skill の文章として積む方向に働く

  | skill | SKILL.md | 参照モジュールの合計 |
  |---|---|---|
  | issue | 876 行 | 3,523 行 |
  | spec | 1,144 行 | 5,137 行 |
  | code | 975 行 | 4,937 行 |
  | review | 1,168 行 | 3,729 行 |
  | merge | 387 行 | 1,420 行 |
  | verify | 1,023 行 | 3,970 行 |
  | auto | 1,523 行 | 4,110 行 |

- **製品としての構造**: フェーズ・ラベル・Spec・PR は人間がいつでも介入できる checkpoint であり、捨てる対象ではない。記事の主張は「モデルのための構造」に向けたものと読むべきである
- **フェーズ別の調整**: 単一 loop にすると、フェーズごとの model/effort 調整 (spec は max、merge は low) はできなくなる
- **未計測の点**: 1M context で全フェーズを通したときの品質は、まだ測っていない

## 6. 選択肢

### E. task-completion eval の整備 (すべての前提)

記事が最初の一歩としているものである。wholework は材料をすでに多く持っている。

- AC と verify command が、そのまま機械採点できる grader になる
- `auto-events.jsonl` は、記事が勧める「重要イベントをタイムスタンプ付きで記録し、後で再生する」形そのもの
- 過去の Spec が 899 件ある

進め方の案は次のとおり。

- **題材**: 過去の Issue から 10〜15 件を選び、マージ前の base commit から再実行する
- **選び方**: Size (XS〜L) を散らし、review で MUST が出た例、verify が FAIL した例、costly step を含む例を入れる
- **採点項目**: AC の pass 率、既知の不具合の検出率、所要時間、出力トークン、介入回数
- **実行回数**: 各 2 回以上実行し、反転したタスクを個別に確認する
- **最大の工数**: GitHub への書き込みを切り離した再実行環境 (fixture repo、または `gh` 書き込みのモック) づくり

### A. フェーズ内 sub-agent の統合 (小規模)

**A1 `/review`**

- review-spec / review-bug / review-light を、review プロセス自身のレビューにまとめる。code からの独立性は、review プロセスが別 context であることで保たれる
- 敵対的な検証 (10.3) だけは任意で残す
- Step 10 の結果受け渡し機構の大半が不要になる
- リスク: Opus の sub-agent から Sonnet の review プロセスに移るため、検出力が下がる可能性がある。`run-review.sh` を Opus にするかは eval で決める

**A2 `/merge`**

- LLM フェーズをやめ、決定的なスクリプトにする (CI 待ち → pre-merge AC ゲート → merge → ブランチ削除)
- LLM を呼ぶのは conflict と CI 失敗のときだけにする
- 記事の「機械的な部分は loop が呼ぶツールの中のコードで」に当たる。2026-08-10 の分析でも、merge の時間は指示量に依存していなかった

**A3 `/issue` の 3 つの観点 agent**

- 調査観点を skill の参照ファイルにまとめる
- 並列化が必要なら、観点ではなくコード領域ごとに分けて調べる (context で分割する)

### B. 密結合フェーズの統合 (中規模)

**B1 spec と code を 1 プロセスにまとめる** (XS〜M を `/auto` 経由で回すとき)

- 最初のターンで Spec を書き、実装しながら改訂する。Spec ファイルと Issue コメントは成果物として残す
- L と `auto-stop-at=spec` (人間の承認を挟む場合) は、これまでどおり分ける
- 根拠
  - 記事の「計画を書くモデルが実行も担う」が最も直接に当てはまる
  - XS ではすでに機能している
  - #951 型の食い違いが構造的に起きなくなる
- 失うもの: spec を `max` effort で回して得ていた設計品質。eval で最も注意して見るべき点である
- 測りたい仮説: spec の調査と code の再調査が重複していれば、合計の出力トークンが減る

**B2 issue と spec も同様にまとめる** (未ラベルの Issue を `/auto` で回すとき)

### C. Issue 単位の単一 loop (大規模、記事の最終形)

**構成**

- 1 Issue に 1 つの context を割り当て、triage から verify までを同じ loop で進める。各フェーズの手順は、skill を必要なときに読み込む形にする
- review だけは独立した sub-agent として呼ぶ (generator-verifier)
- ラベル・Spec・PR は、引き継ぎの経路ではなく「出力と checkpoint」になる
- `/auto` の親は、Issue を振り分けるだけの薄い dispatcher になる。`run-auto-sub.sh` の「Issue ごとに子プロセス」という形はむしろ記事に合っているので、中身のフェーズ連鎖だけを 1 つの loop に置き換える

**得られるもの**

- review の MUST 指摘や verify の FAIL を、同じ context のまま修正できる
- Phase Handoff、フェーズごとの consumed comments、フェーズごとの silent no-op と respawn の多くが不要になる

**課題**

- L では context が長くなる
- model/effort は Issue 単位で、Size に応じて選ぶ形になる
- 手動 AC の確認 (AskUserQuestion) は親プロセスに戻す必要がある
- プロセスの寿命が延びるため、kill されたときの損失が大きくなる。external kill にさらされる量が減るかどうかは不明である (kill までの時間は一定でない。`docs/reports/external-kill-investigation.md` F5)。GitHub の状態から再開する仕組み (`reconcile-phase-state.sh`) はそのまま使える

### D. 回復の判断をルールカタログからモデルへ移す

- `modules/orchestration-fallbacks.md` と `apply-fallback.sh` の既知パターン照合をやめる
- 代わりに、親モデルが reconcile の JSON と wrapper のログを直接見て判断する
- external kill の主因は上流側にある疑いが強いので、回復の仕組みをゼロにはできない。C を選べば、境界が減るぶん自然に小さくなる

### F. フランケンプロンプト対策 (C を選ぶなら必須)

- retro から出てきたルールは、まず検査スクリプトや hook として実装し、文章のルールを増やさない方針にする (記事の「ハードな制約はツールへ」)
- 記事で紹介されている `/claude-api prompt-audit` で、古いモデル向けの指示を定期的に整理する。`docs/reports/de-prescription-audit.md` と `docs/reports/literalism-audit.md` の延長にあたる
- C では全フェーズの手順が 1 つの loop に載るので、この規律が品質に直結する

## 7. 推奨する順序と判断基準

| 段階 | 内容 | 次へ進む条件 |
|---|---|---|
| 1 | **E**: 10 件のゴールデンセットと再実行の手順 | 現行構成で各タスク 2 回のベースラインが取れている |
| 2 | **A2 → A1** | AC の pass 率と既知不具合の検出率が下がらない。所要時間と介入回数が減る |
| 3 | **B1** (XS〜M) | 同上に加えて、反転したタスクを個別に確認して説明がつく |
| 4 | **C**、あわせて D と F | B1 で品質が保てている |

どの段階でも残すもの:

- code と review の独立
- Issue をまたぐ並列処理
- `frontend-visual-review`
- GitHub の状態を SSoT にした再開性

## 8. 次のアクション候補

- E を Issue にする (eval の設計と再実行環境づくり) → **#1552 として起票済み**
- A2 (`/merge` のスクリプト化) を Issue にする → **#1553 として起票済み** (#1552 を blocked-by に設定)
- #598 にこのレポートへのリンクをコメントし、「境界の数を減らす」軸の再評価トリガーを追加するか検討する → **コメント済み** (2026-10-25、トリガーの追加は提案のみで本文は未変更)。#598 自体の凍結継続とは独立に、C を別 Issue として起こす選択肢もある

## Appendix: 再現方法

- イベントは `docs/sessions/*/events.jsonl` を連結して集計した。`.tmp/auto-events.jsonl` (gitignore 対象) は使っていない
- watchdog kill の除外条件: `issue=1060` かつ `timeout_setting` が 10 以下 (#1136 の偽イベント)
- silent no-op は `code_retry_fire` の `trigger_reason=silent_no_op` を数えた
- Spec ファイル名のキーワード集計では、`skill` に含まれる `kill` を誤検出しないように除外した
