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

## アーキテクチャ決定

- **Skills ベースのワークフロー**: 各開発フェーズ（issue/spec/code/review/merge/verify）を独立した Claude Code Skill として実装する。処理ステップは SKILL.md に記述され、LLM がそれらを段階的に実行する
- **Plugin ディレクトリ配布**: `--plugin-dir` を使ったローカル Claude Code plugin として配布する。Claude Code は実行時に `${CLAUDE_PLUGIN_ROOT}` を plugin ディレクトリに設定し、skills/modules がこれを使って scripts や modules を参照する。公開配布は Claude Code marketplace（`.claude-plugin/marketplace.json`）経由で、ユーザーは `/plugin marketplace add saitoco/wholework` + `/plugin install wholework@saitoco-wholework` でインストールできる
- **fork コンテキスト vs main コンテキスト**: コンテキスト分離レベルはスキル単位で設定する。Fork の動機は「独立性/安全性」（1M コンテキスト GA 以降、コスト/容量の動機はほぼ消失）。各スキルの fork 判断（網羅的）:

  | スキル | Fork の要否 | 理由 |
  |-------|-------------|--------|
  | triage | 不要 | 前フェーズのバイアスを避ける必要なし、独立性も不要 |
  | issue | 必要 | L/XL の並列調査には独立性が必要、サブエージェントは分離コンテキストで実行 |
  | spec | 必要 | Issue を読みコードベースを独立調査する、前会話の影響を受けない |
  | code | 必要 | Spec を読み独立して実行する、実装前のコンテキストの影響を受けない |
  | review | 必要 | 実装フェーズのバイアスを継がず、クリーンな視点でコードをレビューする |
  | merge | 必要 | 判断は Spec + PR メタデータで完結、レビューコンテキストを持ち越さない |
  | verify | 必要 | マージ後の状態を独立検証する、前フェーズの判断に影響されてはならない |
  | auto | 不要 | 親オーケストレーターはユーザーの Claude Code セッションで実行される、各子フェーズは `run-*.sh` 経由で独立した `claude -p` プロセスとして実行 |
  | audit | 不要 | ドリフト・脆弱性検出はユーザーセッションで実行される、前フェーズのバイアスを避ける必要なし |
  | doc | 不要 | ドキュメント管理はユーザーセッションで実行される、前フェーズのバイアスを避ける必要なし |

- **`/auto` スキル**: `run-*.sh` 経由で spec→code→review→merge→verify を順次連鎖させるオーケストレーター。各フェーズは設定可能なパーミッションモード（デフォルト: `--dangerously-skip-permissions`、`.wholework.yml` に `permission-mode: auto` を設定すると `--permission-mode auto`）で `claude -p` 独立プロセスとして実行され、フレッシュなコンテキスト分離を保証する。追加機能: `phase/*` ラベル未設定時は issue triage/refinement から自動開始、`phase/ready` がない場合は `/spec` を自動実行、`--batch N` はバックログから N 個の XS/S Issue を処理、XL Issue はサブ issue 依存グラフ（`blockedBy`）を読んで独立サブ issue を並列実行（worktree 分離）し依存先は順次実行、`--base {branch}` でリリースブランチ対象
  - **2 階層オーケストレーション**: `/auto` 本体（親オーケストレーター）はユーザーの Claude Code セッションで動作し、LLM 推論を使った適応的判断を行う（ラベル状態の評価、サイズベースのルーティング、サブ issue 依存関係分析）。XL Issue については `run-auto-sub.sh`（子オーケストレーター）が各サブ issue のフルフェーズシーケンスを実行する。`run-auto-sub.sh` は `claude -p` を呼び出さない純粋な bash スクリプトで、Size に基づく決定的な if/case ルーティングを用いる。これは技術的制約ではなく意図的な設計選択である: 現行のフェーズルーティングは決定的で、各フェーズは `run-*.sh` で自己完結しているため、子オーケストレーター階層での LLM 推論はコストのみ増え利益が無い。適応的リカバリが必要になった場合（code 失敗後に spec を再実行、レビュー結果に基づく戦略調整など）、`run-auto-sub.sh` を `claude -p` オーケストレーターにアップグレードするのが前進ルート
