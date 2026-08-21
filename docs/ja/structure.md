[English](../structure.md) | 日本語

# Structure

## ディレクトリ構成（Required）

```
wholework/
├── .claude/
│   ├── settings.json.template  # ${HOME} プレースホルダー付きテンプレート (トラッキング対象)
│   └── settings.json           # install.sh が生成 (gitignore 対象)
├── .claude-plugin/      # Plugin マニフェストディレクトリ
│   ├── plugin.json      # Plugin マニフェスト (name: "wholework")
│   └── marketplace.json # Marketplace マニフェスト (name: "saitoco-wholework")
├── hooks/               # Plugin レベルの hook 定義
│   └── hooks.json       # UserPromptSubmit hook (session-auto-rename オプトイン)
├── skills/              # Claude Code skills (skill ごとに 1 サブディレクトリ)
│   └── <skill-name>/
│       ├── SKILL.md     # Skill 定義 (必須)
│       └── *.md         # 補助的な phase/guideline ファイル (任意)
├── modules/             # skills から参照される共有モジュール (46 ファイル)
│   └── <module-name>.md
├── agents/              # Agent 定義 (8 ファイル)
│   └── <agent-name>.md
├── scripts/             # skills と agents が使用するユーティリティスクリプト (91 ファイル)
│   ├── git-hooks/       # Git hook スクリプト (commit-msg DCO 強制)
│   └── <script-name>.{sh,py}
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml       # Bug report Issue Form
│   │   ├── feature_request.yml  # Feature request Issue Form
│   │   └── config.yml           # ブランク (テンプレートなし) Issue を無効化
│   └── workflows/
│       ├── test.yml             # CI: bats テスト、skill 構文検証、禁止表現チェック、裸括弧アサーションチェック、言語規約チェック、macOS シェル互換性テスト
│       └── kanban-automation.yml # GitHub Projects board の Issue 自動移動
├── examples/            # Wholework 機能のサンプルファイル
│   └── decomposition/   # /issue --from-decomposition-file 用の decomposition YAML サンプル
├── tests/               # スクリプト用の Bats テストファイル (127 ファイル)
│   ├── <script-name>.bats
│   └── fixtures/        # テストフィクスチャファイル
├── docs/                # ドキュメントと steering document
│   ├── structure.md     # このファイル
│   ├── product.md       # プロジェクトビジョン、Non-Goals、terminology (steering)
│   ├── tech.md          # 技術スタック、アーキテクチャ決定、禁止表現 (steering)
│   ├── workflow.md      # 開発ワークフローフェーズとラベル遷移 (project)
│   ├── migration-notes.md # migration Issue ごとのインターフェース変更記録 (project)
│   ├── environment-adaptation.md # 環境適応アーキテクチャ (4 層) (project)
│   ├── versioning.md    # リリースバージョニングポリシー (project)
│   ├── translation-workflow.md # docs/ja/ ミラー同期のルールと手順 (project)
│   ├── visual-reproduction.md  # UI 再現方法論ガイド (project)
│   ├── guide/           # ユーザー向けマニュアル (index、quick-start、workflow、customization、troubleshooting、adapter-guide、figma-best-practices、scripting、xl-decomposition、autonomy) (project)
│   ├── {lang}/          # /doc translate {lang} が生成する言語翻訳 (docs/{lang}/)
│   ├── spec/            # Issue 仕様
│   ├── reports/         # 最適化と監査のレポート (routines-adoption.md を含む — 採用しなかった方向性だが記録として保持)
│   ├── stats/           # プロジェクトヘルス診断レポート (/audit stats が生成、YYYY-MM-DD.md)
│   └── sessions/        # セッション関連の自動生成出力
│         {SID}-{DATE}/  # L3 セッション retrospective (/auto Step 5 の L3 トリガーが生成、notable な batch/XL のみ)
│           session.md       # L3 ナラティブ (What worked / Findings — disposition タグ付き) + get-auto-session-report.sh --metrics-only による機械生成の `## Metrics` セクション
│           events.jsonl     # .tmp/auto-events.jsonl から抽出されたセッションスコープのイベント (notable ではないセッションはこのファイルのみをコミット)
├── .wholework/          # プロジェクトローカルの Wholework 設定 (ユーザー管理、wholework リポジトリではトラッキングされない)
│   ├── adapters/        # 検証アダプタのオーバーライド
│   ├── verify-commands/ # プロジェクトローカルのカスタム verify command ハンドラ
│   └── domains/         # プロジェクトローカルの Domain file
│       ├── spec/        # /spec 用の Domain file
│       ├── code/        # /code 用の Domain file
│       ├── review/      # /review 用の Domain file
│       └── verify/      # /verify 用の Domain file
├── install.sh           # settings.json、marketplace、plugin を同期 (clone または pull 後に実行)
├── CONTRIBUTING.md      # コントリビューションガイド (DCO sign-off の手順)
├── LICENSE              # Apache License 2.0
├── README.md            # プロジェクト概要
├── README.{lang}.md     # README.md の言語翻訳 (/doc translate {lang} が生成)
├── SECURITY.md          # 副作用、必要な権限、permission-bypass の挙動
└── CLAUDE.md            # Claude Code プロジェクト指示
```

## 主要ファイル（Required）

> **メンテナンスルール**: このセクションの表とリストは実際のファイルと整合させること。以下に列挙されたファイルが追加・削除・リネームされたり、役割/説明が変わった場合は、同じ変更の中で該当エントリを更新すること。`/audit drift` が乖離を検出するが、手動でのメンテナンスは引き続き必要である。
>
> `modules/` または `scripts/` にファイルを追加・削除する場合は、上記 Directory Layout セクションのファイル数コメント (例: `(29 files)`) も更新し、PR の受入基準に件数を確認する verify command を含めること (例: `<!-- verify: grep "(29 files)" "docs/structure.md" -->`)。

### Skills

各 skill は `skills/<skill-name>/SKILL.md` に存在する。多くの skill はサブフェーズや専用ガイドラインのための補助 `.md` ファイルを含む (例: `external-review-phase.md`、`codebase-search.md`)。

| Skill | Path | 役割 |
|---|---|---|
| issue | `skills/issue/SKILL.md` | Issue の作成と洗練 (What レベル) |
| spec | `skills/spec/SKILL.md` | Issue の仕様化と実装計画 (How レベル) |
| code | `skills/code/SKILL.md` | ローカル実装 (patch / pr / operate 経路) |
| review | `skills/review/SKILL.md` | PR レビュー (受入基準 + マルチパースペクティブ) |
| merge | `skills/merge/SKILL.md` | Squash merge とブランチ削除 |
| verify | `skills/verify/SKILL.md` | マージ後の受入テスト |
| auto | `skills/auto/SKILL.md` | spec→code→review→merge→verify を連鎖するオーケストレーター |
| triage | `skills/triage/SKILL.md` | タイトル正規化と Type/Size/Priority/Value の割り当て |
| audit | `skills/audit/SKILL.md` | Drift と fragility の検出、Issue 自動生成 |
| doc | `skills/doc/SKILL.md` | Steering/project document の管理と正規化 |

### Modules

主なモジュール:
- `modules/verify-patterns.md` — verify command パターンの正確性ガイドライン
- `modules/verify-classifier.md` — マージ後条件の検証可能性分類 (同じ `manual` タグ値は、別の `/issue` 経路を通じてマージ前条件にも割り当てられる — モジュール参照)
- `modules/observation-trigger.md` — observation AC トリガーメカニズムの設計 (呼び出しインターフェース、emitter lookup、dispatch contract)
- `modules/run-fact-matching.md` — run-fact AC reconciliation の SSoT: 完了した `/auto` 実行のファクトを構造化し、保留中の `phase/verify` マージ後 AC (manual/observation/opportunistic/auto すべて) と照合する。autonomy tier によってゲートされる
- `modules/verify-executor.md` — verify command の変換と実行
- `modules/worktree-lifecycle.md` — 全 skill 共通の worktree Entry/Exit ライフサイクル
- `modules/test-runner.md` — 品質チェックの実行と結果分析
- `modules/size-workflow-table.md` — Size からワークフローへの決定テーブル
- `modules/detect-config-markers.md` — `.wholework.yml` の設定検出
- `modules/adapter-resolver.md` — 3 層のアダプタ解決 (project-local → user-global → bundled)
- `modules/opportunistic-verify.md` — skill 完了時の opportunistic な検証
- `modules/doc-checker.md` — ドキュメント整合性チェッカー
- `modules/doc-scan-exclusions.md` — frontmatter ベースのドキュメントスキャン除外パターンの SSoT (`/doc` と `/audit` で共有)
- `modules/doc-commit-push.md` — /doc サブコマンド出力のコミット/プッシュガイド
- `modules/domain-loader.md` — bundled および project-local Domain file の発見と条件付き読み込み
- `modules/execution-context.md` — 実行コンテキスト (fork vs main) の決定基準とコンテキストごとの制約 (verify command の safe/full モードポリシー)。「Re-invocation Guarantee and Notification-Dependent Waiting」ルール (バックグラウンドタスクの通知待ちでターンを終えてはならない実行サーフェスを定めた横断的な SSoT) でもある
- `modules/skill-help.md` — skill 共通の `--help` 出力フォーマッタ
- `modules/skill-dev-checks.md` — skill 横断の整合性検証
- `modules/codebase-analysis.md` — `/doc` の deep モード用コードベース分析
- `modules/title-normalizer.md` — issue title の正規化
- `modules/l0-surfaces.md` — L0 (GitHub) サーフェスの SSoT と comment-as-first-class-input ポリシー
- `modules/label-conventions.md` — ラベル名前空間の規約と裸名前空間の例外 (SSoT)
- `modules/ambiguity-detector.md` — issue 記述内の曖昧性検出
- `modules/review-output-format.md` — review 出力のフォーマットと MUST/SHOULD/CONSIDER の重大度分類基準
- `modules/review-type-weighting.md` — review タイプの重み付け設定
- `modules/project-field-update.md` — GitHub Projects フィールドの更新
- `modules/browser-adapter.md` — ブラウザベースの検証アダプタ
- `modules/browser-verify-security.md` — ブラウザ検証のセキュリティチェック
- `modules/lighthouse-adapter.md` — Lighthouse パフォーマンス監査アダプタ
- `modules/visual-diff-adapter.md` — visual diff (3-panel 合成) 検証アダプタ
- `modules/measurement-scope.md` — 測定スコープの定義
- `modules/next-action-guide.md` — 全 skill 共通の次アクションガイダンス
- `modules/phase-banner.md` — skill のフェーズ識別バナー表示
- `modules/phase-handoff.md` — フェーズ間の Phase Handoff サマリー読み書き (フェーズ横断のコンテキスト引き継ぎ)
- `modules/steering-hint.md` — steering doc が存在しない場合に `/doc init` を推奨する動的ヒント
- `modules/orchestration-fallbacks.md` — オーケストレーションレベルの fallback パターンリファレンスカタログ (#319 tier 2、#316 recovery sub-agent、#318 learning loop で消費)。発火履歴がなく参照もされていないエントリは `docs/reports/orchestration-fallbacks-archive.md` にアーカイブされる (#1180)
- `modules/ci-failure-classifier.md` — CI プラットフォーム障害分類の SSoT (シグネチャ表、3 値の判定、消費者ごとの応答)
- `modules/domain-classifier.md` — improvement proposal の Domain 分類 (合成可能、LLM-in-context)
- `modules/retro-proposals.md` — Improvement Proposal の収集、Tier 分類 (retro_proposal_classified イベント発行を伴う)、Issue 作成 (/verify Step 16、/auto Step 4a、/auto Step 5 で共有)
- `modules/filesystem-scope.md` — skill/scripts のファイルシステムアクセススコープの制約と承認済みパターン
- `modules/phase-state.md` — フェーズの前提条件/成功シグネチャと `reconcile-phase-state.sh` の JSON v1 スキーマ (SSoT)
- `modules/skill-dev-doc-impact.md` — skill 開発プロジェクトの `/spec` と `/code` 向け Change Types (`doc-checker.md` 経由)
- `modules/autonomy-tier.md` — autonomy tier (L2→L1 経路の許可) の SSoT: tier × path マトリクス、Tier × L0 write マトリクス、skill frontmatter 宣言ルール
- `modules/event-emission.md` — イベント発行契約の SSoT (フェーズイベントスキーマ、_EMIT_PHASE_OWNED パターン、run-*.sh 用の wrapper カバレッジテーブル)
- `modules/round-ordering.md` — `/auto --batch --until` の Round `ROUND_LIST` 並べ替え (ROI + タイトル prefix クラスタリング + 意味的関係の判断、cluster-first の組み合わせ)
- `modules/costly-step-protocol.md` — `spec-approval-needed` マーカー形式、`/spec` producer contract、`/code` consumer contract、コストのかかる/不可逆的な Implementation Step のための必須 Deferral Protocol 記法

### Agents

| Agent | Path | Description |
|---|---|---|
| review-bug | `agents/review-bug.md` | Bug/Logic Error 検出 (coverage-first、confidence+severity タグ付き) |
| review-light | `agents/review-light.md` | 軽量統合レビュー (4 つの観点すべて) |
| review-spec | `agents/review-spec.md` | Spec/Documentation レビュー |
| issue-scope | `agents/issue-scope.md` | L/XL issue のスコープ調査 |
| issue-risk | `agents/issue-risk.md` | L/XL issue のリスク調査 |
| issue-precedent | `agents/issue-precedent.md` | 類似 issue からの前例調査 |
| orchestration-recovery | `agents/orchestration-recovery.md` | 未知のオーケストレーション障害に対する復旧診断者 |
| frontend-visual-review | `agents/frontend-visual-review.md` | 3-panel 比較画像からの視覚的差異列挙 (visual-diff-adapter が起動) |

### Scripts

**Phase banner:**
- `scripts/phase-banner.sh` — run-*.sh スクリプト向けに `print_start_banner` / `print_end_banner` 関数を提供する sourceable なヘルパー
- `scripts/emit-event.sh` — `.tmp/auto-events.jsonl` への構造化 JSONL イベント発行のための `emit_event()` を提供する sourceable なヘルパー。加えて、非 wrapper の emitter でポインタファイルから `AUTO_SESSION_ID`/`AUTO_EVENTS_LOG` を復元する `restore_auto_session_pointer()` と、in-band `--session-id` の引き継ぎが依存する issue-scoped ポインタファイルの書き込み/削除を行う `persist_auto_session_pointer()` を提供する (#1075)。run-*.sh、claude-watchdog.sh、wait-ci-checks.sh、`skills/verify/SKILL.md` (明示的な bash 呼び出し、wrapper なし) で使用される
- `scripts/append-consumed-comments-section.sh` — フェーズ自身の作業ブランチ上で Spec に `## Consumed Comments` を追記する。呼び出し元の網羅的なリスト、`--no-push` の使い方、フェーズごとの二次層カバレッジは [`modules/l0-surfaces.md`](../modules/l0-surfaces.md) § "Bash wrapper fallback" (SSoT) を参照
- `scripts/dedupe-phase-handoff-section.sh` — `## Phase Handoff` セクション用の決定的な二次層ローテーションフォールバック: 2 個以上の `## Phase Handoff` 見出しを持つ Spec ファイルを最後 (最新) の 1 個に折りたたむ。呼び出し元リスト (`code`/`review`/`merge`) は [`modules/phase-handoff.md`](../modules/phase-handoff.md) § "Deterministic rotation fallback" を参照
- `scripts/hook-worktree-path-guard.sh` — PreToolUse hook: worktree セッション中に親リポジトリの絶対 file_path を伴う Edit/Write 呼び出しをブロックする (`modules/worktree-lifecycle.md § Edit/Write path conventions in worktree sessions` の構造的な強制)

