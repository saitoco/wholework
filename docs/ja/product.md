[English](../product.md) | 日本語

# Product

## Vision

Claude Code ユーザーが Issue 作成からマージ後の検証までを通して使える Issue 駆動型の開発ワークフローを、あらゆる GitHub プロジェクトで動作する組み合わせ可能なスキル群として配布します。各フェーズ（issue → spec → code → review → merge → verify）は独立したスキルであり、段階的に採用でき、プロジェクトごとに設定でき、adapter で拡張できます。

## ワークフロー概要

`/issue` → `/spec` → `/code` → `/review` → `/merge` → `/verify`

ワークフロー図の全体像、各フェーズの詳細、ラベル遷移については [docs/ja/workflow.md](workflow.md) を参照してください。

<a id="spec-design-boundary"></a>

## `/issue`（What）と `/spec`（How）の責務境界

`/issue` と `/spec` はワークフローで連続するフェーズですが、抽象度のレベルが異なります。下表で責務を明確に分けます。

| | `/issue`（What: 何を作るか） | `/spec`（How: どう作るか） |
|---|---|---|
| **記述対象** | ユーザー向けの要件と挙動 | 実装者向けの設計と技術的判断 |
| **例** | 受入条件、ユースケース、制約、背景 | 変更ファイル、実装手順、アーキテクチャ選択 |
| **禁止事項** | ファイルパス、関数名、実装手順、技術的詳細 | 要件の追加・変更（要件は `/issue` で確定） |
| **成果物** | 更新された Issue 本文 | Spec（`docs/spec/issue-N-*.md`） |

**判定ルール**: 「コードベースを知らなくても理解できるか？」— Yes → `/issue` の責務、No → `/spec` の責務。

## ターゲットユーザー

- Claude Code を使って GitHub 上で働くすべての人 — 開発者だけでなく、Issue や PR で作業を推進する PM、デザイナー、テクニカルライター、その他のコントリビューターも含む

## 非ゴール

- main ブランチへの直接コミットとプッシュ（Spec ファイル、`/code --patch` 修正、`/doc translate {lang}` で生成される翻訳ドキュメントを除く）
- `/tmp/` 配下への一時ファイル作成（代わりにプロジェクト内の `.tmp/` を使用すること）
- SKILL.md 本文のコードフェンス外で半角 `!` 文字を使用すること

## 必須依存関係

Wholework が機能するための必須依存は以下のみです:

- **Skills** — 各スキルは Claude Code Plugin として実行される
- **GitHub Issues** — ワークフローのエントリポイントであり、要件の一次情報源
- **`docs/spec/`** — Spec の保存先。GitHub Issues と併せてワークフローの中核をなす。スキルは存在しない場合に自動でディレクトリを作成する

それ以外はすべてオプションであり、オプション依存が存在しない場合は各スキルが優雅にフォールバックします。

| オプション依存 | 存在しない場合のフォールバック |
|---------------------|----------------------|
| Pull Request | patch 経路（main への直接コミット）を使用。XS/S サイズの Issue が対象 |
| Steering Documents（`docs/product.md` など） | 参照ステップをスキップ、デフォルト挙動で進行 |
| GitHub Projects ボード | Priority/Size のプロジェクトフィールド操作をスキップ。ラベルベースの操作（`phase/*` など）は継続して動作 |

この設計により、セットアップコストを最小化し、チームがフルスタックにコミットせずに個別のワークフローフェーズを採用できるようになっています。

> **スキル実装ガイドライン**: オプション依存を使用する前に、必ずそれが存在するかを確認すること。存在しない場合はステップをスキップするかデフォルト値で代替する。エラー終了しないこと。

## ユーザーマニュアル

ユーザー向けドキュメントは `docs/guide/` 配下で保守されています。インストール、クイックスタート、ワークフロー概要、カスタマイズ、トラブルシューティングを扱い、評価者や新規ユーザー向けに設計されています。開発者向けの Steering Documents を補完する位置付けです。

## 今後の方向性