- **`/doc` スキル**: プロジェクト基盤ドキュメント管理。Steering Documents（`product.md`、`tech.md`、`structure.md`）とプロジェクトドキュメントを管理する。主要操作: `sync`（双方向の正規化とドリフト検出、`--deep` で拡張コードベース解析）、`init`（初期セットアップウィザード）、`add` / `project`（ドキュメント登録）、`translate {lang}`（多言語翻訳生成）。`/audit` の補完として機能: `/doc sync` はドキュメント側の修正を提案し、`/audit drift` はコード側の修正を Issue 化する
- **サブエージェント分割**: 2 つのスキルで使用:
  - `/issue`（L/XL）: 3 つの独立サブエージェント（`issue-scope`、`issue-risk`、`issue-precedent`）による並列調査で、変更スコープ、リスク、前例を同時に分析する
  - `/review`: 2 グループに分割する — Spec 準拠レビュー（`review-spec`）とバグ検出（`review-bug`）。2 段階検証（検出→検証サブエージェント）で偽陽性を排除
- **共有モジュールパターン**: 複数スキルを横断する共通処理を `modules/*.md` に切り出し、"Read and follow" パターンで参照する
- **Spec ファースト（使い捨て）**: Spec はタスク完了後の成果物として保守しない。Spec-anchored および Spec-as-source アプローチは採用しない。理由: (1) LLM の非決定性により同じ spec が同じコード再生成を保証しない、(2) spec 保守コストがコード保守コストに上乗せになる
- **プログレッシブ・ディスクロージャー（Core/Domain 分離）**: SKILL.md 本文にはプロジェクト種別やツールに依存しない汎用ロジックだけを記す。特定ツール（Figma、Copilot など）やプロジェクト種別（スキル開発、IaC など）に固有のロジックは補助ファイル（`skills/{name}/xxx-phase.md`）に切り出し、該当するときだけ読み込む。判断基準: 「このツール/プロジェクト種別を使わないプロジェクトでもこのロジックが必要か？」— No なら切り出す
  - **切り出しパターン（標準）（網羅的）**:

    | パターン | 条件 | 例 |
    |---------|-----------|---------|
    | Marker 検出 | `.wholework.yml` の YAML キー | `review/external-review-phase.md`（`copilot-review: true`、`claude-code-review: true`、`coderabbit-review: true` のいずれかで読み込み） |
    | ファイル存在 | 特定ファイルの存在 | `review/skill-dev-recheck.md`（`scripts/validate-skill-syntax.py` が存在すれば読み込み） |

- **配布物ファースト改善原則**: レトロスペクティブで特定された改善は、配布物（Skills、Agents、Modules、Scripts）に反映すること。CLAUDE.md、Steering Documents、Project Documents はユーザーリポジトリ固有の成果物であり、Wholework plugin の一部として配布されない — これらのドキュメントだけに加えた改善は他の Wholework ユーザーに届かない。レトロスペクティブで改善が特定された場合、実装対象は配布レイヤーとすべきであり、配布対象外の成果物だけを更新することは不十分である
- **Effort 最適化戦略（3 軸）**: `claude -p` 呼び出しで実行コストと品質を制御する 3 軸。軸ごとの CLI サポート状況と Wholework の採用方針:
  - **軸 1 — モデル選択**（`--model`）: 実装済み。Sonnet をデフォルトとし、L サイズの spec では `run-spec.sh --opus` で Opus に切替。レビュー・確認済み
  - **軸 2 — Adaptive Thinking**（`--effort`）: `claude -p` は `low/medium/high/max` レベルをサポート（`claude --help` で確認済み）。`run-*.sh` でフェーズごとの effort レベルを実装済み（下記マトリクス参照）。medium effort と Opus advisor を組み合わせると、Sonnet のデフォルト effort 相当の品質をより低コストで達成（Anthropic ベンチマーク準拠）
  - **軸 3 — Advisor 戦略**（`advisor_20260301`）: Anthropic API ベータ機能（`advisor-tool-2026-03-01` ヘッダが必要）。`--betas` フラグで有効化 — API キー利用者のみ、OAuth/サブスクリプション認証（`run-*.sh` のデフォルト）では利用不可。性能向上: Sonnet + Opus advisor で SWE-bench +2.7 pp、コスト −11.9%（Sonnet 単独比）、Haiku + Opus advisor で BrowseComp 41.2%（単独 19.7%）、コスト −85%（Sonnet 比）。`run-*.sh` 実装はフォローアップ Issue

