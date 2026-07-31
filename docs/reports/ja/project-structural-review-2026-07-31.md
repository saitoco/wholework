# Wholework プロジェクト構造診断 (2026-07-31)

**Report date**: 2026-07-31
**Scope**: downstream の実 Web プロジェクトでの約 1 ヶ月の実運用を経た時点での俯瞰診断 — orchestration 信頼性 (外部 kill / silent no-op)、Issue backlog 動態、アーキテクチャの構造的問題の有無
**Method**: 6 観点の並列調査 (dynamic workflow, 6 agents / 174 tool calls)。対象: 主要ドキュメント・open issues 69 件・7 月クローズ 134 件・主要 skills/scripts・session retrospectives・Loop Engineering framework
**Filed**: #1135 (外部 kill 根本原因の tracking)、#1136 (bats イベントログ汚染)

## TL;DR

アーキテクチャに構造的問題は**ある**。ただしそれは 6 フェーズパイプラインや L0 (GitHub SSoT) ではなく、**L1/L2 境界の spawn-and-block 実行モデル**に集中している。外部 kill の原因は Loop Engineering ではなく、時期的には Sonnet 5 リリース (6/30) / Fable 5 再デプロイ (7/1) 直後の 7/2 に初出しており、外因性 regression の疑いが濃厚。「問題の増殖」の主成分は retro 自動起票による**可視化の増殖**であり、これ自体が backlog を発散させる第二の構造問題になっている。最重要の発見: **#598 (in-session 移行) の再評価トリガー「kill 率 5.7% から悪化」は 7/23 の 4/4 (100%) で定量的に発火済みだが、icebox のまま再評価されていない。**

## 1. 外部 kill / silent no-op の実態

### 外部 kill — 6 月 0 件 → 7 月 30 回超、原因調査は事実上停止中

