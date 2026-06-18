[English](../../reports/loop-engineering-wholework-2026-06-18.md) | 日本語

# Loop Engineering を Wholework に適用する

**Report date**: 2026-06-18
**Author**: Addy Osmani 「Loop Engineering」 と suwash 氏 Zenn 翻訳/拡張記事を読んだユーザーからのトリガーで起こしたメモセッション
**Status**: 分析メモ — 最終ロードマップではなく、product/spec 判断のインプットとして扱う

**参照ソース**:
- Addy Osmani, *Loop Engineering* (Substack, 2026-06-08) — https://addyo.substack.com/p/loop-engineering
- suwash, *Loop Engineering 入門* (zenn.dev/suwash/articles/loop-engineering_20260610) — `loop-audit` / `loop-init` などの実装ガイド
- Wholework リポジトリ HEAD ( `f9a1629` )

## 1. Loop Engineering とは何で、なぜ Wholework に持ち込むのか

Osmani の主張はシンプルだ。エージェントに毎ターンプロンプトを送る人間であるのをやめろ。あなたの代わりにエージェントにプロンプトを送るシステムを設計しろ。テコの支点が harness engineering (1 体のエージェントが動く環境を作る) から loop engineering (複数の harness を時系列で駆動するスケジューラ・ディスパッチャ・検証者・メモリ) へ 1 階上がる。

ループは **5 つの構成要素 + memory** に分解される:

| # | 構成要素 | 役割 |
|---|----------|------|
| 1 | **Automations / scheduling** | 心拍。cron / `/loop` / `/goal` / hooks がプロンプト無しに作業を発火する |
| 2 | **Worktrees** | 並列エージェントがファイル上で衝突しない |
| 3 | **Skills** | プロジェクトの意図 ( `SKILL.md` )。1 回書いて毎回読まれる |
| 4 | **Plugins / Connectors** | issue トラッカー、CI、Slack、ブラウザに MCP で届く |
| 5 | **Sub-agents** | 書く側と検証する側を分ける。書いたモデルは自分を採点しない |
| + | **Memory** | 会話の外にある markdown / board / JSON。モデルは忘れる、リポジトリは忘れない |

suwash 氏の Zenn 記事はこれを実装レベルに落とす。リポジトリの準備度を採点する `loop-audit` CLI、scaffolding を作る `loop-init`、**Autonomy Tier (L1 Report / L2 Assisted / L3 Unattended)** の階段、具体的な `STATE.md` / `LOOP.md` パターン、トークン予算、denylist、`acting_on:` キーによる multi-loop 衝突検出 — 全部入っている。

Wholework のビジョン ( `docs/product.md` ) は *GitHub 上で自律的なコーディングエージェントを安全に走らせるための governance-and-verification harness* と書かれている。語彙は既にかなり重なる — harness、sub-agents、retrospective。だが両者は別の階に座っている。本レポートが問うのは「Loop Engineering のどこまでが *既に* Wholework にあり、残りの拡張余地はどこか」だ。

## 2. 5+1 ブロックを今の Wholework にマッピングする

結論を先に: **Wholework はブロック 2・3・5・6 (Memory) はプロダクション品質で揃っており、ブロック 4 (Connectors) は GitHub-CLI レイヤーで深いが横展開が浅く、ブロック 1 (Automation/heartbeat) は「手動で叩くオーケストレータ」止まり**。この非対称性こそが面白い。

### 2.1 Worktrees — フル実装

`modules/worktree-lifecycle.md` が `/spec` / `/code` / `/review` / `/merge` / `/verify` 共通の Entry/Exit ライフサイクルを提供する。ブランチ命名 SSoT は `worktree-<phase>+issue-N` ( `modules/phase-state.md` )。`scripts/worktree-merge-push.sh` がロック獲得 + ff-only マージ + コンフリクトマーカ検査 + push を 1 アトミック単位で実行する。XL Issue は `blockedBy` 依存グラフでゲーティングされた sub-issue ごとの worktree 分離下で並列実行される ( `skills/auto/SKILL.md`, `scripts/get-sub-issue-graph.sh` )。

他の Skills フレームワークと比較してもこれは厚い。衝突は単に分離されるだけでなく、`modules/orchestration-fallbacks.md` の `ff-only-merge-fallback` や worktree 内 rebase 経路で能動的に解消される。

### 2.2 Skills (意図の永続化) — フル実装

