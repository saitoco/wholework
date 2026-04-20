[English](../structure.md) | 日本語

# Structure

## ディレクトリ構成（Required）

```
wholework/
├── .claude/
│   ├── settings.json.template  # ${HOME} プレースホルダ付きテンプレート（追跡対象）
│   └── settings.json           # install.sh により生成（gitignore）
├── .claude-plugin/      # Plugin マニフェストディレクトリ
│   ├── plugin.json      # Plugin マニフェスト（name: "wholework"）
│   └── marketplace.json # Marketplace マニフェスト（name: "saitoco-wholework"）
├── skills/              # Claude Code スキル（1 スキル 1 サブディレクトリ）
│   └── <skill-name>/
│       ├── SKILL.md     # スキル定義（必須）
│       └── *.md         # 補助的な phase/ガイドラインファイル（任意）
├── modules/             # スキルから参照される共有モジュール（27 ファイル）
│   └── <module-name>.md
├── agents/              # エージェント定義（6 ファイル）
│   └── <agent-name>.md
├── scripts/             # スキルとエージェントが使用するユーティリティスクリプト（37 ファイル）
│   └── <script-name>.{sh,py}
├── .github/
│   └── workflows/
│       ├── test.yml             # CI: bats テスト、スキル構文検証、禁止表現チェック
│       └── kanban-automation.yml # GitHub Projects ボードでの自動 issue 移動
├── tests/               # スクリプトの Bats テストファイル（37 ファイル）
│   ├── <script-name>.bats
│   └── fixtures/        # テスト用フィクスチャファイル
├── docs/                # ドキュメントと steering documents
│   ├── structure.md     # このファイル
│   ├── product.md       # プロジェクトビジョン、非ゴール、用語（steering）
│   ├── tech.md          # 技術スタック、アーキテクチャ決定、禁止表現（steering）
│   ├── workflow.md      # 開発ワークフローのフェーズとラベル遷移（project）
│   ├── migration-notes.md # 移行 issue ごとのインターフェース変更記録（project）
│   ├── environment-adaptation.md # 環境適応アーキテクチャ（4 層）（project）
│   ├── versioning.md    # リリース versioning ポリシー（project）
│   ├── routines-adoption.md # Routines 採用ロードマップと PoC 知見（project）
│   ├── guide/           # ユーザー向けマニュアル（index、quick-start、workflow、customization、troubleshooting、adapter-guide、figma-best-practices）（project）
│   ├── {lang}/          # /doc translate {lang} が生成する言語別翻訳（docs/{lang}/）
│   ├── spec/            # Issue 仕様
│   ├── reports/         # 最適化・監査レポート
│   └── stats/           # プロジェクト健全性診断レポート（/audit stats が生成、YYYY-MM-DD.md）
├── .wholework/          # プロジェクトローカルな Wholework 設定（ユーザー管理、wholework リポジトリでは追跡しない）
│   ├── adapters/        # 検証 adapter のオーバーライド
│   ├── verify-commands/ # プロジェクトローカルのカスタム verify command ハンドラ
│   └── domains/         # プロジェクトローカルの Domain files
│       ├── spec/        # /spec の Domain files
│       ├── code/        # /code の Domain files
│       └── review/      # /review の Domain files
├── install.sh           # settings.json、marketplace、plugin の同期（clone/pull 後に実行）
├── CONTRIBUTING.md      # コントリビュートガイド（DCO sign-off 手順）
├── LICENSE              # Apache License 2.0
├── README.md            # プロジェクト概要
├── README.{lang}.md     # README.md の言語別翻訳（/doc translate {lang} が生成）
└── CLAUDE.md            # Claude Code プロジェクト指示
```

## 主要ファイル（Required）

> **保守ルール**: 本セクションの表とリストは実ファイルと揃え続けること。下記一覧のファイルが追加・削除・リネームされたり、役割・説明が変わった場合は、同一の変更でここの対応エントリも更新すること。`/audit drift` が差分を検出するが、手動保守は依然として期待される。

### Skills

Skills は private リポジトリからアクティブに移行中です。各スキルは `skills/<skill-name>/SKILL.md` に存在します。多くのスキルにはサブフェーズや特化ガイドラインの補助 `.md` ファイル（例: `external-review-phase.md`、`codebase-search.md`）も含まれます。現行のリストは `skills/` ディレクトリを参照してください。

