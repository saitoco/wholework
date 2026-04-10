# Structure

## ディレクトリレイアウト（Required）

```
wholework/
├── .claude/
│   └── settings.json    # リポジトリレベルの Claude Code 設定（フック、パーミッション）
├── .claude-plugin/      # Plugin マニフェストディレクトリ
│   ├── plugin.json      # Plugin マニフェスト（name: "wholework"）
│   └── marketplace.json # Marketplace マニフェスト（name: "saitoco-wholework"）
├── skills/              # Claude Code skills（Skill ごとにサブディレクトリを配置）
│   └── <skill-name>/
│       ├── SKILL.md     # Skill 定義（必須）
│       └── *.md         # 補助的なフェーズ/ガイドラインファイル（任意）
├── modules/             # Skill から参照される共有モジュール（22 ファイル）
│   └── <module-name>.md
├── agents/              # エージェント定義（6 ファイル）
│   └── <agent-name>.md
├── scripts/             # Skill やエージェントが使用するユーティリティスクリプト（27 ファイル）
│   └── <script-name>.{sh,py}
├── .github/
│   └── workflows/
│       ├── test.yml             # CI: bats テストと Skill 構文検証
│       └── kanban-automation.yml # GitHub Projects ボード上の Issue 自動移動
├── tests/               # スクリプト用の Bats テストファイル（25 ファイル）
│   ├── <script-name>.bats
│   └── fixtures/        # テストフィクスチャファイル
├── docs/                # ドキュメントと Steering Documents
│   ├── structure.md     # このファイル
│   ├── product.md       # プロジェクトビジョン、非目標、用語集（steering）
│   ├── tech.md          # 技術スタック、アーキテクチャ決定、Forbidden Expressions（steering）
│   ├── workflow.md      # 開発ワークフローのフェーズとラベル遷移（project）
│   ├── figma-best-practices.md # Figma MCP UI デザインガイドライン（project）
│   ├── migration-notes.md # 移行 Issue ごとのインターフェース変更記録（project）
│   ├── environment-adaptation.md # 環境適応アーキテクチャ（4 レイヤー）（project）
│   ├── ja/              # /doc translate が生成する日本語翻訳（docs/ja/）
│   └── spec/            # Issue 仕様書
├── LICENSE              # Apache License 2.0
├── README.md            # プロジェクト概要
├── README.ja.md         # README.md の日本語訳（/doc translate が生成）
└── CLAUDE.md            # Claude Code プロジェクト指示
```

## Key Files（Required）

### Skills

Skill はプライベートリポジトリから現在進行形で移行されています。各 Skill は `skills/<skill-name>/SKILL.md` に配置されます。多くの Skill はサブフェーズや特化したガイドライン用の補助 `.md` ファイル（例: `external-review-phase.md`、`codebase-search.md`）も含みます。現在のリストは `skills/` ディレクトリを参照してください。

### Modules

主要モジュール:
- `modules/verify-patterns.md` — verify command パターンの精度ガイドライン
- `modules/verify-classifier.md` — post-merge 条件の検証可能性分類
- `modules/verify-executor.md` — verify command の変換と実行
- `modules/worktree-lifecycle.md` — 全 Skill 共通の worktree Entry/Exit ライフサイクル
- `modules/test-runner.md` — 品質チェックの実行と結果分析
- `modules/size-workflow-table.md` — Size→ワークフロー判定表
- `modules/detect-config-markers.md` — `.wholework.yml` 設定の検出
- `modules/adapter-resolver.md` — 3 層のアダプタ解決（project-local → user-global → bundled）
- `modules/opportunistic-verify.md` — Skill 完了時の日和見検証
- `modules/doc-checker.md` — ドキュメント整合性チェッカ
- `modules/skill-help.md` — Skill 用の共有 `--help` 出力フォーマッタ
- `modules/skill-dev-checks.md` — Skill 横断の整合性検証
- `modules/codebase-analysis.md` — `/doc` deep モード用のコードベース分析
- `modules/title-normalizer.md` — Issue タイトル正規化
- `modules/ambiguity-detector.md` — Issue 記述の曖昧性検出
- `modules/review-output-format.md` — レビュー出力フォーマット
- `modules/review-type-weighting.md` — レビュー種別の重み付け設定
- `modules/project-field-update.md` — GitHub Projects フィールド更新
- `modules/browser-adapter.md` — ブラウザベース検証アダプタ
- `modules/browser-verify-security.md` — ブラウザ検証のセキュリティチェック
- `modules/lighthouse-adapter.md` — Lighthouse パフォーマンス監査アダプタ
- `modules/measurement-scope.md` — 測定範囲定義