10 個のスキル ( `auto`, `audit`, `code`, `doc`, `issue`, `merge`, `review`, `spec`, `triage`, `verify` ) を `modules/` 配下の 36 の共有モジュールが支える。adapter-resolver パターン ( `modules/adapter-resolver.md` ) は capability 名 ( `browser`, `mcp`, `visual-diff`, ...) をキーに **project-local → user-global → bundled** の 3 層フォールバックを実装する。`.wholework.yml` がプロジェクト単位の capability を露出する。Steering Documents ( `product.md`, `tech.md`, `structure.md` ) は Osmani の言う「書き留めた意図」をスキル横断で運ぶ。

**特筆すべき要素** は Spec ファイル ( `docs/spec/issue-N-*.md` ) だ。これは `/spec` が設計成果物として作るが、後続の各フェーズが Retrospective とローテーション式の Phase Handoff ( `modules/phase-handoff.md` ) を追記するので、Spec はフェーズ横断メモリも兼ねる。Osmani の「リポジトリは忘れない」は repo 全体ではなく sub-issue 粒度で実現されている。

### 2.3 Sub-agents — フル実装、しかも多様

`agents/` 配下に 8 個の sub-agent が出荷されている。各役割は明確に分離している:

| Agent | フェーズ | 役割 |
|-------|----------|------|
| `issue-scope`, `issue-precedent`, `issue-risk` | Issue 作成 (L/XL) | 3 軸で並列調査 |
| `review-bug`, `review-spec`, `review-light` | Review | maker/checker 分離 — 書いた人がコードを採点しない |
| `frontend-visual-review` | Verify (視覚) | 構造化 JSON で視覚差分採点 |
| `orchestration-recovery` | Recovery (Tier 3) | 未知障害の診断者、recovery-plan JSON を出力 |

全 `run-*.sh` ラッパで使われる `claude -p --dangerously-skip-permissions` パターンは各フェーズに fresh context を与え ( `skills/code/SKILL.md`, `skills/review/SKILL.md` )、maker が自分を採点する失敗モードを *プロセス* レベルで阻止する (プロンプトレベルではなく)。`/code` は **Tier 0 → Tier 3 のエスカレーション** を内蔵 ( `skills/code/SKILL.md:239` ) し、構造化されたテスト失敗 recovery を試みてから recovery sub-agent に引き渡す。

ここは Wholework が Loop Engineering の理想に *最も近い* ブロックだ。Osmani が Claude Code の `/goal` に帰している「検証者がループの終了を判定する」パターンは部分的に既に実装されている — 別コンテキストの `/verify` が phase/done を判定し、コードを書いた `/code` セッションが判定するわけではない。

### 2.4 Memory — 多層、durable

Wholework は少なくとも 6 つの異なる面に状態を永続化している:

1. **GitHub Issues / Labels / PRs** — public な SSoT ( `docs/workflow.md § Label Transition Map` )
2. **Spec + Retrospective + Phase Handoff** — Issue 単位のフェーズ横断メモリ
3. **`.tmp/auto-state-N.json` / `.tmp/auto-batch-state.json`** — `/auto --resume`, `/auto --batch --resume` 用のチェックポイント
4. **`.tmp/auto-events.jsonl`** — `scripts/emit-event.sh` 経由の追記専用イベントストリーム ( `session_id` キー、`flock` で並行制御)
5. **`docs/reports/orchestration-recoveries.md`** — Issue 横断 recovery ログ、`/audit recoveries` が頻度ベースで掘る
6. **`docs/reports/auto-events-rollup-YYYY-MM-DD.md`** — `scripts/auto-events-rollup.sh` が生成する日次キュレーション

Zenn 記事の典型的な `STATE.md` パターンより密度が高い。Wholework は *セッション復元状態* ( `.tmp/*.json` ) と *Issue 単位の durable メモリ* (Spec) と *Issue 横断学習* (orchestration-recoveries + audit retro-proposals) を分離している。`~/.claude/projects/.../memory/` 配下の auto-memory が 7 つ目、リポジトリ横断のユーザレベル面を加える。

設計上の制約として 1 点: **`acting_on:` 形式の multi-loop 衝突検出は無い**。Wholework は GitHub label と `worktree-merge-push.sh` のロックに依存し、クロスセッション presence キーには依存しない。複数の長時間ループが同じリポを同時に触り始めると効いてくる。

### 2.5 Plugins / Connectors — GitHub-CLI レイヤー深、横展開浅

