[English](../product.md) | 日本語

# Product

## Vision

Wholework は、自律的なコーディングエージェントを実際の GitHub リポジトリ上で安全に実行するための **governance-and-verification harness (ガバナンス・検証ハーネス)** である。作業を GitHub Issues・Specs・PR・Labels・Retrospectives へと外部化することで、人間・将来のセッション・チームがその作業を可視化し、ゲートし、監査できるようにし、マージ後には成果物が受入基準を満たしているかを検証する。

このハーネスは、Issue 作成からマージ後検証までの全フェーズをカバーする、組み合わせ可能な Claude Code Skills 群として配布される。各フェーズ (issue → spec → code → review → merge → verify) は独立した Skill であり、段階的に導入し、プロジェクトごとに設定し、アダプタで拡張できる。

## ワークフロー概要

`/issue` → `/spec` → `/code` → `/review` → `/merge` → `/verify`

最終フェーズの `/verify` はマージ後に独立して実行される。各受入条件 (Acceptance condition) に対して verify command を実行し、手動 AC を対話的に確認し、FAIL の場合は Issue を再オープンして修正サイクルへ戻す。L/XL の Issue では、`/issue` と `/review` が並列サブエージェント (scope / risk / precedent / bug / spec) を起動し、メインコンテキストを肥大化させずに調査を深める。

ワークフロー全体の図・フェーズの詳細・ラベル遷移については [docs/workflow.md](workflow.md) を参照。

<a id="spec-design-boundary"></a>

## `/issue` (What) vs `/spec` (How) の責務境界

`/issue` と `/spec` は連続するワークフローフェーズだが、抽象度のレベルが異なる。以下の表でそれぞれの責務を明確に分離する。

| | `/issue` (What: 何を作るか) | `/spec` (How: どう作るか) |
|---|---|---|
| **記述内容** | ユーザー向けの要件と挙動 | 実装者向けの設計と技術的決定 |
| **具体例** | 受入基準、ユースケース、制約、背景 | 変更対象ファイル、実装手順、アーキテクチャの選択 |
| **禁止事項** | ファイルパス、関数名、実装手順、技術的詳細 | 要件の追加・変更 (要件は `/issue` で確定済み) |
| **出力** | 更新された Issue 本文 | Spec (`docs/spec/issue-N-*.md`) |

**判断基準**: 「コードベースを知らなくても理解できるか？」— Yes → `/issue` の責務、No → `/spec` の責務。

## ターゲットユーザー

- GitHub 上で Claude Code を使って作業するすべての人 — 開発者だけでなく、Issue や PR を通じて作業を推進する PM、デザイナー、テクニカルライター、その他のコントリビューターも含む

## 非ゴール

- main ブランチへの直接コミット・プッシュ (Spec ファイル、`/code --patch` の修正、`/doc translate {lang}` が生成する翻訳ドキュメントを除く)
- `/tmp/` 配下への一時ファイル作成 (プロジェクト内の `.tmp/` を使用すること)
- SKILL.md 本文でのコードフェンス外での半角 `!` 文字の使用

## 必須依存関係

Wholework が機能するために必須なのは以下のみである。

- **Skills** — 各 Skill は Claude Code Plugin として実行される
- **GitHub Issues** — ワークフローの入口であり、要件の記録元
- **`docs/spec/`** — Spec の保存場所。GitHub Issues と合わせてワークフローの中核をなす。存在しない場合は Skill が自動的にディレクトリを作成する。

それ以外はすべてオプションであり、オプション依存が存在しない場合は各 Skill が適切にフォールバックする。

| オプション依存 | 存在しない場合のフォールバック |
|---------------------|----------------------|
| Pull Requests | patch 経路 (main への直接コミット) を使用。XS/S サイズの Issue が対象 |
| Steering Documents (`docs/product.md` 等) | 参照ステップをスキップし、デフォルト挙動で進行 |
| GitHub Projects board | Priority/Size のプロジェクトフィールド操作をスキップ。ラベルベースの操作 (`phase/*` 等) は継続して機能する |