### Agents

| エージェント | パス | 説明 |
|---|---|---|
| review-bug | `agents/review-bug.md` | バグ/ロジックエラー検出（HIGH SIGNAL） |
| review-light | `agents/review-light.md` | 軽量統合レビュー（全 4 観点） |
| review-spec | `agents/review-spec.md` | Spec/ドキュメントレビュー |
| scope-agent | `agents/scope-agent.md` | L/XL Issue のスコープ調査 |
| risk-agent | `agents/risk-agent.md` | L/XL Issue のリスク調査 |
| precedent-agent | `agents/precedent-agent.md` | 類似 Issue からの先行事例調査 |

### Scripts

**GitHub API ユーティリティ:**
- `scripts/gh-graphql.sh` — キャッシュ付き GraphQL クエリ実行
- `scripts/gh-issue-comment.sh` — Issue へのコメント投稿
- `scripts/gh-issue-edit.sh` — Issue 本文の編集（チェックボックス更新）
- `scripts/gh-label-transition.sh` — phase ラベルの遷移
- `scripts/gh-check-blocking.sh` — ブロッキング Issue 依存のチェック
- `scripts/gh-extract-issue-from-pr.sh` — PR からリンクされた Issue の抽出
- `scripts/gh-pr-merge-status.sh` — PR マージ状態の確認
- `scripts/gh-pr-review.sh` — PR レビューの投稿

**プロジェクトユーティリティ:**
- `scripts/get-issue-size.sh` — Issue の Size ラベル取得
- `scripts/get-issue-type.sh` — Issue の Type ラベル取得
- `scripts/get-sub-issue-graph.sh` — サブ Issue 依存グラフ構築
- `scripts/log-permission.sh` — パーミッションイベントのログ出力（JSON）
- `scripts/opportunistic-search.sh` — 日和見 Skill 検索
- `scripts/triage-backlog-filter.sh` — triage 対象のバックログフィルタ

**Skill ランナー:**
- `scripts/run-auto-sub.sh` — サブ Issue に対する auto ワークフロー実行
- `scripts/run-code.sh` — code Skill の実行
- `scripts/run-issue.sh` — issue Skill の実行
- `scripts/run-merge.sh` — merge Skill の実行
- `scripts/run-review.sh` — review Skill の実行
- `scripts/run-spec.sh` — spec Skill の実行
- `scripts/run-verify.sh` — verify Skill の実行

**ツーリング:**
- `scripts/validate-permissions.sh` — Skill ディレクトリ ↔ `name:` フィールドの整合性検証
- `scripts/validate-skill-syntax.py` — SKILL.md の frontmatter と構文検証
- `scripts/check-file-overlap.sh` — リポジトリ間のファイル重複検出
- `scripts/setup-labels.sh` — ワークフロー用 GitHub ラベルの作成
- `scripts/test-skills.sh` — 全 Skill テストの実行
- `scripts/wait-external-review.sh` — 外部レビュー完了待ち

### CI ワークフロー

- `.github/workflows/test.yml` — push/PR で bats テストと `validate-skill-syntax.py` を実行
- `.github/workflows/kanban-automation.yml` — `phase/*` ラベルイベントで Issue をプロジェクトボードのカラムへ自動移動

### インストール

Wholework は 2 つのインストール方法をサポートします:

**Marketplace インストール**（主要）:

```sh
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Marketplace マニフェストは `.claude-plugin/marketplace.json`（name: `saitoco-wholework`）にあります。

**開発インストール**（ローカル）:

```sh
git clone https://github.com/saitoco/wholework.git
claude --plugin-dir <path-to-wholework>
```

Skill は `wholework:<skill-name>` として検出されます。Claude Code は実行時に `${CLAUDE_PLUGIN_ROOT}` を Plugin ディレクトリに設定し、Skill とモジュールがスクリプトやモジュールを参照する際に使用します。

<!-- ## Module Dependencies（Optional）

モジュール間の依存関係を記述する。 -->

<!-- ## File Naming Conventions（Optional）

ファイル命名規則を記述する。 -->