Wholework は Claude Code Plugin ( `.claude-plugin/plugin.json` v0.3.0 ) として出荷され、自己ホストしている (auto-memory `project_selfhost.md`)。事実上の connector レイヤーは `gh` CLI + ヘルパースクリプト群 ( `gh-graphql.sh`, `gh-issue-edit.sh`, `gh-issue-comment.sh`, `gh-label-transition.sh`, `gh-check-blocking.sh`, `gh-pr-merge-status.sh`, `gh-pr-review.sh` )。capability 解決型の adapter が `browser` / `lighthouse` / `visual-diff` を拡張する。`skills/spec/SKILL.md` の `allowed-tools` は design fetch 用に Figma MCP ツールまで明示している。

**無いもの**: Slack / Linear / email / カレンダー connector。ループの outbound チャンネルは GitHub 自身 (Issue コメント、PR 説明、label)。単一チーム単一リポの Pattern A/B mid-scale モダナイゼーションには十分 — Issue が *人間に見える inbox そのもの* だから。multi-team や long-tail 観測の場面では不在が効いてくる。

### 2.6 Automations / heartbeat — イベント駆動のみ、cron 無し

最大のギャップ。Wholework にあるのは:

- **イベント駆動 automation**: `.github/workflows/kanban-automation.yml` が `issues.types: [labeled]` に反応してプロジェクトカードを動かす。
- **ワンショットオーケストレータ**: `/auto` と `/auto --batch` がフェーズを手続き的に連結する — だが叩くのはユーザ。`.github/workflows/` に `schedule:` ブロックは無い。
- **heartbeat 検出器としての watchdog**: `scripts/claude-watchdog.sh` は無音タイムアウト (デフォルト 1800 秒) で `watchdog_kill` イベントを発火する。これは heartbeat の *逆* — ハング検出による kill であって、ループを起こす機構ではない。

Claude Code の `/loop <interval>` / `/goal <condition>` に相当するプリミティブが Wholework には埋め込まれていない。Zenn 記事の Daily Triage / CI Sweeper / Dependency Sweeper パターンに対応するものは無い — ユーザが cron / GitHub Actions `schedule:` / claude-code-host のスケジューリングで Skills の外側に配線する必要がある。

これは Wholework のポジショニング ( `docs/reports/wholework-positioning-memo-2026-06-13.md` ) と整合している — anchor case は *人間 in the loop* の mid-scale modernization であって 24/7 無人 sweep ではない。だが同時に、現状の「ループ」は半周ループでもある — 仕事は `/auto` でディスパッチされ、自律処理され、その後 *人間に戻る* — システム自身が「次にやるべきこと」を見つけるわけではない。

## 3. スコアシート

| Loop Engineering ブロック | Wholework 状態 | 根拠 |
|--------------------------|----------------|------|
| 1. Automations / scheduling | **部分 — オーケストレータのみ** | `/auto` / `/auto --batch` / watchdog。cron / `/loop` / `/goal` 無し |
| 2. Worktrees | **フル** | `modules/worktree-lifecycle.md`、アトミックな `worktree-merge-push.sh`、XL 並列 |
| 3. Skills | **フル** | 10 skills、36 modules、adapter-resolver、Steering Documents、`.wholework.yml` |
| 4. Plugins / Connectors | **部分 — GitHub 深** | `gh` CLI + adapter + Figma MCP。Slack/Linear/email 無し |
| 5. Sub-agents | **フル + recovery tier** | 8 agents、フェーズ毎コンテキスト分離、Tier 0→3 エスカレーション |
| 6. Memory | **フル、多層** | Spec + retro + handoff、`.tmp/*.json`、events.jsonl、recoveries.md、rollups |

Loop Engineering 用語では Wholework は **harness + sub-agent verifier + durable memory を備えた逐次オーケストレータ** — 発見された 1 つの仕事に対して *作用する* のに必要なものは全部ある。欠けているのは **発見と再発火のレイヤー** — 「新しくやるべきことがある、ディスパッチせよ」をユーザがスラッシュコマンドを打たずに決める部分だ。

## 4. 拡張余地 — Wholework のポジショニングとの適合度で評価

ポジショニングメモは fleet-class 100+ concurrent 実行を明示的に out-of-scope にしている (anchor: mid-scale modernization、5–10 concurrent、$10K/10 日/50–100 PR)。以下の提案はこのレンズを通している — subscription-auth / GitHub-native の moat を壊さずに、より完全なループ *の方向に* Wholework を伸ばす。

### 4.1 適合度 高 — 既存サーフェスの自然な拡張

既に置かれているブロックを再利用し、チームが認識している可視ギャップを塞ぐ提案。

