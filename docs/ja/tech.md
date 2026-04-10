[English](../tech.md) | 日本語

# Tech

## 言語とランタイム

- **Bash/Shell Script**: ラッパースクリプト（`scripts/run-*.sh`）、ユーティリティスクリプト
- **Markdown**: Skill 定義（`SKILL.md`）、エージェント定義（`agents/*.md`）、共有モジュール（`modules/*.md`）、ドキュメント
- **Python**: バリデーションスクリプト（`scripts/validate-skill-syntax.py`）
- **GitHub Actions**: CI/CD ワークフロー（`.github/workflows/`）

## 主要依存関係

| パッケージ | 役割 |
|---------|------|
| Claude Code CLI (`claude`) | Skill 実行エンジン、サブエージェント生成 |
| GitHub CLI (`gh`) | Issue/PR 操作、GitHub API アクセス |
| GitHub Copilot | コードレビュー（Step 6）、Issue からの自動実装 |
| bats (Bash Automated Testing System) | シェルスクリプトテスト |

## アーキテクチャ決定

- **Skills ベースワークフロー**: 各開発フェーズ（issue/spec/code/review/merge/verify）は独立した Claude Code Skill として実装。処理ステップは SKILL.md に記述され、LLM がステップバイステップで実行。
- **Plugin ディレクトリ配布**: `--plugin-dir` を使用してローカル Claude Code プラグインとして配布。Claude Code は実行時に `${CLAUDE_PLUGIN_ROOT}` をプラグインディレクトリに設定し、Skill とモジュールはこれを使用してスクリプトやモジュールを参照。
- **fork コンテキスト vs メインコンテキスト**: コンテキスト分離レベルは Skill ごとに設定。fork の根拠: 「独立性/安全性」（1M コンテキスト GA 以降、コスト/容量の動機は大幅に低下）。Skill ごとの fork 判定（網羅）:

  | Skill | fork 必要 | 理由 |
  |-------|-------------|--------|
  | triage | いいえ（削除） | 先行フェーズバイアスを回避する必要なし、独立性不要 |
  | code | はい | Spec を読み取り独立して実行。実装前のコンテキストに影響されない |
  | review | はい | 実装フェーズのバイアスを引き継がず、クリーンな視点でコードをレビュー |
  | merge | はい | 判断は Spec + PR メタデータで完結。レビューコンテキストを引き継がない |
  | verify | はい | マージ後の状態を独立して検証。先行フェーズの判断に影響されてはならない |

- **`/auto` Skill**: spec→code→review→merge→verify を `run-*.sh` 経由で順次連鎖するオーケストレーター。各フェーズは `claude -p --dangerously-skip-permissions` で独立プロセスとして実行され、フレッシュなコンテキストと完全なパーミッションバイパスを保証。追加機能: `phase/*` ラベル未設定時は Issue トリアージ/リファインから自動開始、`phase/ready` 未設定時は `/spec` を自動実行、`--batch N` はバックログから N 件の XS/S Issue を処理、XL Issue はサブ Issue の依存グラフ（`blockedBy`）を読み取り独立サブ Issue を並列実行（worktree 分離）してから依存するものを順次実行、`--base {branch}` は main の代わりにリリースブランチをターゲットにする。
  - **2 階層オーケストレーション**: `/auto` 自体（親オーケストレーター）はユーザーの Claude Code セッション内で動作し、LLM 推論による適応的判断（ラベル状態評価、Size ベースルーティング、サブ Issue 依存グラフ解析）を行う。XL Issue の場合、`run-auto-sub.sh`（子オーケストレーター）が各サブ Issue の全フェーズシーケンスを実行する。`run-auto-sub.sh` は純粋な bash スクリプトであり `claude -p` を呼び出さず、Size に基づく決定的な if/case ルーティングを使用する。これは技術的制約ではなく意図的な設計選択: 現在のフェーズルーティングは決定的であり各フェーズは `run-*.sh` により自己完結しているため、子オーケストレーターレベルでの LLM 推論はコスト増のみで利点がない。適応的リカバリが必要になった場合（例: code 失敗後の spec 再実行、review 結果に基づく戦略変更）、`run-auto-sub.sh` を `claude -p` オーケストレーターにアップグレードする方向になる。