### Modules

主要モジュール:
- `modules/verify-patterns.md` — verify command パターン精度ガイドライン
- `modules/verify-classifier.md` — マージ後条件の検証可能性分類
- `modules/verify-executor.md` — verify command の変換と実行
- `modules/worktree-lifecycle.md` — 全スキル共有の worktree Entry/Exit ライフサイクル
- `modules/test-runner.md` — 品質チェック実行と結果分析
- `modules/size-workflow-table.md` — サイズ→ワークフロー判断テーブル
- `modules/detect-config-markers.md` — `.wholework.yml` 設定検出
- `modules/adapter-resolver.md` — 3 層 adapter 解決（プロジェクトローカル → ユーザーグローバル → バンドル）
- `modules/opportunistic-verify.md` — スキル完了時の opportunistic 検証
- `modules/doc-checker.md` — ドキュメント一貫性チェッカー
- `modules/doc-commit-push.md` — /doc サブコマンド出力の commit/push ガイド
- `modules/domain-loader.md` — プロジェクトローカル domain ファイルの発見とロード
- `modules/skill-help.md` — スキル共通の `--help` 出力フォーマッタ
- `modules/skill-dev-checks.md` — スキル横断の一貫性検証
- `modules/codebase-analysis.md` — `/doc` deep モード用のコードベース分析
- `modules/title-normalizer.md` — issue タイトル正規化
- `modules/ambiguity-detector.md` — issue 記述のあいまいさ検出
- `modules/review-output-format.md` — レビュー出力フォーマット
- `modules/review-type-weighting.md` — レビュー種別の重み付け設定
- `modules/project-field-update.md` — GitHub Projects のフィールド更新
- `modules/browser-adapter.md` — ブラウザベース検証 adapter
- `modules/browser-verify-security.md` — ブラウザ検証のセキュリティチェック
- `modules/lighthouse-adapter.md` — Lighthouse パフォーマンス監査 adapter
- `modules/measurement-scope.md` — 計測スコープ定義
- `modules/next-action-guide.md` — 全スキル共通の次アクション案内
- `modules/phase-banner.md` — スキル用フェーズ識別バナー表示
- `modules/steering-hint.md` — steering docs が無い場合に `/doc init` を促す動的ヒント

### Agents

| Agent | パス | 説明 |
|---|---|---|
| review-bug | `agents/review-bug.md` | バグ/ロジックエラー検出（HIGH SIGNAL） |
| review-light | `agents/review-light.md` | 軽量統合レビュー（4 観点すべて） |
| review-spec | `agents/review-spec.md` | Spec/ドキュメントレビュー |
| issue-scope | `agents/issue-scope.md` | L/XL issue のスコープ調査 |
| issue-risk | `agents/issue-risk.md` | L/XL issue のリスク調査 |
| issue-precedent | `agents/issue-precedent.md` | 類似 issue からの前例調査 |

### Scripts

**Phase banner:**
- `scripts/phase-banner.sh` — run-*.sh スクリプトで `print_start_banner` / `print_end_banner` 関数を提供する source 可能なヘルパー

**GitHub API ユーティリティ:**
- `scripts/gh-graphql.sh` — キャッシュ付き GraphQL クエリ実行
- `scripts/gh-issue-comment.sh` — issue へのコメント投稿
- `scripts/gh-issue-edit.sh` — issue 本文編集（チェックボックス更新）
- `scripts/gh-label-transition.sh` — フェーズラベル遷移
- `scripts/gh-check-blocking.sh` — ブロッキング issue 依存関係チェック
- `scripts/gh-extract-issue-from-pr.sh` — PR からリンク先 issue を抽出
- `scripts/gh-pr-merge-status.sh` — PR のマージステータス確認
- `scripts/gh-pr-review.sh` — PR レビュー投稿

