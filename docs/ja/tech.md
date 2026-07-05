[English](../tech.md) | 日本語

# Tech

## 言語とランタイム

- **Bash/Shell Script**: ラッパースクリプト（`scripts/run-*.sh`）、ユーティリティスクリプト
- **Markdown**: スキル定義（`SKILL.md`）、エージェント定義（`agents/*.md`）、共有モジュール（`modules/*.md`）、ドキュメント
- **Python**: バリデーションスクリプト（`scripts/validate-skill-syntax.py`）
- **GitHub Actions**: CI/CD ワークフロー（`.github/workflows/`）

## 主要依存関係

| パッケージ | 役割 |
|---------|------|
| Claude Code CLI (`claude`) | スキル実行エンジン、サブエージェント起動 |
| GitHub CLI (`gh`) | Issue/PR 操作、GitHub API アクセス |
| GitHub Copilot | コードレビュー（Step 7）、Issue からの自動実装 |
| bats (Bash Automated Testing System) | シェルスクリプトのテスト |
| jq | JSON プロセッサー。verify-executor / gh-graphql / get-issue-* ヘルパーで使用 |

## アーキテクチャ決定

- **Skills ベースのワークフロー**: 各開発フェーズ（issue/spec/code/review/merge/verify）を独立した Claude Code Skill として実装する。処理ステップは SKILL.md に記述され、LLM がそれらを段階的に実行する
- **Plugin ディレクトリ配布**: `--plugin-dir` を使ったローカル Claude Code plugin として配布する。Claude Code は実行時に `${CLAUDE_PLUGIN_ROOT}` を plugin ディレクトリに設定し、skills/modules がこれを使って scripts や modules を参照する。公開配布は Claude Code marketplace（`.claude-plugin/marketplace.json`）経由で、ユーザーは `/plugin marketplace add saitoco/wholework` + `/plugin install wholework@saitoco-wholework` でインストールできる
- **fork コンテキスト vs main コンテキスト**: コンテキスト分離レベルはスキル単位で設定する。Fork の動機は「独立性/安全性」（1M コンテキスト GA 以降、コスト/容量の動機はほぼ消失）。各スキルの fork 判断（網羅的）:

  | スキル | Fork の要否 | 実行基盤 | 理由 |
  |-------|-------------|---------|--------|
  | triage | 不要 | In-session | 前フェーズのバイアスを避ける必要なし、独立性も不要 |
  | issue | 条件付き | headless（run-issue.sh）/ in-session（直接呼び出し） | 直接呼び出し時は shared、run-issue.sh 経由時は fork（L/XL 並列調査ではサブエージェントが分離コンテキストで実行） |
  | spec | 条件付き | headless（run-spec.sh）/ in-session（直接呼び出し） | 直接呼び出し時は shared、run-spec.sh 経由時は fork |
  | code | 必要 | headless（run-code.sh）/ in-session（直接呼び出し） | Spec を読み独立して実行する、実装前のコンテキストの影響を受けない |
  | review | 必要 | headless（run-review.sh）/ in-session（直接呼び出し） | 実装フェーズのバイアスを継がず、クリーンな視点でコードをレビューする |
  | merge | 必要 | headless（run-merge.sh） | 判断は Spec + PR メタデータで完結、レビューコンテキストを持ち越さない |
  | verify | 不要 | In-session | 大部分が機械的処理（verify command 実行 + checkbox 更新）、manual AC 確認には fork コンテキストで実行できない AskUserQuestion が必要、FAIL → /code（fork）で再実行するため bias 伝播リスクは低い |
  | auto | 不要 | In-session | 親オーケストレーターはユーザーの Claude Code セッションで実行される、各子フェーズは `run-*.sh` 経由で独立した `claude -p` プロセスとして実行 |
  | audit | 不要 | In-session | ドリフト・脆弱性検出はユーザーセッションで実行される、前フェーズのバイアスを避ける必要なし |
  | doc | 不要 | In-session | ドキュメント管理はユーザーセッションで実行される、前フェーズのバイアスを避ける必要なし |

  コンテキスト判定基準と各コンテキストでの制約については、[`modules/execution-context.md`](../modules/execution-context.md) を参照。

- **verify command 実行モード (safe vs full)**: `/review` は **safe mode** (プリマージ) で動作する: 外部コマンドや副作用のある verify command タイプは CI 参照にフォールバックし、プリマージで安全に評価できない条件は UNCERTAIN を返す。`/verify` は **full mode** (ポストマージ) で動作する: shell コマンドや外部サービス呼び出しを含む全 verify command タイプが実行される。この分離により、プリマージのレビューは再現性が保たれ、ポストマージの検証は実際の副作用を発揮できる。SSoT とモード別ポリシー: [`modules/execution-context.md`](../modules/execution-context.md)。