- **サブエージェント分割**: 2 つの Skill で使用:
  - `/issue`（L/XL）: 3 つの独立サブエージェント（`scope-agent`、`risk-agent`、`precedent-agent`）による並列調査で、変更スコープ、リスク、前例を同時分析。
  - `/review`: 2 グループに分割 — Spec 準拠レビュー（`review-spec`）とバグ検出（`review-bug`）— 2 段階検証（検出→検証サブエージェント）で偽陽性を排除。
- **共有モジュールパターン**: 複数 Skill にまたがる共通処理を `modules/*.md` に抽出し、「Read and follow」パターンで参照。
- **Spec ファースト（使い捨て）**: Spec はタスク完了後に成果物として維持されない。Spec アンカード方式と Spec-as-source 方式は採用しない。理由: (1) LLM の非決定性により同じ Spec が同じコード再生成を保証しない、(2) Spec のメンテナンスコストがコードのメンテナンスコストに上乗せされる。
- **Progressive disclosure（Core/Domain 分離）**: SKILL.md 本体にはプロジェクトタイプやツールに依存しない汎用ロジックのみを含む。特定のツール（Figma、Copilot 等）やプロジェクトタイプ（Skill 開発、IaC 等）固有のロジックは補助ファイル（`skills/{name}/xxx-phase.md`）に抽出し、該当する場合にのみ読み込む。判断基準: 「このツール/プロジェクトタイプを使用しないプロジェクトでこのロジックは必要か？」 — No なら抽出。
  - **抽出パターン（標準）（網羅）**:

    | パターン | 条件 | 例 |
    |---------|-----------|---------|
    | マーカー検出 | `.wholework.yml` の YAML キー | `review/external-review-phase.md`（`copilot-review: true`、`claude-code-review: true`、または `coderabbit-review: true` の時に読み込み） |
    | ファイル存在 | 特定ファイルの存在 | `review/skill-dev-recheck.md`（`scripts/validate-skill-syntax.py` が存在する時に読み込み） |

- **工数最適化戦略（3 軸）**: `claude -p` 呼び出しにおける実行コストと品質を制御する 3 つの軸。軸ごとの CLI サポート状況と Wholework の採用方針:
  - **軸 1 — Model selection**（`--model`）: 実装済み。Sonnet がデフォルト、`run-spec.sh --opus` で L サイズ Spec に Opus を使用。レビュー確認済み。
  - **軸 2 — Adaptive Thinking**（`--effort`）: `claude -p` は `low/medium/high/max` レベルをサポート（`claude --help` で確認済み）。`run-*.sh` にフェーズ別 effort レベルを実装済み（下記マトリクス参照）。medium effort + Opus advisor の組み合わせで、デフォルト effort の Sonnet と同等品質を低コストで達成可能（Anthropic ベンチマークによる）。
  - **軸 3 — Advisor 戦略**（`advisor_20260301`）: Anthropic API ベータ機能（`advisor-tool-2026-03-01` ヘッダー必須）。`--betas` フラグで有効化 — API キーユーザーのみ、OAuth/サブスクリプション認証（`run-*.sh` のデフォルト）では利用不可。パフォーマンス向上: Sonnet + Opus advisor で SWE-bench +2.7 pp、コスト -11.9%（Sonnet 単体比）、Haiku + Opus advisor で BrowseComp 41.2%（単体 19.7% 比）、コスト -85%（Sonnet 比）。`run-*.sh` への実装はフォローアップ Issue。

  **フェーズ別 model・effort マトリクス**（`ssot_for: model-effort-matrix`）:

  | コンポーネント | フェーズ | Model | Effort | 根拠 |
  |-----------|-------|-------|--------|-----------|
  | run-spec.sh | spec | Sonnet（L では `--opus` で Opus） | max | 設計品質が最重要。Spec エラーは全後続フェーズに波及。`/auto` は L サイズのみ `--opus` を渡す（XL は spec 前に分割） |
  | run-code.sh | code | Sonnet | high | 実装には十分な推論が必要 |
  | run-review.sh | review | Sonnet | high | レビューオーケストレーション。サブエージェントが深い分析を担当 |
  | run-issue.sh | issue | Sonnet | high | L/XL スコープ分析とサブ Issue 分割に十分なオーケストレーションが必要 |
  | run-verify.sh | verify | Sonnet | medium | 構造化された受入テスト。中程度の複雑度 |
  | run-merge.sh | merge | Sonnet | low | 機械的なマージ操作。最小限の推論で十分 |
  | review-bug | review | Opus | — | バグ検出には最高精度が必要（サブエージェント、effort は親から継承） |
  | review-spec | review | Opus | — | Spec 逸脱検出には高精度が必要（サブエージェント、effort は親から継承） |
  | review-light | review | Sonnet | — | 軽量統合レビュー（サブエージェント、effort は親から継承） |
  | scope-agent | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査に使用。スコープ特定精度がサブ Issue 分割判断に直結 |
  | risk-agent | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査に使用。リスク評価精度が受入条件品質を向上 |
  | precedent-agent | issue（L/XL のみ） | Opus | — | `/issue` Step 11a で L/XL 並列調査に使用。前例抽出が受入条件品質を向上 |
  | triage（skill） | triage | Sonnet | — | メタデータ割り当て。Sonnet で十分（直接呼び出し、effort 未設定） |

  SSoT 注記: このマトリクスは全 model・effort 設定の唯一の信頼できる情報源（Single Source of Truth）です。run-*.sh、agents、skills の model/effort を変更する場合は、まずこのテーブルを更新してください。