**プロジェクトユーティリティ:**
- `scripts/get-issue-size.sh` — issue サイズラベル取得
- `scripts/get-issue-type.sh` — issue タイプラベル取得
- `scripts/get-issue-priority.sh` — issue priority フィールド取得
- `scripts/get-sub-issue-graph.sh` — サブ issue 依存グラフ構築
- `scripts/get-verify-iteration.sh` — Issue コメントから `<!-- verify-iteration: N -->` マーカーの最大値を読み取る
- `scripts/log-permission.sh` — 権限イベントログ（JSON 出力）
- `scripts/opportunistic-search.sh` — opportunistic スキル検索
- `scripts/triage-backlog-filter.sh` — triage 向けバックログフィルタ
- `scripts/get-verify-permission.sh` — verify コマンドハンドラファイルから permission 値を抽出

**プロセス管理:**
- `scripts/claude-watchdog.sh` — `claude -p` 呼び出し用の watchdog ラッパー（hang 検知 + 1 回リトライ）
- `scripts/watchdog-reconcile.sh` — kill 後の状態リコンサイラ。watchdog kill（exit 143）後に期待 phase 状態を検証し、到達済みなら exit 0 に昇格
- `scripts/wait-ci-checks.sh` — claude 実行前に PR の全 CI チェック完了を待機

**Skill runners:**
- `scripts/run-auto-sub.sh` — サブ issue 向け auto ワークフロー実行
- `scripts/run-code.sh` — code スキル実行
- `scripts/run-issue.sh` — issue スキル実行
- `scripts/run-merge.sh` — merge スキル実行
- `scripts/run-review.sh` — review スキル実行
- `scripts/run-spec.sh` — spec スキル実行
- `scripts/run-verify.sh` — verify スキル実行

**ツーリング:**
- `scripts/validate-permissions.sh` — skill ディレクトリと name: フィールドの一貫性を検証
- `scripts/validate-skill-syntax.py` — SKILL.md frontmatter と構文を検証
- `scripts/check-file-overlap.sh` — リポジトリ間のファイル重複検出
- `scripts/check-translation-sync.sh` — docs/ja/* と docs/* の翻訳同期状況を確認
- `scripts/check-forbidden-expressions.sh` — docs/product.md § Terms の deprecated terms を検出
- `scripts/setup-labels.sh` — ワークフロー用 GitHub ラベルを作成
- `scripts/test-skills.sh` — 全スキルテスト実行
- `scripts/wait-external-review.sh` — 外部レビュー完了待ち

### CI ワークフロー

- `.github/workflows/test.yml` — push/PR 時に bats テスト、`validate-skill-syntax.py`、禁止表現チェックを実行
- `.github/workflows/dco.yml` — 全 PR コミットに対して DCO `Signed-off-by:` を必須化
- `.github/workflows/kanban-automation.yml` — `phase/*` ラベルイベントで issue をプロジェクトボードのカラムへ自動移動

### Install

Wholework は 2 種類のインストール方法をサポートします。

**Marketplace install**（推奨）:

```sh
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Marketplace マニフェストは `.claude-plugin/marketplace.json` にあります（name: `saitoco-wholework`）。

**Development install**（ローカル）:

```sh
git clone https://github.com/saitoco/wholework.git
cd wholework
./install.sh
claude --plugin-dir <path-to-wholework>
```

Skill は `wholework:<skill-name>` として検出されます。Claude Code は実行時に `${CLAUDE_PLUGIN_ROOT}` を plugin ディレクトリに設定し、skills や modules はこれを使って scripts や modules を参照します。

**なぜ `./install.sh` が必要か?** `.claude/settings.json` は `.claude/settings.json.template` からユーザー実際の `$HOME` を `${HOME}` に置換して生成されます。Claude Code は `permissions.allow` 内部で `${HOME}` や `~/` を展開しないため、各開発者がテンプレートをローカルで具体化する必要があります。生成される `.claude/settings.json` は gitignore 対象です。clone 後に 1 回、その後 `git pull` で `.claude/settings.json.template` が変わるたびに `./install.sh` を実行してください。

`./install.sh` は `claude plugin marketplace update` と `claude plugin update` も実行し、ローカルの plugin をリポジトリの最新バージョンと同期します。`--no-plugin` で plugin 更新ステップをスキップできます（settings.json 再生成のみ）。`--marketplace NAME` で marketplace 名を上書きできます（デフォルト: `saitoco-wholework`）。

<!-- ## Module Dependencies（Optional）

モジュール間の依存関係を記述する。 -->

<!-- ## File Naming Conventions（Optional）

ファイル命名規則を記述する。 -->