- **`.wholework.yml` 設定のカスタマイズ**: Spec 保存先（デフォルト: `docs/spec/`）などのパスをプロジェクト単位で設定可能にする。既存のディレクトリ構造を持つプロジェクトで Wholework を採用する際の摩擦を減らす
- **ワークフロー最適化（3軸）**: Model 選択（スキル/フェーズごとのモデル切替）、Adaptive Thinking（`--effort` による推論深度の動的制御）、Advisor 戦略（コスト効率的な品質のための Opus advisor）を組み合わせて、ワークフローの品質・速度・コストを最適化する。現行のフェーズ別マトリクスは `docs/tech.md` Architecture Decisions（`ssot_for: model-effort-matrix`）を参照
- **コンテキスト分離戦略（コンテキスト腐敗対策）**: Spec がフェーズ横断のメモリとして機能することで、各スキルは fork コンテキストで動作してもフェーズ間で情報を失わない。実行フェーズのスキルを積極的に fork コンテキストで動かすことでコンテキスト腐敗を防ぐ
  - **共有コンテキスト**（`/issue` + `/spec`）: 要件と設計を詰める対話フェーズ。却下された選択肢の理由などの暗黙のコンテキストに価値があるため共有。ただし `/auto` から呼び出される場合（すなわち `run-issue.sh` / `run-spec.sh`）は、独立した `claude -p` プロセスとして fork コンテキストで実行される
  - **fork コンテキスト**（`/code`, `/review`, `/merge`, `/verify`）: 実行フェーズ。各スキルは Spec から必要な情報を読み取り、独立して実行される。4 スキルすべてが fork コンテキストで動作する
  - **`/auto` のハイブリッドアプローチ**: `/auto` は各スキルを `run-*.sh` から `claude -p --dangerously-skip-permissions` として呼び出し、フェーズ間のコンテキスト分離と権限の完全バイパスを保証する。`/auto` 自身は軽量なオーケストレーターとして機能し、情報は Spec 経由でのみ伝達される。`phase/*` ラベルが設定されていない場合、`/auto` は issue triage/refinement から自動開始する。`phase/ready` がない場合は `/spec` を先に自動実行する。`--batch N` はバックログから N 個の XS/S Issue を順番に処理する。XL Issue はサブ issue の `blockedBy` 依存グラフを読み、独立サブ issue を並列実行（worktree 分離）し、依存先はブロッカー完了後に順次実行する。`--base {branch}` は main の代わりにリリースブランチを対象にする
- **対象プロジェクト種別の拡大**: 現在の主ユースケースはアプリケーション/Web 開発だが、「Issue → spec → 成果物 → レビュー」のフローが当てはまるあらゆる GitHub プロジェクトへ一般化することをゴールとする。共通項: Issue で要件を定義し、設計ドキュメントがあり、成果物があり、レビュー手順があること
  - **ドキュメント / コンテンツ**: 技術文書、API ドキュメント、翻訳プロジェクト、書籍執筆（GitBook スタイル）
  - **データ / リサーチ**: データ分析パイプライン、ML モデル開発、学術論文（LaTeX + Git）
  - **インフラ / IaC**: Terraform/Pulumi 定義、Kubernetes マニフェスト、CI/CD パイプライン構築
  - **OSS 運用**: RFC プロセス、CHANGELOG 管理、自動化されたリリースノート
  - **ビジネス / 企画**: マーケティングキャンペーン管理、プロダクトロードマップ、法務文書
- **特化コンテンツのプログレッシブ・ディスクロージャー（Core/Domain 分離）**: 現状 SKILL.md 本文に埋め込まれている特化コンテンツ（UI デザイン、スキル開発など）を、関連プロジェクトでのみ読み込まれる補助ファイルに切り出す。Core を軽量に保ちつつ、ドメイン特化の拡張を可能にする
- **capability ベース拡張のための adapter パターン**: ツールアクセス（browser、CI、外部サービス）を adapter レイヤで抽象化し、capability の可用性に基づいてスキル挙動を切り替える。adapter は 3 ステップで動作し（検出 → コマンド変換 → 実行委譲）、解決は優先度順（プロジェクトローカル → ユーザーグローバル → バンドル）。これによりスキル本体と特定ツールを分離し、同一スキルが異なる環境（Playwright あり/なし、CI 連携あり/なしなど）で動作するようになる