この設計により、セットアップコストを最小化し、チームは全スタックにコミットすることなく個々のワークフローフェーズを導入できる。

> **Skill 実装ガイドライン**: オプション依存を使用する前に、必ずその存在を確認すること。存在しない場合はそのステップをスキップするか、デフォルト値で代替する。エラーで停止しないこと。

## ユーザーマニュアル

ユーザー向けドキュメントは `docs/guide/` 配下で管理されている。インストール、クイックスタートチュートリアル、ワークフロー概要、カスタマイズ、トラブルシューティングをカバーしており、評価者や新規ユーザー向けに、開発者向けの Steering Documents を補完する設計になっている。

## 今後の方向性

- **ガバナンスと検証の深化**: コーディングエージェントがより自律的になるにつれ、価値はオーケストレーションからガバナンスへとシフトする — 要件の捕捉、変更のゲーティング、成果の検証、監査証跡の維持。Wholework のロードマップは、モデルの自律性が高まるにつれてハーネスの各層を深化させることを優先する。
- **自律性階層 (autonomy-tiered) ガバナンス**: 4 つの層 — L0 (GitHub 状態: Issues、Labels、PRs、blockedBy) / L1 (Claude Code プリミティブ: `/loop`、`ScheduleWakeup`、`CronCreate`) / L2 (Wholework skill 内部: Spec、retro、`auto-events.jsonl`) / L3 (OS スケジューラ) — は Claude Code の `--permission-mode` サブプロセスフラグと直交する。このフラグはサブプロセスの権限を統制するものであり、GitHub 状態のスコープを統制するものではない。`.wholework.yml` の `autonomy:` フィールドは、skill がどこまで L0 を書き込み、L2→L1 経路を発火できるかを宣言する。SSoT: `modules/autonomy-tier.md`。
- **設定サーフェスの拡張**: `.wholework.yml` を通じて公開される Skill の挙動の範囲を広げ、Skill にパッチを当てることなくプロジェクトが Wholework を適応できるようにする。新しい設定可能な挙動は、Skill が汎用化されるにつれて追加される。
- **ワークフロー最適化 (3 軸)**: Model 選択、Adaptive Thinking (`--effort`)、Advisor 戦略のチューニングによって品質・速度・コストのバランスを取る。`docs/tech.md` (`ssot_for: model-effort-matrix`) のフェーズ別マトリクスは、新しいモデルや利用データが得られるたびに再調整される。
- **第一級制約としてのコンテキスト分離**: 実行フェーズの Skill を fork context に保ち、Spec をフェーズ横断のメモリとして維持することで、新しい Skill が以前のフェーズのコンテキスト劣化を引き継ぐことなく合成できるようにする。
- **対象プロジェクトタイプの拡大**: アプリケーション/Web 開発を超えて、「Issue → spec → artifact → review」が適用できるあらゆる GitHub プロジェクトへ汎用化する — ドキュメント/コンテンツ、データ/研究、インフラ/IaC、OSS 運用、ビジネス/企画領域など。
- **テーマ駆動のバックログ消化**: Issue には (`/triage` によって割り当てられる) `theme/*` ラベルが付与され、Value/Priority の順序のみに依存するのではなく、関連するバックログ Issue のバッチをまとめて選択・消化できるようにする。未分類の Issue はタグなしのままでよく、全件のカバレッジは必須ではない。テーマカタログは 2 層構造になっている: プロジェクトは `.wholework.yml` の `themes:` キーでシードカタログを宣言し (`scripts/setup-labels.sh` がこれを消費して `theme/*` ラベルを作成する。`docs/guide/customization.md` 参照)、`/triage` のランタイム分類は、GitHub 状態とドキュメントの二重メンテナンスを避けるため、このドキュメントや `.wholework.yml` ではなく、生成された GitHub ラベルを直接読み取る (`gh label list`)。

<!-- ## Success Metrics (Optional)

Describe success metrics here. -->

## 類似製品

### SDD フレームワーク / 方法論