**GitHub API ユーティリティ:**
- `scripts/gh-graphql.sh` — キャッシュ付き GraphQL クエリ実行
- `scripts/gh-issue-comment.sh` — issue へのコメント投稿
- `scripts/gh-issue-edit.sh` — issue 本文の編集 (チェックボックス更新)
- `scripts/gh-label-transition.sh` — フェーズラベルの遷移
- `scripts/gh-check-blocking.sh` — ブロッキング issue 依存関係のチェック
- `scripts/set-blocked-by.sh` — issue 番号による GitHub blocked-by 関係の設定 (`add-blocked-by` mutation の wrapper)
- `scripts/get-blocked-by.sh` — GitHub blocked-by 関係の単一読み取りウィンドウ (単一 issue モード、または全 open issue グラフ用の `--all`)
- `scripts/gh-extract-issue-from-pr.sh` — PR から紐づく issue を抽出
- `scripts/gh-pr-merge-status.sh` — PR のマージステータスをチェック
- `scripts/gh-pr-review.sh` — PR レビューの投稿

**Project ユーティリティ:**
- `scripts/collect-recovery-candidates.sh` — `docs/reports/orchestration-recoveries.md` をパースし、group-key の頻度を集計する (group-key は素の symptom-short、またはエントリの Diagnosis 本文に `- cause:` 行がある場合の `symptom-short/cause-slug`)。各エントリのタイムスタンプを解決済み Issue の `closedAt` と比較して個別に除外する (open Issue: グループ内の全エントリを除外。closed: `closedAt` 以前のエントリを除外し、それ以降のエントリをカウント — `--issues-json` が `state`/`closedAt` を欠く場合はグループ自身の最新の `起票済み #N` エントリのタイムスタンプにフォールバック)。加えて、`### Improvement Candidate` 本文が `- N/A` で始まるエントリ (対応不要な Tier 2 fallback 成功) を除外する。`--threshold K` フィルタを適用し、`<group-key>\t<count>` の候補を出力する (`--with-tracking` で 3 列目の `tracked:#N:open`/`tracked:#N:closed`/`untracked` を追加 — open/closed の接尾辞はトラッキング対象 Issue の解決済み状態を反映し、状態が解決できない場合は素の `tracked:#N` にフォールバックする)。Issue の解決には `--issues-json PATH` (`state`/`closedAt` を含む全状態の issue リスト) を受け付ける
- `scripts/collect-opportunistic-retire-candidates.sh` — コミットされた `docs/sessions/*/events.jsonl` から `opportunistic_verify_result` イベントを集計する。(issue, ac_index) でグループ化し、直近の連続した判定がすべて `SKIP` であるグループ (trailing-SKIP streak) を `/audit stats --retention` Section 11 用に報告する
- `scripts/collect-verify-retention-stats.sh` — verify-type ごとに `phase/verify` の滞留を測定する (マージ後 AC がどれだけ待機中か、その待機がどれだけ古いか)。比較ウィンドウの日付フィルタはオプション。`/audit stats --retention` 用
- `scripts/get-config-value.sh` — `.wholework.yml` から設定値を抽出
- `scripts/html-selector-match.py` — 標準ライブラリのみを使う Python の CSS セレクタマッチャ (複合セレクタ + descendant/`>`/`+`/`~` コンビネータチェーン)。`modules/verify-executor.md` の `html_check` verify command で使用される。`curl | python3 html-selector-match.py "selector"` で stdin から HTML を読み、マッチ件数を出力する
- `scripts/handle-permission-mode-failure.sh` — `--permission-mode auto` classifier の失敗の可能性を診断し、修復ヒントを stderr に出力する (ヒューリスティック: exit!=0 かつ elapsed<=30s)
- `scripts/get-verify-permission.sh` — verify command ハンドラファイルから権限値を抽出
- `scripts/get-issue-size.sh` — issue の size ラベルを取得
- `scripts/get-issue-type.sh` — issue の type ラベルを取得
- `scripts/get-issue-priority.sh` — issue の priority フィールドを取得
- `scripts/compute-round-order.sh` — `ROUND_LIST` 内の各 issue のタイトル/Size/Value を取得し (issue ごとに 1 回の `gh-graphql.sh` ラウンドトリップ、`size/*`/`value/*` ラベルへのフォールバック)、ROI (Value/Size) を計算する。`modules/round-ordering.md` から使用される
- `scripts/get-sub-issue-graph.sh` — sub-issue 依存グラフの構築
- `scripts/get-sub-issue-progress.sh` — XL 親 issue 配下の全 sub-issue (OPEN + CLOSED) を状態、ラベル、タイムスタンプ、blockedBy とともに取得する (`/audit progress` 用)
- `scripts/get-auto-session-report.sh` — `.tmp/auto-events.jsonl` (session_id でフィルタ) から /auto セッション retrospective の `## Metrics` markdown セクション (`--metrics-only`) を発行する。`session.md` への埋め込みと `/audit auto-session` 用
- `scripts/get-verify-iteration.sh` — Issue コメントから最も高い `<!-- verify-iteration: N -->` マーカーを読み取る
- `scripts/resolve-preview-ac-fallback.sh` — Issue コメントから最新の `type=preview-ac-unverified` マーカーを解決し、`/verify` フォールバックが必要な AC の 1-based インデックスを出力する (なければ空)
- `scripts/verify-executability-marker.sh` — 手動のマージ後 AC に対する `/verify` Step 8b の Claude-executability 判断を記録する `type=verify-executability` マーカーを生成 (`format`) および解決 (`resolve`、最新優先) する
- `scripts/check-pre-merge-ac.sh` — Issue 本文の `### Pre-merge` サブセクションで未チェックのチェックボックスをスキャンし、グローバルな 1-based インデックス + テキストを JSON として出力する。`skills/merge/SKILL.md` Step 1 の pre-merge AC ゲートで使用される
- `scripts/hook-rename-on-auto.sh` — UserPromptSubmit hook: プロンプトが `/auto` パターンにマッチした場合にセッションタイトルを自動リネームする
- `scripts/log-permission.sh` — permission イベントをログに記録 (JSON 出力)
- `scripts/observation-trigger.sh` — イベント発生時に observation タイプの AC をディスパッチする: `opportunistic-search.sh --event` を呼び出し、マッチした各 Issue に `/verify` の再実行を推奨するコメントを投稿し、呼び出し元のディスパッチ用にマッチした Issue 番号を stdout に出力する
- `scripts/filter-session-verified-issues.sh` — 現在の `/auto` セッションで既に `phase=verify` イベントが記録されている Issue を除外して、observation スキャン候補の Issue 番号をフィルタする (fail-open)
- `scripts/rotate-observation-dispatch.sh` — `OBSERVATION_DISPATCH_THRESHOLD` の cap を適用する前に、永続化したカーソル (最後に dispatch した Issue 番号) を基準に observation-dispatch 候補の Issue 番号を回転させ、premise が不変の chronically-stalled Issue が dispatch スロットを恒久占有しないようにする
- `scripts/opportunistic-search.sh` — opportunistic な skill 検索と observation イベントスキャン
- `scripts/post_merge_check.sh` — 複数の Issue のマージ後 manual (verify-type: manual) AC を 1 セッションでまとめて実行する。AC ごとに P/F/S をプロンプトし、全 PASS で phase/done に遷移するか、FAIL で再オープンする
- `scripts/collect-run-facts.sh` — 完了した `/auto` 実行のファクト (diff-less な operate 値を含む経路、実行モード、Size、フェーズの結果、PR の状態、異常件数、リコンサイル tier、fact トークン) を `.tmp/auto-events.jsonl` から JSON として構造化する。run-fact AC reconciliation (`modules/run-fact-matching.md`) 用
- `scripts/scan-pending-ac.sh` — `phase/verify` Issue (全状態) 全体で未チェックのマージ後受入条件を列挙する。オプションで `collect-run-facts.sh` の fact トークンによる事前フィルタが可能
- `scripts/rank-verify-backlog.sh` — verify command を伴う (自動チェック可能な) 未チェックの Post-merge 受入条件の数で `phase/verify` バックログ Issue をランク付けする (コードフェンスで囲まれたサンプルのチェックボックステキストは除外)。`/audit verify-backlog` 用に上位 N 件の Issue 番号を出力する
- `scripts/collect-verify-path-done-rate.sh` — バッチスイープ / observation ディスパッチ / opportunistic-verify ディスパッチの各経路間で `phase/done` 到達率を比較する (最初の 2 つは Issue コメントマーカー、3 つ目は `docs/sessions/*/events.jsonl`。経路は互いに排他的ではない)。`/audit stats --retention` Section 12 用
- `scripts/apply-run-fact-match.sh` — run-fact AC マッチ判定 (satisfied/not_satisfied/ambiguous) に対する決定的な autonomy-tier ゲート: チェックボックスを自動チェックするか、`Recommend:` 行を出力するか、何もしない
- `scripts/triage-backlog-filter.sh` — triage 用のバックログフィルタ

