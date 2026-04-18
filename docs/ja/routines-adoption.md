[English](../routines-adoption.md) | 日本語

# Routines 採用計画

Claude Code の Routines 機能を wholework に取り込むための長期イニシアチブドキュメント。方向性、未解決の疑問、Tier ロードマップ、PoC の学びをセッションを跨いで蓄積します。

参考: https://claude.com/blog/introducing-routines-in-claude-code

## 背景

Claude Code Routines（2026-04 発表）は Claude プロンプトをクラウドホストでイベント駆動実行する機能を提供します。トリガーは 3 種類: cron スケジュール、HTTP API エンドポイント、GitHub webhook。各 routine は Claude のウェブインフラで実行され、ローカルマシンは不要です。

Wholework にとってこれはアーキテクチャ的に重要です。現在 wholework スキルは Claude Code CLI 経由でローカル実行されるため、`/auto` の batch 実行にはユーザーのマシンが起動し続ける必要があり、手動起動なしに GitHub イベントへ反応することもできません。Routines は両方の制約を解消します。

## コアインサイト

Routines は wholework を「ローカルで起動する CLI スキル」から「クラウド常駐のイベント駆動ワークフローエンジン」へと昇華させる可能性があります。3 つの構造的勝ち筋:

1. **ローカル依存の解消** — `/auto` の夜間バッチがユーザーの PC 起動に依存しなくなる
2. **GitHub イベント反応性** — スキルが現在欠いている reactive な振る舞いを獲得
3. **PR ごとの永続セッション** — Routines 公式の「session per PR」パターンが wholework の PR ライフサイクルモデルと構造的に整合

## 設計原則

- **phase ラベルをステートマシンとして扱う** — wholework は既に `phase/*` ラベルを使う。ラベル遷移を routine トリガーとして扱えばライフサイクル全体の自動化が可能（ラベル = 状態、routine = 遷移）
- **クォータ経済性** — Pro 5/day、Max 15/day、Team/Enterprise 25/day。高頻度な webhook は debounce / batch レイヤーが必要。routine クォータは「人間がボトルネックになる箇所の解消」に割り当て、trivial な自動化には使わない
- **Human-in-the-loop の境界** — `/merge` は routine 化しない（destructive）。`/verify` の FAIL 処理は reopen 前に人間確認を入れる mode flag を持つべき
- **冪等性は必須** — webhook はリトライする; コマンドは既存 comment / label を検知してスキップする実装が必要

## Tier ロードマップ

| Tier | テーマ | 状態 | 備考 |
|---|---|---|---|
| 1 | Webhook 駆動（低リスク・高価値） | planned | PoC 候補: `issues.opened` での auto-triage |
| 2 | Per-PR Shepherd（継続的 PR アシスタント） | planned | 個人優先度は低い（`/auto` でカバー可）、手動 merge ユーザーには高価値 |
| 3 | Cron（バックログ消化） | planned | スケジュール時刻の Claude 使用制限との兼ね合い要決定 |
| 4 | API トリガーブリッジ（Slack、アラート） | planned | |
| — | `/auto` の解体 | 探索的 | phase 遷移 routine により `/auto` が不要になる可能性; 移行パスは TBD |

### Tier 1 — Webhook 駆動

| Routine | トリガー | アクション | 状態 |
|---|---|---|---|
| auto-triage | `schedule`（毎時/毎日） | `gh` CLI を呼ぶ inline prompt または project skill としての `/triage` | **再設計済** — Issues webhook イベント未対応（Learnings Log 2026-04-16 参照） |
| phase-transition executor | （Issues webhook） | 対応するスキルを起動（`/spec`、`/code`） | **blocked** — Issues webhook 対応待ち |
| verify-on-merge | `pull_request.closed`（merged） | `/verify`（project skill 経由）— 「手動 verify を忘れる」failure mode を排除 | 実行可能 |

#### Setup Runbook — auto-triage（schedule ベースのバッチ）