**E1. `/audit triage` cron — daily-triage プリミティブ**
`schedule:` workflow を追加して `/audit drift` + `/audit fragility` を毎晩実行し、`audit/*` ラベル付きで Issue を起票する。Triage スキルが新規 Issue に対して走り、翌朝 `/auto --batch` がそれを拾う。これは Osmani の例示ループの Daily Triage を Wholework の既存プリミティブで表現したもの — 新スキル不要、workflow ファイル 1 つで足りる。リスク: トークン予算。緩和策: `/triage` には既に `--limit N` がある。

**E2. `/audit recoveries` の閾値超え auto-fire**
`/audit recoveries` は既存だが手動起動。orchestration recoveries ログは受動的に蓄積する。頻度閾値 (現在 3) を超えると Issue を auto-file するロジックを cron に配線すれば、再発 → Issue 変換が人間起動なしに起こる。「ループの検証者フィードバックループ」を儀式から実ループに変える。

**E3. `/goal N` — 検証者駆動の `/code` 再発火**
現在の `/verify` FAIL は Issue を reopen して *ユーザに戻し*、次のアクション選択を委ねる ( `/code --patch` vs `/code --pr` vs `/spec` )。同じ Spec を使って `/code` を再発火し、受入条件が全 PASS するかリトライ予算が尽きるまで続ける `/goal N` スキルは、Claude Code の `/goal` の直接的なアナログだ。maker/checker 分離は既に構造的 (別の `claude -p` プロセス)。変えるのは *ループ* の配線でエージェントではない。Zenn 記事の停止条件規律に従い `max_iterations` と `token_daily_budget` でキャップする。

**E4. Phase-State heartbeat レポータ**
`scripts/reconcile-phase-state.sh` は既に任意 Issue のフェーズの v1 JSON スナップショットを返す。全 `phase/*` Issue に対して定期実行し、ロールアップコメント / Slack メッセージ / Markdown ファイル ( `docs/reports/loop-state-YYYY-MM-DD.md` ) を 1 本出すジョブを足せば、ループに「踏む前に見る」面ができる。Zenn 記事の `STATE.md` だが、手作業ではなく live GitHub 状態から派生する。

### 4.2 適合度 中 — Connectors ブロックを触る

新規 connector が要るがスコープ内。

**E5. Slack / Linear 通知 adapter**
capability-resolver チェーンに `notify-adapter.md` を追加。発火サイトは既に名前付き — `/verify` FAIL、`/review` MUST findings、`/auto` Tier 3 recovery 成功、`/audit recoveries` 閾値超え。adapter は MCP サーバ (slack-mcp, linear-mcp) 上の薄い shim。「GitHub のみ」から離れる — GitHub は SSoT だが人間が読むチャンネルとは限らない、を認める。outbound 専用に限定 — inbound トリガーは GitHub-native のまま。

**E6. MCP 同梱型プラグイン配布**
Zenn 記事は plugin = 配布形態、skill = 執筆形態と整理する。Wholework は既に Claude Code Plugin としてスキルを配布しているが、project-local adapter は手で `.wholework/adapters/` 配下にコピーする必要がある。browser-adapter + lighthouse-adapter + (任意) slack/linear MCP サーバを 1 インストールで配布する同梱型 `wholework-connectors` プラグインがあれば、オンボードが「`.wholework.yml` を書いてファイルをコピー」から `claude plugin install` 一発に短縮される。

### 4.3 適合度 思弁 — Autonomy tier の明示化

ガバナンスに触る — つまり Wholework のコア差別化要素。

**E7. `.wholework.yml: autonomy:` field — L1/L2/L3 tier**
Zenn 記事の L1 Report / L2 Assisted / L3 Unattended の枠は Wholework の経路に既に暗黙に存在する — `/review --review-only` は概ね L1、`/auto` patch route は L2、`/auto --batch` は L3。tier を明示的に命名し、ループ発火スキル (E1/E3) を tier ≥ L2 でゲートすれば、チームはスケジュール導入を驚き無く段階的に行える。E4 の heartbeat reporter と自然にペアになる。

**E8. Multi-loop 衝突検出 ( `acting_on:` キー)**
Zenn 記事の `grep "acting_on:" state-*.md | sort | uniq -d` 衝突チェックに対応するものが Wholework に無い。今は同じ Issue に対する 2 つの並列 `/auto N` が worktree ロックと phase ラベルでレースする。`/auto` Step 1 で `.tmp/auto-lock-<issue>-<sid>` の presence ファイルを書き、毎チェックポイント resume で確認すればギャップは塞がる。E1/E3 がスケジュール発火を生むようになってから意味を持つ。