**プロセス管理:**
- `scripts/auto-checkpoint.sh` — `/auto --resume` 用のチェックポイントヘルパー: 単一 Issue の verify カウンタとバッチの remaining リストのアトミックな読み書き/削除。BATCH_ID で名前空間化されたセッションごとの状態ファイルが並行 `--batch` の衝突を防ぐ (サブコマンド: `read_single`、`write_single`、`delete_single`、`read_batch`、`write_batch`、`update_batch`、`delete_batch`、`list_active_batches`)
- `scripts/resolve-batch-query.sh` — `/auto --batch --until <query>` の `label:`/`status:` クエリを、ソート済みで除外考慮済みのマッチする open Issue 番号リストに解決する (決定的、bash 3.2 互換。Issue ごとの Status GraphQL 失敗はハードエラーではなく fail-closed で除外される)
- `scripts/watchdog-defaults.sh` — `WATCHDOG_TIMEOUT_DEFAULT` 定数と run-*.sh スクリプト向けの `load_watchdog_timeout` 関数を提供する sourceable なヘルパー
- `scripts/retry-on-kill.sh` — `run_with_retry_on_kill()` を提供する sourceable なヘルパー: early-kill ウィンドウ (<300s) 内での SIGTERM/SIGKILL (exit 137/143) を検出し、自動的に 1 回リトライする。run-issue.sh、run-spec.sh、run-code.sh、run-auto-sub.sh で使用される
- `scripts/claude-watchdog.sh` — `claude -p` 呼び出し用の watchdog wrapper (ハング検出 + 1 回リトライ)
- `scripts/reconcile-phase-state.sh` — 全フェーズにわたる前提条件・完了チェックのための汎用状態リコンサイラ。`modules/phase-state.md` SSoT に従って JSON v1 を出力する (watchdog-reconcile.sh の後継)
- `scripts/wait-ci-checks.sh` — PR 上の全 CI チェックが非 pending 状態 (`gh pr checks --json bucket` の pass/fail/skipping/cancel) に達するまで待機する。猶予期間 + チェックがゼロ件の場合の警告付き。claude 実行前に `/review` と `/merge` から呼び出される。また `capabilities.pr-preview: true` の場合 `/code` の pr 経路からも呼び出される
- `scripts/pre-merge-check.sh` — baseline diff 分類器: 指定されたチェックを base と head の両ブランチで ephemeral worktree 内に実行する。結果を NEW_FAILURE (exit 2) / PRE_EXISTING / FIXED / CLEAN (exit 0) / env エラー (exit 1) に分類する
- `scripts/worktree-merge-push.sh` — 短命な patch lock を取得。lock 取得後の fetch、checkout なしの ref-fetch マージ (`git fetch . <from>:<base>`)、is-ancestor による rebase スキップ、push リトライループ (最大 3 回) による並行セッションのレース耐性
- `scripts/detect-foreign-worktree.sh` — CWD が foreign (別オーナー) の git worktree 内にあるかを検出する。`modules/worktree-lifecycle.md` Entry セクション、`skills/verify/SKILL.md` Step 2 (base ブランチのチェックアウトガード)、`skills/review/SKILL.md` Opportunistic Verification (worktree exit 前提条件) から使用される
- `scripts/reclaim-stale-worktrees.sh` — 既に完了済み (CLOSED/MERGED) の Issue/PR に対する古い worktree と orphan ブランチを棚卸し・回収する。デフォルトは dry-run、`--apply` でローカル削除を実行。並行セッションガード (lock かつ HEAD が main と一致)、未コミット変更ガード、安全な squash-merge ブランチ削除 (`git branch -d` が失敗した場合、ブランチ tip が MERGED PR の `headRefOid` と一致すれば `-D` にフォールバック — `kind=pr` ブランチはその PR 自身、`kind=issue` ブランチは `closes #<N>` を検索して解決し一致を検証する。`/code` の pr 経路も `<phase>+issue-N` ブランチを作成し独自の PR で squash-merge されるため)。`origin` 上の orphan `worktree-*` ブランチも回収する: 常に列挙 (dry-run レポート)、`--apply-remote` (`--apply` とは独立) で実際に `git push origin --delete` を実行。ローカルと同等の安全ガード — ライブなローカルチェックアウトを持つブランチは除外 (ローカル回収経路に委ねる)、`kind=pr` ブランチは MERGED PR の `headRefOid` と厳密に一致する必要がある、`kind=issue` ブランチは見つかれば同じ closes-PR の `headRefOid` マッチを使用し、見つからなければ `origin/<default-branch>` の ancestor かどうかのチェックにフォールバックする
- `scripts/detect-wrapper-anomaly.sh` — シェル wrapper 出力の既知の失敗パターンを検出し、Auto Retrospective の markdown フラグメントを生成する
- `scripts/detect-external-kill.sh` — `external-kill-parent-respawn` シグネチャを機械的に検出する (exit code 137 単独、または exit code 143/unknown で wrapper ログの `Exit code: ` トレーラーと `auto-events.jsonl` の `wrapper_exit` イベントの両方が issue/phase に対して不在)。exit 0 = マッチ、exit 1 = 不一致 (`modules/orchestration-fallbacks.md#external-kill-parent-respawn` 参照)。`wrapper_exit` 不在という条件は、`spec` や `issue` を含むすべてのフェーズで判別力を持つ — `run-spec.sh`/`run-issue.sh` は claude 実行後の emit ブロックに到達する全ての exit で `wrapper_exit` を発行する (`_EMIT_PHASE_OWNED`、#1228)。つまり wrapper がフェーズを所有している限り、その不在はフェーズ全体の偽陽性ではなく external-kill のシグナルとなる
- `scripts/detect-unrecorded-kills.sh` — 記録されていない external kill を検出し、`.tmp/auto-events.jsonl` の `phase_start` 重複 (respawn シグナル — 連続するペアの間に `wrapper_exit`/`phase_complete`/`manual_intervention` がない) を `docs/reports/orchestration-recoveries.md` のエントリと `--window` 秒の許容範囲 (デフォルト 300s) で突き合わせてバーストにグループ化する。`/verify` Step 15 から呼び出される (Issue #1387)
- `scripts/test-failure-classify.sh` — テスト失敗の出力を復旧カテゴリ (snapshot/mock/fixture/logic/infra) に分類する。exit 0 = 修復可能、exit 1 = 修復不可
- `scripts/validate-recovery-plan.sh` — orchestration-recovery サブエージェントからの復旧計画 JSON を検証する (スキーマチェック + 禁止操作ガード)
- `scripts/apply-fallback.sh` — `modules/orchestration-fallbacks.md` の Tier 2 bash 射影。wrapper ログから既知の症状アンカーを検出し復旧ハンドラをディスパッチする (ハンドラ: dco-signoff-missing-autofix、code-patch-silent-no-op、json-mode-silent-hang)。ハンドラ失敗時は exit 2 (アンカーはマッチしたがハンドラが失敗、アンカー不一致の exit 1 とは区別) で終了する。成功した復旧を自身の `write_recovery_entry()` 経由で `docs/reports/orchestration-recoveries.md` に記録する。これは `spawn-recovery-subagent.sh` の Tier 3 writer と対をなす
- `scripts/spawn-recovery-subagent.sh` — `run-auto-sub.sh` から呼び出される Tier 3 復旧オーケストレーター。`agents/orchestration-recovery` を起動し、返された計画を `validate-recovery-plan.sh` で検証し、`WHOLEWORK_MAX_RECOVERY_SUBAGENTS` の mkdir ベースのスロットロックで並行性を強制し、成功した復旧を `write_recovery_entry()` 経由で `docs/reports/orchestration-recoveries.md` に記録する
- `scripts/post-fallback-review-summary.sh` — `run-review.sh` が exit 0 + `matches_expected:false` (silent no-op) の場合に呼び出される。PR に対して "Acceptance Criteria Verification Results" を含む先行 review が見つかり、その最新の `state` (認証されたアクター自身による review のみから計算、`gh api user` 経由で解決できる場合) が `CHANGES_REQUESTED` でない場合に限り、`<!-- review-summary -->` マーク付きの fallback Review Response Summary を投稿し、その直後に `<!-- wholework-event: type=review-incomplete -->` マーカーを付ける。これにより下流 (`/merge` の pre-merge ゲート) がこの fallback 由来の完了を `/review` 自身のオーガニックな完了と区別できる。それ以外の場合は exit 1 (証拠なし) または exit 2 (MUST の課題が未解決 — `run-review.sh` は投稿の代わりに review セッションを 1 回リトライする) で終了する

**Skill runners:**
- `scripts/guard-prefix.sh` — 全 run-*.sh からソースされる共有 GUARD_PREFIX 定義。自律実行のための anti-early-stop・境界に関するリマインダーと、5 つの wrapper 起動フェーズ (issue/spec/code/review/merge) すべてに及ぶバックグラウンドタスク完了待ち禁止 (これらの実行サーフェスには re-invocation 保証がない) を含む。`modules/execution-context.md` § "Wrapper-Level Constraint Injection" 参照
- `scripts/run-auto-sub.sh` — sub-issue 用の auto ワークフローを実行
- `scripts/run-code.sh` — code skill を実行
- `scripts/run-issue.sh` — issue skill を実行
- `scripts/run-merge.sh` — merge skill を実行
- `scripts/run-review.sh` — review skill を実行
- `scripts/run-spec.sh` — spec skill を実行

**Tooling:**
- `scripts/check-allowed-tools.sh` — 中間コミット前に SKILL.md 本文と allowed-tools の不一致を検出する。`skills/code/SKILL.md` Step 8 から呼び出される
- `scripts/check-eager-load-capability.sh` — eager-load される共有モジュール (verify-patterns.md、verify-executor.md) に混入した capability ガイダンスを検出する。/audit drift Step 2 から呼び出される
- `scripts/validate-permissions.sh` — skill ディレクトリと name: フィールドの整合性を検証
- `scripts/validate-skill-syntax.py` — SKILL.md の frontmatter と構文を検証
- `scripts/check-file-overlap.sh` — リポジトリ間のファイル重複を検出
- `scripts/check-verify-dirty.sh` — /verify Step 1 用のセッション認識ダーティファイル分類器 (self-worktree / other-worktree / other-session / self-spec / own-issue-scope / foreign-session / parent-main (attribution-undetermined フォールバック) の 7 分類。own-issue-scope と foreign-session は Issue 自身の Spec の `## Changed Files` マニフェストに対して判定される。owning Issue が OPEN かつアクティブな `phase/*` ラベル (`phase/done` 以外) を持つ、無関係な spec ファイルも `gh issue view` によって foreign-session に再分類され、`gh` 失敗時は既存の blocking 分類にフォールバックする。stderr に classify=... を出力する)
- `scripts/check-session-findings-disposition.sh` — L3 の `session.md` 内で正規の disposition タグを欠く `## Findings` の箇条書きを検出する。コミット直前に `skills/auto/SKILL.md` Step 5 から warn-only で呼び出される
- `scripts/check-skill-change-observation-ac.sh` — Issue 本文が `skills/*/SKILL.md` を参照しているにもかかわらず `session=next` を欠くマージ後 `verify-type: observation` AC を検出する。`skills/issue/SKILL.md` Step 4 から warn-only で呼び出される
- `scripts/check-ac-checkbox-format.sh` — Issue 本文の `### Pre-merge` / `### Post-merge` セクション内の非チェックボックス形式の条件行を検出する。`skills/issue/SKILL.md` Step 4 から warn-only で呼び出される
- `scripts/check-premise-expiry.sh` — Issue 本文の `<!-- premise: ... -->` マーカー (`grep_count`/`file_exists`/`file_not_exists`) を現在の作業ツリーに対して再評価する。失効時は exit 2 + stdout に `EXPIRED:` 行。それ以外は exit 0 (fail-open な `UNEVALUABLE:` 行は stderr に出力され exit code には影響しない)。`/audit premise` Step 2 Layer 1 から呼び出される
- `scripts/check-translation-sync.sh` — docs/ja/* の docs/* に対する翻訳同期状態をチェック
- `scripts/check-forbidden-expressions.sh` — docs/product.md § Terms から非推奨用語を検出
- `scripts/check-bare-bracket-assertions.sh` — `|| false` を伴わない裸の `[[ "$output"/"$status"` bats アサーションを検出する (informational; ビルドを失敗させない)
- `scripts/check-known-events-firing.sh` — `scripts/opportunistic-search.sh` の `KNOWN_EVENTS` の各エントリに実際の `--event <name>` 呼び出しサイトがあることを検証する (コメント行と echo/printf の使用文字列は除外)
- `scripts/check-language-convention.py` — unified diff から skills/、modules/、scripts/ の英語専用パスに転記された CJK 文字を検出する。`language-convention` CI ジョブから実行される
- `scripts/setup-labels.sh` — ワークフロー用の GitHub ラベルを作成
- `scripts/compute-escalation-level.sh` — phase/verify または Icebox の滞留時間に対するエスカレーションレベルを計算する。`/audit stats --retention` の retire-proposal コメントルーティングに使用される
- `scripts/test-skills.sh` — 全 skill のテストを実行
- `scripts/wait-external-review.sh` — 外部レビューの完了を待機

### CI ワークフロー

- `.github/workflows/test.yml` — bats テストを実行 (flaky な失敗と genuine な失敗を区別するため、parallel-only の失敗を `bats --filter-status failed` で serial に再実行)、`validate-skill-syntax.py`、禁止表現チェック、裸括弧アサーションチェック、言語規約チェック、macOS シェル互換性テストを push/PR で実行
- `.github/workflows/dco.yml` — 全 pull request コミットに DCO `Signed-off-by:` を強制
- `.github/workflows/kanban-automation.yml` — `phase/*` ラベルイベントで issue を project board のカラムへ自動移動

### Install

Wholework は 2 つのインストール方法をサポートする。

**Marketplace install** (推奨):

```sh
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Marketplace マニフェストは `.claude-plugin/marketplace.json` にある (name: `saitoco-wholework`)。

**Development install** (ローカル):

```sh
git clone https://github.com/saitoco/wholework.git
cd wholework
./install.sh
claude --plugin-dir <path-to-wholework>
```

Skill は `wholework:<skill-name>` として検出される。Claude Code はランタイムで `${CLAUDE_PLUGIN_ROOT}` を plugin ディレクトリに設定し、skill と module はこれを使ってスクリプトやモジュールを参照する。

**なぜ `./install.sh` が必要か?** `.claude/settings.json` は `.claude/settings.json.template` からユーザーの実際の `$HOME` を `${HOME}` に置換して生成される。Claude Code は `permissions.allow` 内の `${HOME}` や `~/` を展開しないため、各開発者はテンプレートをローカルで実体化する必要がある。生成された `.claude/settings.json` は gitignore 対象である。clone 後に一度、`.claude/settings.json.template` が変更された `git pull` のたびに再度 `./install.sh` を実行すること。

`./install.sh` は `claude plugin marketplace update` と `claude plugin update` も実行し、ローカルの plugin をリポジトリ内の最新バージョンと同期する。plugin の更新ステップをスキップするには `--no-plugin` を使用する (settings.json の再生成のみ)。marketplace 名を上書きするには `--marketplace NAME` を使用する (デフォルト: `saitoco-wholework`)。

<!-- ## Module Dependencies（Optional）

モジュール間の依存関係を記述する。 -->

<!-- ## File Naming Conventions（Optional）

ファイル命名規則を記述する。 -->
