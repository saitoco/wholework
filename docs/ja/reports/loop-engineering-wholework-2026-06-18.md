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

提案空間をさらに 2 つの設計原則で絞り込む:

- **Local-first 実行**。ループ発火はユーザマシン上の Claude Code セッション内で起こる (subscription-auth を維持)。Claude Code Action / GitHub Actions `schedule:` 経由のリモート実行は技術的には可能 (action は `claude_code_oauth_token` Secret を受け付ける) だが、**スキル毎の「実行サーフェス」問題** を別レーンで解いてから乗せる。Skill ごとに local↔CI の越境特性が大きく違う — `${CLAUDE_PLUGIN_ROOT}` の解決、`.tmp/` の永続性、`run-*.sh` の `claude -p` 子プロセス、git worktree のランナー寿命、MCP サーバの事前インストール — 特に `/auto` はそのリスクをほぼ全部抱える。CI 実行は後段トラックであり、E1–E4 の範囲外。
- **Tail 拡張 > 新プリミティブ**。Wholework の既存設計パターン (Phase Handoff が各フェーズの *出口* で書かれ、次の *入口* で読まれる) は一般化できる: ループは *既存ワークフローの終端を予算下で入口に折り返す* ことで作る。新しいトップレベルオーケストレータを差し込まない。これにより既存の human gate 配置 (PR review、AC 確認、retro proposal 承認) がそのまま生き、Spec / retrospective / event-log の基盤を無改造で再利用できる。以下の E1–E4 は *既存スキルの tail 拡張* として再構成され、新スキルではない。

### 4.1 適合度 高 — 既存スキルの tail 拡張

既存ワークフローの終端を opt-in 予算下で折り返す。新トップレベルスキル無し。新スケジューラ無し。すべて起動中の Claude Code セッション内で発火する。

**E3. `/verify` tail — `auto-retry-on-fail` (最小の最初の一歩)**
現在の `/verify` FAIL 経路: `gh issue reopen` + `phase/*` 全削除 → ユーザに戻り、`/code --patch` / `/code --pr` / `/spec` を手動選択。拡張: `.wholework.yml: auto-retry-on-fail` が設定 (opt-in) かつリトライ予算未消費なら、tail が自動で折り返す — 同じ Spec と verify 失敗コンテキストを渡して `/code` を再発火し、`/verify` を再実行。AC PASS、`max_iterations` 到達、`budget_tokens` 枯渇のいずれかで停止。maker/checker 分離は既に構造的 ( `/code` と `/verify` が別 `claude -p` プロセス) なので、変えるのは *ループ配線* であってエージェント設計ではない。新規サーフェス: `.wholework.yml` フラグ 1 つ、`/verify` SKILL.md の数ステップ、Spec retrospective のリトライカウンタ、`auto-events.jsonl` の `verify_retry_fire` イベント。これは Claude Code の `/goal` に最も近い Wholework アナログであり、最小の変更で「tail 拡張」パターンを実体化するので最初の一歩として推奨。

**E2. `/verify` retrospective tail — `/audit recoveries` の閾値超え auto-fire**
`/audit recoveries` は既存だが手動起動。拡張: `/verify` の retrospective-proposal 書き出しの tail で、orchestration recovery symptom が頻度閾値 (現在 3) を超えていれば improvement Issue を inline で auto-file する。同じスキル、同じ retrospective フック、新エントリポイント無し。毎回の verify で走るステップに乗せることで、「検証者フィードバックループ」を儀式から実ループに変える。

**E1. `/auto --batch` tail — 次サイクル種の emit**
今、`/auto --batch N1 N2 ...` はバッチ完了で止まる。拡張: バッチの tail で、軽量スキャン ( `/audit drift --since=<batch start>` + `/audit fragility --since=<batch start>` + バッチ開始以降に作られた `audit/*` Issue のフィルタ) を任意で走らせ、次バッチの候補 Issue 番号を列挙した `next-cycle.json` を吐く。次セッションでユーザ (または `/auto --batch --resume`) が拾う。これは Osmani の Daily Triage パターンだが — 「cron が次を決める」ではなく「各バッチが次の種を残す」として表現する。`schedule:` ブロック無し、Actions 無し、API キー懸念無し。