<!-- ## Success Metrics (Optional)

Describe success metrics here. -->

## 類似製品

### SDD フレームワーク / 方法論

| 製品 | 性質 | Spec-driven ワークフロー | Review/Merge | 配布形態 |
|---------|--------|---------------------|--------------|-------------|
| [GitHub Spec Kit](https://github.com/github/spec-kit) | Spec テンプレートと方法論 | Specify → Plan → Tasks | なし | CLI + テンプレート（22+ ツール） |
| [AWS Kiro](https://kiro.dev/) | IDE（VS Code fork） | requirements → design → tasks | 部分的 | スタンドアロン IDE |
| [Tessl](https://tessl.io/) | SDD プラットフォーム | spec → generate/describe → test | なし | フレームワーク（closed beta） + Spec Registry |
| [GSD](https://github.com/gsd-build/get-shit-done) | メタプロンプト + コンテキストエンジニアリング | discuss → research → plan → execute → verify | なし | npm package（Claude Code/OpenCode/Gemini CLI） |
| [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) | アジャイル AI 開発フレームワーク | analyst → PM → architect → SM → dev → QA | QA エージェントを含む | npm package（21 エージェント、50+ ワークフロー） |
| [OpenSpec](https://github.com/Fission-AI/OpenSpec) | SDD フレームワーク | proposal → specs → design → tasks → apply | なし | npm package（20+ ツール） |
| [cc-sdd](https://github.com/gotalab/cc-sdd) | Kiro ベースのツール | requirements → design → tasks → impl | なし | npm package（8 エージェント） |
| [Taskmaster AI](https://github.com/eyaltoledano/claude-task-master) | AI タスク管理 | PRD → parse → tasks.json → execute | なし | npm package + MCP server（Cursor/Windsurf/Lovable/Roo/その他） |

### Claude Code Plugins / Skills

| 製品 | 性質 | Spec-driven ワークフロー | Review/Merge | 配布形態 |
|---------|--------|---------------------|--------------|-------------|
| [feature-dev](https://claude.com/plugins/feature-dev) | Anthropic 公式 feature 開発ワークフロー | Discovery → Codebase Exploration → Clarifying Questions → Architecture Design → Implementation → Quality Review（7 フェーズ） | code-reviewer 同梱 | Claude Code Plugin（131K+ インストール） |
| [Superpowers](https://github.com/obra/superpowers) | Skills フレームワーク | brainstorm → plan → implement | コードレビュースキル同梱 | Claude Code plugin |
| [Tsumiki](https://github.com/classmethod/tsumiki) | AI 駆動開発フレームワーク | requirements → design → tasks → implement（+ TDD） | なし | Claude Code Plugin |
| [claude-code-workflows](https://github.com/shinpr/claude-code-workflows) | E2E 開発 plugin | analyze → design → plan → build → verify | recipe-* でレビュー | Claude Code Plugin（backend/frontend 分離） |
| [claude-code-skills](https://github.com/levnikolaevich/claude-code-skills) | アジャイル pipeline スイート | scope → stories → tasks → quality gate | マルチモデルレビュー（Claude+Codex+Gemini） | Claude Code Plugin（7 plugins） |
| [Simone](https://github.com/Helmi/claude-simone) | プロジェクト管理フレームワーク | ディレクトリベースのタスク管理 | なし | Claude Code + MCP server |
| [CCPM](https://github.com/automazeio/ccpm) | GitHub Issue 連携の PM | PRD → epic → tasks → GitHub sync → 並列実行 | PR ワークフロー同梱 | Claude Code Skills（worktree 並列実行） |
| [AgentSys](https://github.com/avifenesh/AgentSys) | ワークフロー自動化 | task → production、ドリフト検出 | マルチエージェントコードレビュー | Claude Code Plugin + agnix linter |
| [spec-workflow-mcp](https://github.com/Pimzino/spec-workflow-mcp) | MCP server | Steering → Specs → Impl → Verify | 承認ワークフロー同梱 | MCP server + dashboard |
| [cc-blueprint-toolkit](https://github.com/croffasia/cc-blueprint-toolkit) | Blueprint 駆動 SDD plugin | Define → Architect → Build → Iterate（DABI） | なし | Claude Code Plugin（13 skills、8 agents） |

### GitHub ワークフローアシスタント / AI Code Review

| 製品 | 性質 | ターゲットフェーズ | 配布形態 |
|---------|--------|-------------|-------------|
| [GitHub Agentic Workflows](https://github.blog/changelog/2026-02-13-github-agentic-workflows-are-now-in-technical-preview/) | GitHub 公式のリポジトリ自動化 | Issue triage、PR レビュー、CI 分析 | GitHub Actions（Markdown 定義、technical preview） |
| [GitHub Copilot Code Review](https://docs.github.com/copilot) | GitHub 公式 AI レビュー | PR レビュー | Copilot サブスクリプション |
| [CodeRabbit](https://coderabbit.ai/) | AI PR レビューサービス | PR レビュー（セキュリティ、ロジック、パフォーマンス） | SaaS（GitHub/GitLab/Bitbucket/Azure DevOps） |
| [Qodo PR-Agent](https://github.com/qodo-ai/pr-agent) | OSS PR レビューエージェント | /review, /improve, /ask | GitHub Actions / CLI（OSS + 有償） |
| [Graphite](https://graphite.dev/) | Stacked PR + AI レビュー | PR 管理 → AI レビュー → merge queue | SaaS（GitHub のみ） |
| [Sweep](https://sweep.dev/) | AI GitHub issue → PR エージェント | Issue triage → PR 作成 | GitHub App（OSS + 有償） |
| [Ellipsis](https://www.ellipsis.dev/) | AI PR レビュー + 自動修正 | PR レビュー | SaaS（GitHub/GitLab、YC W24） |

### 差別化サマリ

**Wholework の差別化ポイント**: GitHub Issue と PR を中心とした、spec 作成からマージ後の検証までのエンドツーエンドワークフローを、Claude Code のネイティブ機能（Skills、CLAUDE.md）のみで完結させる。外部サービスや専用 IDE は不要。

他ツールとの主な違い:

- **フェーズ横断メモリとしての Spec**: 多くの SDD ツールは spec を「計画フェーズの成果物」として扱う。Wholework では Spec が各フェーズの実行結果（レトロスペクティブ）も蓄積し、ワークフロー全体のメモリとして機能する
- **GitHub ネイティブ**: Issues/PRs/Labels がワークフローの骨格 — 専用 IDE（Kiro のような）、タスク管理 JSON（Taskmaster のような）、独自ファイルシステム（GSD の `.planning/` や BMAD の `bmad/` のような）は不要
- **サイズベースのルーティング**: XS〜XL のサイズに応じて patch/pr 経路、レビュー深度、Spec 粒度を自動調整する仕組みは他ツールには見られない
- **マージ後検証**: マージ後の受入テストを独立した `/verify` フェーズとして持つツールはごく少数

## 用語

| 用語 | 定義 | コンテキスト | 日本語訳 |
|------|------------|---------|---------|
| `/auto` | `claude -p` を介して非対話的に spec→code→review→merge→verify を連鎖させるオーケストレータースキル。`phase/*` ラベルが未設定の場合は issue triage から自動開始、`phase/ready` が無い場合は `/spec` を自動実行。`--batch N` はバックログから N 個の XS/S Issue を処理、XL Issue は独立サブ issue を並列実行（worktree 分離）する。`--base {branch}` でリリースブランチを対象にする。旧称: 'Dispatch' | 開発ワークフロー | `/auto` |
| Acceptance condition | Issue の受入条件内の、検証可能な単一要件項目。チェックリストの 1 行として現れ、通常 verify command と対になる | /issue, /verify | 受入条件項目 |
| Acceptance criteria | Issue の受入条件の完全な集合。Issue 本文の `## Acceptance Criteria` 配下に定義される。L1 の集合としての L2 個別受入条件群 | /issue, /verify | 受入条件 |
| Adapter | ツールアクセス（ブラウザ、CI、Lighthouse、外部サービス）を抽象化する capability ベースの拡張レイヤー。3 ステップで動作（detect → translate command → delegate execution）し、優先順位順に解決する: プロジェクトローカル（`.wholework/adapters/`）→ ユーザーグローバル → バンドル済み（`modules/*-adapter.md`） | スキル開発、verify | Adapter |
| auto-verify | `/verify` が実行する自動検証プロセス。各受入条件の verify command を実行し、合格条件にチェックを入れ、失敗時に Issue を reopen する | /verify Skill | 自動検証 |
| Capability | `.wholework.yml` `capabilities.*`（例: `capabilities.browser: true`）で宣言する機能の可用性。`HAS_{NAME}_CAPABILITY` 環境変数に変換され、スキルが補助ファイルの読み込みや adapter の呼び出し前に確認する。実行環境に応じたプログレッシブ・ディスクロージャーを実現する | スキル開発、設定 | Capability |
| Domain file | スキルから marker 検出、ファイル存在確認、ディレクトリスキャンによって条件付きで読み込まれる補助 Markdown。SKILL.md のコアを補い、環境やプロジェクト固有のロジックを加えつつコアを軽量に保つ。プロジェクトローカルのカスタマイズは `.wholework/domains/{skill}/` で対応 | スキル開発 | Domain file |
| Drift | ドキュメント化された仕様（Steering Documents や Spec）と実際のコード実装とのあいだの意味的乖離。`/audit drift` で検出 | /audit Skill | ドリフト |
| Fork context | メインの対話に影響を与えないスキル実行モード | Claude Code | fork コンテキスト |
| Patch route | XS/S サイズ Issue のワークフロー経路。Pull Request を作成せず main ブランチに直接コミットする | 開発ワークフロー | パッチ経路 |
| Phase label | Issue の現在のワークフローステージを示す `phase/*` GitHub ラベル（例: `phase/issue`、`phase/spec`、`phase/ready`、`phase/code`） | 開発ワークフロー | フェーズラベル |
| PR route | M/L サイズ Issue のワークフロー経路。マージ前にコードレビュー用の Pull Request を作成する | 開発ワークフロー | PR 経路 |
| Project Documents | プロジェクトのワークフローや運用手順ドキュメント。`docs/` 配下に保存 | /doc Skill | Project Documents |
| Retrospective | 各スキル実行後に Spec に追記されるセクション。そのフェーズの観察、判断、不確実性の解消を記録する。ワークフローフェーズ横断の実行履歴を蓄積する | 開発ワークフロー | レトロスペクティブ |
| Shared module | `modules/*.md` に保存され、複数スキルから "Read and follow" パターンで参照される手順ドキュメント。旧称: "shared procedure document" | スキル開発 | 共有モジュール |
| Size | triage で割り当てられる複雑度/工数の見積もり（XS/S/M/L/XL）。ワークフロー経路（patch vs PR）と Spec の深度を決める | /triage Skill | サイズ |
| Skill | Claude Code の拡張。処理ステップが `skills/<n>/SKILL.md` に記述され、`/<n>` で呼び出される | Claude Code | スキル |
| Spec | `/spec` により作成される実装計画ドキュメント。`docs/spec/issue-N-short-title.md` に保存される。**各スキル実行後の Retrospective も蓄積し、ワークフロー横断のメモリとして機能する**。旧称: 'Design file' / 'Issue Spec' | 開発ワークフロー | Spec |
| Steering Documents | 基盤ドキュメント（product/tech/structure）の総称。`docs/` 配下に保存 | /doc Skill | Steering Documents |
| Sub-agent | Task ツール経由で起動されるサブエージェント。メインエージェントには結果のみを返す | Claude Code | サブエージェント |
| Sub-issue | XL Issue を分解した子 Issue。`/auto` は `blockedBy` 依存グラフを読み、独立サブ issue を並列実行（worktree 分離）し、依存先はブロッカー完了後に順次実行する | 開発ワークフロー | サブ Issue |
| verify command | `<!-- verify: ... -->` 形式の HTML コメント。受入条件に機械検証可能な方法を付与する。旧称: "verification hint / Acceptance check" | /issue, /verify | verify command |
| verify command type | verify command の先頭トークン（例: `file_exists`、`grep`、`section_contains`、`command`）。受入条件に適用する検査方法を識別する | /issue, /verify | verify command タイプ |