## テスト戦略

| ツール | 目的 | タイミング |
|------|---------|------|
| **bats** (Bash Automated Testing System) | シェルスクリプトのユニットテスト | マージ前（`command` verify command 経由） |
| **validate-skill-syntax.py** | SKILL.md 構文検証（半角 `!` 検出、frontmatter バリデーション） | マージ前 |
| **Verify commands** (`<!-- verify: ... -->`) | 受入条件の機械的検証（ファイル存在、テキスト内容、コマンド実行） | `/verify` Skill 実行時 |

## 禁止表現

| 表現 | 理由 | 代替 |
|------------|--------|-------------|
| 半角 `!`（SKILL.md 本文、コードフェンスおよびインラインコード外） | Claude Code の Bash パーミッションチェッカーが zsh ヒストリ展開として誤検出し、Skill 実行時にエラーが発生 | 全角「！」または言い換え |
| Acceptance check | 用語再設計（「verify command」に変更） | "verify command" |

## 用語マイグレーションスコープルール

deprecated な用語を Terms の 'Formerly called' に追加する Issue を作成する場合、同一ファイル内の deprecated 用語の置換がスコープに含まれるかどうかを明示的に記載する。

### スコープ宣言テンプレート

Issue 本文の「Scope」または「Acceptance Criteria」セクションに以下のいずれかを含める:

```
[同一ファイル内 deprecated 用語の置換] 含む / 含まない（フォローアップ Issue #N で対応）
```

### 理由

段階的マイグレーションでは、禁止表現に追加した後も同一ファイル内に deprecated 用語が残る期間がある。この期間中、レビュワー（Copilot 等）が禁止表現と本文テキストの矛盾を指摘する可能性があり、段階的マイグレーションポリシーと競合する。明示的なスコープ宣言により、誤ったレビューコメントを防止。

### 適用範囲

- 禁止表現への deprecated 用語追加を含むすべての Issue に適用
- 「含まない」の場合、deprecated 用語の置換をフォローアップ Issue で対応し、その Issue 番号を参照

## 注意事項

### `.claude/settings.json` はホットリロードされない

`.claude/settings.json` はセッション開始時にキャッシュされ、**セッション中はリロードされない**。`permissions.allow` パターン（およびその他の設定）の変更は、Claude Code セッションを再起動した後にのみ有効になる。

**影響**: `settings.json` を変更した後は、新しいパーミッションパターンが正しく動作するかテストする前に、必ずセッションを再起動すること。

**セッション内プローブの偽陰性リスク**: 古い設定がロードされたセッション内で新しい `permissions.allow` パターンをプローブして検証すると、偽陰性が発生する可能性がある。プローブはキャッシュされた設定に基づいて成功（または失敗）する可能性があり、更新された設定に基づかない — 新しいパターンが実際に機能するかどうかが隠される。パーミッション検証プローブを実行する前に、必ずセッションを再起動すること。
