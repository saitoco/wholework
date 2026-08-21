[English](../tech.md) | 日本語

# Tech

## 言語とランタイム

- **Bash/Shell Script**: Wrapper スクリプト (`scripts/run-*.sh`)、ユーティリティスクリプト
- **Markdown**: Skill 定義 (`SKILL.md`)、agent 定義 (`agents/*.md`)、共有モジュール (`modules/*.md`)、ドキュメント
- **Python**: 検証スクリプト (`scripts/validate-skill-syntax.py`)
- **GitHub Actions**: CI/CD ワークフロー (`.github/workflows/`)

## 主要依存関係

| Package | Role |
|---------|------|
| Claude Code CLI (`claude`) | Skill 実行エンジン、サブエージェント起動 |
| GitHub CLI (`gh`) | Issue/PR 操作、GitHub API アクセス |
| GitHub Copilot | コードレビュー (Step 7)、Issue からの自動実装 |
| bats (Bash Automated Testing System) | シェルスクリプトテスト |
| jq | verify-executor / gh-graphql / get-issue-* ヘルパーが使用する JSON プロセッサ |

## アーキテクチャ決定

- **Skills ベースのワークフロー**: 各開発フェーズ (issue/spec/code/review/merge/verify) は独立した Claude Code Skill として実装される。処理ステップは SKILL.md に記述され、LLM がステップごとに実行する。
- **Plugin ディレクトリ配布**: `--plugin-dir` を使ったローカル Claude Code plugin として配布される。Claude Code はランタイムで `${CLAUDE_PLUGIN_ROOT}` を plugin ディレクトリに設定し、skill と module はこれを使ってスクリプトやモジュールを参照する。公開配布は Claude Code marketplace (`.claude-plugin/marketplace.json`) 経由で行われ、ユーザーは `/plugin marketplace add saitoco/wholework` + `/plugin install wholework@saitoco-wholework` でインストールできる。
- **fork context vs main context**: コンテキスト分離レベルは skill ごとに設定される。fork の根拠は「独立性/安全性」(1M context の GA 以降、コスト/容量的な動機はほぼ薄れている)。skill ごとの fork 判断 (網羅的):

  | Skill | Fork 必要性 | 実行プラットフォーム | 理由 |
  |-------|-------------|-------------------|--------|
  | triage | No | In-session | 前フェーズのバイアスを避ける必要がなく、独立性は不要 |
  | issue | Conditional | headless (run-issue.sh) / in-session (direct) | 直接呼び出し時は共有。run-issue.sh 経由の場合は fork (L/XL 並列調査のサブエージェントは分離コンテキストで実行) |
  | spec | Conditional | headless (run-spec.sh) / in-session (direct) | 直接呼び出し時は共有。run-spec.sh 経由の場合は fork |
  | code | Yes | headless (run-code.sh) / in-session (direct) | Spec を読み独立して実行。実装前コンテキストの影響を受けない |
  | review | Yes | headless (run-review.sh) / in-session (direct) | 実装フェーズのバイアスを引き継がず、クリーンな視点でコードをレビューする |
  | merge | Yes | headless (run-merge.sh) | Spec + PR メタデータで判断が完結。review コンテキストは引き継がない |
  | verify | No | In-session | ほとんど機械的な処理 (verify command 実行 + チェックボックス更新)。手動 AC 確認には fork context で実行できない AskUserQuestion が必要。FAIL → /code (fork) が再実行するためバイアス伝播のリスクは低い |
  | auto | No | In-session | 親オーケストレーターはユーザーの Claude Code セッション内で動作。各子フェーズは `run-*.sh` 経由で独立した `claude -p` プロセスとして動作する |
  | audit | No | In-session | Drift、fragility、recovery パターン検出はユーザーセッション内で実行。前フェーズのバイアスを避ける必要はない |
  | doc | No | In-session | ドキュメント管理はユーザーセッション内で実行。前フェーズのバイアスを避ける必要はない |

  コンテキスト決定基準とコンテキストごとの制約については [`modules/execution-context.md`](../modules/execution-context.md) を参照。

- **verify command 実行モード (safe vs full)**: `/review` は **safe mode** (マージ前) で動作する: 外部コマンドと副作用のある verify command タイプは CI 参照にフォールバックし、マージ前に安全に評価できない条件は UNCERTAIN を返す。`/verify` は **full mode** (マージ後) で動作する: シェルコマンドや外部サービス呼び出しを含む全ての verify command タイプが実行される。この分割により、マージ前レビューは再現可能なまま保たれ、マージ後検証は実際の副作用を行使できる。SSoT とモードごとのポリシー: [`modules/execution-context.md`](../modules/execution-context.md)。