このランブックは Claude Code ウェブ UI で auto-triage routine を設定する手順を記述しています。元の設計（`issues.opened` → `/triage`）は Routines の GitHub webhook サポートが現状 Pull Request と Release イベントに限定されているため実現不可。以下のランブックは schedule ベースのトリガーと inline prompt で untriaged Issue をバッチ処理します。

**前提条件**

- Claude Code アカウント（Pro/Max/Team/Enterprise）で Routines にアクセス可能
- ターゲットリポジトリが Claude Code に接続済み（`/web-setup` で clone アクセスを付与。webhook トリガーを使うには別途 Claude GitHub App のインストールが必要）
- ターゲットリポジトリに `triaged` ラベルが存在（初回使用時に自動作成されるか、`gh label create triaged` で事前作成）

**Action Prompt のオプション**

Routines ランタイムで動作する 2 パターンがあります。ターゲットリポジトリの `.claude/skills/` に wholework スキルがコミットされているかで選択:

**Option A — Inline prompt（skill 非依存、どのリポジトリでも動作）:**

```
You are running in a Claude Code Routine (cloud environment).
Execute these steps autonomously without asking for confirmation.
Use only `gh` CLI — do not reference plugin paths.

Step 1: List untriaged open issues
  Run: gh issue list --state open --search "-label:triaged" --json number,title,body --limit 10

Step 2: For each issue returned, classify:
  - Type: Bug / Feature / Task (from title + body keywords)
  - Size: XS / S / M / L / XL (estimate from scope in body)
  - Priority: urgent / high / medium / low (only if explicitly stated)

Step 3: Apply labels (run each command individually, no && chaining):
  - gh issue edit <N> --add-label "type/<type>"
  - gh issue edit <N> --add-label "size/<size>"
  - gh issue edit <N> --add-label "priority/<priority>"   (skip if not detected)
  - gh issue edit <N> --add-label "triaged"

Step 4: Post a single summary comment via:
  gh issue comment <N> --body "Auto-triage: Type=<type>, Size=<size>, Priority=<priority or none>"

Step 5: Output a results table summarizing all processed issues.
```

**Option B — Project skill（ターゲット repo の `.claude/skills/triage/` コミット済みが前提）:**

```
/triage --limit 10
```

Routines は clone したリポジトリの `.claude/skills/` ディレクトリから project skill をロードしますが、marketplace からの plugin スキルはロード**しません**。wholework 自身のリポジトリでは `skills/` が plugin / project skill 両用に構造化されているため動作しますが、他リポジトリでは wholework のスキルを `.claude/skills/` に vendor するか Option A を使う必要があります。

**設定手順**

1. Claude Code ウェブ UI を開き **Routines** に遷移
2. **New Routine** をクリック
3. routine 名を付け（例: `wholework-auto-triage`）、上記 action prompt のいずれかを貼り付け
4. ターゲットリポジトリを選択
5. environment を選択（`gh` CLI には Default で OK。ネットワークアクセスが有効か確認）
6. **Select a trigger** で **Schedule** を選び頻度を選択（平日朝の daily が妥当なデフォルト）
7. routine を保存
8. 配信確認: routine の詳細ページで **Run now** をクリックし、現在 untriaged な Issue が処理されることを確認

**冪等性**

両オプションとも Step 1 の `-label:triaged` フィルタ / `--search` 述語で冪等性を確保: 既に triaged な Issue はリストから除外されるため、繰り返し起動（schedule 再実行やデバッグ中の手動再実行）しても同じ Issue を再処理しません。これは旧設計が依存していた `/triage` スキル内のラベル検出よりも強力な冪等性保証です（リスト段階でショートカットされるため）。

**クォータへの影響**

schedule のたびに 1 回の routine 起動で最大 N 件の Issue を単一バッチ処理します（N = prompt 内 `--limit`）。元々計画されていた webhook 毎 Issue 方式（`issues.opened` 1 件あたり 1 起動）と比べ、schedule ベースのバッチは active なリポジトリで大幅にクォータ効率が高い — ただし triage レイテンシとのトレードオフ（作成時の triage ではなく次回スケジュール起動まで待つ）。

**期待される結果**