**E4. フェーズ遷移 tail — 別レポータではなく副作用としての heartbeat**
各 `/auto` フェーズ遷移は既に `auto-events.jsonl` にイベントを emit し、`phase/*` ラベルを更新する。拡張: 各遷移の tail で、`scripts/reconcile-phase-state.sh` から派生させた repo 全体のフェーズスナップショットを 1 行 `docs/reports/loop-state-YYYY-MM-DD.md` に追記する。専用スケジュールレポータ無し — heartbeat はワークフローが進む副作用。読めば「踏む前に見る」面ができる (Zenn 記事の `STATE.md` )。1 遷移あたりのコストはほぼゼロ。

### 4.2 適合度 中 — Connectors ブロックを触る

新規 connector が要るがスコープ内。

**E5. Slack / Linear 通知 adapter**
capability-resolver チェーンに `notify-adapter.md` を追加。発火サイトは既に名前付き — `/verify` FAIL、`/review` MUST findings、`/auto` Tier 3 recovery 成功、`/audit recoveries` 閾値超え。adapter は MCP サーバ (slack-mcp, linear-mcp) 上の薄い shim。「GitHub のみ」から離れる — GitHub は SSoT だが人間が読むチャンネルとは限らない、を認める。outbound 専用に限定 — inbound トリガーは GitHub-native のまま。

**E6. MCP 同梱型プラグイン配布**
Zenn 記事は plugin = 配布形態、skill = 執筆形態と整理する。Wholework は既に Claude Code Plugin としてスキルを配布しているが、project-local adapter は手で `.wholework/adapters/` 配下にコピーする必要がある。browser-adapter + lighthouse-adapter + (任意) slack/linear MCP サーバを 1 インストールで配布する同梱型 `wholework-connectors` プラグインがあれば、オンボードが「`.wholework.yml` を書いてファイルをコピー」から `claude plugin install` 一発に短縮される。

### 4.3 適合度 思弁 — Autonomy tier の明示化

ガバナンスに触る — つまり Wholework のコア差別化要素。

**E7. `.wholework.yml: autonomy:` field — L1/L2/L3 tier**
Zenn 記事の L1 Report / L2 Assisted / L3 Unattended の枠は Wholework の経路に既に暗黙に存在する — `/review --review-only` は概ね L1、`/auto` patch route は L2、`/auto --batch` は L3。tier を明示的に命名し、tail 拡張の振る舞い (E3 の `auto-retry-on-fail` 等) を tier ≥ L2 でゲートすれば、チームはループ semantics を驚き無く段階的に導入できる。E4 の遷移 tail heartbeat と自然にペアになる。

**E8. Multi-loop 衝突検出 ( `acting_on:` キー)**
Zenn 記事の `grep "acting_on:" state-*.md | sort | uniq -d` 衝突チェックに対応するものが Wholework に無い。今は同じ Issue に対する 2 つの並列 `/auto N` が worktree ロックと phase ラベルでレースする。`/auto` Step 1 で `.tmp/auto-lock-<issue>-<sid>` の presence ファイルを書き、毎チェックポイント resume で確認すればギャップは塞がる。E1/E3 がスケジュール発火を生むようになってから意味を持つ。

**E9. トークン予算ゲート ( `token_daily_budget` )**
`claude-watchdog.sh` は invocation 毎の *時間* 予算を強制する。カレンダー日単位の *トークン* 予算は、E3 着地後に `auto-retry-on-fail` が自動発火し始めたときの暴走 tail 拡張ループからユーザを守る。全 `run-*.sh` invocation の前に発火する hook として配線し、超過時には `auto-events.jsonl` にログして定義済みコードで終了し、`/audit recoveries` が拾えるようにする。

### 4.4 Out of scope ( `wholework-positioning-memo-2026-06-13.md` と整合)

スコープクリープを先回りで予防するため明示する:

- **Fleet-class 100+ concurrent 実行** — Managed Agents 領域。subscription-auth moat を壊す。
- **Wholework と別の loop-as-product オーケストレータ** ( `wholework loop` デーモン、新トップレベル `/goal` / `/loop` スキル等) — Wholework のサーフェスは *Skills + GitHub* のままで良く、ループは既存スキルの tail 拡張で組み立てる。新オーケストレータを差し込まない。
- **E1–E4 の CI 駆動スケジュール実行 (Claude Code Action / GitHub Actions `schedule:` )** — 拒否ではなく先送り。ブロッカーは「スキル毎の実行サーフェス」問題 (どのスキルがランナーで素直に動き、どれがローカルセッション前提か) であり、スケジュール導入の前に別途解く必要がある。出発点は明示的に local-first。
- **ループ内インタラクティブ単一タスク UI** — インタラクティブセッションは Cursor / Claude Code の仕事。ループの役割は無人ディスパッチ。

## 5. Osmani が突きつけるより難しい問い — Wholework の打ち出し方は変わるのか

Osmani の主張は 2 つに分けられる。第 1 (「構成要素はもう製品に同梱されているのでループは tooling 問題ではなく設計問題だ」) は Wholework の GitHub-native / 外部サービス不要のスタンスと *完全に整合* する。第 2 (「ループは verification debt / comprehension debt / cognitive surrender を *鋭く* する」) こそ、Wholework の差別化が鈍るのではなく *尖る* 場所だ。

Osmani を読んだ後で `docs/product.md` を読み直すと:

- **「Spec as cross-phase memory」** は comprehension debt 対策 — 人間も未来のセッションも、各フェーズが何をどう決めたかを読める。
- **「Human review gates as first-class」** は cognitive surrender 対策 — ループはゲートを潰さずゲートを通す。
- **「Post-merge verification ( `/verify` )」** は verification debt 対策 — 「終わった」はコードが主張すること。`/verify` がそれをチェックに変える。

product narrative の良い再フレーミング: **Wholework は「ループを作る」ではない。「他人のループを信頼できるものにする harness を作る」だ**。5 つのブロックは Claude Code に同梱される。verification の厳密さ、GitHub-visible な audit trail、spec-as-memory のプラクティスは、Wholework がその上に乗せるものだ。

このフレーミングは E1–E4 の導入を生き残るはずだ — tail 拡張は既存 harness の上の発火制御であって、human gate 配置の代替ではない。

## 6. 推奨 next actions