**E9. トークン予算ゲート ( `token_daily_budget` )**
`claude-watchdog.sh` は invocation 毎の *時間* 予算を強制する。カレンダー日単位の *トークン* 予算は、cron-fire (E1, E2, E3) が入った後の暴走ループからユーザを守る。全 `run-*.sh` invocation の前に発火する hook として配線し、超過時には `auto-events.jsonl` にログして定義済みコードで終了し、`/audit recoveries` が拾えるようにする。

### 4.4 Out of scope ( `wholework-positioning-memo-2026-06-13.md` と整合)

スコープクリープを先回りで予防するため明示する:

- **Fleet-class 100+ concurrent 実行** — Managed Agents 領域。subscription-auth moat を壊す。
- **Wholework と別の loop-as-product オーケストレータ** ( `wholework loop` デーモン等) — Wholework のサーフェスは *Skills + GitHub* のままで良い。cron は GitHub Actions かユーザホストの責務。
- **ループ内インタラクティブ単一タスク UI** — インタラクティブセッションは Cursor / Claude Code の仕事。ループの役割は無人ディスパッチ。

## 5. Osmani が突きつけるより難しい問い — Wholework の打ち出し方は変わるのか

Osmani の主張は 2 つに分けられる。第 1 (「構成要素はもう製品に同梱されているのでループは tooling 問題ではなく設計問題だ」) は Wholework の GitHub-native / 外部サービス不要のスタンスと *完全に整合* する。第 2 (「ループは verification debt / comprehension debt / cognitive surrender を *鋭く* する」) こそ、Wholework の差別化が鈍るのではなく *尖る* 場所だ。

Osmani を読んだ後で `docs/product.md` を読み直すと:

- **「Spec as cross-phase memory」** は comprehension debt 対策 — 人間も未来のセッションも、各フェーズが何をどう決めたかを読める。
- **「Human review gates as first-class」** は cognitive surrender 対策 — ループはゲートを潰さずゲートを通す。
- **「Post-merge verification ( `/verify` )」** は verification debt 対策 — 「終わった」はコードが主張すること。`/verify` がそれをチェックに変える。

product narrative の良い再フレーミング: **Wholework は「ループを作る」ではない。「他人のループを信頼できるものにする harness を作る」だ**。5 つのブロックは Claude Code に同梱される。verification の厳密さ、GitHub-visible な audit trail、spec-as-memory のプラクティスは、Wholework がその上に乗せるものだ。

このフレーミングは E1–E4 の導入を生き残るはずだ — cron は既存 harness の上の発火制御であって、human gate 配置の代替ではない。

## 6. 推奨 next actions

優先順位順、現状のバックログ (#583–#591 が既に起票済み) との突き合わせ:

1. **Spike: E4 Phase-State heartbeat レポータ** — script 1 本、workflow ファイル 1 本、新スキル無し。cron 発火スキルを作る前に「踏む前に見る」パターンを本番で検証する。Output: `docs/reports/loop-state-*.md` 日次。
2. **Spike: E2 `/audit recoveries` auto-fire** — 既存スキルの再利用。実装コスト最小。既存インフラを実フィードバックループに変える。
3. **Design: E7 `.wholework.yml: autonomy:` field** — スケジュール導入の前に tier を命名し、E1/E3 が裏で居住できるゲートを作る。
4. **Design: E3 `/goal N`** — 順序が重要。E2 がフィードバックループ基盤を実証してから着手する。
5. **Spike: E1 `/audit triage` cron** — Zenn 記事の Daily Triage に最も近い。理想的には E2 / E7 着地後に乗せ、新 cron が実証されたフィードバックチャンネルを持つようにする。
6. **Defer**: E5 / E6 (Slack/Linear、MCP 同梱プラグイン)、E8 (multi-loop 衝突)、E9 (トークン予算) — ポジショニングメモの慣習に従い Icebox で起票。E1–E4 着地後に再評価。

E1–E4 + E7 の累積効果は、Wholework がポジショニング内に留まったまま **完全な** Osmani ループを end-to-end で走らせる、最小の追加セットだ。それ以外は任意であり、願望ではなく根拠で発火させるべきだ。

---

*本メモは分析であり、`docs/product.md` が SSoT である項目を上書きしない。確定した拡張は本メモから Issue へ、最終的に Steering Document へ昇格する。*