schedule 起動のたびに `-label:triaged` にマッチする Issue のうち設定 limit 分が Type/Size/Priority ラベル付与（label fallback 経由）と summary comment を受けます。Option A は inline prompt が wholework の `project-field-update.md` モジュールを呼べないため Project v2 field 更新はデフォルトで省略 — Project v2 field が必要なら Option B を使用。

### Tier 2 — Per-PR Shepherd

PR ごとに 1 つの routine を割り当て、永続セッションでライフサイクルを管理:
- `pull_request_review_comment.created` → フィードバックに対応した commit
- `workflow_run.completed`（failure）→ CI 失敗を診断し修正試行
- コンフリクト検知 → rebase 試行（失敗時は人間にエスカレーション）
- Approve + CI green → `phase/ready-to-merge` ラベル付与（merge 自体は人間）

`/review` を single-shot から継続的 PR アシスタントへ進化させる。`/auto` が既に同等の review-fix-merge ロジックを実装しているため migration はクリーン。

### Tier 3 — Cron

- **夜間バッチ auto**: `/auto --batch 3`（XS/S）— 現在の手動夜間 kick を置換
- **週次 audit スイート**: `/audit drift` + `/audit fragility` — 生成された Issue は翌営業日の auto-triage routine が拾う
- **月次 health report**: `/audit stats` を Discussions に投稿

スケジュール時刻は未解決（下記参照）。

### Tier 4 — API トリガー

- **Slack → `/issue`** — スレッド要約から Issue 作成（GitHub アクセスを持たないステークホルダーに対応）
- **Incident → Issue** — 監視 / アラートから、Priority=P0 強制の fast-path triage

## 未解決の疑問

### Q1. 夜間バッチのスケジュール時刻（Tier 3）

ユーザーは Claude 使用制限が厳しい時間帯に routine を走らせたくない。解釈により最適ウィンドウが変わる:

- **(a) インタラクティブ利用との 5 時間クォータ競合回避** → JST 02:00-05:00 が最適（ユーザー就寝中、インタラクティブ競合ゼロ）
- **(b) グローバル API 混雑回避** → JST 14:00-18:00 が最適（= 米国深夜）。ただし日本の業務時間と競合
- **(c) 妥協案** → JST 05:00-06:00 開始（PT 13:00 / ET 16:00、米国 end-of-day 下降期）; ユーザー起床直前に結果が出ている

現状の傾き: 解釈 (a)、JST 03:00 開始、朝の review フローに統合。PoC 使用データで検証してから確定。

### Q2. `/auto` の陳腐化

Tier 1 の phase-transition executor が実現すれば、`/auto` のローカル phase チェーンシミュレーションを置き換えるクラウドネイティブなステートマシンが誕生する。移行パス:

1. Routines を `/auto` と共存（opt-in、experimental）
2. Routines をデフォルトに、`/auto` は「ローカルフォールバック」に降格（webhook が届かないオフライン / プライベート repo 用途向けに保持）
3. 完全移行判断 — 削除するか fallback として残すか

`/auto` は webhook が届かない repo で standalone value を持つ。「ローカルフォールバック」ポジショニングは Routines 後も生き残る可能性が高い。

### Q3. アクティブ repo でのクォータ枯渇

アクティブなリポジトリでの webhook 頻度は容易に daily routine クォータを超える可能性がある。debounce / aggregation レイヤーが必要 — 例: 同一 Issue への 5 分窓内のラベル変更を単一 routine 起動に集約。

### Q4. 手動スキル起動と routine の race

ユーザーが `/triage 123` をローカル実行している最中に同 Issue の auto-triage routine が発火する可能性。lock / claim 機構が必要 — 候補: routine 開始時に `routine/claim` ラベルを付与、完了時にクリア、ローカルスキルはこれを尊重する。

### Q5. Phase ラベルの SSoT 整合性

現在 `phase/*` ラベルはスキル実装内で管理されている。routine が webhook ハンドラから直接ラベルを更新する場合、スキル ↔ routine の書き込み間の整合性に契約が必要。

### Q6. `/verify` FAIL 処理モード