- **`/auto` スキル**: `run-*.sh` 経由で spec→code→review→merge→verify を順次連鎖させるオーケストレーター。各フェーズは設定可能なパーミッションモード（デフォルト: `--permission-mode auto`、`.wholework.yml` に `permission-mode: bypass` を設定すると `--dangerously-skip-permissions`）で `claude -p` 独立プロセスとして実行され、フレッシュなコンテキスト分離を保証する。`verify-max-iterations`（デフォルト: 3、最大: 20、`.wholework.yml` で設定可能）が verify-reopen ループを上限で止める。カウンターが上限に達すると Issue は `phase/verify` に留まり人間の判断を待つ。`/auto` スキルは verify 出力の `MAX_ITERATIONS_REACHED` を検出し、無限ループの代わりに連鎖実行を停止する。フラグ動作・バッチ処理・レジューム・リリースブランチワークフローは [docs/workflow.md § Orchestration](../workflow.md#orchestration) を参照。
  - **2 階層オーケストレーション**: `/auto` 本体（親オーケストレーター）はユーザーの Claude Code セッションで動作し、LLM 推論を使った適応的判断を行う（ラベル状態の評価、サイズベースのルーティング、サブ issue 依存関係分析）。XL Issue については `run-auto-sub.sh`（子オーケストレーター）が各サブ issue のフルフェーズシーケンスを実行する。`run-auto-sub.sh` は bash オーケストレーションを維持しつつ、段階的適応リカバリを備える: (1) `reconcile-phase-state.sh` 完了チェック、(2) `apply-fallback.sh` 既知パターンリカバリ、(3) 未知異常時に `spawn-recovery-subagent.sh` が `claude -p` で `agents/orchestration-recovery` を起動。通常経路は bash のままコストと並列安定性を維持し、Tier 1–2 が失敗した場合のみ `claude -p` を診断に使用する。`WHOLEWORK_MAX_RECOVERY_SUBAGENTS` cap（デフォルト 1）により並列コストを制限する。
- **フェーズ状態整合（Phase state reconciliation）**: `scripts/reconcile-phase-state.sh` は、`modules/phase-state.md`（SSoT、`ssot_for: phase-signatures, reconcile-json-schema`）で定義されたフェーズ固有の期待シグネチャ（前提条件・成功シグネチャ）に対して、ライブな GitHub/git 状態を検証する汎用フェーズ状態整合スクリプトである。呼び出し元（`/auto` watchdog リカバリ、フェーズ実行前の前提条件チェック）は同モジュールで固定された JSON v1 出力スキーマを利用するため、整合スクリプトの内部実装に結合しない。以前の Issue 固有の `watchdog-reconcile.sh` を、共有かつフェーズ単位で拡張可能な仕組みに置き換えた。整合スクリプトは各 `/auto` フェーズに適用される **Observe-Diagnose-Act パターン**を実装している: (1) **Observe** — フェーズ実行前にライブな GitHub/git 状態を読み取る（前提条件チェック）、(2) **Diagnose** — 観測された状態を期待シグネチャと比較し、実行・スキップ・リカバリを判断する、(3) **Act** — フェーズを実行し、成功シグネチャを再確認して完了チェックとする。#314 で導入され、下流 Issue #315–#319（verify・merge・review・code 各フェーズの状態検出）に向けた orchestration reliability の基盤となっている: 状態検証を 1 つの整合スクリプトに集約することで、各フェーズがアドホックな個別チェックなしに独立して検証・回復可能になる
- **`/doc` スキル**: プロジェクト基盤ドキュメント管理。Steering Documents（`product.md`、`tech.md`、`structure.md`）とプロジェクトドキュメントを管理する。主要操作: `sync`（双方向の正規化とドリフト検出; ドキュメント別 variant: `sync product` / `sync tech` / `sync structure` で選択的な逆生成; `--deep` でコードベース解析 + .md 統合スキャン + Narrative Semantic Drift Check + Terms 整合チェックを追加）、`init`（初期セットアップウィザード）、`add` / `project`（ドキュメント登録）、`translate {lang}`（多言語翻訳生成）。`/audit` の補完として機能: `/doc sync` はドキュメント側の修正を提案し、`/audit drift` はコード側の修正を Issue 化する
- **`/triage` スキル**: メインワークフロー開始前に Type/Priority/Size/Value を割り当てる初期 Issue 評価。タイトル正規化（`modules/title-normalizer.md`）と 4 視点の深い分析（`/triage --backlog`）を実行する。Issue に `phase/*` ラベルがない場合、`/auto` が自動的に `/triage` を連鎖させる
- **`/merge` スキル**: CI 通過・レビュー承認後に PR を squash-merge し、リモートブランチを削除する。決定ルール: AC 検証が GREEN（または明示的に承認済み）の場合のみマージ。`/review` から Phase Handoff を読み込み、`/verify` 向けに Phase Handoff を書き込む。機械的な操作のため `model: sonnet` + `low` effort で十分
- **`/code` スキル**: `docs/spec/issue-N-*.md` の Spec を読み込み実装ステップを実行するローカル実装フェーズ。Issue サイズに基づき patch ルート（XS/S: main への直接コミット）または PR ルート（M/L: ブランチ + PR）にルーティングする。既存の AC verify command を実装の参考にし、下流の `/review` / `/merge` / `/verify` 向けに Phase Handoff を出力する
- **サブエージェント分割**: 2 つのスキルで使用:
  - `/issue`（L/XL）: 3 つの独立サブエージェント（`issue-scope`、`issue-risk`、`issue-precedent`）による並列調査で、変更スコープ、リスク、前例を同時に分析する
  - `/review`: Full モードでは 2 グループに分割する — Spec 準拠レビュー（`review-spec`）とバグ検出（`review-bug`）。2 段階検証（検出→検証サブエージェント）で偽陽性を排除。Light モードでは統合エージェント（`review-light`）1 つで 4 観点（spec・bug・エッジケース・ドキュメント）をまとめて担当
- **共有モジュールパターン**: 複数スキルを横断する共通処理を `modules/*.md` に切り出し、"Read and follow" パターンで参照する
- **Spec ファースト（使い捨て）**: Spec はタスク完了後の成果物として保守しない。Spec-anchored および Spec-as-source アプローチは採用しない。理由: (1) LLM の非決定性により同じ spec が同じコード再生成を保証しない、(2) spec 保守コストがコード保守コストに上乗せになる
- **フェーズ横断メモリ機構**: 新規フォークコンテキストで実行されるフェーズ間でコンテキストを引き継ぐための 2 つの補完的な仕組み。
  - **Spec レトロスペクティブ**: 各フェーズが Spec に Retrospective セクションを追記し、観察・判断・不確実性の解消を記録する。使い捨て Spec 内に蓄積され、同一ファイルを通じて下流フェーズに引き継がれる。
  - **Phase Handoff** (`modules/phase-handoff.md`): 生産フェーズが書き込み、消費フェーズが読み込む構造化サマリー（例: review → merge → verify）。AC 確認結果・スコープ注記・残存リスクなどの短命な引き継ぎシグナルを Spec 本文から切り離すことで、フォークコンテキストのフェーズが必要な情報だけを参照できる。Spec レトロスペクティブが「履歴」を格納するのに対し、Phase Handoff は「次ステップの作業コンテキスト」を伝達する。
- **プログレッシブ・ディスクロージャー（Core/Domain 分離）**: SKILL.md 本文にはプロジェクト種別やツールに依存しない汎用ロジックだけを記す。特定ツール（Figma、Copilot など）やプロジェクト種別（スキル開発、IaC など）に固有のロジックは補助ファイル（`skills/{name}/xxx-phase.md`）に切り出し、該当するときだけ読み込む。判断基準: 「このツール/プロジェクト種別を使わないプロジェクトでもこのロジックが必要か？」— No なら切り出す。**この判断基準は実行ロジックだけでなくガイダンス（適用シナリオ、判断基準、使い分け表）にも適用される** — capability 固有のガイダンスを eager-load される共通モジュール（`modules/verify-patterns.md` など）に置くと、domain 外プロジェクトでも skill 起動時に毎回フルトークンコストが発生する。代わりに `load_when: capability: {name}` gate を持つ Domain file を使うこと（参考: Issue #441 visual-diff capability + `skills/spec/visual-diff-guidance.md`）
  - **切り出しパターン（標準）（網羅的）**:

    | パターン | 条件 | 例 |
    |---------|-----------|---------|
    | Marker 検出 | `.wholework.yml` の YAML キー | `review/external-review-phase.md`（`copilot-review: true`、`claude-code-review: true`、`coderabbit-review: true` のいずれかで読み込み） |
    | ファイル存在 | 特定ファイルの存在 | `review/skill-dev-recheck.md`（`scripts/validate-skill-syntax.py` が存在すれば読み込み） |
    | MCP 可用性 | Claude Code セッションに MCP ツールが存在 | `spec/figma-design-phase.md`（Figma MCP ツールが ToolSearch でロードされた場合に読み込み） |
    | 深度ルーティング | スキル呼び出しモード（`--full` / `--light`） | `spec/codebase-search.md`（`--full` で読み込み、`--light` ではスキップ） |
    | Capability フラグ | `.wholework.yml` の `capabilities.{name}: true` | `verify/browser-verify-phase.md`（`HAS_BROWSER_CAPABILITY=true` で読み込み） |

- **Autonomy tier（L0 書き込みガバナンス）**: Wholework は 4 層で動作する — L0（GitHub state: Issues, Labels, PRs, blockedBy, `closes #N`）、L1（Claude Code primitive: `/loop`, `/goal`, `ScheduleWakeup`, `CronCreate`）、L2（Wholework skill 内部: Spec, retro, `auto-events.jsonl`）、L3（OS スケジューラ）。`.wholework.yml` の `autonomy:` field は、skill が L0 をどこまで書き込め、L2→L1 経路（A Advisory / B CronCreate / C ScheduleWakeup / E Seed file emission）をどこまで使用できるかを宣言する。tier × 経路マトリクスと Tier × L0 書き込みマトリクスの SSoT は [`modules/autonomy-tier.md`](../modules/autonomy-tier.md)、surface 別の L0 書き込み分類は [`modules/l0-surfaces.md`](../modules/l0-surfaces.md)。このレイヤーは `permission-mode`（Claude Code subprocess 権限を管理）とは直交する。Skill frontmatter `loop-paths-used` は skill が使用する L2→L1 経路を宣言する（例: `loop-paths-used: [A]` = advisory print のみ）; #700（`/verify` auto-retry-on-fail tail 拡張）で実装済み。残りのゲーティング実施（#702、#703）はフォローアップ Issue で追跡

- **配布物ファースト改善原則**: レトロスペクティブで特定された改善は、配布物（Skills、Agents、Modules、Scripts）に反映すること。CLAUDE.md、Steering Documents、Project Documents はユーザーリポジトリ固有の成果物であり、Wholework plugin の一部として配布されない — これらのドキュメントだけに加えた改善は他の Wholework ユーザーに届かない。レトロスペクティブで改善が特定された場合、実装対象は配布レイヤーとすべきであり、配布対象外の成果物だけを更新することは不十分である
- **Effort 最適化戦略（3 軸）**: `claude -p` 呼び出しで実行コストと品質を制御する 3 軸。軸ごとの CLI サポート状況と Wholework の採用方針:
  - **軸 1 — モデル選択**（`--model`）: 実装済み。Sonnet をデフォルトとし、L サイズの spec では `run-spec.sh --opus` で Opus に切替。レビュー・確認済み
  - **軸 2 — Adaptive Thinking**（`--effort`）: `claude -p` は `low/medium/high/max` レベルをサポート（`claude --help` で確認済み）。`run-*.sh` でフェーズごとの effort レベルを実装済み（下記マトリクス参照）。medium effort と Opus advisor を組み合わせると、Sonnet のデフォルト effort 相当の品質をより低コストで達成（Anthropic ベンチマーク準拠）
  - **軸 3 — Advisor 戦略**（`advisor_20260301`）: Anthropic API ベータ機能（`advisor-tool-2026-03-01` ヘッダが必要）。`--betas` フラグで有効化 — API キー利用者のみ、OAuth/サブスクリプション認証（`run-*.sh` のデフォルト）では利用不可。性能向上: Sonnet + Opus advisor で SWE-bench +2.7 pp、コスト −11.9%（Sonnet 単独比）、Haiku + Opus advisor で BrowseComp 41.2%（単独 19.7%）、コスト −85%（Sonnet 比）。`run-*.sh` 実装はフォローアップ Issue

### フェーズ別モデル・effort マトリクス

(`ssot_for: model-effort-matrix`)

エントリはワークフロー順（triage → issue → spec → code → review → merge → verify）でグループ化: まずオーケストレーションスクリプト、次にフェーズ別のサブエージェント、最後に skill のみのエントリ。

**デフォルト親モデル = Sonnet 5**（`claude-sonnet-5`、2026-06-30 リリース）: 下記の表全体（`run-*.sh`、skill、サブエージェントの frontmatter）で使われている bare `Sonnet` エイリアスは、現在 Sonnet 5 に解決される。これにより旧デフォルトの Sonnet 4.6 は置き換えられた。切替の根拠と alias pin 方針については表の下の **Sonnet 5** の注記を参照。

| コンポーネント | フェーズ | モデル | Effort | 根拠 |
|-----------|-------|-------|--------|-----------|
| run-issue.sh | issue | Sonnet | high | L/XL のスコープ分析とサブ issue 分割には徹底したオーケストレーションが必要 |
| run-spec.sh | spec | Sonnet（L では `--opus` で Opus；`--fable` で Fable 5） | Sonnet: max；Opus: xhigh（デフォルト）、max（`--max` 明示）；Fable 5: high（デフォルト）、max（`--max` 明示） | 設計品質が重要、spec のエラーは後続全フェーズに波及する。`/auto` は L サイズのみ `--opus` を渡す（XL は spec 前に分割済み） |
| run-code.sh | code | Sonnet | high | 実装には徹底した推論が必要 |
| run-review.sh | review | Sonnet | high | レビューのオーケストレーション、深い分析はサブエージェントが担う |
| run-merge.sh | merge | Sonnet | low | 機械的なマージ操作、推論は最小限でよい |
| issue-scope | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査向けに呼び出される。スコープ特定精度はサブ issue 境界判断に直結 |
| issue-risk | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査向けに呼び出される。リスク評価精度が受入条件品質を高める |
| issue-precedent | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査向けに呼び出される。前例抽出が受入条件品質を高める |
| review-bug | review | Opus | — | バグ検出は最高精度が必要（サブエージェント、effort は親から継承） |
| review-spec | review | Opus | — | Spec 逸脱は高精度が必要（サブエージェント、effort は親から継承） |
| review-light | review | Sonnet | — | 軽量統合レビュー（サブエージェント、effort は親から継承） |
| orchestration-recovery | auto（リカバリ） | Sonnet | — | Bash Tier 1–2 が失敗したとき `spawn-recovery-subagent.sh` が起動する Tier 3 リカバリ診断エージェント。フェーズ状態を分析し最小リカバリプランを JSON で生成 |
| frontend-visual-review | verify（visual-diff） | Opus | — | 3 パネル比較画像からビジュアルギャップを列挙。`visual_diff` verify コマンド向けに `modules/visual-diff-adapter.md` が起動 |
| triage（skill） | triage | Sonnet | — | メタデータ付与、Sonnet で十分。インライン実行（`run-*.sh` ラッパーなし）— `/auto` が未ラベル issue に triage を連鎖させる場合も含む — のため effort は設定しない |
| auto（skill） | orchestration | Sonnet | — | 親オーケストレーター、ユーザーの Claude Code セッションでインライン実行（`run-*.sh` ラッパーなし）。各子フェーズはフェーズ固有の effort で `run-*.sh` 経由で実行される。スキルレベルでは effort を設定しない |
| audit（skill） | audit | Sonnet | — | drift 検出 (`drift`)・脆弱性解析 (`fragility`)・プロジェクト健全性統計 (`stats`)・XL サブ Issue 進捗 (`progress`)・/auto セッションレトロスペクティブ (`auto-session`); Sonnet で十分。インライン実行 (`run-*.sh` ラッパーなし) のため effort は設定しない |
| doc（skill） | doc | Sonnet | — | ドキュメント管理、Sonnet で十分。インライン実行（`run-*.sh` ラッパーなし）のため effort は設定しない |

**Opus 4.8 effort calibration**: Opus 4.8 は厳格な effort キャリブレーションを適用する — `low` と `medium` は文字通りのタスク要件に積極的にスコープを絞る。`max` は Opus 4.8 では過剰思考のリスク（diminishing returns）があるため、知的要求の高い実験的タスクにのみ使用する。`xhigh` が Opus 4.8 の多くのコーディング・エージェントユースケースにおける推奨デフォルト。エージェント frontmatter の `model: opus` / `model: sonnet` エイリアス値は現在の Opus（4.8）に auto-resolve する。

**Fable 5（Mythos クラス）**: Fable 5（`claude-fable-5`）は Opus より上のティアであり、`opus` エイリアスでは**到達できない** — 明示的なモデル文字列 `claude-fable-5` が必要。以下のハード制約によりデフォルトモデル変更ではなく**オプトイン**のみ許可: コスト $10/$50 per MTok（Opus 4.8 の 2 倍、Sonnet 4.6 の 3.3 倍）、30 日 retention 必須（ゼロデータ保持 org は非対応）、2026-06-22 以降はサブスクリプションの usage credit ゲート。Fable 5 オプトインを公開するスキル（例: `/spec --fable`）はスキル単位でドキュメント化する。採用ガイダンスは `docs/reports/claude-fable-5-impact-strategy.md` §3.3 および §5.2 を参照。Fable 5 上で実行する場合、レビューフェーズのセキュリティ関連クエリは cyber classifier によって Opus 4.8 へ自動ルーティングされる可能性がある（CLI 経由では透過）— Fable 5 がセキュリティ分析を直接処理することを前提としないこと。

**Sonnet 5**: Sonnet 5（`claude-sonnet-5`、2026-06-30 リリース）は、旧デフォルト親モデル（Sonnet 4.6）に対する大幅なエージェント性能の向上であり、多くのタスクで `effort: xhigh` 時に Opus 4.8 に迫る性能を、Opus 4.8 のおよそ 40–60% の価格（導入価格 $2/$10 per MTok、2026-08-31 まで。以降は標準価格 $3/$15 — Wholework のコストモデルで Sonnet 4.6 が既に占めていたのと同じ価格帯）で実現する。Opus 4.7 の変更と同系統のトークナイザー更新を伴い（同一入力に対しトークン数が 1.0×–1.35× 増加）、`claude-watchdog.sh` のタイムアウトキャリブレーションおよびコンテキストバジェットのヒューリスティクスに直接影響する。2 件のブロッキング計測はいずれも着地済み: `#877`（`/verify` interactive 摩擦の再測定）は **NO-GO**（再設計不要）と判定され、`#878`（トークナイザー/watchdog 影響測定）は**有意**と判定され `#903` の再校正（`WATCHDOG_TIMEOUT_CODE_DEFAULT` 3600→4680、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 2000→2600）で対応済み。両ブロッカーの着地により、デフォルト親モデルの Sonnet 5 への切替は**確定・最終**となった — もはや note only のエントリではなく、上記マトリクス表は既に Sonnet 5 をデフォルト親モデルとして記載している（表直前の一文を参照）。完全な影響分析、decision matrix（§4.1）、候補 Issue 実行計画（§8）は `docs/reports/claude-sonnet-5-impact-strategy.md` を参照。

**Alias pin 方針**: Wholework は `claude-sonnet-5` への明示的な pin ではなく、bare `sonnet` CLI エイリアス（および `ANTHROPIC_MODEL=sonnet`）を継続して使用する。根拠: (1) reactive recalibration は既に実績のある運用パターンである — Fable 5 → Sonnet 4.6 移行（`#628`）および今回の Sonnet 5 移行自体（`#877`/`#878`/`#903`）の両方が、事前ゲートではなく切替後の watchdog/effort フォローアップで問題なく対応できている。(2) 明示的な pin を行うには 5 本の `run-*.sh` スクリプトと `model: sonnet` を持つ約 10 の skill/サブエージェント frontmatter への協調編集が必要になるが、Anthropic が bare エイリアスの参照先を変更するのは意図的・大規模なモデルローンチ時のみであるため、安全性の効果は限定的である。(3) トレードオフ: 将来のモデル世代についても、専用の計測 Issue が着地する前にエイリアス経由でデフォルト親モデルとして自動採用されてしまう（今回の Sonnet 5 で実際に発生したのと同様）— reactive recalibration SOP の実績（`#628`、`#903`）を踏まえ、Wholework はこのリスクを許容する。

SSoT 備考: run-*.sh のモデル値は CLI エイリアス（sonnet/opus）を使用する。run-*.sh、agents、skills でモデル/effort を変更する際はこの表を更新すること。

- **watchdog タイムアウトのキャリブレーション**: `scripts/watchdog-defaults.sh` のフェーズ別タイムアウト定数は、支配的な親モデルの per-token レイテンシに対してキャリブレーションされている。デフォルト親モデルが変更された場合は再キャリブレーションが必要（例: Fable 5 → Sonnet 4.6 移行で `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` を 600 → 1200 に引き上げ: #628）。**#903 再校正 (Sonnet 5)**: #878 が実測した Sonnet 5 の ~1.3-1.4× トークナイザー比を受け、実際の `/code`/`/review` 本番 wall-clock サンプル (n=10 / n=9、`docs/reports/sonnet-5-watchdog-recalibration.md`) を計測したところ、両フェーズとも p95/max がタイムアウトの80%超という再校正基準に既に達していた (code: p95 81.3%、max 93.8% (対 3600秒); review: p95 92.2%、max 100.2% (対 2000秒) — 実サンプル1件が既にタイムアウト上限に到達)。`WATCHDOG_TIMEOUT_CODE_DEFAULT` を 3600→**4680**、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を 2000→**2600** に引き上げた (いずれも #878 実測比率の保守側である ×1.3。#628 の 2× precedent よりあえて控えめとし、Icebox #596 が指摘するタイムアウト引き上げと真のスタック検知遅延のトレードオフに配慮)。`WATCHDOG_TIMEOUT_SPEC_DEFAULT` / `_ISSUE_DEFAULT` / `_MERGE_DEFAULT` は #903 のスコープ外 (根拠はレポート参照)。同レポートには #878/#903 で挙がった2件の **prompt slimming** 候補の検討結果も記録されている: `/auto` の L3 auto-retrospective「notable judgment」ステップ (完全に機械的な判定のためにセッション全体の `events.jsonl` を丸ごとコンテキストに注入していた — #913 で生ダンプを `jq -sc` によるイベント件数集計に置き換えて対応済み) と、`/issue`/`/review` の L/XL parallel investigation sub-agent input (diff・変更ファイル全文を使用 — スコープ/リスク/バグ検出の精度低下リスクがトークン削減効果を上回るため slimming 不要と判断)。
- **code フェーズ自動リトライ (silent no-op)**: `auto-retry-on-fail.enabled: true` かつ `autonomy: L2/L3` の場合、`run-code.sh` は `reconcile-phase-state.sh` から `matches_expected: false` (silent no-op) を検出した際に内部でリトライする。最大リトライ数は `auto-retry-on-fail.max_iterations` から取得 (レガシーキー `threshold` も受け入れ; デフォルト: 3)。リトライカウンタ (`CODE_RETRY_COUNT`) は `exec` ベースの再起動を通じて export された環境変数で引き継がれる。`skills/verify/SKILL.md` Step 11(b) の verify 側自動リトライと対称的 (同じ tier ゲート: L2/L3 + `AUTO_RETRY_ENABLED=true` + count < max)。組み込みリトライが有効な場合、`apply-fallback.sh` の `code-patch-silent-no-op` Tier 2 ハンドラは二重リトライを防ぐため抑制される。`exec` ベースのリトライ再実行の直前に、preflight ステップが silent no-op 自体の副産物として残った parent-main の untracked file を stash へ退避する (`git stash push --include-untracked`、`docs/sessions/**` は除外) ため、リトライ側の `check-verify-dirty.sh` 再チェックが直前の試行自身の stray output でブロックされることを防ぐ (#886)。
- **Sonnet 5 effort 再校正 — code/review (#921, C2)**: Sonnet 5 の effort curve widening (impact strategy レポート §3.3/§4.2) を踏まえ、`run-code.sh`/`run-review.sh` の effort を `high` から `medium` に下げられるか再評価した。**判定: 両方とも `high` を維持**（詳細分析: `docs/reports/sonnet-5-effort-recalibration-code-review.md`）。`run-code.sh`: impact strategy レポートが `medium` 候補として挙げていたのは XS/S patch-route Issue に限定されていた (§4.2) が、`--effort` フラグは Issue サイズによる条件分岐のないグローバル設定であり、#229 の手戻りリスクの論拠 (14 ステップの推論チェーン、sub-agent への fan-out なし) はモデル世代交代によって変化しない。`run-review.sh`: orchestrator は dispatch 以外にも実質的な推論作業を行っている — Step 7.2/7.4/7.6 は外部レビューのフィードバックを解釈して fix コミットを作成しており、`run-code.sh` 自身の実装推論と同種の作業である — これは impact strategy レポートの「mechanical」という位置づけと矛盾する。加えて `review-bug`/`review-spec` (Opus) は orchestrator セッションから effort を継承する (Claude Code CLI changelog で確認: エージェントレベルの `effort:` frontmatter override が未設定の場合、sub-agent はセッションの extended-thinking/effort 設定を継承する。`agents/review-bug.md`/`review-spec.md` には現状この override が設定されていない) ため、降格すると精度が重要なこれらの sub-agent の推論深度も暗黙に低下する。両判定は `docs/reports/sonnet-effort-recalibration.md` (#229、2026-04-18、Sonnet 4.6 ベースライン) を Sonnet 5 の観点から再確認するものである。**フォローアップ (本 Issue では未実装)**: 将来 `run-review.sh` の effort を再検討する場合、先に `agents/review-bug.md`/`review-spec.md` に明示的な `effort: high` frontmatter を追加し、orchestrator の設定から精度を切り離すことを推奨する (CLI は per-agent の `effort:` override をサポート済みだが、本リポジトリでは未採用)。
- **Sonnet 5 effort 再校正 — spec (#922, C3)**: Sonnet 5 の effort curve widening (impact strategy レポート §3.3/§4.2) を踏まえ、`run-spec.sh` の Sonnet パスのデフォルト effort を `max` から `xhigh` に下げられるか、既存の Opus fallback (`--opus`、L サイズ限定、#217 以降 `xhigh` デフォルト) との比較も含めて再評価した。**判定: Sonnet パスのデフォルトは `max` を維持** (詳細分析: `docs/reports/sonnet-5-effort-recalibration-spec.md`)。#921 (C2) と異なり、この Sonnet パスのデフォルトはこれまで一度も評価されたことがない (#217 は Opus の `xhigh` 導入時に Sonnet パスを明示的にスコープ外とし、#229 も Sonnet effort ladder の再評価から `run-spec.sh` を明示的に除外していた)。`/spec` は `run-code.sh` と構造的に類似しており、sub-agent への fan-out がない単一の 19 ステップ推論チェーンだが、下流への波及範囲は `run-code.sh` よりさらに大きい — spec のエラーは code・review・merge の 3 フェーズに波及する (code のエラーより 1 フェーズ多い)。本表に記載されている唯一の diminishing-returns 根拠 (上記の「Opus 4.8 effort calibration」ノート) は Opus 4.8 に明示的に限定されており、Sonnet 5 には適用されない — impact strategy レポート §3.3 の Sonnet 5 固有の主張 (`medium` がより競争力を持つ、`xhigh` が Opus に迫る) 自体は、Sonnet 5 自身の `max` が `xhigh` に対して過剰投資であるとは主張していない。#914 (Sonnet 5 のデフォルト親モデル化) 以降にコードされた Issue の Code Retrospective を対象にした本番サンプル調査では、設計推論に起因するギャップは見つからなかった (記録されていたギャップはいずれも環境/実行時固有の事象 — #917 のセキュリティ classifier との相互作用、#930 の macOS シンボリックリンクパス不一致など) — downgrade を裏付けも否定もしない中立的な結果である。Opus fallback の `xhigh` デフォルトは、Opus 4.8 独自の (別建ての) effort calibration ガイダンスに基づく、より狭い L サイズ限定のスコープを反映したものであるため、Sonnet パスへの転用可能な根拠とは扱わない。`run-spec.sh`・本マトリクス表・`tests/run-spec.bats` はいずれも変更しない。

## Wholework ラベル管理

`scripts/setup-labels.sh` は Wholework が管理するすべてのラベルの**唯一の真実（SSoT）**です。すべてのラベル名・色・説明はここで定義します。

### ラベルグループ

| グループ | 数 | ラベル | 作成条件 |
|----------|-----|--------|----------|
| 常時 | 17 | `phase/*`（9）、`triaged`、`retro/verify`、`retro/code`、`retro/recoveries`、`audit/drift`、`audit/fragility`、`audit/auto`、`stale-verify` | 常に作成 |
| フォールバック | 17 | `type/*`（3）、`priority/*`（4）、`size/*`（5）、`value/*`（5） | 対応する GitHub 機能が未構成の場合に作成（以下参照） |

### 自動ブートストラップ

`scripts/gh-label-transition.sh` は `phase/*` ラベルの遷移を試みた際に対象ラベルがリポジトリに存在しない場合、自動的に `setup-labels.sh` を実行します。Plugin インストールのみのユーザー（リポジトリ clone 不要）が手動で `setup-labels.sh` を実行する必要はありません。初回のスキル実行時に自動起動されます。

### フォールバックラベルの検出条件

フォールバックラベルは対応する GitHub 機能が未構成の場合に作成されます。検出条件は `setup-labels.sh` 内のインラインコメントにも記載しています：

| フォールバックグループ | 検出関数 | チェック対象 |
|----------------------|---------|------------|
| `type/*` | `detect_issue_types()` | GitHub Issue Types（`issueTypes` API） |
| `priority/*` | `detect_projects_field("Priority")` | Projects V2 Priority フィールド |
| `size/*` | `detect_projects_field("Size")` | Projects V2 Size フィールド |
| `value/*` | `detect_projects_field("Value")` | Projects V2 Value フィールド |

検出失敗（API エラー、権限不足など）は「未構成」扱いとし、フォールバックラベルを作成してワークフローを先に進めます。

### 変更ルール

Wholework 内でラベルを追加・変更・削除する場合（skills、scripts、modules 問わず）、同一 PR で `scripts/setup-labels.sh` も更新してください：

- **ラベル参照の追加**（`gh label create`、`--add-label`、`grep 'label-name'` など）: 検出条件コメントを付けて `ALWAYS_LABELS` または `FALLBACK_LABELS` に追加する
- **ラベル名や色の変更**: `setup-labels.sh` 内のエントリを更新する
- **ラベル参照の削除**: `setup-labels.sh` からエントリを削除する

このルールによりコード上のラベル参照と SSoT 定義のドリフトを防ぎます。将来の `/audit drift` 検出では、コードベース内のラベル参照集合と `setup-labels.sh` で定義された集合の一致チェックを行う予定です。

## テスト戦略

| ツール | 目的 | タイミング |
|------|---------|------|
| **bats**（Bash Automated Testing System） | シェルスクリプトのユニットテスト | マージ前(`command` verify command 経由) |
| **validate-skill-syntax.py** | SKILL.md 構文検証（半角 `!` 検出、frontmatter 検証） | マージ前 |
| **Verify commands**（`<!-- verify: ... -->`） | 受入条件の機械検証（ファイル存在、テキスト内容、コマンド実行） | `/verify` スキル実行時 |

## 禁止表現

| 表現 | 理由 | 代替 |
|------------|--------|-------------|
| 半角 `!`（SKILL.md 本文、コードフェンス外およびインラインコード外） | Claude Code の Bash 権限チェッカーが zsh の履歴展開と誤検出し、スキル実行時にエラーとなる | 全角「！」または言い換え |
| Acceptance check | 用語リデザイン（"verify command" に変更） | "verify command" |

**非推奨用語**: 上記表に加えて、`docs/product.md` § Terms の「旧称（Formerly called）」に列挙された用語は新規コンテンツ（コードコメント、ドキュメント、コミットメッセージ、Spec ファイルなど）で使用してはならない。現行リストは `docs/product.md` § Terms を参照すること。新たな非推奨用語が生じた場合は `docs/product.md` § Terms に 'Formerly called' エントリとして追記すれば十分で、この表の更新は不要。

**Spec Retrospective: 非推奨用語の引用**
Spec の retrospective セクション（例: `## Code Retrospective`、`## Spec Retrospective`）で非推奨用語を引用する場合、具体的な deprecated 文字列を直接書かないこと。`docs/spec/` 配下の Spec ファイルは CI スキャン対象（`scripts/check-forbidden-expressions.sh` の `SCAN_DIRS`）であるため、直接引用するとスキャンが FAIL する。代わりに以下のいずれかを使用すること:
- **説明的記述**: 用語自体を引用せずに件数などで説明する（例: 用語名そのものの代わりに「N 個の deprecated 語」）
- **`旧称:` 接頭辞**: `旧称: <用語>` と書く（例: `旧称: verify hint`）— CI 除外フィルタは `旧称` を含む行をスキップする

## 用語移行スコープルール

Terms の 'Formerly called'（段階的用語移行）に非推奨用語を追加する Issue を作成する際、同一ファイル内の非推奨用語置換をスコープに含めるかを明示すること。

### スコープ宣言テンプレート

Issue 本文の "Scope" または "Acceptance Criteria" セクションに以下のいずれかを含める:

```
[Same-file deprecated term replacement] included / not included (handled in follow-up Issue #N)
```

### 理由

段階的移行では、非推奨用語を Forbidden Expressions に追加した後も同一ファイル内に非推奨用語が残る期間がある。この期間、レビュアー（Copilot など）が Forbidden Expressions と本文の矛盾を指摘することがあり、段階的移行方針と衝突する。スコープ宣言を明示することで誤ったレビューコメントを防ぐ。

### 適用範囲

- Forbidden Expressions への非推奨用語追加を含むすべての Issue に適用
- "not included" の場合は非推奨用語置換をフォローアップ Issue で扱い、その Issue 番号を参照する

## 環境変数

| 変数 | デフォルト | 説明 |
|----------|---------|-------------|
| `WHOLEWORK_CI_TIMEOUT_SEC` | `1200` | `wait-ci-checks.sh` の最大待機時間（秒）。タイムアウト挙動をテストするときは低い値（例: `60`）に設定する |
| `WHOLEWORK_CONFIG_PATH` | *(未設定)* | `scripts/get-config-value.sh` が参照する設定ファイルパスを上書きする。設定されている場合、CWD 相対 `.wholework.yml` の代わりに指定したパスを読む。BATS テストでは `/dev/null` を設定してデフォルト値を強制できる。未設定または空の場合は `.wholework.yml`（CWD 相対）にフォールバックする |
| `WHOLEWORK_ISSUE_BODY_DIR` | *(未設定)* | `scripts/get-auto-session-report.sh` が verify-type 内訳を取得する際の Issue body ソースを上書きする。設定されている場合は `gh issue view` を呼び出す代わりに `${WHOLEWORK_ISSUE_BODY_DIR}/<issue_number>.md` を読む。BATS テストのハーメティック実行用。未設定または空の場合は `gh issue view` にフォールバックする（`--no-github` 時はスキップ）。 |
| `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` | `1` | `scripts/spawn-recovery-subagent.sh` が生成する Tier 3 recovery sub-agent の最大並列数。XL 並列実行時のコスト上限のためデフォルト 1 (逐次回復)。 |
| `WHOLEWORK_PATCH_LOCK_TIMEOUT` | `300` | `scripts/worktree-merge-push.sh` の patch lock タイムアウト秒数。優先順位: env var > `.wholework.yml` `patch-lock-timeout` > 300。 |
| `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` | `30` | `scripts/worktree-merge-push.sh` で patch lock 待機中のログ出力間隔秒数。 |
| `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` | `300` | `scripts/retry-on-kill.sh` の early-kill ウィンドウ (秒)。run-*.sh ラッパーが exit 137/143 でこのウィンドウ内に終了した場合、自動で 1 回リトライする。テストでは `0` を設定して late-kill (no-retry) ブランチを強制可能。最小 `WATCHDOG_TIMEOUT` (merge フェーズで 600s) より厳密に小さい値を維持し、watchdog hang-kill が自動リトライされないようにする必要がある。 |
| `WHOLEWORK_YML` | `${CLAUDE_PROJECT_DIR:-}/.wholework.yml` | `scripts/hook-rename-on-auto.sh` が参照する `.wholework.yml` のパス。`CLAUDE_PROJECT_DIR` から導出され、オペレーター override パターン (`${WHOLEWORK_YML:-...}`) ではない (スクリプトが直接代入)。 |

### Capability フラグ

以下の変数は、`detect-config-markers.md` が `.wholework.yml` の `capabilities.*` キーから設定する。組み込み capability は下記の固定マッピングを使用する。ユーザー定義の `capabilities.{name}: true` キーは動的に `HAS_{UPPERCASE_NAME}_CAPABILITY` へマッピングされる。

| 変数 | 設定条件 | 説明 |
|----------|---------|-------------|
| `HAS_BROWSER_CAPABILITY` | `capabilities.browser: true` | ブラウザ自動化 capability が有効なとき `true`。ブラウザ向け verify パターン（`verify/browser-verify-phase.md` など）を条件付きで読み込むために使用する |
| `HAS_VISUAL_DIFF_CAPABILITY` | `capabilities.visual-diff: true` | ビジュアル差分 capability が有効なとき `true`。ビジュアル diff モジュール（`modules/visual-diff-adapter.md` など）を条件付きで読み込むために使用する |
| `HAS_WORKFLOW_CAPABILITY` | `capabilities.workflow: true` | Workflow ツールが利用可能なとき `true`。`/review` での並列マルチエージェントレビューを条件付きで有効化するために使用する |
| `HAS_PR_PREVIEW_CAPABILITY` | `capabilities.pr-preview: true` | プロジェクトの PR が preview URL を生成するとき `true`。`/issue` Step 4 の pre-merge-preview AC 分類のゲートとして機能する。URL/UX 系 AC に `ac-tier: preview` タグと `--when="test -n \"$PREVIEW_URL\""` ガードを付与し、`/review` 時に実行、`/verify` post-merge では二重検証防止のため skip する |
| `MCP_TOOLS` | `capabilities.mcp` リスト | プロジェクトで有効化された MCP ツール名のカンマ区切りリスト（例: `"mf_list_quotes,mf_list_invoices"`）。注意: `capabilities.mcp` は直接 `MCP_TOOLS` にマッピングされる。動的な `HAS_*_CAPABILITY` マッピングの対象外のため、`HAS_MCP_CAPABILITY` は設定されない |

## Gotchas

### `.claude/settings.json` はホットリロードされない

`.claude/settings.json` はセッション開始時にキャッシュされ、**セッション中はリロードされない**。`permissions.allow` パターン（あるいは他の設定）の変更は Claude Code セッション再起動後にのみ有効となる。

**含意**: `settings.json` を変更した後は、新しい権限パターンが正しく動作するかをテストする前に必ずセッションを再起動する。

**セッション内プローブによる偽陰性リスク**: 古い設定がロードされたままのセッション内で新しい `permissions.allow` パターンを検証すると偽陰性が起こり得る。プローブはキャッシュされた設定に基づいて成功（または失敗）する可能性があり、更新されたパターンが実際に動作するかを覆い隠す。権限検証プローブの実行前には必ずセッションを再起動すること。