優先順位順、現状のバックログ (#583–#591 が既に起票済み) との突き合わせ。各ステップは *既存スキルの tail 拡張* — 新トップレベルスキル無し、新スケジューラ無し、すべて local-first。

1. **Spike: E3 `/verify` tail `auto-retry-on-fail`** — 最小の最初の一歩。opt-in `.wholework.yml` フラグ 1 つ、`/verify` SKILL.md の数ステップ、Spec retrospective のリトライカウンタ、新イベント型 1 つ。今のループが最も明確に半周で止まっている場所 (FAIL → 人間) で tail 拡張パターンを実体化する。`max_iterations` と `budget_tokens` でキャップ。
2. **Spike: E2 `/verify` retrospective tail auto-fire** — E3 が触る同じ retrospective フックに相乗りする。閾値超え検出が `/audit recoveries` の手動起動から毎 verify 実行の副作用に移る。
3. **Design: E7 `.wholework.yml: autonomy:` field** — tail 拡張の振る舞いが積み上がる前に tier を命名し、E3 の `auto-retry-on-fail` 以降の追加が裏で居住できるゲートを作る。
4. **Spike: E4 フェーズ遷移 tail heartbeat** — `reconcile-phase-state.sh` 由来の 1 行を遷移毎に `docs/reports/loop-state-*.md` に追記する。専用レポータ無し — heartbeat はワークフローの副作用。
5. **Spike: E1 `/auto --batch` 次サイクル種** — Zenn 記事の Daily Triage に最も近いが、cron ではなく「各バッチが次の種を残す」として実体化する。種の流し先ができた後に乗せるのでこのグループ最後。
6. **Defer**: E5 / E6 (Slack/Linear、MCP 同梱プラグイン)、E8 (multi-loop 衝突)、E9 (トークン予算)、CI 実行トラック全体 (Claude Code Action + スキル毎の実行サーフェス宣言) — ポジショニングメモの慣習に従い Icebox で起票。E1–E4 着地後に再評価。

E3 → E2 → E7 → E4 → E1 の累積効果は、Wholework がポジショニング内に留まったまま **完全な** Osmani ループを end-to-end で走らせる、最小の追加セットだ — ワークフロー自身が *置換* ではなく *拡張* で自分に餌を与えるようになる。それ以外は任意であり、願望ではなく根拠で発火させるべきだ。

---

## Addendum — 2026-06-20 議論ログ

初稿後の追議論で出た 3 つの洗練を、context から消える前に記録する。本体を無効化するものではなく、本体の上に乗る追記。

### A1. 4 層への再整理 (§4 から L0 が抜けていた)

§4 は L1/L2/L3 (Claude Code primitive / Wholework skill 内部 / OS or `CronCreate`) で拡張を整理した。議論で、この 3 層がさらに **下にある第 4 の基層** の上に立っていることが明らかになった:

| Layer | ループ状態の所在 | 駆動 | 永続性 |
|-------|----------------|------|--------|
| **L0: GitHub state** | Issues / Labels / PRs / `blockedBy` グラフ / `closes #N` | event-driven (PR merge、label 遷移、comment、close) | ◎ 公開・複数アクター・横断クエリ可能 |
| **L1: Claude Code primitive** | session memory | `/loop` / `/goal` / `ScheduleWakeup` | × volatile |
| **L2: Wholework skill 内部** | Spec / retro / `auto-events.jsonl` | tail extension (#700/702/703) | ○ ファイル永続 |
| **L3: OS / `CronCreate`** | crontab / cron registry | OS スケジューラ | ◎ 環境依存 |

Wholework の **XL Issue 機能は既に L0 ループそのもの**: 親 Issue がゴール、sub-issue + `blockedBy` が DAG、`phase/*` が状態機械、`docs/workflow.md § XL Parent Issue Phase Management` の集約ルールが停止条件。本体 §2.4 では「memory」として扱っていたが、より正確には *L1/L2/L3 すべてが reconcile する対象の substrate*。L1/L2/L3 が意味を持つのは L0 に書き戻すからこそ。

これは Wholework の差別化軸を再フレーミングする: 他のスキルフレームワークはループ状態を揮発な in-session memory か skill ローカル JSON に持つ。Wholework は L0 (公開・durable・複数アクター) を書く。**ガバナンスの問いは「スキルはどこまで L0 を変更してよいか、その tier は何か」**。

### A2. L2→L1 経路 = autonomy tier の作動メカニズム (E7 / #704)

§4.3 の E7 は tier を命名したが意味は曖昧だった。議論で具体的な作動定義に収束した: **autonomy tier は L2→L1 経路の許可リスト**。5 経路を列挙、4 採用 / 1 却下:

| ID | 経路 | メカニクス | 例 |
|----|------|----------|-----|
| **A** | Advisory | skill が推奨を print し、ユーザが踏む | `Recommend: /loop 1d /audit drift` |
| **B** | `CronCreate` | skill が Claude Code primitive で永続スケジュールを登録 | `/auto 670` が日次 `/audit progress 670` を予約 |
| **C** | `ScheduleWakeup` | `/loop` 内で動くスキルが次回 wake-up を動的制御 | `/verify` UNCERTAIN (CI 未完了) → N 分後に再 verify |
| **D** | Detached subprocess | detached `claude -p` を起動 | **却下** — 親終了で死ぬため信頼性低 |
| **E** | Seed file emission | skill が `.tmp/next-cycle.json` を書き、別 L1 が拾う | #703 (`/auto --batch` next-cycle seed) |

Tier × 経路 許可マトリクス:

| Tier | A | B | C | E | L0 write | デフォルト用途 |
|------|---|---|---|---|----------|---------------|
| **L1 Report** | ○ | × | × | × | × (advisory のみ) | 監査・人間が踏む |
| **L2 Assisted** | ○ | × | ○ (in-loop) | ○ | ○ (label 遷移、issue close、comment — 現在の `/auto` 挙動) | mid-scale modernization (anchor case) |
| **L3 Unattended** | ○ | ○ | ○ | ○ | ○ + recurring template / cross-issue 起票 | 完全無人 |

L0 列が A1 と A2 を接続する: tier はスキルが呼んでよい Claude Code primitive だけでなく、**どこまで L0 を変更してよいか** も決める。**autonomy は 1 つの宣言、2 つの帰結**。#704 として起票済み。

### A3. 起票済み拡張のステータス (#700–#704)

実装順:

| # | Issue | tail target | L2→L1 経路 | Blocked by |
|---|-------|-------------|------------|-----------|
| [#704](https://github.com/saitoco/wholework/issues/704) | E7 autonomy tier (L0 + 経路マトリクス) | (config layer) | マトリクス定義 | — |
| [#700](https://github.com/saitoco/wholework/issues/700) | E3 `/verify` tail `auto-retry-on-fail` | `/verify` | A のみ (retry は L2 内部) | #704 |
| [#701](https://github.com/saitoco/wholework/issues/701) | E4 phase-transition heartbeat | `/auto` | — (ファイル書き込み、tier 中立) | — |
| [#702](https://github.com/saitoco/wholework/issues/702) | E2 recoveries auto-fire | `/verify` retrospective | A のみ | #704, #700 |
| [#703](https://github.com/saitoco/wholework/issues/703) | E1 `/auto --batch` next-cycle seed | `/auto` | A, E (経路 E の最初の実装) | #704, #701 |

### A4. 浮上したが未起票の応用パターン

L0 フレーミングから自然に派生したが、今回はバッチを締まったまま保つために起票見送り。将来 Issue 候補:

- **Recurring Issue templates** — OPEN な Issue 1 つが定期作業の単位。`/audit recurring create --schedule weekly --label audit/drift "Weekly drift sweep"` が、close 時に次週分を自動起票する verify command 付き Issue を作る。Issue 自身が cron tick になり、project ボードで可視、close で停止、セッション再起動を超えて生存、OS cron 不要。本議論で出た **最も独立性の高い新機能候補**。
- **observation-AC を L0 heartbeat として再フレーミング** — #583 で部分的に進行中 (observation verify-type)。`phase/verify` の Issue + 時間窓 observation AC は、ユーザ (または `/audit stats --retention`) が tick を与えるループ。L3 `CronCreate` と組み合わせれば「全 `phase/verify` Issue の週次自動再 verify」(L0+L3 ハイブリッド) になる。
- **Issue-as-Goal** — 現在の Wholework 挙動に既に暗黙。L0 フレーミングで明示化する。`<!-- verify: ... -->` AC 付き親 Issue は、durable で公開な状態として実体化された `/goal` であり、generic model ではなく `/verify` の構造化された verify-command エンジンが判定する。
- **PR comment / review event を loop tick に** — `/review --review-only` は finding 提示で停止する。opt-in `.wholework.yml: review-event-driven: true` を入れれば、reviewer comment 追加が `/code` と `/review` を comment 数または予算が尽きるまで再発火する。E5 (notify-adapter) と発火パターンが対称。
- **Cross-repo Issue chain** — `closes <other-org>/<other-repo>#N` は GitHub 側で既に動く。L0 substrate は repo 横断に自然に伸びる。Wholework 側で cross-repo session/auth 処理が必要。現ポジショニング (single-team anchor) の外だが、自然な拡大経路。

### A5. CI / Claude Code Action を L0/L1 レンズで再検討

短く: Claude Code Action に `claude_code_oauth_token` を渡せば subscription auth は維持できる。だが本当の壁は **スキル毎の実行サーフェス** ( `${CLAUDE_PLUGIN_ROOT}` 解決、`.tmp/` 揮発性、`run-*.sh` の `claude -p` 子プロセス、git worktree のランナー寿命、MCP サーバ事前インストール)。将来的に skill frontmatter に `execution: [local, ci]` を持たせれば、ユーザは初日に「どのスキルが local↔CI の境界を生き残るか」が分かる。起票は保留 — 複数ユーザが同じ壁にぶつかった時に判断。

### A6. 本体から不変なもの

§4 の優先順位 (新プリミティブより tail 拡張、local-first、E1–E4 + E7 が最小の自己給餌ループ) は無事生き残る。A1–A2 は **なぜ** を鋭くする (L0 = substrate、autonomy = L0 + 経路許可) が、**何を** (既存スキルの tail 拡張) は変えない。A4 は将来仕事リストを広げるが、直近の実装キューには影響しない。

---

*本メモは分析であり、`docs/product.md` が SSoT である項目を上書きしない。確定した拡張は本メモから Issue へ、最終的に Steering Document へ昇格する。*