現在 `/verify` は FAIL 時に Issue を auto-reopen する。routine 実行下ではこれは攻撃的すぎる可能性がある（FAIL は reopen 前に人間の解釈が必要かもしれない）。`mode: auto-reopen | notify-only` flag を提案。

### Q7. Routines 利用者向けのスキル配布

2026-04-16 の PoC で判明: plugin 配布のスキルは Routines ランタイムでロードされない — project skill（clone した repo の `.claude/skills/`）のみが可視。これは wholework にとって配布戦略の分岐点:

- **(a) 二重配布** — plugin manifest と並列の `.claude/skills/` ツリーを両方維持。ファイルレイアウトが倍になり、すべてのパス解決トークン（`${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_SKILL_DIR}`）を両コンテキストで動作させる必要がある。
- **(b) Setup スクリプトでインストール** — クラウド環境の setup script が wholework plugin を clone してインストールしてから実行。起動ごとのインストール overhead が追加され、ユーザーはカスタム環境を設定する必要がある。
- **(c) Inline prompt パターンのみ** — Routines から wholework スキルを呼ぶのを諦め、routine ごとに手書きの inline prompt を使う。合成性を失うが配布摩擦ゼロ。

決定未定。verify-on-merge 実装（Tier 1 の次ステップ）が forcing function となる: `/verify` に選ばれたパスが後続 routine のパターンを決定する。

## ロールアウト計画

1. **PoC: auto-triage routine** — 当初 `issues.opened` → `/triage N` を計画、2026-04-16 に `schedule` + inline-prompt に改訂（Learnings Log 参照）。最小・低リスク・有効。クォータ消費、冪等性、スキル配布のデータ取得が目的
2. **verify-on-merge**（`pull_request.closed` → `/verify`）— 即時 ROI、手動忘れ failure mode を排除。Q7 のスキル配布判断の forcing function
3. **夜間バッチ auto** — 既存 `/auto --batch` を routine 化、Q1 の時刻判断を検証
4. **Phase-transition executor** — Issues webhook サポート待ち（Tier 1 テーブル参照）。Anthropic のイベント拡張時に再評価
5. **Per-PR shepherd** — 最も野心的、最大価値、先行 Tier がクォータ / 冪等性 / 配布の前提を証明した後に延期

## Learnings Log

PoC の発見と決定を蓄積して追記します。各エントリは日付、tier、観測、設計調整を含むべきです。

### 2026-04-16 — auto-triage PoC (Tier 1)

**コンテキスト**

本ドキュメント（改訂前）の runbook に従って Claude Code ウェブ UI で auto-triage routine の設定を試みた。設定中に 3 つのランタイム制約が判明し、元の設計が無効化され、Tier 1 テーブルと Setup Runbook の両方の書き換えを余儀なくされた。

**観測**

- **サポートされている GitHub webhook イベントは Pull Request と Release のみ。** Claude Code ウェブ UI のイベント picker は `issues.opened` や Issues 系イベントを一切公開していない。公式ドキュメント（https://code.claude.com/docs/en/routines 、"Supported events" セクション、2026-04-16 確認）と一致。旧 runbook テキストの `issues.opened` → `/triage N` は実装不可だった。Anthropic の Threads 投稿が "More event sources are coming soon"（https://www.threads.com/@claudeai/post/DXHotXUADxk ）と示唆しているため、Issues イベントは将来追加される可能性あり; 機能追加待ちのブロッカーとして扱い、恒久制約ではない。

- **Plugin 配布のスキルは Routines ランタイムでロードされない。** `/triage N` の action prompt は解決されなかった — リモート Claude Code セッションは起動したがスキルを呼ばずに終了。公式ドキュメント: "The session can run shell commands, use skills committed to the cloned repository, and call any connectors you include." つまり **project skill**（clone した repo の `.claude/skills/`）のみが利用可能で、marketplace からの plugin skill はロードされない。wholework のスキル配布は Routines 駆動実行のため project-skill vendor パス（または setup-script インストールパス）が必要。