- 時系列: 6 月は外部 kill 0 件 (watchdog の自己 kill 12 件は設計通りの別クラス)。7/2 初出 → 7/12-16 に 19 件クラスタ → 7/22-23 はバックグラウンド wrapper の kill 率 100% (pr route 4/4) → 7/29 に 5 件 (通算 30 回目) → 7/31 も 3 件継続中。
- 確定事実 (docs/reports/external-kill-investigation.md): プロセスグループごと SIGKILL、EXIT trap 不発火、OOM/jetsam 証拠ゼロ、全件 `/auto --batch` セッション内で発生・単発実行では 0 件。wrapper_exit_code は全件 "unknown" で、この観測経路は構造的にデータを生めないことが判明済み。
- 調査レポートは 7/15 更新で停止し「respawn 自動化に方針転換、根本原因追跡は deferred」と明記。open の kill 系 Issue (#1070 / #1081 / #1093) は全て根本原因調査を Out of Scope 宣言しており、根本原因を追う open Issue は 0 件だった → **#1135 として起票済み**。
- 未分析の手がかり: #1045 (7/23) で導入した wrapper_alive heartbeat のデータ 31 events + kill 5 件分が未分析。暫定分析では「subprocess 実行中の kill と phase 間制御フロー中の kill が混在 = wrapper の状態と無関係な無差別 kill」で、H-a 一般形 (Claude Code harness の per-background-task lifecycle) を支持する形。
- スループット実害: 6/15 の 28 issues・4.4 issues/hr・介入 0 に対し、7 月後半は 2-3 issues・0.2-0.7 issues/hr。7/29 は wall-clock 5h50m の大半が respawn ceremony に消費された。「以前の --batch は堅牢だった」という体感は実データで裏付けられる (ただし 6 月は XS/S 大量バッチ、7 月は M/L pr-route 中心という Issue 構成差の割引が必要)。

### silent no-op — 主因クラスは特定済みなのにクラス対策が未着地

- 主因は決定論的な設計欠陥: headless `claude -p` には background task の完了通知で再呼び出しされる仕組みがないため、子セッションが「バックグラウンド実行して通知を待つ」を選んだ瞬間に silent no-op が確定する。#465 (6 月起票) が未解決のまま #908 (7/6)・#1097 (7/29) と同型再発。#1123 自身が「この機構を一箇所で禁止する横断規約がない」と診断している。
- 検出側にも fail-open の穴: `run-code.sh` L293 で reconcile 呼び出しが `2>/dev/null || true` のため、reconcile 自体が失敗すると silent no-op が「成功」として素通りする。

## 2. 「Loop Engineering から問題が増殖」の因果評価

| 仮説 | 評価 | 根拠 |
|---|---|---|
| (a) loop 化が kill/no-op を作った | 弱い | Loop Engineering 由来の欠陥は計上・帰属バグ (#1047/#1049/#1075/#1098) に限られ、kill の原因ではない。3-Tier recovery は loop 以前 (4 月) から存在 |
| (b) 観測性向上による可視化 | **最有力** | L3 auto-retrospective (6/20 稼働) 以降、従来消えていた anomaly が全件 Issue 化。7 月起票 188 件の 82% が retro 起票 |
| (c) 運用量増による露出増 | 中程度 | pr-route の長時間 wrapper (15-67 分) を含む batch への露出が増えた |
| (d) 外因性 regression | **kill についてはこれが最重要** | kill 波の開始 (7/2-7/12) は Loop Engineering (6/20) と 3 週間ずれ、Sonnet 5 / Fable 5 デプロイ (6/30-7/1) と一致 |

副作用は実在する: retro 自動起票 3 系統 (auto retrospective / verify retro-proposals / recoveries auto-fire) の生成レートが消化レートを超えた。open 69 件中 57 件 (83%) が retro/verify、うち 48 件は 7/29-31 の 3 日間起票。7/29 は単日 37 起票 vs 10 クローズ。6 月は高スループット (クローズ 288 件) がこの動態を覆い隠していただけで、均衡は「メタ issue 消化に容量を使い続けること」で維持されていた。downstream プロジェクト由来の web 検証系は open のわずか 3%、7 月クローズの 9%。

## 3. 構造的問題 — 3 つ

### 問題 A: spawn-and-block 実行モデルが単一障害点 (最重要)

親 LLM セッション → run-auto-sub.sh (1,106 行) → run-code.sh 等 → watchdog → `claude -p` の 4-5 層 spawn 構造。プロセスグループごと SIGKILL されると内側の全防御層 (retry-on-kill / EXIT trap / watchdog) が同時に死に、L2 側からは原理的に観測も防御もできない (investigation.md F6)。silent no-op (headless 通知欠如) も同じ境界の問題。モデル世代が background 実行を好む方向に進化しているため、この impedance mismatch は放置すると悪化する。

### 問題 B: 補償層の発散 — 「信頼性のための層」が最大のバグ供給源に

- 回復・検出系スクリプトは約 4,000 行 = scripts 全体の 30-35% で、フェーズ実行本体 (11%) の約 3 倍。リトライ/回復機構は 15 系統並存、retry 層は二重 (run-auto-sub.sh と run-code.sh の両方が `run_with_retry_on_kill` で包み、early-kill 時に leaf が最大 4 回起動され得る)、3-Tier recovery は SKILL.md prose と bash に二重実装で同期は人手。
- 実績: recovery 記録機構 (--write-manual-recovery) だけに 3 週間で 8 issues (#984→#1094)、anomaly 検出器の誤検出モグラ叩きに 5 issues (#916→#1105)、recovery の main 直接 push が merge conflict を生んだ実績 3 件 (#890/#1005/#1006)。7 月の churn 上位は全てメタ層 (orchestration-recoveries.md 46 commits、run-auto-sub.sh 21 commits)。
- 修正チェーンの実例: #1050 (exit 2 = PENDING 導入) → #1115 (呼び出し側が exit 2 を知らず recovery 誤発火) → #1128 (契約整合) → #1133 (その merge の CI で新バグ発見) — 36 時間で 3 リンク。

### 問題 C: retro 起票の粒度とガバナンスのデッドレター化

- 起票が症状単位のため、同一根本機構が別トリガーで別 issue として再発 (#1097/#1103 を #1123 が指摘)。症状個別対処 47 件 (68%) vs 根本構造変更 6 件 (9%) で 8:1 の偏重。
- 構造修正の二大レバーが両方停止中: #483 は kill 波以前のデータ (2026-05, #485) に基づき「fork 維持」に rescope 済み、#598 は再評価トリガー発火済みなのに icebox で 48 日間コメントゼロ。トリガーを書いても発火を監視する仕組みがない。
- 判断の土台も損傷: Metrics は多重故障 (#1006/#1007/#1049/#1098) に加え、tests/claude-watchdog.bats が本番 auto-events.jsonl に偽 watchdog_kill を混入 (7/29・7/31 に各 6 件、7 月の純正 watchdog_kill は 1 件のみ) → **#1136 として起票済み**。docs/stats の健康診断も 6/27 で停止。

## 4. アクションプラン

### Phase 0: 止血 (即時)

1. downstream プロジェクトの運用回避策: 根本対処まで pr-route の長時間 --batch を避け、patch-route 中心 + 単発 /auto に寄せる (kill は 100% --batch 限定という事実に基づく)。
2. 補償層モラトリアム: orchestration-fallbacks.md への新パターン追加・新リトライ機構の導入を凍結し、構造判断に集中する。
3. retro 起票の fan-out 制御: batch 1 回あたりの自動起票に上限またはセッション単位の umbrella issue 集約を導入。

### Phase 1: 原因確定 (1 週間以内) → #1135

4. wrapper_alive データ分析 (31 events + kill 5 件分) を external-kill-investigation.md に Update として追記。
5. 決定的切り分け実験: 同一 batch を harness の background Bash と素のターミナル (nohup/setsid/tmux) から起動して kill 再現性を比較。harness 内でのみ kill するなら H-a 一般形が確定し、Anthropic への報告材料 (30 回分の再現データ) が揃う。
6. 根本原因 tracking issue → **#1135 起票済み**。

### Phase 2: 構造判断 (Phase 1 の結果を受けて)

7. #598 を icebox から解凍して正式再評価 (トリガー発火済み)。#483 の rescope も 7 月データで再審査。全面移行の前に、kill が最も集中する review phase を Task tool 非同期 sub-agent に移す限定 spike で kill 消滅・可観測性・bias 伝播の 3 点を実測。
8. silent no-op のクラス対策: 「headless 実行での background 完了通知待ち禁止」を modules/ に横断規約として 1 箇所定義し、#465/#1097/#994 系をクラスごとクローズ。run-code.sh L293 の fail-open (reconcile 失敗 → 成功扱い) を塞ぐ。
9. 契約の SSoT 化: exit code / PREVIEW_URL 等の wrapper 契約を、run-*.sh と SKILL.md の双方が消費する機械可読な単一テーブルにする (#1020/#1115/#1128/#1108 の同型再発を止める)。

### Phase 3: backlog と観測層の健全化 (2 週間以内)

10. retro/verify 57 件の一括 triage: 根本原因クラスタ (spawn-and-block 起因 / 補償層自体の欠陥 / SSoT ドリフト / 並行セッション guard / verify 精度) でタグ付けし、「#598 移行で不要になるもの」を分離。同一クラスタ N 件で症状起票を止めて構造 issue へ昇格するゲートを導入。
11. 観測層の信頼性復旧を XL 親 issue に統合: #1006/#1049/#1098 + **#1136 (起票済み)** を束ね、「Metrics 全行が events.jsonl と突合一致」を AC に。直るまで L3 Metrics を意思決定に使わない。
12. /audit stats --retention を再実行 (6/27 で停止中) し、phase/verify 滞留の現在値を確定。#465 型の「実装済みなのに manual AC 1 件で 72 日 open」を retire escalation で終端。

## 5. 補足: 実証されたもの

L0 (GitHub SSoT) は kill 通算 30 回全件からの復旧に成功しており、「label-as-SSoT + milestone resume」というアーキテクチャの中核主張はむしろ実証された。kill が毀損しているのは正しさではなく時間である。これは「設計が間違っていた」話ではなく、実行サーフェスの選択 (spawn-and-block) が harness の進化と衝突した話であり、#598 の方向 (harness に沿う in-session 非同期 sub-agent) への移行判断材料はすでに揃っている。

## Appendix: 調査で確認した主要数値

| 指標 | 値 |
|---|---|
| 回復・検出系スクリプト | 約 4,000 行 (全 scripts の 30-35%、フェーズ実行本体の約 3 倍) |
| リトライ/回復機構の系統数 | 15 (fallback カタログの名前付きパターン 19) |
| run-auto-sub.sh の肥大 | 6/14: 228 行 → 6/29: 724 行 (2 週間で 3.2 倍) → 7/31: 1,106 行 |
| orchestration recovery エントリ | 6 月 16 件 → 7 月 42 件 (respawn 系 24 件は 7 月新出) |
| 外部 kill | 6 月 0 件 → 7 月通算 30 回超、全件 --batch セッション内 |
| 純正 watchdog kill | 6 月 12 件 → 7 月 1 件 (故障モードが外部 kill に置換) |
| open issues | 69 件中 retro/verify 57 件 (83%)、downstream 由来 2 件 (3%) |
| 7 月フロー | 起票 188 件 (retro 82%) / クローズ 134 件。7/29 単日は起票 37 vs クローズ 10 |
| throughput | 6/15: 4.4 issues/hr → 7 月後半: 0.2-0.7 issues/hr |
| SSoT の分散 | 最低 8 系統 (labels / checkpoint / batch state / git / PR / events.jsonl / Spec 記録 / wrapper log) |