- **`/auto` skill**: `run-*.sh` 経由で spec→code→review→merge→verify を逐次連鎖するオーケストレーター。各フェーズは独立した `claude -p --permission-mode auto` プロセスとして動作し、新鮮なコンテキスト分離を保証する。`verify-max-iterations` (デフォルト: 3、最大: 20、`.wholework.yml` で設定可能) は verify-reopen ループの上限を定める。カウンタが上限に達すると、Issue は `phase/verify` のまま人間の判断を待つ。`/auto` skill は verify 出力内の `MAX_ITERATIONS_REACHED` を検出し、無限にループする代わりにチェーンを停止する。フラグの挙動、バッチ処理、resume、リリースブランチワークフローについては [docs/workflow.md § Orchestration](workflow.md#orchestration) を参照。
  - **Two-tier orchestration**: `/auto` 自身 (親オーケストレーター) はユーザーの Claude Code セッション内で動作し、LLM の推論 (ラベル状態の評価、Size ベースのルーティング、sub-issue 依存分析) を用いて適応的な判断を行う。XL Issue の場合、`run-auto-sub.sh` (子オーケストレーター) が各 sub-issue のフルフェーズシーケンスを実行する。`run-auto-sub.sh` は bash によってオーケストレーションされ、段階的な適応リカバリを持つ: (1) `reconcile-phase-state.sh` の完了チェック、(2) `apply-fallback.sh` の既知パターン復旧、(3) 未知の異常に対する `spawn-recovery-subagent.sh` (`agents/orchestration-recovery` への `claude -p`)。通常経路はコストを最小化し並行安定性を最大化するため bash のままとし、Tier 1〜2 が失敗した場合の診断でのみ `claude -p` を呼び出す。並行コストを抑えるため `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` の上限を設ける。デフォルトは 1 (逐次復旧) で、環境変数を明示的に設定すれば引き上げられる。
    - **親セッションによる手動再起動 (Tier 1/2/3 の機構の外)**: バックグラウンドの `run-*.sh` wrapper 自身のプロセスグループが外部から kill された場合 (`modules/orchestration-fallbacks.md#external-kill-parent-respawn` 参照)、上記の 3 つの tier のいずれも発火できない — Tier 3 の Layer B リトライは kill されている同じプロセスグループ内で動作するためである。この kill を観測して該当フェーズを再起動できるのは親の `/auto` セッションのみであり、`run-auto-sub.sh --write-manual-recovery` (`#manual-recovery-spec-write` 参照。任意の `--cause SLUG`/`--diagnosis TEXT` フラグは機械可読な cause 行を追加し、`collect-recovery-candidates.sh` が同一症状・異なる原因のイベントを別グループとして扱えるようにする — Issue #1123。任意の `--notification CLASS` フラグ (`harness-stop`/`external-signal`/`indeterminate`/`unobserved`) は、親セッションが観測した kill されたバックグラウンドタスクのタスク通知文言の分類を記録する — Issue #1153) 経由でその復旧を記録する。これは `docs/reports/orchestration-recoveries.md` と `manual_intervention` イベントに書き込まれ、Tier 1/2/3 の語彙やメトリクスには含まれない。2 つ目の呼び出しサイトがバックストップとして存在する: `skills/verify/SKILL.md` Step 12 は、`orchestration-recoveries.md` にも既存の Spec エントリにも記録されていない Manual recovery を検出した場合、同じ `--write-manual-recovery` 呼び出しを事後的に (マージ後に) 発行する — これは、リアルタイムのハンドオフが復旧自体の最中に見逃されたギャップを埋めるものである (Issue #1049)。
  - **Phase state reconciliation**: `scripts/reconcile-phase-state.sh` は、`modules/phase-state.md` (SSoT、`ssot_for: phase-signatures, reconcile-json-schema`) で定義されたフェーズ固有の期待シグネチャ (前提条件と成功シグネチャ) に対して、ライブの GitHub/git 状態を検証する汎用フェーズ状態リコンサイラである。呼び出し元 (`/auto` の watchdog リカバリ、フェーズ実行前の precondition チェック) は、そのモジュールで固定された JSON v1 出力スキーマを消費するため、リコンサイラの内部実装に結合しない。これは、以前の issue 固有の `watchdog-reconcile.sh` を、共有され per-phase に拡張可能なメカニズムに置き換えるものである。リコンサイラは各 `/auto` フェーズに適用される **Observe-Diagnose-Act パターン** を実装する: (1) **Observe** — フェーズ実行前にライブの GitHub/git 状態を読み取る (precondition チェック)。(2) **Diagnose** — 観測された状態を期待シグネチャと比較し、進行・スキップ・リカバリのトリガーを判断する。(3) **Act** — フェーズを実行し、完了チェックとして成功シグネチャを再チェックする。オーケストレーション信頼性の基盤として #314 で導入され、下流の issue #315〜#319 (verify、merge、review、code フェーズごとの状態検出) に対応する: Observe-Diagnose-Act を 1 つのリコンサイラに集約することで、各フェーズをアドホックな per-phase 状態チェックなしに独立して検証・復旧可能にする。
- **`/doc` skill**: プロジェクト基盤ドキュメント管理。Steering Documents (`product.md`、`tech.md`、`structure.md`) と Project Documents を管理する。主な操作: `sync` (双方向正規化と drift 検出。ドキュメントごとのバリアント: 選択的な reverse-generation のための `sync product` / `sync tech` / `sync structure`。`--deep` はコードベース分析 + .md 統合スキャン + Narrative Semantic Drift Check + Terms 整合性チェックを追加拡張する)、`init` (初期セットアップウィザード)、`add` / `project` (ドキュメント登録)、`translate {lang}` (多言語翻訳生成)。`/audit` を補完する: `/doc sync` はドキュメント側の修正を提案し、`/audit drift` はコード側の修正のための Issue を生成する。
- **`/triage` skill**: メインワークフロー開始前に Type/Priority/Size/Value/Theme を割り当てる初期 Issue 評価。Title 正規化 (`modules/title-normalizer.md`) と 4 観点の deep 分析 (`/triage --backlog`) を実行する。Issue に `phase/*` ラベルがない場合、`/auto` は `/triage` を自動的に連鎖実行する。
- **`/merge` skill**: CI 通過とレビュー承認後に PR を squash-merge し、リモートブランチを削除する。判断基準: AC 検証が GREEN (または明示的に承認済み) の場合のみマージする。`/review` から Phase Handoff を読み、`/verify` 用に Phase Handoff を書き込む。機械的な操作であり、`model: sonnet` + `low` effort で十分。
- **`/code` skill**: `docs/spec/issue-N-*.md` から Spec を読み取り実装ステップを実行するローカル実装フェーズ。Issue のサイズに基づいて patch (XS/S の main への直接コミット) または PR (M/L のブランチ+PR) にルーティングする。既存の AC の verify command を読み取って実装に反映させ、下流の `/review` / `/merge` / `/verify` 向けに Phase Handoff を発行する。
- **operate 経路 (diff-less ワークフロー経路)**: Spec がリポジトリのファイル変更を伴わない外部ツール操作 (CMS 編集、インフラ操作) のみを記述する Issue のための、Size とは直交する 3 つ目の `/code` 経路。Spec の `## Changed Files`/`## Implementation Steps` から機械的に検出され、新しいラベルや Issue メタデータは追加されない。新しい Skill としてではなく、`/code` の既存の patch/pr 分岐点に 3 つ目の値として実装される: #437 の教訓は、新しいメカニズムを導入するより既存のパターンを拡張することを優先しており、独立した Skill であれば追加で 6〜8 の SSoT ドキュメントに触れることになっただろう。結果は git diff の代わりに `## Execution Log` の Issue コメントとして記録される。`phase/code` → `phase/verify` のラベル遷移は patch 経路と同じで、PR が存在しないため `/review`/`/merge` をスキップする。operate 経路は `closes #N` コミットを一切生成しないため、`code-patch` の完了シグネチャ (`scripts/reconcile-phase-state.sh`) は Execution Log/Execution Plan マーカーコメントも代替の成功シグネチャとして受け付ける — `modules/phase-state.md` § "Operate Route Completion Signature" 参照。`modules/size-workflow-table.md` § "Diff-less Axis (operate route)" も参照。
- **サブエージェント分割**: 2 つの skill で使用される:
  - `/issue` (L/XL): 変更範囲・リスク・前例を同時に分析するため、3 つの独立したサブエージェント (`issue-scope`、`issue-risk`、`issue-precedent`) による並列調査。
  - `/review`: Full モードは Spec 準拠レビュー (`review-spec`) とバグ検出 (`review-bug`) の 2 グループに分割され、2 段階検証 (detection→verification サブエージェント) で偽陽性を排除する。Light モードは 4 つの観点 (spec、bug、edge cases、documentation) すべてをカバーする単一の統合エージェント (`review-light`) を使用する。
- **共有モジュールパターン**: 複数 skill にまたがる共通処理は `modules/*.md` に抽出され、「Read and follow」パターンで参照される。
- **Spec-first (使い捨て)**: Spec はタスク完了後に成果物として維持されない。Spec-anchored や Spec-as-source のアプローチは採用しない。理由: (1) LLM の非決定性により、同じ spec が同じコードの再生成を保証しない。(2) spec の保守コストがコードの保守コストに上乗せされる。
- **フェーズ横断メモリメカニズム**: フレッシュな fork context で動作するフェーズをまたいでコンテキストを運ぶ、2 つの補完的なメカニズムがある。
  - **Spec retrospectives**: 各フェーズは、そのフェーズの観察・決定・不確実性の解消を記録する Retrospective セクションを Spec に追記する。使い捨ての Spec 内にサーフェスが蓄積され、下流フェーズに供給される。
  - **Phase Handoff** (`modules/phase-handoff.md`): 生成側フェーズが書き込み、消費側フェーズが読む構造化サマリー (例: review → merge → verify)。短命な hand-off シグナル (受入条件の結果、スコープに関するメモ、残存リスク) を Spec 本文から切り離すことで、fork context のフェーズが Spec の全履歴を読み直すことなく必要な情報だけを取得できるようにする。Spec retrospective は *履歴* を保存し、Phase Handoff は *次のステップの作業コンテキスト* を運ぶ。
- **Progressive disclosure (Core/Domain 分離)**: SKILL.md 本文には、プロジェクトタイプやツールに依存しない汎用ロジックのみを含める。特定のツール (Figma、Copilot など) やプロジェクトタイプ (skill development、IaC など) に固有のロジックは補助ファイル (`skills/{name}/xxx-phase.md`) に抽出され、該当する場合のみ読み込まれる。判断基準: 「このツール/プロジェクトタイプを使わないプロジェクトでもこのロジックが必要か?」— No なら抽出する。**この基準は実行ロジックだけでなく、ガイダンス内容 (適用シナリオ、判断基準、比較表) にも適用される** — capability 固有のガイダンスを eager-load される共有モジュール (例: `modules/verify-patterns.md`) に置くと、対象外のプロジェクトが呼び出しのたびにトークンコストをフルに負担することになる。代わりに `load_when: capability: {name}` ゲート付きの Domain file を使うこと (参考: Issue #441 の visual-diff capability と `skills/spec/visual-diff-guidance.md`)。抽出パターン (Marker-detection / File-existence / MCP-availability / Depth-routing / Capability-flag / Directory-scan) の網羅的なリストは [docs/environment-adaptation.md § Extraction Patterns](environment-adaptation.md#extraction-patterns-exhaustive) (SSoT: `environment-adaptation-architecture`) を参照。

- **Autonomy tier (L0 write ガバナンス)**: Wholework は 4 つの層にまたがって動作する — L0 (GitHub 状態: Issues、Labels、PRs、blockedBy、`closes #N`)、L1 (Claude Code プリミティブ: `/loop`、`/goal`、`ScheduleWakeup`、`CronCreate`)、L2 (Wholework skill 内部: Spec、retro、`auto-events.jsonl`)、L3 (OS スケジューラ — 現在 Wholework のどのメカニズムも使用していない。上記 L1 に挙げた `CronCreate` が最も近い利用可能なプリミティブだが、それ自体セッションスコープ/インメモリであり、OS レベルの永続スケジューラではない — `modules/autonomy-tier.md` 参照)。`.wholework.yml` の `autonomy:` フィールドは、skill がどこまで L0 を書き込み L2→L1 経路を発火できるかを宣言する (A Advisory / B CronCreate / C ScheduleWakeup)。tier × path マトリクスと Tier × L0 write マトリクスの SSoT は [`modules/autonomy-tier.md`](../modules/autonomy-tier.md)、サーフェスごとの L0 write 分類は [`modules/l0-surfaces.md`](../modules/l0-surfaces.md) にある。この層は Claude Code の `--permission-mode` サブプロセスフラグ (サブプロセスの権限を統制するものであり、Wholework の GitHub 状態スコープではない) と直交する。Skill frontmatter の `loop-paths-used` は、その skill が使用する L2→L1 経路を宣言する (例: `loop-paths-used: [A]` = advisory print のみ)。#700 (`/verify` auto-retry-on-fail テールの拡張) で実装された。

- **Distributable-first improvement principle**: retrospective を通じて特定された改善は、配布可能なコンポーネント (Skills、Agents、Modules、Scripts) に反映されなければならない。CLAUDE.md、Steering Documents、Project Documents はユーザーリポジトリ固有の成果物であり、Wholework plugin の一部として配布されない — これらのドキュメントのみへの改善は他の Wholework ユーザーには届かない。retrospective が改善点を特定した場合、実装対象は配布可能な層とすべきであり、配布不可能な成果物のみの更新では不十分である。
- **Effort 最適化戦略 (3 軸)**: `claude -p` 呼び出しにおける実行コストと品質を制御する 3 つの軸。軸ごとの CLI サポート状況と Wholework の採用ポリシー:
  - **軸 1 — Model 選択** (`--model`): 実装済み。Sonnet がデフォルト。`run-spec.sh --opus` は L サイズの spec で Opus に切り替える。レビュー・確認済み。
  - **軸 2 — Adaptive Thinking** (`--effort`): `claude -p` は `low/medium/high/xhigh/max` レベルをサポートする (`claude --help` で確認済み)。`run-*.sh` にフェーズ固有の effort レベルで実装済み (下記マトリクス参照)。medium effort と Opus advisor を組み合わせると、より低いコストで default-effort Sonnet に匹敵する品質を達成できる (Anthropic のベンチマークによる)。
  - **軸 3 — Advisor 戦略** (`advisor_20260301`): Anthropic API のベータ機能 (`advisor-tool-2026-03-01` ヘッダーが必要)。`--betas` フラグで有効化 — API key ユーザーのみ、OAuth/サブスクリプション認証 (`run-*.sh` のデフォルト) では利用不可。パフォーマンス向上: Sonnet + Opus advisor は SWE-bench で +2.7pt、コストは Sonnet 単独比 −11.9%。Haiku + Opus advisor は BrowseComp で 41.2% (単独の 19.7% に対して)、コストは Sonnet 単独比 −85%。`run-*.sh` への実装はフォローアップ Issue。

### フェーズ別モデルと Effort マトリクス

(`ssot_for: model-effort-matrix`)

エントリはワークフロー順 (triage → issue → spec → code → review → merge → verify) にグループ化されている: まずオーケストレーションスクリプト、次にフェーズごとのサブエージェント、最後に skill のみのエントリ。

**デフォルトの親 = Sonnet 5** (`claude-sonnet-5`、2026-06-30 リリース): 下記マトリクス全体 (`run-*.sh`、skill、サブエージェントの frontmatter) で使われている裸の `Sonnet` エイリアスは、これ以降 Sonnet 5 を指す — 従来のデフォルト親であった Sonnet 4.6 を置き換える。切り替えの根拠とエイリアス pin ポリシーについては表の下の **Sonnet 5** の注記を参照。

**「Default parent」のスコープ (表を読む前に)**: この用語が統制するのは (1) `run-*.sh` が起動する `claude -p` フェーズプロセスが実行されるモデル (`--model sonnet` / `ANTHROPIC_MODEL=sonnet`)、および (2) 自身の frontmatter に `model:` 値を固定している skill (例: `merge`、`triage`、`verify` — 誰が呼び出しても固定) のみである。あなた自身の対話的な Claude Code セッションのモデルは設定しない — それは Sonnet 5、Opus 5、その他いずれであれ、このテーブルとは独立してあなた自身が選ぶものである。`run-*.sh` wrapper も `model:` frontmatter 値も持たずにインラインで呼び出される skill (例: `auto`、`audit`、`doc`) は、呼び出し元のセッションが既に動作しているモデルをそのまま継承する — `/auto` 自身のトップレベル呼び出しについては、それはあなたの対話的セッションの選択であり「Default parent」ではない。`/auto` が `run-*.sh` 経由で起動するフェーズのみが上記 (1) に従って固定される。

| Component | Phase | Model | Effort | Rationale |
|-----------|-------|-------|--------|-----------|
| run-issue.sh | issue | Sonnet | high | 既存 Issue Refinement は、パイプラインの最も上流の成果物を生成するための実質的な判断作業 (曖昧性解消、AC/verify-command 作成) を行う。エラーはすべての下流フェーズに伝播する — C シリーズの中で最も長い波及範囲 |
| run-spec.sh | spec | Sonnet (L の場合 `--opus` で Opus 経由。Fable 5 は `--fable`) | Sonnet: max; Opus: xhigh (デフォルト)、max (明示的な `--max`); Fable 5: high (デフォルト)、max (明示的な `--max`) | 設計品質が重要。spec のエラーは後続の全フェーズに伝播する。`/auto` は L サイズのみ `--opus` を渡す (XL は spec 前に分割される) |
| run-code.sh | code | Sonnet | high | 実装には徹底的な推論が必要 |
| run-review.sh | review | Sonnet | high | オーケストレーターは dispatch を超えた実質的な推論を行う — Steps 7.2/7.4/7.6 は外部レビューフィードバックを解釈し fix コミットを作成する。これは run-code.sh 自身の実装推論に匹敵する作業である |
| run-merge.sh | merge | Sonnet | low | 機械的なマージ操作。最小限の推論で十分 |
| issue-scope | issue (L/XL のみ) | Opus | high | L/XL 並列調査のために `/issue` Step 11a から呼び出される。スコープ特定の精度は sub-issue 境界の判断にとって重要。agent frontmatter に `effort: high` を設定 (#1063)。`run-issue.sh` 自身の `--effort high` と一致させ、サブエージェントの effort をオーケストレーターセッションから切り離す |
| issue-risk | issue (L/XL のみ) | Opus | high | L/XL 並列調査のために `/issue` Step 11a から呼び出される。リスク評価の精度は受入基準の品質を改善する。agent frontmatter に `effort: high` を設定 (#1063)。`run-issue.sh` 自身の `--effort high` と一致させ、サブエージェントの effort をオーケストレーターセッションから切り離す |
| issue-precedent | issue (L/XL のみ) | Opus | high | L/XL 並列調査のために `/issue` Step 11a から呼び出される。前例抽出は受入基準の品質を改善する。agent frontmatter に `effort: high` を設定 (#1063)。`run-issue.sh` 自身の `--effort high` と一致させ、サブエージェントの effort をオーケストレーターセッションから切り離す |
| review-bug | review | Opus | high | バグ検出には最高の精度が必要。agent frontmatter に `effort: high` を設定 (#1063)。`run-review.sh` 自身の `--effort high` と一致させ、サブエージェントの effort をオーケストレーターセッションから切り離す |
| review-spec | review | Opus | high | Spec 逸脱の検出には高い精度が必要。agent frontmatter に `effort: high` を設定 (#1063)。`run-review.sh` 自身の `--effort high` と一致させ、サブエージェントの effort をオーケストレーターセッションから切り離す |
| review-light | review | Sonnet | high | 軽量統合レビュー。agent frontmatter に `effort: high` を設定 (#1063)。`run-review.sh` 自身の `--effort high` と一致させ、サブエージェントの effort をオーケストレーターセッションから切り離す |
| orchestration-recovery | auto (recovery) | Sonnet | — | bash tier 1〜2 が失敗した場合に `spawn-recovery-subagent.sh` が起動する Tier 3 復旧診断者。フェーズ状態を分析し JSON 形式の最小復旧計画を生成する。#1063 の `effort:` frontmatter ロールアウトの対象外 — `spawn-recovery-subagent.sh` はこの agent を Task tool のサブエージェントとして起動せず、frontmatter を取り除いて本文をスタンドアロンの `claude -p ... --effort medium` プロセスとして実行するため、`effort:` frontmatter 値は決して読まれない。effort はそのスクリプトの `--effort medium` フラグで既に明示されている |
| frontend-visual-review | verify (visual-diff) | Opus | high | 3-panel 比較画像からの視覚的差異列挙。`visual_diff` verify command 用に `modules/visual-diff-adapter.md` が起動する。呼び出し元のセッションコンテキストで `run-*.sh` wrapper なしに動作するため、実効 effort は以前は未定であった。agent frontmatter に `effort: high` を設定 (#1063)。intelligence-sensitive なタスクに対する Opus 5 の推奨最低値に基づく |
| triage (skill) | triage | Sonnet | — | メタデータ割り当て。Sonnet で十分。(wrapper なしで) インラインで呼び出される — `/auto` がラベルなし issue に対して triage を連鎖する場合も含む — ため effort は設定されない |
| merge (skill) | merge | Sonnet | — | 機械的なマージ操作。frontmatter に `model: sonnet` を固定。effort は設定されない (skill 呼び出し。`run-merge.sh` は `low` effort を設定する) |
| verify (skill) | verify | Sonnet | — | 構造化された受入テスト。frontmatter に `model: sonnet` を固定。呼び出し元のコンテキストで動作 (wrapper スクリプトなし)。skill レベルでは effort は設定されない |
| auto (skill) | orchestration | Sonnet | — | 親オーケストレーター。ユーザーの Claude Code セッション内でインラインに動作 (`run-*.sh` wrapper なし)。各子フェーズはフェーズ固有の effort で `run-*.sh` 経由で動作する。skill レベルでは effort は設定されない |
| audit (skill) | audit | Sonnet | — | Drift 検出 (`drift`)、fragility 分析 (`fragility`)、プロジェクトヘルス統計 (`stats`)、XL sub-issue 進捗 (`progress`)、/auto セッション retrospective (`auto-session`)、Issue premise の失効 (`premise`)。Sonnet で十分。(wrapper なしで) インラインで呼び出されるため effort は設定されない |
| doc (skill) | doc | Sonnet | — | ドキュメント管理。Sonnet で十分。(wrapper なしで) インラインで呼び出されるため effort は設定されない |

**Opus 4.8 effort calibration** (過去の記録 — この注記の見出しテキストは `#922` がこれを判断根拠として名指しで引用しているためそのまま保持している。実際に `opus` エイリアスに今日適用されるガイダンスについては下記の **Opus 5 effort calibration** の注記を参照): Opus 4.8 は厳格な effort calibration を強制する — `low` と `medium` は文字通りのタスク要件に積極的にスコープする。`max` は Opus 4.8 では過剰思考というリスク逓減効果を伴う。知性を要する実験的なタスクにのみ温存すること。`xhigh` はほとんどのコーディング・エージェンティックなユースケースにおける Opus 4.8 の推奨デフォルトである。

**Opus 5 effort calibration**: Opus 5 (`claude-opus-5`、2026-07-24 リリース) は上記の Opus 4.8 ガイダンスを改訂する — コーディング/エージェンティックなタスクでは `xhigh` から始め、それ以外のタスクでは `high` から始めて、そこから下方向へ調整すること。`low`/`medium` はティア名から想像されるより強力だと報告されているためである。`max` は極めて難しく、レイテンシに寛容なタスクにのみ温存すること。agent frontmatter の `model: opus` / `model: sonnet` エイリアス値は現行の Opus (5) に自動解決される。フルの影響分析は `docs/reports/claude-opus-5-impact-strategy.md` (`#1062`) を参照。

**Fable 5 (Mythos クラス)**: Fable 5 (`claude-fable-5`) は Opus より上位のティアであり、`opus` エイリアス経由では**到達できない** — 明示的なモデル文字列 `claude-fable-5` が必要。ハードな制約 (コスト $10/$50 per MTok、Opus 4.8 の 2 倍・標準価格の Sonnet 5 の約 3.3 倍、30 日間の保持が必須 (zero-data-retention 組織は非対応)、サブスクリプションプランでの usage-credit ゲート) により、採用は**オプトインのみ** (デフォルトモデルの切り替えは行わない)。Fable 5 のオプトインを公開する skill (例: `/spec --fable`) は skill ごとにドキュメント化する。採用ガイダンスの詳細は `docs/reports/claude-fable-5-impact-strategy.md` §3.3・§5.2 を参照。Fable 5 で実行する場合、review フェーズのセキュリティ関連クエリは cyber classifier によって自動的に Opus 4.8 にルーティングされることがある (CLI 経由で透過的) — Fable 5 がセキュリティ分析を直接処理すると想定しないこと。Fable 5 の biology-classifier フォールバック先は Opus 5 のリリースで変更された: Fable 5 の biology classifier によってブロックされたリクエストは、Opus 4.8 ではなく **Opus 5** にルーティングされるようになった (cyber-classifier のフォールバック先は変更なし — 引き続き Opus 4.8)。

**Sonnet 5**: Sonnet 5 (`claude-sonnet-5`、2026-06-30 リリース) は、従来のデフォルト親 (Sonnet 4.6) からの大幅なエージェンティック性能アップグレードであり、`effort: xhigh` において多くのタスクで Opus 4.8 に近づきながら、価格は Opus 4.8 のおよそ 40〜60% ($2/$10 per MTok、2026-08-31 までの導入価格、以降は $3/$15 の標準価格 — Sonnet 4.6 が Wholework のコストモデルで既に占めていたのと同じ帯域) である。Opus 4.7 の変更と同系統のトークナイザー更新 (同じ入力に対して 1.0〜1.35 倍のトークン数) を伴い、`claude-watchdog.sh` のタイムアウト校正とコンテキスト予算のヒューリスティックに直接影響する。両方のブロッキング測定は既に完了している: `#877` (`/verify` interactive-friction の再測定) は **NO-GO** (再設計不要) で解決し、`#878` (トークナイザー/watchdog 影響測定) は **significant** で解決し、`#903` の再校正 (`WATCHDOG_TIMEOUT_CODE_DEFAULT` 3600→4680、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 2000→2600) で対応済みである。両方のブロッカーが解決したことで、Sonnet 5 へのデフォルト親切り替えは **確定・最終決定** となった — これはもはや注記のみのエントリではなく、上記マトリクス表は既に Sonnet 5 をデフォルト親として記載している (表の直前の文を参照)。フルの影響分析、決定マトリクス (§4.1)、候補 Issue 実行計画 (§8) は `docs/reports/claude-sonnet-5-impact-strategy.md` を参照。

**Alias pin policy**: Wholework は引き続き裸の `sonnet` CLI エイリアス (および `ANTHROPIC_MODEL=sonnet`) を使用し、`claude-sonnet-5` への明示的な pin は行わない。根拠: (1) reactive recalibration は既に実証済みの運用パターンである — Fable 5 → Sonnet 4.6 の移行 (`#628`) も、この Sonnet 5 移行自体 (`#877`/`#878`/`#903`) も、事前のゲートではなく切り替え後の watchdog/effort フォローアップによってうまく処理された。(2) 明示的な pin は 5 つの `run-*.sh` スクリプトと `model: sonnet` を持つおよそ 10 の skill/サブエージェント frontmatter ファイルにわたる協調的な編集を必要とし、安全上の利益は限定的である。Anthropic は意図的な主要モデルのリリース時にのみ裸のエイリアスを再指定するためである。(3) トレードオフ: 将来のモデル世代も同様に、専用の測定 Issue が着地する前にエイリアス経由でデフォルト親として自動採用される (ここで Sonnet 5 に起きたように) — Wholework は reactive-recalibration SOP の実績 (`#628`、`#903`) を踏まえてこのリスクを受け入れる。同じトレードオフは、Opus 5 の 2026-07-24 リリースで `opus` エイリアスに対して 3 度目に発現した — 直下の注記を参照。

**Opus 5 default parent evaluation — deferred (`#1062`)**: Sonnet 5 → Opus 5 のデフォルト親切り替えは評価されたが、明示的に見送られた (採用されなかった)。理由: (a) Sonnet 5 のデフォルト親確定 (`#914`) はこの評価のおよそ 4 週間前に着地しており、新たな根拠なしに再検討するには近すぎる。(b) `#921`/`#922`/`#923` — Wholework の Sonnet-5 時代の 3 つの effort 再校正 (それぞれ code/review、spec、issue) — は、いずれも独立して本番サンプルに設計推論のギャップを見出さず **maintain** と結論した — より高価なデフォルトを動機づける品質シグナルはない。(c) Opus 5 は Sonnet 5 より 1.7 倍 (標準価格) 〜2.5 倍 (Sonnet 5 の導入価格比) 高価であり、Sonnet 4.6 → Sonnet 5 の切り替えをゲートした `#877`/`#878` に匹敵する測定チェーンは、このプレミアムを正当化するために実行されていない。**再評価トリガー**: (i) 将来の Sonnet 5 の effort または能力の再評価が真の品質ギャップを明らかにするか、(ii) Claude Max 自体のデフォルトモデルが既に Opus 5 になっていることが Wholework のデフォルト親選択にとって独立した重みを持つと判断される場合に、この見送りを再検討する — この注記の時点ではどちらの条件も成立していない。フルの決定マトリクスは `docs/reports/claude-opus-5-impact-strategy.md` §4.1 を参照。

**Opus 5 watch items**: 2 つの Opus 5 の変更が監視対象として記録されているが、まだ対応はしていない: (1) プロンプトキャッシュは **512** トークンの最小プロンプトから有効化されるようになった。Opus 4.8 の 1024 トークンの下限の半分であり、512〜1024 トークン範囲の Opus ルーティングされたプロンプトにとって有利であるが、Wholework は現在この閾値に対してコンポーネントごとのプロンプトサイズを追跡していない。(2) Opus 5 のレート制限は、統合された Opus 4.x プールとは**別のプール**にある。これは、複数の L/XL Issue の Opus サブエージェント (`issue-scope`/`issue-risk`/`issue-precedent`、`review-bug`/`review-spec`) を同時に扇状展開する `/auto --batch` 実行の並行キャパシティの見通しを変える。いずれの項目も具体的なインシデントはまだ伴っていない。`docs/reports/claude-opus-5-impact-strategy.md` §3.3/§3.4 を参照。

SSoT の注記: run-*.sh のモデル値は CLI エイリアス (sonnet/opus) を使用する。run-*.sh、agents、skills でモデル/effort を変更する場合はこの表を更新すること。

- **Watchdog タイムアウトの校正**: `scripts/watchdog-defaults.sh` のフェーズ固有のタイムアウト定数は、支配的な親オーケストレーターモデルのトークンあたりレイテンシに対して校正される。デフォルトの親モデルが変わったときに再校正する (例: #628 の Fable 5 → Sonnet 4.6 移行では `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` を 600 から 1200 に引き上げる必要があった)。**#903 の再校正 (Sonnet 5)**: #878 で測定された Sonnet 5 の約 1.3〜1.4 倍のトークナイザー比を受け、実際の `/code`/`/review` 本番稼働時間サンプル (n=10 / n=9、`docs/reports/sonnet-5-watchdog-recalibration.md`) は、両フェーズとも p95/max の使用率が再校正閾値である「タイムアウトの 80%」に既に達しているか超えていることを示した (code: p95 81.3%、max 93.8% (3600s に対して)。review: p95 92.2%、max 100.2% (2000s に対して) — 実サンプルの 1 件が既に限界に達していた)。`WATCHDOG_TIMEOUT_CODE_DEFAULT` を 3600→**4680** に、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を 2000→**2600** に引き上げた (両方とも ×1.3、#878 で測定された範囲の控えめな側であり、Icebox #596 の timeout-inflation-vs-stuck-detection のトレードオフに従い #628 の 2 倍という前例より意図的に控えめにしている)。`WATCHDOG_TIMEOUT_SPEC_DEFAULT` / `_ISSUE_DEFAULT` / `_MERGE_DEFAULT` は #903 のスコープ外であった (根拠はレポート参照)。**#939 (`WATCHDOG_TIMEOUT_SPEC_DEFAULT` 再チェック、`--opus` proxy 測定)**: Fable 5 の実トラフィックは #560 の未計測な単一データポイントのままであるため (`docs/reports/watchdog-recovery-strategy.md` § 2026-07 再測定を参照)、2026-08-07 の Issue Retrospective は AC1/AC2 の証拠範囲を拡張し、`--opus` の実トラフィックも proxy として受け入れるようにした。`/auto` は Size L の spec フェーズに対して自動的に `--opus` をディスパッチし、同じ `WATCHDOG_TIMEOUT_SPEC_DEFAULT` 予算を共有するためである。測定結果 (`docs/reports/watchdog-recovery-strategy.md` § 2026-08 再測定、N=20、2026-06-28〜2026-08-07、`size=="L"` の `sub_start` イベントと issue+session_id で結合した `phase=="spec"` の `max_silent_window`): min 660s / mean 978.5s / **p95 1340s (1800s の 74.4%)** / max 1460s (1800s の 81.1%)。post-Opus-5 サブセット (2026-07-24 以降、N=11) の max は 1340s (74.4%)。この母集団内で `phase=="spec"` の `watchdog_kill` イベントはゼロ。**判定: `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` を維持** — #903 の再校正閾値 (実使用がタイムアウトの 80% 以上に達したら引き上げる) を適用すると、p95 (74.4%) はそれを下回っており、80% を超えた唯一のサンプル (max、81.1%) は 2026-07-05 の Opus-5 以前の単発の外れ値であり、繰り返しパターンではない — post-Opus-5 サブセット単独では最大でも 74.4% にとどまる。`tests/watchdog-defaults.bats` への変更なし (値は変更なし)。**フォローアップ (#1301)**: その後の 2 回の `/auto --batch` セッション (2026-08-08、2026-08-09) で `phase=="spec"` に対して 5 回の閾値超過と 1 回の `watchdog_kill` が記録され、クリーンサンプルのマージンは 1800s のデフォルトに対して最小 10s まで狭まった — この判定自身の「再発時に再評価する」という条件を満たしている。グローバルデフォルトを改訂する代わりに、`#1301` はプロジェクトローカルの `.wholework.yml` オーバーライド (`watchdog-timeout-spec-seconds: 2340`、`#903` と同じ ×1.3 の係数) を適用した。これは `#939` の review フェーズパスが使ったのと同じ immediate-override-then-later-promote の順序 (`PR #1201` → このエントリ) に従っている。

**#939 (`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 再校正、Issue #1058 / PR #1201)**: 2026-08-06 の Issue #1058 (PR #1201) に対する実本番測定で、当時の `WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2600` において `watchdog_kill` (`silent_window_sec=2600`) が発生した。`.wholework.yml` のプロジェクトローカルオーバーライド `watchdog-timeout-review-seconds: 5400` のもとで実行された即時リトライは、`max_silent_window=4110s` (5400s の 76.1%)、総稼働時間約 4303s で完了した。観測された 4110s に #903 と同様の ×1.3 再校正係数を適用すると (4110×1.3≈5343s)、既に検証済みの 5400s のオーバーライド内に収まる。そのため今回のパスは、新たな値を再導出するのではなく `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を 2600→5400 に**引き上げる**。透明性のため反証も記録する: 同日、Issue #1214 (PR #1216) は新しい 5400s の設定でちょうど `watchdog_kill` に達したが、その即時リトライは 1250s (5400s の 23.1%) で完了した — これは真に時間を要したためというより stuck/hang による kill と整合する (Icebox #596 の timeout-inflation-vs-stuck-detection のトレードオフ)。そのためこの単一データポイントはさらなる引き上げの根拠とは扱わない。`tests/watchdog-defaults.bats` には、既存の `code`-phase テストを模した新しい `review`-phase の `5400` デフォルトを検証する `@test` が追加される。同じ #903 のレポートは、#878/#903 で提起された 2 つの候補についての **prompt slimming** 評価も記録している: `/auto` の L3 auto-retrospective 「notable judgment」ステップ (純粋に機械的な決定のためにセッション全体の `events.jsonl` を注入していた — #913 で生の dump を `jq -sc` によるイベント件数集計に置き換えることで対応)、および `/issue`/`/review` の L/XL 並列調査サブエージェント入力 (全 diff/ファイル内容 — スコープ/リスク/バグ検出の精度に対して切り詰めのリスクがトークン節約を上回るため slimming は推奨されない)。
- **code/spec 側の auto-retry (silent no-op)**: `auto-retry-on-fail.enabled: true` かつ `autonomy: L2/L3` の場合、`run-code.sh` と `run-spec.sh` (#1369) はそれぞれ `reconcile-phase-state.sh` から `matches_expected: false` (silent no-op) を検出した後、内部で自動的にリトライする。最大リトライ回数は `auto-retry-on-fail.max_iterations` から取得する (レガシーな `threshold` キーも受け付ける。デフォルト: 3)。リトライカウンタ (`CODE_RETRY_COUNT` / `SPEC_RETRY_COUNT`) は `exec` ベースの再起動をまたいでエクスポートされた環境変数として渡される。`skills/verify/SKILL.md` Step 11(b) の verify 側 auto-retry と対称的である (同じ tier ゲート: L2/L3 + `AUTO_RETRY_ENABLED=true` + カウント < 最大)。ただし verify 側のゲートは、documented-deferral のエスケープハッチ (#947) が先行する点が異なる: FAIL が意図的で既にドキュメント化された延期であると検出された場合 (`deferral=true` マーカー属性、または Spec の retrospective/Phase Handoff セクション経由)、tier/config/count に関わらず tier ゲートは無条件にスキップされる。組み込みリトライがアクティブな場合、二重リトライを防ぐため `apply-fallback.sh` の `code-patch-silent-no-op` Tier 2 ハンドラは抑制される (spec フェーズには Tier 2 ハンドラが一切存在しない — `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` の Phase Scope Decision 参照)。`exec` ベースのリトライ再起動の直前に、preflight ステップが (`docs/sessions/**` を除く) `git stash push --include-untracked` を実行し、silent no-op 自体が残した親 main の未追跡ファイルをスタッシュする。これにより、リトライパスでの `check-verify-dirty.sh` の再チェックが、前回の試行自体の意図しない出力によってブロックされないようにする (#886)。同じく `exec` の直前に、wrapper はリトライの発火を `docs/reports/orchestration-recoveries.md` に記録する (`modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` 参照) — これは `exec` がリトライされたプロセスに、それが従った失敗についての記憶を一切残さないため、`wrapper-retry-on-kill` 自身の記録との非対称性を解消するものである (#1320、#1369 で `run-spec.sh` にも拡張)。特に `code-pr` フェーズについては、上記のリトライ適格性チェックに入る前に、`run-code.sh` はまず `reconcile-phase-state.sh` の出力が `worktree_commits_found:true` を持つかどうかをチェックする — これは worktree ブランチが既にコミット済み (未プッシュ) の実装作業を持つことを意味する。そうであれば `/code` をゼロから再実行して既存の作業を破棄する代わりに、exec リトライは無条件にスキップされ、wrapper は直ちに `EXIT_CODE=1` で終了し、Tier 1/2/3 リカバリに委ねる (#1391、#1224 の `code-pr-tier3-recovery` 再発を受けて)。
- **コストのかかる/不可逆的な Implementation Step のマーキング (#951)**: `/spec` はコストのかかる (実費/トークン消費を伴う) または不可逆的な (本番環境への副作用を伴う) Implementation Step を非対話的に事前承認し、`/code` (これも非対話的で `AskUserQuestion` なし) は構造化された記録なしに独立してそれを再検討し延期していた — これは 2 回発生した (**#903**: Spec で事前承認された新しいベンチマーク実行を、`/code` がコストを理由に拒否。**#939**: Spec で事前承認された新しい `--fable` 実行を、`/code` がコスト/副作用/認可の理由で延期)。いずれの場合も、そのステップが実行されたかのように受入基準が書かれたままになっていた。**採用: (a) `spec-approval-needed` マーカー + (c) 必須の Deferral Protocol 記法** (`modules/costly-step-protocol.md`) — `/spec` はコストのかかる/不可逆的なステップにマーカーを付け、延期された場合に `/code` が代わりに何をすべきかを記録する。`/code` はマーカーを検出し、非対話モードでは、独立して再決定するのではなく High-Stakes Decision (`modules/ambiguity-detector.md` の skip tier) として扱う。**却下: (b) `/code` から親セッションへの対話的フォールバック** — `/code` の非対話実行 (`run-code.sh`) には保証されたライブの対話的な親が存在しない (`/auto --batch`、スケジュール実行は通常の unattended ケースである) ため、「親セッションにフォールバックする」新しいチャネルはこの前提と矛盾する。既存の Three-Tier Policy の skip tier が、この種の問題形状を新しいメカニズムなしに既にカバーしている。これは **#947** (`/verify` の documented-deferral エスケープハッチ、Step 11(b)) の生産側の対応物である: #947 は既に発生した延期を `/verify` 時にリアクティブに検出し、#951 は `/spec`/`/code` 時にその曖昧さをプロアクティブに防止する。両者は同じ `## Code Retrospective` > `### Deviations from Design` の記録を共有するため、#947 の検出ロジックには変更が不要であった。
- **`recoveries-auto-fire` のデフォルト opt-out (#1179)**: `recoveries-auto-fire` は、このリポジトリ自身の `.wholework.yml` のオプトイン (`enabled: true`) から、配布時のデフォルト (`enabled: false`、`modules/detect-config-markers.md` 参照) に撤回された。2026-08-05 の測定で `retro/verify` Issue が open Issue の 81% (67/83) を占め、`orchestration-recoveries.md` エントリの 58% が `parent-session-manual-recovery` (このリポジトリの実装では修正できない、上流の未解決な `anthropics/claude-code` issue に起因する外部 kill 後の日常的な再実行) であることが判明した (`docs/reports/external-kill-investigation.md`)。閾値の引き上げ (3→8) は同じ失敗ペースの下で元に戻るため非構造的として却下され、#1123 の group-key 細分化の撤回は `#1181` の `--cause`/`--diagnosis` フローにとって独立した価値があるため却下された。`/verify` Step 15 の auto-fire 分岐ロジックは変更なし — 撤回されたのはこのリポジトリのオプトインのみである。頻度の可視性は維持されている: `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1` を実行するか、`/audit stats --retention` (Section 10: Recovery Candidate Frequency) を使ってグループキーごとの発生回数を確認できる。
- **Sonnet 5 effort 再校正 — code/review (#921, C2)**: Sonnet 5 の広がった effort カーブのもとで `run-code.sh`/`run-review.sh` の effort を `high` から `medium` に下げられるかを再評価した (impact strategy report §3.3/§4.2)。**判定: 両方とも `high` を維持** (フル分析: `docs/reports/sonnet-5-effort-recalibration-code-review.md`)。`run-code.sh`: impact report は `medium` の候補を XS/S patch 経路の Issue のみにスコープしていたが (§4.2)、`--effort` フラグは Issue サイズによる条件分岐のない単一のグローバル設定であり、#229 の rework-risk の根拠 (14 ステップの推論チェーン、サブエージェントの扇状展開なし) はモデル切り替えによって変わらない。`run-review.sh`: オーケストレーターは dispatch を超えた実質的な推論作業を行う — Steps 7.2/7.4/7.6 は外部レビューフィードバックを解釈し fix コミットを作成する。これは `run-code.sh` 自身の実装推論と種類として比較可能な作業であり、impact report の「機械的」というフレーミングと矛盾する。さらに `review-bug`/`review-spec` (Opus) はオーケストレーターセッションから effort を継承する (Claude Code CLI のチェンジログで確認済み: サブエージェントは、agent レベルの `effort:` frontmatter オーバーライド (`agents/review-bug.md`/`review-spec.md` は現在これを設定していない) がない限り、セッションの extended-thinking/effort 設定を継承する) ため、ダウングレードはそれらの精度に重要な推論深度も静かに低下させることになる。両方の判定は、Sonnet 5 のレンズの下で `docs/reports/sonnet-effort-recalibration.md` (#229、2026-04-18、Sonnet 4.6 baseline) を再確認するものである。**フォローアップ (#1063 で実装済み)**: `effort: high` の frontmatter は `agents/review-bug.md`/`review-spec.md` (および上記表に挙げた他の Opus/Sonnet サブエージェント) に既に追加されており、それらの effort をオーケストレーターの設定から切り離している — 現在の状態は上記の表の行を参照。
- **Sonnet 5 effort 再校正 — spec (#922, C3)**: Sonnet 5 の広がった effort カーブのもとで `run-spec.sh` の Sonnet 経路のデフォルト effort を `max` から `xhigh` に下げられるかを、既存の Opus フォールバック (`--opus`、L サイズのみ、#217 以来デフォルト `xhigh`) との比較を含めて再評価した (impact strategy report §3.3/§4.2)。**判定: Sonnet デフォルト経路について `max` を維持** (フル分析: `docs/reports/sonnet-5-effort-recalibration-spec.md`)。#921 (C2) と異なり、この Sonnet 経路のデフォルトはこれまで一度も評価されたことがない (#217 は Opus に `xhigh` を導入した際に Sonnet 経路を明示的にスコープ外とし、#229 は `run-spec.sh` を Sonnet-ladder 再校正から明示的に除外していた)。`/spec` は `run-code.sh` と構造的に類似している — サブエージェントの扇状展開のない、単一の途切れない 19 ステップの推論チェーン — しかし下流の波及範囲は厳密により大きい。spec のエラーは code、review、*さらに* merge (code フェーズのエラーより 1 フェーズ多い) を通じて伝播するためである。この表に記録されている唯一の diminishing-returns ガイダンス (上記の「Opus 4.8 effort calibration」注記) は Opus 4.8 に明示的にスコープされたものであり、Sonnet 5 には該当しない — impact report §3.3 の Sonnet-5 固有の主張 (`medium` がより競争力を持つ、`xhigh` が Opus に近づく) 自体は、Sonnet 5 自身の `max` が `xhigh` に対して過剰供給であるとは主張していない。#914 (Sonnet 5 がデフォルト親になって) 以降にコーディングされた Issue にわたる本番サンプルチェックでは、Code Retrospective に設計推論に起因するギャップは見つからなかった (記録されたギャップはすべて環境/ランタイム固有のもの — 例: #917 のセキュリティ classifier との相互作用、#930 の macOS シンボリックリンクパスの不一致) — これはダウングレードを確認も否定もしない net-neutral な証拠である。Opus フォールバックの `xhigh` デフォルトは、移転可能な証拠としては扱わない。これは Opus 4.8 自身の (別個の) より狭い、L サイズ限定の effort calibration ガイダンスを反映しているためである。`run-spec.sh`、このマトリクス表、`tests/run-spec.bats` への変更なし。
- **Sonnet 5 effort 再校正 — issue (#923, C4)**: Sonnet 5 の広がった effort カーブのもとで `run-issue.sh` の effort を `high` から `medium` に下げられるかを再評価した (impact strategy report §3.3/§4.2)。impact report は issue フェーズを「実装ではなくスコープ分析」と位置づけ、4 つの候補の中で最も優先度が低いとしていた。**判定: `high` を維持** (フル分析: `docs/reports/sonnet-5-effort-recalibration-issue.md`)。`run-issue.sh` は `phase/*` ラベルがない Issue に対して `/auto` からのみ呼び出され、常に非対話的に動作する。常に数値の Issue 番号を渡すため、常に `skills/issue/SKILL.md` の「Existing Issue Refinement」フローを実行する。これは単一エージェントによる 15 ステップの推論チェーンであり、唯一のサブエージェントの扇状展開 (Step 12 の L/XL `issue-scope`/`issue-risk`/`issue-precedent` Opus サブエージェント) は非対話モードでは Issue サイズに関わらず無条件にスキップされる (「sub-issue splitting is a High-Stakes Decision」)。これは、`#229` の当初の `high` の根拠と、この表の行自身の Rationale テキスト (「L/XL scope analysis and sub-issue splitting require thorough orchestration」) の両方が、`run-issue.sh` が実際には決して到達しないコードパスを記述していることを意味する — `#921` が `run-review.sh` の「機械的」というフレーミングについて見出したのと同種の不正確さである。修正された根拠: Existing Issue Refinement は、パイプラインの最も上流の成果物 (エラーが下流の全フェーズ — spec、code、review、merge、verify — に伝播する) を生成するための実質的な判断作業 (曖昧性の自動解決、受入基準/verify-command の作成、背景のファクトチェック) を行う。Sonnet-5-as-default のもとでコーディングされた 9 件の Issue (#915〜#932) にわたる本番サンプルチェックでは、issue フェーズに起因する設計ギャップは見つからなかった (継続的に十分な性能であることと整合する net-neutral な結果)。`run-issue.sh`、このマトリクス表、`tests/run-issue.bats` への変更なし (`--effort` のアサーションが存在しないことを確認済み)。
- **Opus 5 effort 再校正 — `run-spec.sh --opus` (#1064)**: `run-spec.sh` の Opus フォールバック経路 (`--opus`、Size L Issue のみ、#217 で Opus 4.8 のガイダンスのもとデフォルト `xhigh` に設定) が、Opus 5 のガイダンスの変化 (上記の **Opus 5 effort calibration** 注記を参照: コーディング/エージェンティックなタスクは `xhigh` から始め、そこから下方向に調整する。`low`/`medium` は想定より強力だと報告されているため) のもとで依然として適切に校正されているかを再評価した。これは `#922` (C3、Sonnet デフォルト経路を評価し、Opus フォールバックを移転不可能な証拠として明示的にスコープ外とした) の対称的な対応物である。**判定: `xhigh` を維持** (フル分析: `docs/reports/opus-5-effort-recalibration-spec.md`)。`#922` — 記録されている唯一の diminishing-returns ガイダンスが Opus 4.8 にスコープされ Sonnet 5 に移転しなかった — とは異なり、Opus 5 の下方調整ガイダンスはこの経路に実際に該当する。実際に Opus 5 上で動作するためである。しかしこのガイダンスは探索的なもの (「調整してチェックせよ」) であり、特定の下位ティアが既にこのワークロードで `xhigh` に匹敵するという主張ではない。また `--opus` は Size L の Issue のみにスコープされている — 構造上、複雑度が最も高いサブセットであり、推論要求が Sonnet デフォルト経路を超えるために意図的に Opus にルーティングされている。`/spec` の構造的リスクプロファイル (`#922` の Analysis 2: サブエージェントの扇状展開のない単一の 19 ステップ推論チェーンで、エラーが code、review、merge に伝播する) は skill の性質であり、モデルの性質ではなく、ここでも変わらず当てはまる。ダウングレードを責任を持って検証するために必要なテレメトリはまだ存在しない: `#1228` は spec フェーズの `token_usage` 発行のブロックを解除したが、`.tmp/auto-events.jsonl` にはこのレポート時点で `--opus` のサンプルがゼロである。wall-clock proxy (Opus 5 世代の 9 実行平均 16:22 対 Opus 4.8 世代の 5 実行平均 13:22、+22%、同じ `xhigh` effort) は存在するが、並行セッション負荷により交絡しており、いずれの方向にも余地を示していない。証拠なしに方向性のガイダンスだけに基づいて行動することは、パイプラインの中で最も波及範囲の大きい単一フェーズに対しては、デフォルト変更の根拠として不十分と判断する。別途、`--max` の明示的オーバーライドフラグの位置づけは**再確認**される: Opus 5 の「極めて難しく、レイテンシに寛容なタスクにのみ」という狭いフレーミングは、少なくとも Opus 4.8 の曖昧なフレーミングと同程度に、このフラグの既存のオプトイン・呼び出しごとの・人間/オペレーター判断によるエスカレーションのセマンティクスに適合する。`run-spec.sh`、このマトリクス表、`tests/run-spec.bats` への変更なし。**再評価トリガー**: 実際の `--opus` テレメトリサンプルが本番サンプルチェックに十分な量蓄積された時点で再検討する — Spec の最終的な記録済み Size ではなく、`sub_start` イベントの dispatch 時点の `size=L` フィールドから Opus 生成のサブセットを抽出すること。`/spec` 内での Size 昇格 (M→L) は Opus/Sonnet の dispatch 決定の後に発生しうるためである (実例: `#1175`)。

## Wholework ラベル管理

`scripts/setup-labels.sh` は、Wholework が管理する全ラベルの **単一の真実の源泉 (SSoT)** である。すべてのラベル名・色・説明はここで定義される — 唯一の例外は `theme/*` ラベルで、プロジェクト依存であり各プロジェクト自身の `.wholework.yml` の `themes:` キー (`docs/guide/customization.md` 参照) で定義され、`setup-labels.sh` にはハードコードされない。`setup-labels.sh` は固定色 (`006B75`) とパース/作成ロジックのみを提供する。

### ラベルグループ

| Group | Count | Labels | Creation condition |
|-------|-------|--------|-------------------|
| Always | 17 | `phase/*` (9)、`triaged`、`retro/verify`、`retro/code`、`retro/recoveries`、`audit/drift`、`audit/fragility`、`audit/auto`、`stale-verify` | 常に作成 |
| Theme | プロジェクト依存 | `theme/*` | `.wholework.yml` の `themes:` ブロックマッピングから作成 (`docs/guide/customization.md`)。未設定の場合は何も作成されない — デフォルト/フォールバックカタログはない |
| Fallback | 17 | `type/*` (3)、`priority/*` (4)、`size/*` (5)、`value/*` (5) | 対応する GitHub 機能が利用できない場合に作成 (下記参照) |

### 自動ブートストラップ

`scripts/gh-label-transition.sh` は、`phase/*` ラベル遷移が最初に試みられ、対象ラベルがリポジトリに存在しない場合に `setup-labels.sh` を自動実行する。これにより、Plugin install ユーザー (リポジトリの clone なし) は `setup-labels.sh` を手動で実行する必要がない — 最初の skill 実行時に自動的に呼び出される。

### フォールバックラベルの検出条件

Fallback ラベルは、対応する GitHub 機能が利用できない場合に作成される。検出条件は `setup-labels.sh` 内のインラインコメントとしても記載されている:

| Fallback group | Detection function | Feature checked |
|----------------|-------------------|-----------------|
| `type/*` | `detect_issue_types()` | GitHub Issue Types (`issueTypes` API) |
| `priority/*` | `detect_projects_field("Priority")` | Projects V2 Priority field |
| `size/*` | `detect_projects_field("Size")` | Projects V2 Size field |
| `value/*` | `detect_projects_field("Value")` | Projects V2 Value field |

検出失敗 (API エラー、権限問題) は「利用不可」として扱われる — ワークフローが進行できるよう fallback ラベルが作成される。

### 変更ルール

Wholework 内 (skills、scripts、modules) のどこかでラベルを追加・変更・削除する場合、同じ PR で `scripts/setup-labels.sh` **も**必ず更新すること:

- **ラベル参照の追加** (`gh label create`、`--add-label`、`grep 'label-name'` など): 検出条件のコメントとともに `ALWAYS_LABELS` または `FALLBACK_LABELS` にラベルを追加する。
- **ラベル名や色の変更**: `setup-labels.sh` のエントリを更新する。
- **ラベル参照の削除**: `setup-labels.sh` のエントリを削除する。

このルールは、コード内のラベル参照と SSoT 定義との間の drift を防ぐ。将来の `/audit drift` 検出は、コードベース内のラベル参照の集合と `setup-labels.sh` で定義された集合を比較し、不整合をフラグする予定である。

**例外**: `theme/*` ラベルはこのルールの対象外である — プロジェクト依存であり、`setup-labels.sh` にハードコードされる代わりに、各プロジェクトの `.wholework.yml` の `themes:` キー (`docs/guide/customization.md` 参照) でプロジェクトごとに宣言される。`theme/*` ラベルの追加・リネーム・削除は、該当プロジェクトの `.wholework.yml` を編集するだけでよい。

## テスト戦略

| Tool | Purpose | When |
|------|---------|------|
| **bats** (Bash Automated Testing System) | シェルスクリプトの単体テスト | マージ前 (`command` verify command 経由)、および CI (`.github/workflows/test.yml`) |
| **validate-skill-syntax.py** | SKILL.md 構文検証 (半角 `!` 検出、frontmatter 検証) | マージ前 |
| **Verify commands** (`<!-- verify: ... -->`) | 受入基準の機械的検証 (ファイル存在、テキスト内容、コマンド実行) | `/verify` skill 実行時 |

### CI bats の並列/逐次分割 (`.github/workflows/test.yml`)

CI は速度のため bats スイート全体を並列 (`bats --jobs $(nproc) tests/`) で実行する。一部のテストは並列実行時のみ flaky である — #1221 / #1224 / #1227 / #1260 で独立して観測されており、主に `tests/post_merge_check.bats` である。この並列実行時のみの flakiness を genuine な失敗と区別するため、並列ステップは `continue-on-error: true` で実行され、その結果が `failure` になった場合は常に、失敗したテストのみを逐次で再実行するフォローアップステップ (`bats --filter-status failed tests/`) が実行され、その出力は `$GITHUB_STEP_SUMMARY` に追記される:

| Parallel run | Serial re-run | Job result | Meaning |
|---|---|---|---|
| PASS | (実行なし) | Success | 通常 |
| FAIL | PASS | Success | 並列実行時のみの flaky — 再実行結果は `$GITHUB_STEP_SUMMARY` に記録 |
| FAIL | FAIL | Failure | Genuine な失敗 |

並列ステップの `continue-on-error: true` は、その結果が直接ジョブを失敗させないようにする。genuine な失敗は代わりに逐次再実行ステップの非ゼロ終了によって顕在化する。したがって、CI ジョブが green であっても並列実行時のみの flakiness に当たっている可能性がある — `$GITHUB_STEP_SUMMARY` に "Serial re-run" セクションがあるか確認して判断すること。

### BATS モッキング規約

`scripts/` 配下のスクリプトは、`WHOLEWORK_SCRIPT_DIR` 環境変数でオーバーライド可能な
`SCRIPT_DIR` 経由で兄弟ヘルパーを解決する。BATS テストは
`export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定し、モックヘルパー (例:
`$MOCK_DIR/gh-graphql.sh`) をモックディレクトリ配下に配置する。これにより、
より低レベルのツール (`gh api graphql` など) をモックすることなく、
任意の兄弟スクリプトをテストごとに差し替えられる。

## 禁止表現

| Expression | Reason | Alternative |
|------------|--------|-------------|
| 半角 `!` (SKILL.md 本文中、コードフェンスとインラインコード外) | Claude Code の Bash permission checker がこれを zsh の history expansion と誤検知し、skill 実行時にエラーを起こす | 全角「！」または言い換え |
| Acceptance check | 用語の再設計 (「verify command」に変更) | "verify command" |
| Issue 作成時の `triaged` ラベル割り当て (`gh issue create --label` または `gh issue edit --add-label`) | `triaged` は triage が実際に実行されたことを示すマーカーである。事前に割り当てると `triage-backlog-filter.sh` がその Issue をスキップし、Type/Size/Priority/Value が未設定のままになる | Issue 作成時は `triaged` を省略する。triage skill が `/triage` 実行後に割り当てる |

**Deprecated terms**: 上記の表に列挙された表現に加え、`docs/product.md` § Terms で 'Formerly called' とマークされている用語はいずれも、新しいコンテンツ (コードコメント、ドキュメント、コミットメッセージ、Spec ファイルなど) で使用してはならない。現在のリストは `docs/product.md` § Terms を参照。新しい非推奨用語が生じた場合は、`docs/product.md` § Terms に 'Formerly called' エントリを追加すること — この表の更新は不要である。

**Spec Retrospective: 非推奨用語の引用について**
Spec retrospective セクション (`## Code Retrospective`、`## Spec Retrospective` など) で非推奨用語を引用する際は、その特定の非推奨文字列を直接記述することを避ける。`docs/spec/` 配下の Spec ファイルは CI スキャン (`scripts/check-forbidden-expressions.sh` の `SCAN_DIRS`) に含まれるため、直接引用するとスキャン失敗を引き起こす。代わりに以下のいずれかを使用すること:
- **記述的な表現**: 用語自体を引用せずに記述する (例: 用語そのものの代わりに「N 個の非推奨用語」)
- **`旧称:` 接頭辞**: `旧称: <term>` と書く (例: `旧称: verify hint`) — CI の除外フィルタは `旧称` を含む行をスキップする

## Config Schema Validation

`scripts/check-config-schema.sh` は、`.wholework.yml` のトップレベルキーが `modules/detect-config-markers.md` の Marker Definition Table (既知キーの SSoT) に見つからない場合に警告する — これにより、警告なしに既定値へ静かにフォールバックしてしまう typo (例: `autonomy:` を `autonomy-tier:` と誤記) を検出できる。

**検証タイミング**: CI 上で、`.github/workflows/test.yml` の `check-config-schema` ジョブが push/PR ごとに実行する (`check-forbidden-expressions.sh`/`check-bare-bracket-assertions.sh` と同じパターン)。

**検証スコープ**: トップレベルキーのみ。ネストされた子キー (例: `capabilities.browser`) は範囲外。

**警告メッセージの形式**: `Unknown key '<key>' in <config-file> (not found in modules/detect-config-markers.md's Marker Definition Table). Check for a typo, or add it to the table if intentional.` 1件以上検出した場合、スクリプトは非ゼロで終了する。

## 用語移行スコープルール

非推奨用語を Terms の 'Formerly called' に追加する Issue (段階的な用語移行) を作成する際は、同じファイル内の非推奨用語の置き換えがスコープに含まれるかどうかを明示すること。

### スコープ宣言テンプレート

Issue 本文の「Scope」または「Acceptance Criteria」セクションに以下のいずれかを含めること:

```
[Same-file deprecated term replacement] included / not included (handled in follow-up Issue #N)
```

### 理由

段階的な移行では、非推奨用語を Forbidden Expressions に追加した後も、同じファイル内に非推奨用語が残る期間がある。この期間中、レビュアー (Copilot など) が Forbidden Expressions と本文テキストの矛盾をフラグすることがあり、段階的移行のポリシーと衝突する。明示的なスコープ宣言により、誤ったレビューコメントを防ぐ。

### 適用範囲

- Forbidden Expressions への非推奨用語の追加を含むすべての Issue に適用される
- 「not included」の場合は、フォローアップ Issue で非推奨用語の置き換えを扱い、その Issue 番号を参照すること

## 環境変数

| Variable | Default | Description |
|----------|---------|-------------|
| `WHOLEWORK_CI_TIMEOUT_SEC` | `1200` | `wait-ci-checks.sh` の最大待機秒数。タイムアウト挙動をテストするには低い値 (例: `60`) に設定する。 |
| `WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC` | `120` | `gh pr checks` が登録済みチェック 0 件を報告している間、`wait-ci-checks.sh` がポーリングを続ける猶予期間 (秒)。猶予期間が経過してもまだ 0 件の場合、スクリプトは明示的な警告を発して待機を停止する。テストでは猶予期間をスキップするため `0` に設定する。 |
| `WHOLEWORK_SCRIPT_DIR` | *(自動解決)* | `scripts/*.sh` が兄弟ヘルパーを解決する際に使用する `SCRIPT_DIR` を上書きする。BATS テストで呼び出しをモックディレクトリにリダイレクトするために使用される。本番では未設定のままにすること (自動的にスクリプト自身のディレクトリに解決される)。 |
| `WHOLEWORK_CONFIG_PATH` | *(未設定)* | `scripts/get-config-value.sh` が使用する設定ファイルパスを上書きする。設定されている場合、スクリプトは CWD 相対の `.wholework.yml` の代わりに指定されたパスを読む。BATS テストではデフォルト値を強制するため `/dev/null` に設定する。未設定または空の場合は `.wholework.yml` (CWD 相対) にフォールバックする。 |
| `WHOLEWORK_ISSUE_BODY_DIR` | *(未設定)* | `scripts/get-auto-session-report.sh` が verify-type breakdown を取得する際に使用する issue body のソースを上書きする。設定されている場合、`gh issue view` を呼び出す代わりに `${WHOLEWORK_ISSUE_BODY_DIR}/<issue_number>.md` を読む。ヘルメティックな実行のため BATS テストで使用される。未設定または空の場合は `gh issue view` にフォールバックする (`--no-github` の場合はスキップ)。 |
| `WHOLEWORK_MAX_RECOVERY_SUBAGENTS` | `1` | `scripts/spawn-recovery-subagent.sh` が起動する Tier 3 復旧サブエージェントの最大同時実行数。XL 並列実行中のコストを抑えるためデフォルトは 1 (逐次復旧)。 |
| `WHOLEWORK_PATCH_LOCK_TIMEOUT` | `300` | `scripts/worktree-merge-push.sh` の patch lock のタイムアウト秒数。優先順位: 環境変数 > `.wholework.yml` の `patch-lock-timeout` > 300。 |
| `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` | `30` | `scripts/worktree-merge-push.sh` が patch lock を待機中のログ出力間隔秒数。 |
| `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` | `300` | `scripts/retry-on-kill.sh` の early-kill ウィンドウ秒数。run-*.sh wrapper がこのウィンドウ内に exit 137 または 143 で終了した場合、自動的に 1 回リトライする。late-kill (no-retry) 分岐を強制するテストでは `0` に設定する。watchdog のハング kill が自動リトライされないよう、最小の `WATCHDOG_TIMEOUT` (merge フェーズの 600s) より厳密に小さく保つ必要がある。 |
| `WHOLEWORK_SPAWN_DETACH` | *(未設定)* | 実験的なオプトイン (issue #1142): `1` に設定すると、`scripts/run-auto-sub.sh` は python3 の `start_new_session=True` シム (macOS には setsid(1) バイナリがないため) を経由して、新しいセッション/プロセスグループのリーダーとして自身を再実行する。これにより、起動元のグループを狙ったプロセスグループ全体への外部 SIGKILL が wrapper のサブツリーを道連れにできなくなる。detach する前に、シムは pre-detach の PGID ポインタから `AUTO_SESSION_ID` を解決し、発行されるイベントがその session_id を保持するようにする。内部の `_WHOLEWORK_DETACHED=1` 変数は再実行された子をマークする (再帰ガード — 手動で設定してはならない)。デフォルト (未設定) では spawn の挙動は完全に変わらない。この値は `.tmp/auto-events.jsonl` の `phase_start` イベントの `spawn_detach` フィールドとして記録される (Issue #1387)。背景: `docs/reports/external-kill-investigation.md` (H-a vs H-b' の裁定)。 |
| `WHOLEWORK_YML` | `${CLAUDE_PROJECT_DIR:-}/.wholework.yml` | `scripts/hook-rename-on-auto.sh` が解決する `.wholework.yml` のパス。`CLAUDE_PROJECT_DIR` から導出される。operator-override パターンではない (スクリプトは `${WHOLEWORK_YML:-...}` を使う代わりに直接代入する)。 |
| `WHOLEWORK_PREVIEW_TIMEOUT_SEC` | `600` | `scripts/run-review.sh` の PR preview デプロイポーリング (`capabilities.pr-preview: true` のプロジェクトのみ) の最大待機秒数。両方の分岐で共有される上限: `PREVIEW_URL` が未設定の場合の GitHub Deployments API ポーリング (PR ブランチの最新デプロイの `state` をチェック)、および `PREVIEW_URL` fast path の HTTP 到達性ポーリング (設定時)。いずれもタイムアウト内に準備完了を確認できない場合、`run-review.sh` は review セッションを起動せずに `PENDING` (exit code 2) で終了する。 |
| `WHOLEWORK_REVIEW_PENDING_RETRY_SEC` | `300` | `run-review.sh` が `PENDING` (exit code 2) で終了した後、review フェーズをリトライするまでのスリープ秒数。`scripts/run-auto-sub.sh` の `run_phase_with_recovery()` と `skills/auto/SKILL.md` の pr 経路 item 8 で消費される。`modules/orchestration-fallbacks.md#review-pending-not-failure` 参照。 |
| `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES` | `2` | `run-review.sh` が `PENDING` (exit code 2) で終了した後、通常の Tier 1/2/3 リカバリパスにフォールスルーするまでの、上限付きリトライの最大回数。`WHOLEWORK_REVIEW_PENDING_RETRY_SEC` と同じ消費者。 |
| `WHOLEWORK_CI_OUTAGE_RECHECK_SEC` | `600` | `modules/ci-failure-classifier.md` からの `ci-infra` 判定を再判断するまでの待機秒数。`skills/auto/SKILL.md` Step 6 の CI プラットフォーム障害事前チェックで消費される。 |
| `WHOLEWORK_CI_OUTAGE_MAX_RECHECKS` | `2` | `skills/auto/SKILL.md` Step 6 の CI プラットフォーム障害事前チェックが Tier 1/2/3 に入る代わりに停止するまでの、`ci-infra` 判定の最大再判断回数。`WHOLEWORK_CI_OUTAGE_RECHECK_SEC` と同じ消費者。 |

### Capability フラグ

以下の変数は `detect-config-markers.md` が `.wholework.yml` の `capabilities.*` キーから設定する。組み込みの capability は下記の固定マッピングを使用する。ユーザー定義の `capabilities.{name}: true` キーは、動的に `HAS_{UPPERCASE_NAME}_CAPABILITY` にマッピングされる。

| Variable | Set when | Description |
|----------|---------|-------------|
| `HAS_BROWSER_CAPABILITY` | `capabilities.browser: true` | ブラウザ自動化 capability が有効な場合 `true`。ブラウザベースの verify パターン (例: `verify/browser-verify-phase.md`) を条件付きで読み込むために使用される。 |
| `HAS_VISUAL_DIFF_CAPABILITY` | `capabilities.visual-diff: true` | visual diffing capability が有効な場合 `true`。visual diff モジュール (例: `modules/visual-diff-adapter.md`) を条件付きで読み込むために使用される。 |
| `HAS_WORKFLOW_CAPABILITY` | `capabilities.workflow: true` | Workflow tool が利用可能な場合 `true`。`/review` でのマルチエージェント並列レビューを条件付きで有効化するために使用される。 |
| `HAS_PR_PREVIEW_CAPABILITY` | `capabilities.pr-preview: true` | プロジェクトの PR が preview URL を生成する場合 `true`。`/issue` Step 4 の pre-merge-preview AC 分類をゲートする: preview 環境に対してのみ確認できる AC は、verify command の有無に関わらず、`ac-tier: preview` タグ付きで pre-merge セクションに配置される (verify command がある auto サブケースは追加で `--when="test -n \"$PREVIEW_URL\""` ガードを持ち、ない manual サブケースは追加で `verify-type: manual` タグ付きでガードなし)。両サブケースとも `/review` 時に実行/提示され、`/review` の最新の `type=preview-ac-unverified` マーカーがその AC を未検証としてリストしない限り `/verify` のマージ後ではスキップされる (`modules/l0-surfaces.md` § "Machine-Readable Event Marker" 参照)。リストされている場合、`/verify` は auto サブケースについて本番 URL チェックにフォールバックする (manual サブケースはフォールバックする verify command がないため、人間によるチェック項目として提示される)。また `/code` の pr 経路の Step 13 (Preview Build Verification) もゲートする: `true` の場合、`/code` は PR 作成後にデプロイ/preview ビルドの完了を待ち、失敗時は `/review` にフォールスルーする前に code フェーズ内から (最大 3 回まで) fix コミットをプッシュする。この capability を宣言していないプロジェクトは `/code` の従来の挙動を維持する — code フェーズは PR 作成時にビルド待機なしで完了する。また `scripts/run-review.sh` の pre-session preview デプロイ待機もゲートする: `true` かつ `PREVIEW_URL` 環境変数が既にエクスポートされている場合、`run-review.sh` は GitHub Deployments API のルックアップを完全にスキップする fast path を取り、`skills/review/SKILL.md` Step 8.0 の既存の `PREVIEW_URL` 優先順位と一致させ、さらに `PREVIEW_URL` の HTTP 到達性 (2xx、および Basic-Auth 保護された preview 用の 401/403 も到達可能とみなす) をポーリングする — この到達性チェックは `run-review.sh` にとって新しいものであり、Step 8.0 自身の契約の一部ではない。`curl` が利用できない場合、プローブはスキップされエクスポート済みの `PREVIEW_URL` がそのまま受け入れられる (fail-open)。stderr に警告が出力される。`PREVIEW_URL` が未設定で `.wholework.yml` に `preview-url-command` が宣言されている場合、`run-review.sh` はまずそのコマンドを実行し (30 秒で上限、`{pr}` プレースホルダは PR 番号に置換される)、コマンドが 0 終了かつ出力が空でなく 2048 文字以下の `http(s)://` URL であるときに限りその出力を `PREVIEW_URL` として採用する。それ以外の結果は下記の Deployments API 経路へそのままフォールバックする (#1410 参照)。`PREVIEW_URL` が未設定 (かつ `preview-url-command` が未宣言、またはその解決が失敗した) 場合、`run-review.sh` は PR ブランチの最新デプロイ状態について GitHub Deployments API をポーリングする従来の挙動にフォールバックする (変更なし、後方互換)。いずれのポーリングも `WHOLEWORK_PREVIEW_TIMEOUT_SEC` で上限が設定され、`run-review.sh` はどちらも時間内に準備完了を確認できない場合、review セッションを開始せず `PENDING` (exit code 2) で終了する。同じゲート内のブロックは、`PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` のいずれも未 export の場合、宣言された `preview-basic-auth-command` から追加でこれらを解決する。`preview-url-command` の解決契約 (30 秒で上限、`{pr}` 置換、`username:password` 形式の出力を最初の `:` で分割、それ以外の結果は両変数を未設定のまま維持) を踏襲している — 詳細は `docs/guide/customization.md` § "Automating Basic Auth credential resolution with `preview-basic-auth-command`" (#1417) を参照。 |
| `MCP_TOOLS` | `capabilities.mcp` list | プロジェクトで有効化された MCP ツール名のカンマ区切りリスト (例: `"mf_list_quotes,mf_list_invoices"`)。注: `capabilities.mcp` は直接 `MCP_TOOLS` にマッピングされる — 動的な `HAS_*_CAPABILITY` マッピングからは除外されるため、`HAS_MCP_CAPABILITY` が設定されることはない。 |

## Gotchas

### `.claude/settings.json` はホットリロードされない

`.claude/settings.json` はセッション開始時にキャッシュされ、**セッション中は再読み込みされない**。`permissions.allow` パターン (またはその他の設定) への変更は、Claude Code セッションを再起動した後にのみ有効になる。

**影響**: `settings.json` を変更した後は、新しい permission パターンが正しく機能するかテストする前に、必ずセッションを再起動すること。

**セッション内プローブによる偽陰性のリスク**: 古い設定がロードされている同じセッション内で新しい `permissions.allow` パターンをプローブで検証すると、偽陰性を生む可能性がある。プローブは更新後の設定ではなくキャッシュされた設定に基づいて成功 (または失敗) することがあり、新しいパターンが実際に機能するかどうかを覆い隠してしまう。permission 検証プローブを実行する前は必ずセッションを再起動すること。