- **Schedule トリガー + inline `gh` CLI prompt が最小実用パターン。** 手動発火したテスト routine で inline prompt（untriaged Issue をリスト、`gh` で分類、ラベル付与、コメント投稿）を実行したところ Issue #206 で end-to-end に成功: `triaged`、`type/feature`、`size/xs` ラベルが付与され auto-triage comment が投稿された。これにより Routines ランタイム内で `gh` CLI が使用可能 / 認証済み、`gh issue edit --add-label` 書き込みが成功、slash-command 依存のない inline prompt が正しく実行される、ことが確認できた。

- **クォータ観測（限定的、PoC スコープ）。** PoC 中に消費した routine 起動は 2 回のみ（失敗した `/triage` 試行 1 回と #206 での inline 成功 1 回）。意味のある daily クォータプロファイリングには有機的な Issue 作成率下での持続運用が必要で、rollout 後のモニタリングに回す。備考: schedule ベースバッチ（1 起動で N 件カバー）は、当初計画された 1-Issue 1-webhook モデルよりも本質的にクォータ効率が高い（具体値によらず）。

- **list-filter レベルで冪等性確認。** inline prompt の `gh issue list --search "-label:triaged"` 述語により各バッチから triage 済み Issue が除外されるため、schedule 再実行（またはデバッグ時の `Run now`）は Issue を再処理しない。これは旧設計が依存していた `/triage` のスキル内ラベル検出より強い冪等性保証（分類作業に入る前で short-circuit するため）。

**設計調整**

- **Tier 1 テーブル書き換え。** auto-triage を `issues.opened` webhook から `schedule` トリガー + inline-prompt 実行へ移行; phase-transition executor は Issues webhook サポート待ちで blocked にマーク; verify-on-merge は `pull_request.closed` がサポート済みのため継続可能。
- **Setup Runbook 書き換え。** 元の webhook ベースフローを schedule ベースフローに置換し、action-prompt の 2 オプションを提示: (A) どの repo でも動く inline `gh` CLI prompt、(B) wholework の `.claude/skills/` を vendor しているリポジトリ向けの project skill としての `/triage`。
- **新しい open question（Q7）を下記に追加** — Routines 利用者向けの plugin-vs-project スキル配布戦略を追跡。

**Stop / Disable 手順**

auto-triage routine を一時停止または削除する必要がある場合:

1. Claude Code ウェブ UI を開き **Routines** に遷移
2. `wholework-auto-triage` routine を探す
3. 以下のいずれかを選択:
   - **Disable（可逆）** — routine を `disabled` にトグル。schedule 発火停止; トグルで再有効化可能。
   - **Delete（非可逆）** — routine を完全削除。再有効化には setup runbook 全体の再実行が必要。
4. 確認: disabled routine では `Run now` が表示されない（または効果なし）。

一時停止には **disable** を優先。**delete** は真に decommission する場合のみ。

**Tier 1 次ステップの推奨**

学んだ内容に基づく順序付き次ステップ:

1. **verify-on-merge**（`pull_request.closed` → `/verify`）— PR webhook は公式サポート済みで `/verify` には既に冪等性セマンティクスがあるため、最低リスクの次 routine。`.claude/skills/verify/` を vendor（またはクリティカルパスを inline prompt で書き換え）する必要がある — `/verify` は現状 plugin skill のため。
2. **wholework を Routines 互換にリファクタ** — `${CLAUDE_PLUGIN_ROOT}` に加え `${CLAUDE_SKILL_DIR}`（project-skill コンテキスト）でも動くよう scripts / modules を汎化。または代替として cloud 環境内での setup-script ベース plugin install パターンにコミット。いずれのパスを選ぶにしても Tier 1 拡大前にドキュメント化とテストカバーが必要。
3. **schedule ベースの auto-triage を有効なまま維持** — 実クォータデータ蓄積のため（2-invocation PoC では signal 不足）、より多くの routine にスケールする前に edge case を surface する。
4. **phase-transition executor は延期** — Issues webhook サポートが来るまで。Anthropic がイベント拡張を発表した時に再評価。

明示的に先送り: `/merge` の routine 化は引き続きスコープ外（destructive アクション、設計原則に従い human-in-the-loop を必須とする）。

**関連 Issue**

- Setup runbook（改訂前）: #189（closed）
- この PoC: #191