### フェーズ別モデル・effort マトリクス

(`ssot_for: model-effort-matrix`)

エントリはワークフロー順（triage → issue → spec → code → review → merge → verify）でグループ化: まずオーケストレーションスクリプト、次にフェーズ別のサブエージェント、最後に skill のみのエントリ。

| コンポーネント | フェーズ | モデル | Effort | 根拠 |
|-----------|-------|-------|--------|-----------|
| run-issue.sh | issue | Sonnet | high | L/XL のスコープ分析とサブ issue 分割には徹底したオーケストレーションが必要 |
| run-spec.sh | spec | Sonnet（L では `--opus` で Opus） | max | 設計品質が重要、spec のエラーは後続全フェーズに波及する。`/auto` は L サイズのみ `--opus` を渡す（XL は spec 前に分割済み） |
| run-code.sh | code | Sonnet | high | 実装には徹底した推論が必要 |
| run-review.sh | review | Sonnet | high | レビューのオーケストレーション、深い分析はサブエージェントが担う |
| run-merge.sh | merge | Sonnet | low | 機械的なマージ操作、推論は最小限でよい |
| run-verify.sh | verify | Sonnet | medium | 構造化された受入テスト、中程度の複雑度 |
| issue-scope | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査向けに呼び出される。スコープ特定精度はサブ issue 境界判断に直結 |
| issue-risk | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査向けに呼び出される。リスク評価精度が受入条件品質を高める |
| issue-precedent | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査向けに呼び出される。前例抽出が受入条件品質を高める |
| review-bug | review | Opus | — | バグ検出は最高精度が必要（サブエージェント、effort は親から継承） |
| review-spec | review | Opus | — | Spec 逸脱は高精度が必要（サブエージェント、effort は親から継承） |
| review-light | review | Sonnet | — | 軽量統合レビュー（サブエージェント、effort は親から継承） |
| triage（skill） | triage | Sonnet | — | メタデータ付与、Sonnet で十分。インライン実行（`run-*.sh` ラッパーなし）— `/auto` が未ラベル issue に triage を連鎖させる場合も含む — のため effort は設定しない |
| auto（skill） | orchestration | Sonnet | — | 親オーケストレーター、ユーザーの Claude Code セッションでインライン実行（`run-*.sh` ラッパーなし）。各子フェーズはフェーズ固有の effort で `run-*.sh` 経由で実行される。スキルレベルでは effort を設定しない |
| audit（skill） | audit | Sonnet | — | ドリフト・脆弱性検出と統計、Sonnet で十分。インライン実行（`run-*.sh` ラッパーなし）のため effort は設定しない |
| doc（skill） | doc | Sonnet | — | ドキュメント管理、Sonnet で十分。インライン実行（`run-*.sh` ラッパーなし）のため effort は設定しない |

SSoT 備考: run-*.sh のモデル値は CLI エイリアス（sonnet/opus）を使用する。run-*.sh、agents、skills でモデル/effort を変更する際はこの表を更新すること。

## Wholework ラベル管理

`scripts/setup-labels.sh` は Wholework が管理するすべてのラベルの**唯一の真実（SSoT）**です。すべてのラベル名・色・説明はここで定義します。

### ラベルグループ

| グループ | 数 | ラベル | 作成条件 |
|----------|-----|--------|----------|
| 常時 | 12 | `phase/*`（7）、`triaged`、`retro/verify`、`retro/code`、`audit/drift`、`audit/fragility` | 常に作成 |
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

## Gotchas

### `.claude/settings.json` はホットリロードされない

`.claude/settings.json` はセッション開始時にキャッシュされ、**セッション中はリロードされない**。`permissions.allow` パターン（あるいは他の設定）の変更は Claude Code セッション再起動後にのみ有効となる。

**含意**: `settings.json` を変更した後は、新しい権限パターンが正しく動作するかをテストする前に必ずセッションを再起動する。

**セッション内プローブによる偽陰性リスク**: 古い設定がロードされたままのセッション内で新しい `permissions.allow` パターンを検証すると偽陰性が起こり得る。プローブはキャッシュされた設定に基づいて成功（または失敗）する可能性があり、更新されたパターンが実際に動作するかを覆い隠す。権限検証プローブの実行前には必ずセッションを再起動すること。