| Product | Nature | Spec-driven workflow | Review/Merge | Distribution |
|---------|--------|---------------------|--------------|-------------|
| [GitHub Spec Kit](https://github.com/github/spec-kit) | Spec テンプレートと方法論 | Specify → Plan → Tasks | なし | CLI + テンプレート (22+ ツール) |
| [AWS Kiro](https://kiro.dev/) | IDE (VS Code フォーク) | requirements → design → tasks | 一部あり | スタンドアロン IDE |
| [Tessl](https://tessl.io/) | SDD プラットフォーム | spec → generate/describe → test | なし | フレームワーク (クローズドベータ) + Spec Registry |
| [GSD](https://github.com/gsd-build/get-shit-done) | メタプロンプティング + コンテキストエンジニアリング | discuss → research → plan → execute → verify | なし | npm パッケージ (Claude Code/OpenCode/Gemini CLI) |
| [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) | アジャイル AI 開発フレームワーク | analyst → PM → architect → SM → dev → QA | QA agent 含む | npm パッケージ (21 agents、50+ workflows) |
| [OpenSpec](https://github.com/Fission-AI/OpenSpec) | SDD フレームワーク | proposal → specs → design → tasks → apply | なし | npm パッケージ (20+ ツール) |
| [cc-sdd](https://github.com/gotalab/cc-sdd) | Kiro 発想のツール | requirements → design → tasks → impl | なし | npm パッケージ (8 agents) |
| [Taskmaster AI](https://github.com/eyaltoledano/claude-task-master) | AI タスク管理 | PRD → parse → tasks.json → execute | なし | npm パッケージ + MCP サーバー (Cursor/Windsurf/Lovable/Roo/その他) |

### Claude Code Plugins / Skills

| Product | Nature | Spec-driven workflow | Review/Merge | Distribution |
|---------|--------|---------------------|--------------|-------------|
| [feature-dev](https://claude.com/plugins/feature-dev) | Anthropic 公式の機能開発ワークフロー | Discovery → Codebase Exploration → Clarifying Questions → Architecture Design → Implementation → Quality Review (7 フェーズ) | code-reviewer 含む | Claude Code Plugin (13.1万+ インストール) |
| [Superpowers](https://github.com/obra/superpowers) | Skills フレームワーク | brainstorm → plan → implement | Code review skill 含む | Claude Code plugin |
| [Tsumiki](https://github.com/classmethod/tsumiki) | AI 駆動開発フレームワーク | requirements → design → tasks → implement (+ TDD) | なし | Claude Code Plugin |
| [claude-code-workflows](https://github.com/shinpr/claude-code-workflows) | E2E 開発プラグイン | analyze → design → plan → build → verify | review 用の recipe-* | Claude Code Plugin (backend/frontend 分割) |
| [claude-code-skills](https://github.com/levnikolaevich/claude-code-skills) | アジャイルパイプラインスイート | scope → stories → tasks → quality gate | マルチモデルレビュー (Claude+Codex+Gemini) | Claude Code Plugin (7 plugins) |
| [Simone](https://github.com/Helmi/claude-simone) | プロジェクト管理フレームワーク | ディレクトリベースのタスク管理 | なし | Claude Code + MCP サーバー |
| [CCPM](https://github.com/automazeio/ccpm) | GitHub Issue 統合 PM | PRD → epic → tasks → GitHub sync → parallel exec | PR ワークフロー含む | Claude Code Skills (worktree 並列実行) |
| [AgentSys](https://github.com/avifenesh/AgentSys) | ワークフロー自動化 | task → production、drift detection | マルチエージェントコードレビュー | Claude Code Plugin + agnix linter |
| [spec-workflow-mcp](https://github.com/Pimzino/spec-workflow-mcp) | MCP サーバー | Steering → Specs → Impl → Verify | Approval workflow 含む | MCP サーバー + dashboard |
| [cc-blueprint-toolkit](https://github.com/croffasia/cc-blueprint-toolkit) | Blueprint 駆動 SDD プラグイン | Define → Architect → Build → Iterate (DABI) | なし | Claude Code Plugin (13 skills、8 agents) |

### GitHub ワークフローアシスタント / AI Code Review

| Product | Nature | Target phase | Distribution |
|---------|--------|-------------|-------------|
| [GitHub Agentic Workflows](https://github.blog/changelog/2026-02-13-github-agentic-workflows-are-now-in-technical-preview/) | GitHub 公式リポジトリ自動化 | Issue triage、PR review、CI 分析 | GitHub Actions (Markdown 定義、technical preview) |
| [GitHub Copilot Code Review](https://docs.github.com/copilot) | GitHub 公式 AI レビュー | PR review | Copilot サブスクリプション |
| [CodeRabbit](https://coderabbit.ai/) | AI PR レビューサービス | PR review (security、logic、performance) | SaaS (GitHub/GitLab/Bitbucket/Azure DevOps) |
| [Qodo PR-Agent](https://github.com/qodo-ai/pr-agent) | OSS PR review agent | /review、/improve、/ask | GitHub Actions / CLI (OSS + 有償) |
| [Graphite](https://graphite.dev/) | Stacked PR + AI review | PR management → AI review → merge queue | SaaS (GitHub のみ) |
| [Sweep](https://sweep.dev/) | AI GitHub issue → PR agent | Issue triage → PR creation | GitHub App (OSS + 有償) |
| [Ellipsis](https://www.ellipsis.dev/) | AI PR review + auto-fix | PR review | SaaS (GitHub/GitLab、YC W24) |

### Anthropic 公式のエージェンティック開発

| Product | Nature | Outcome loop | Auth | Distribution |
|---------|--------|--------------|------|-------------|
| Managed Agents + Outcomes | Anthropic ファーストパーティの自律エージェントプラットフォーム | `define_outcome` → run → rubric grading → revise | API key / Anthropic ホスト | ホスト型サービス |

### 差別化サマリ

**Wholework の差別化ポイント**: GitHub 上で動く自律コーディングエージェントのための governance-and-verification harness — 要件の捕捉からマージ後の受入テストまでを、Claude Code のネイティブ機能 (Skills、CLAUDE.md) のみで実装している。外部サービスや専用 IDE は不要。

他ツールとの主な違い:

- **フェーズ横断メモリとしての Spec**: 多くの SDD ツールは spec を「計画フェーズの成果物」として扱う。Wholework では、Spec は各フェーズの実行結果 (retrospective) も蓄積し、ワークフロー全体を通じたメモリとして機能する。
- **GitHub ネイティブ**: Issues/PRs/Labels がワークフローの背骨である — 専用 IDE (Kiro のような) も、タスク管理用 JSON (Taskmaster のような) も、独自のファイルシステム (GSD の `.planning/` や BMAD の `bmad/` のような) も不要。
- **サイズベースのルーティング**: XS〜XL のサイズに基づいて patch/pr 経路、レビュー深度、spec の粒度を自動調整する機能は他のツールには見られない。
- **マージ後検証**: マージ後の独立した受入テストのための専用 `/verify` フェーズを持つツールはほとんどない。

**Managed Agents + Outcomes との比較**

Anthropic の Managed Agents + Outcomes は、隣接する outcome-rubric ループ (outcome を定義 → 自律実行 → 採点 → 修正) を提供する。この比較における Wholework の持続的な差別化要因:

1. **GitHub ネイティブな成果物** — 作業の記録は、チームがすでに日常的に使っている Issues、PRs、Labels、レビュースレッドであり、不透明なサーバーセッションではない。
2. **サブスクリプション / OAuth 認証** — Wholework は Claude Code サブスクリプション経路で動作する。Managed Agents は API key と Anthropic ホスト型コンテナを必要とする。
3. **段階的導入** — チームは、ホスト型エージェントスタック全体にコミットすることなく、`/review` のみ、あるいは `/verify` のみを導入できる。
4. **第一級の人間レビューゲート** — Outcomes はルーブリックに基づいて自律的に採点する。Wholework は Issue、PR、AC 確認の各時点で人間の承認を挿入する。

## 用語

| Term | Definition | Context | 日本語訳 |
|------|------------|---------|---------|
| `/auto` | `claude -p` 経由で spec→code→review→merge→verify を非対話的に連鎖実行するオーケストレーター Skill。`phase/*` ラベルが設定されていない場合は issue triage から自動開始し、`phase/ready` がない場合は `/spec` を自動実行する。`--batch N` はバックログから N 件の XS/S Issue を処理する。XL Issue は独立した sub-issue を並列実行する (worktree 分離)。`--base {branch}` はリリースブランチを対象にする。旧称: 'Dispatch' | Development workflow | `/auto` |
| `/audit` | プロジェクトヘルス検出のための複合 skill。サブコマンド: `/audit drift` (ドキュメントとコードの drift 検出、Issue 自動生成)、`/audit fragility` (構造的脆弱性検出)、`/audit stats` (Issue のスループット/構成/初回成功率の集計。`--retention` で phase/verify の滞留・Icebox 滞留・recovery 候補頻度を追加)、`/audit progress` (XL sub-issue の進捗スナップショット)、`/audit auto-session` (session.md に埋め込まれた `## Metrics` セクション、または `.tmp/auto-events.jsonl` からのフォールバック生成)、`/audit premise` (open Issue 本文の `premise:` マーカーを現在のコードベースと照合し再評価。premise が失効している Issue にコメントする)。 | /audit Skill | `/audit` |
| AC | "Acceptance Criteria" の略語 (インデックスで参照される個々の「受入条件」を指す場合もある。例: `AC1`、`AC2`)。Issue の retrospective、Skill の出力、レビューコメントで略記として使用される | /issue, /spec, /review, /verify | AC |
| Acceptance condition (受入条件項目) | Issue の受入基準内にある単一の検証可能な要件項目。チェックリストの 1 行として現れ、通常は verify command と対になる | /issue, /verify | 受入条件項目 |
| Acceptance criteria (受入基準) | Issue の本文の `## Acceptance Criteria` で定義される、受入条件の完全な集合。L2 の個々の受入条件からなる L1 の集合 | /issue, /verify | 受入基準 |
| Adapter | ツールアクセス (ブラウザ、CI、Lighthouse、外部サービス) を抽象化する capability ベースの拡張レイヤー。3 ステップ (detect → translate command → delegate execution) で動作し、優先順位 (project-local (`.wholework/adapters/`) → user-global → bundled (`modules/*-adapter.md`)) で解決する | Skill development, verify | Adapter |
| Ambiguity point (曖昧ポイント) | Issue 本文における、複数の解釈が可能な要件・制約・条件。`/issue` と `/spec` が ambiguity-detector のパターン表を通じて検出し、ユーザーによる明確化または既存コードベースのパターンに基づく自動解決によって解消される | /issue, /spec | 曖昧ポイント |
| Auto-resolution (自動解決) | モデルの判断による曖昧ポイントの非対話的な解決 (リスクが最小で既存パターンに沿った選択肢を優先)。選ばれた選択肢と理由は Auto-Resolve Log として retrospective に記録される。skip (高リスクの延期) や hard-error (前提条件) の階層とは区別される | /issue, /spec, non-interactive mode | 自動解決 |
| auto-verify (自動検証) | `/verify` によって実行される自動検証プロセス。各受入条件に対して verify command を実行し、通過した条件をチェックし、失敗時は Issue を再オープンする | /verify Skill | 自動検証 |
| Autonomy tier | skill がどこまで L0 の GitHub 状態を書き込み、L2→L1 経路を発火できるかを宣言する `autonomy:` フィールド (`L1` / `L2` / `L3`)。SSoT: `modules/autonomy-tier.md`。Claude Code の `--permission-mode` サブプロセスフラグとは直交する | Skill development, configuration | Autonomy tier |
| Capability | `.wholework.yml` の `capabilities.*` 下で宣言される機能可用性フラグ (例: `capabilities.browser: true`)。環境変数 (`HAS_{NAME}_CAPABILITY`) に変換され、Skill が補助ファイルの読み込みやアダプタの呼び出し前にチェックする。実行環境に応じた progressive disclosure を可能にする | Skill development, configuration | Capability |
| Checkpoint (チェックポイント) | `/auto` が verify のイテレーションカウンタと code フェーズのマイルストーンヒントを中断をまたいで持ち運ぶために書き込む、レジューム用のヒント状態ファイル (単一 Issue 用の `.tmp/auto-state-N.json`、バッチ実行用の `.tmp/auto-batch-state*.json`)。`scripts/auto-checkpoint.sh` によって管理される。フェーズ状態の権威は GitHub ラベルのままである (reconciler-first 設計) — 古いチェックポイントは、実際のラベルと矛盾した場合は信頼されず破棄される | /auto, --resume, --batch --resume | チェックポイント |
| Config marker (コンフィグマーカー) | `modules/detect-config-markers.md` がランタイムフラグ (`HAS_BROWSER_CAPABILITY`) に変換する `.wholework.yml` のキー (例: `capabilities.browser`)。Skill は補助的な domain file の読み込みやアダプタの呼び出し前にこれらのフラグをチェックする | Skill development | コンフィグマーカー |
| Deferral Protocol | `/code` がマークされたステップの実行を延期する場合に何をすべきかを記述する、Spec approval marker と対になる Spec 内の必須 `## Notes` エントリ。SSoT: `modules/costly-step-protocol.md` | /spec, /code | Deferral Protocol |
| Domain file | マーカー検出、ファイル存在確認、ディレクトリスキャンによって Skill が条件付きで読み込む補助 Markdown。SKILL.md のコアを軽量に保ちながら、環境固有・プロジェクト固有のロジックを補完する。プロジェクトローカルなカスタマイズは `.wholework/domains/{skill}/` でサポートされる | Skill development | Domain file |
| Drift (ドリフト) | ドキュメント化された仕様 (Steering Documents または Specs) と実際のコード実装との意味的な乖離。`/audit drift` によって検出される | /audit Skill | ドリフト |
| Fork context (fork コンテキスト) | メインの会話に影響を与えない Skill 実行モード | Claude Code | fork コンテキスト |
| Issue triage | メインワークフロー開始前に Type/Priority/Size/Value/Theme を割り当てる初期評価フェーズ。`/triage` skill として実装される。Issue に `phase/*` ラベルがない場合、`/auto` は自動的に triage を連鎖実行する | /triage, /auto | Issue triage |
| Non-interactive mode (非対話モード) | `AskUserQuestion` が使用できない `claude -p --permission-mode auto` を伴う `run-*.sh` 経由で呼び出される Skill 実行。決定ポイントで 3 段階のポリシー (auto-resolve / skip / hard-error) をトリガーする。`ARGUMENTS` 内の `--non-interactive` によってシグナルされる | run-*.sh, /auto | 非対話モード |
| Orchestration recovery (オーケストレーション復旧) | `/auto` オーケストレーション失敗に対する 3 段階の復旧メカニズム: (1) `reconcile-phase-state.sh` の完了チェック、(2) `apply-fallback.sh` の既知パターン復旧、(3) `spawn-recovery-subagent.sh` の Tier 3 サブエージェント診断 | /auto, orchestration | オーケストレーション復旧 |
| Operate route (Operate 経路) | diff を伴わない operational Issue (CMS 編集、インフラ操作) 向けのワークフロー経路。コミットや Pull Request を作成せず外部の MCP/CLI/API 操作を直接実行し、git diff の代わりに `## Execution Log` の Issue コメントを記録する。Spec から判定される (空の `## Changed Files` + 外部操作のみの Implementation Steps)。Size とは直交する | Development workflow | Operate 経路 |
| Patch route (パッチ経路) | XS/S サイズの Issue 向けのワークフロー経路。Pull Request を作成せず main ブランチへ直接コミットする | Development workflow | パッチ経路 |
| Phase Handoff | `modules/phase-handoff.md` に実装された、構造化されたフェーズ横断のサマリーメカニズム。各フェーズは終了前に Handoff を書き込み、次のフェーズはエントリ時にそれを読む。次のステップの作業コンテキスト (受入条件の結果、スコープに関するメモ、残存リスクなど) を運び、実行履歴を記録する Retrospective とは区別される。主に code → review → merge → verify の経路で使用される | /code, /merge, /review, /verify | Phase Handoff |
| Phase label (フェーズラベル) | Issue の現在のワークフロー段階を示す `phase/*` GitHub ラベル (例: `phase/issue`、`phase/spec`、`phase/ready`、`phase/code`) | Development workflow | フェーズラベル |
| PR route (PR 経路) | M/L サイズの Issue 向けのワークフロー経路。マージ前にコードレビュー用の Pull Request を作成する | Development workflow | PR 経路 |
| Premise marker (前提マーカー) | Issue 本文の記述がコードベースの現在の状態に依存していることを宣言する HTML コメントマーカー (`<!-- premise: ... -->`)。`/audit premise` が現在のコードベースと照合して再評価し、失効を検出する | /issue, /audit | 前提マーカー |
| Project Documents | プロジェクトのワークフローと運用手順のドキュメント。`docs/` 配下に保存される | /doc Skill | Project Documents |
| Reconcile / reconciliation (リコンサイル) | `scripts/reconcile-phase-state.sh` によって実装される Observe-Diagnose-Act パターン。ライブの GitHub/git 状態を `modules/phase-state.md` で定義されたフェーズごとの期待される前提条件/成功シグネチャ (Orchestration recovery の Tier 1) と比較する。完了した実行の構造化ファクトと保留中のマージ後受入条件を照合する run-fact AC reconciliation (`modules/run-fact-matching.md`) とは別のメカニズムであり区別される | /auto, orchestration, /verify | リコンサイル |
| Retrospective (レトロスペクティブ) | 各 Skill 実行後に Spec に追記されるセクションで、そのフェーズの観察・決定・不確実性の解消を記録する。ワークフローフェーズをまたいで実行履歴を蓄積する | Development workflow | レトロスペクティブ |
| safe mode (safe モード) | `/review` (マージ前) が使用する verify 実行モード。外部コマンド実行や副作用のある verify command は制限され、CI 参照にフォールバックする。マージ前に安全に評価できない条件は UNCERTAIN を返す。`full mode` と対になる | /review, verify-executor, verify-classifier | safe モード |
| full mode (full モード) | `/verify` (マージ後) が使用する verify 実行モード。シェルコマンドや外部サービス呼び出しを含め、すべての verify command が `safe mode` の制限なく実行される。`safe mode` と対になる | /verify, verify-executor | full モード |
| Session ID (`AUTO_SESSION_ID`) | 発行されたイベント (`.tmp/auto-events.jsonl`) とフェーズ横断のポインタファイルを発生元のセッションにスコープする、`/auto` 実行ごとの識別子 (`$$-$(date +%s)` 形式)。並行する `/auto` セッション下での誤帰属を防ぐ。`restore_auto_session_pointer()` によって 2 段階フォールバック (issue-scoped ポインタファイル → PGID ポインタファイル) で解決される。`.tmp/auto-session-current` フォールバックは、並行性の下で構造的に信頼できないため削除された (#1224) | /auto, scripts/emit-event.sh, /verify | セッションID |
| Shared module (共有モジュール) | `modules/*.md` に保存され、複数の Skill から「Read and follow」パターンで参照される手順ドキュメント。旧称: "shared procedure document" | Skill development | 共有モジュール |
| Silent no-op (サイレント no-op) | `claude -p` フェーズ呼び出しが可観測な効果 (コミットなし、コメントなし、状態変化なし) なしに exit 0 で終了する、`reconcile-phase-state.sh` の `matches_expected: false` 完了チェックによって検出される既知の失敗モード。`auto-retry-on-fail` (code/spec フェーズ、tier ゲート付き) と、リトライが尽きたか無効化されている場合の Tier 2/3 Orchestration recovery をトリガーする | /auto, run-code.sh, run-spec.sh, orchestration recovery | サイレント no-op |
| Size (サイズ) | triage 時に割り当てられる複雑度/工数の見積もり (XS/S/M/L/XL)。ワークフロー経路 (patch vs. PR) と Spec の深度を決定する | /triage Skill | サイズ |
| Smoke Test | `/code` がコミット/プッシュ前に実行するオプションの最小限の動作サニティチェック。既存の full-mode verify command (`mcp_call`、`command` など) を使って Spec の `## Smoke Test` セクションで定義される。`/verify` の前に動作の不一致を早期検出できる。オプトイン: Spec にセクションが含まれる場合のみ存在する | /spec, /code | Smoke Test |
| Skill (スキル) | Claude Code の拡張機能。処理ステップは `skills/<name>/SKILL.md` に記述され、`/<name>` で呼び出される | Claude Code | スキル |
| Spec | `/spec` によって作成され、`docs/spec/issue-N-short-title.md` に保存される実装計画ドキュメント。**各 Skill 実行後に Retrospective も蓄積し、ワークフローのフェーズ横断メモリとしても機能する**。旧称: 'Design file' / 'Issue Spec' | Development workflow | Spec |
| Spec approval marker (Spec approval マーカー) | コストのかかる/不可逆的な Implementation Step に `/spec` が付与する HTML コメントマーカー (`<!-- spec-approval-needed: cost=..., reversibility=... -->`)。`/code` はマークされたステップを High-Stakes Decision として扱い、非対話モードでは対になる Deferral Protocol に従って延期する。SSoT: `modules/costly-step-protocol.md` | /spec, /code | Spec approval マーカー |
| Steering Documents | 基盤ドキュメント (product/tech/structure) の総称。`docs/` 配下に保存される | /doc Skill | Steering Documents |
| Steering hint (Steering hint) | Steering Documents が存在しない場合に `modules/steering-hint.md` が発する `/doc init` を推奨する動的ガイダンス。`.wholework.yml` の `steering-hint: false` で無効化できる | Skill development | Steering hint |
| Sub-agent (サブエージェント) | Task tool 経由で起動されるサブエージェント。結果のみをメインエージェントに返す | Claude Code | サブエージェント |
| Sub-issue (サブ Issue) | XL Issue の分解内の子 Issue。`/auto` は `blockedBy` の依存グラフを読み取り、独立した sub-issue を並列実行し (worktree 分離)、依存先はブロッカー完了後に順序付けて実行する | Development workflow | サブ Issue |
| verify command | `<!-- verify: ... -->` 形式の HTML コメント。受入条件に機械検証可能な方法を紐づける。旧称: 'verification hint'、'verify hint'、'verify ヒント'、'検証ヒント'、'Acceptance check' | /issue, /verify | verify command |
| verify command type (verify command タイプ) | verify command の最初のトークン (例: `file_exists`、`grep`、`section_contains`、`command`)。受入条件に適用するチェック方法を識別する | /issue, /verify | verify command タイプ |
| Watchdog (ウォッチドッグ) | ハングした `claude -p` フェーズ呼び出しを検出し、kill してから 1 回リトライするバックグラウンドのサイレントウィンドウタイムアウトメカニズム (`scripts/claude-watchdog.sh`)。フェーズ固有のタイムアウト定数は `scripts/watchdog-defaults.sh` にあり、`.wholework.yml` の `watchdog-timeout-*-seconds` キーでプロジェクトごとに設定可能。SIGKILL ベースの external-kill 失敗モード (`docs/tech.md` § Two-tier orchestration 参照) とは区別される | run-*.sh, orchestration, configuration | ウォッチドッグ |
| Worktree | XL Issue の sub-issue を並列実行するために `/auto` が使用する git worktree。各 sub-issue の実装を独自の作業ツリーに分離し、ファイル競合を防ぐ。ライフサイクル (create/enter/exit/cleanup) は `modules/worktree-lifecycle.md` によって管理される | `/auto`, `/code`, `/spec` | Worktree |
