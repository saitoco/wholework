# Tech

## 言語とランタイム

- **Bash/Shell Script**: ラッパースクリプト（`scripts/run-*.sh`）、ユーティリティスクリプト
- **Markdown**: Skill 定義（`SKILL.md`）、エージェント定義（`agents/*.md`）、共有モジュール（`modules/*.md`）、ドキュメント
- **Python**: 検証スクリプト（`scripts/validate-skill-syntax.py`）
- **GitHub Actions**: CI/CD ワークフロー（`.github/workflows/`）

## 主要依存

| パッケージ | 役割 |
|------------|------|
| Claude Code CLI（`claude`） | Skill 実行エンジン、サブエージェントの起動 |
| GitHub CLI（`gh`） | Issue/PR 操作、GitHub API アクセス |
| GitHub Copilot | コードレビュー（Step 6）、Issue からの自動実装 |
| bats（Bash Automated Testing System） | シェルスクリプトのテスト |

## アーキテクチャ決定

- **Skill ベースのワークフロー**: 開発の各フェーズ（issue/spec/code/review/merge/verify）を独立した Claude Code Skill として実装します。処理ステップは SKILL.md に記述され、LLM がそれをステップごとに実行します。
- **Plugin ディレクトリによる配布**: `--plugin-dir` を用いてローカルの Claude Code plugin として配布します。Claude Code は実行時に `${CLAUDE_PLUGIN_ROOT}` を plugin ディレクトリに設定し、Skill とモジュールがスクリプトやモジュールを参照する際に使用します。
- **fork コンテキスト vs main コンテキスト**: コンテキスト分離レベルは Skill ごとに設定されます。フォーク根拠は「独立性/安全性」です（1M コンテキスト GA 以降、コスト/容量面の動機はほぼなくなりました）。Skill 別のフォーク判断（網羅的）:

  | Skill | フォーク要否 | 理由 |
  |-------|--------------|------|
  | triage | 不要（削除済み） | 先行フェーズバイアスを避ける必要がない。独立性は不要 |
  | code | 必要 | Spec を読み込んで独立実行。実装前のコンテキストに影響されない |
  | review | 必要 | 実装フェーズのバイアスを引き継がず、クリーンな視点でコードをレビューする |
  | merge | 必要 | 判断は Spec + PR メタデータで完結。レビューコンテキストを引き継がない |
  | verify | 必要 | マージ後状態を独立に検証。先行フェーズの判断に影響されてはならない |

- **`/auto` skill**: spec→code→review→merge→verify を `run-*.sh` 経由で順に連鎖させるオーケストレータです。各フェーズは `claude -p --dangerously-skip-permissions` により独立プロセスで実行され、フレッシュなコンテキストと完全なパーミッションバイパスを保証します。追加機能: `phase/*` ラベルがない場合は Issue の triage/精査から自動開始、`phase/ready` がない場合は `/spec` を自動実行、`--batch N` はバックログから XS/S の Issue を N 件処理、XL Issue はサブ Issue の依存グラフ（`blockedBy`）を読み取って独立なサブ Issue を並列実行（worktree 分離）し、依存先の完了後に後続を順次実行、`--base {branch}` は main の代わりにリリースブランチを対象にします。
- **サブエージェント分割**: 2 つの Skill で使用されます:
  - `/issue`（L/XL）: 3 つの独立サブエージェント（`scope-agent`、`risk-agent`、`precedent-agent`）による並列調査。変更スコープ、リスク、先行事例を同時に分析します。
  - `/review`: 2 グループ（Spec 準拠レビュー `review-spec` とバグ検出 `review-bug`）に分割し、2 段階検証（検出→検証サブエージェント）で偽陽性を排除します。
- **共有モジュールパターン**: 複数の Skill で共通する処理を `modules/*.md` に抽出し、「Read and follow」パターンで参照します。
- **Spec ファースト（使い捨て）**: Spec はタスク完了後に成果物として保守されません。Spec アンカー方式や Spec ソース方式は採用しません。理由: (1) LLM の非決定性により、同じ Spec が同じコードを再生成することは保証されない、(2) Spec の保守コストがコード保守コストに上乗せされる。
- **段階的開示（Core/Domain 分離）**: SKILL.md 本体にはプロジェクト種別やツールに依存しない汎用ロジックのみを記述します。特定ツール（Figma、Copilot など）やプロジェクト種別（Skill 開発、IaC など）固有のロジックは補助ファイル（`skills/{name}/xxx-phase.md`）に抽出し、該当する場合のみ読み込みます。判断基準は「このロジックはこのツール/プロジェクト種別を使わないプロジェクトでも必要か？」— No なら抽出します。
  - **抽出パターン（標準）（網羅的）**:

    | パターン | 条件 | 例 |
    |----------|------|---|
    | マーカー検出 | `.wholework.yml` の YAML キー | `review/external-review-phase.md`（`copilot-review: true`、`claude-code-review: true`、または `coderabbit-review: true` のときに読み込む） |
    | ファイル存在 | 特定ファイルの存在 | `review/skill-dev-recheck.md`（`scripts/validate-skill-syntax.py` が存在するときに読み込む） |

## テスト戦略

| ツール | 目的 | タイミング |
|--------|------|------------|
| **bats**（Bash Automated Testing System） | シェルスクリプトのユニットテスト | pre-merge（`command` 受入チェック経由） |
| **validate-skill-syntax.py** | SKILL.md 構文検証（半角 `!` 検出、frontmatter 検証） | pre-merge |
| **受入チェック**（`<!-- verify: ... -->`） | 受入条件の機械的検証（ファイル存在、テキスト内容、コマンド実行） | `/verify` Skill 実行時 |

## Forbidden Expressions

| 表現 | 理由 | 代替 |
|------|------|------|
| 半角 `!`（SKILL.md 本文、コードフェンス外および inline code 外） | Claude Code の Bash パーミッションチェッカが zsh の履歴展開として誤検知し、Skill 実行時にエラーが発生する | 全角「！」または表現の書き換え |

## 用語移行のスコープルール

Terms の 'Formerly called' に非推奨用語を追加する Issue（段階的な用語移行）を作成する際は、同一ファイル内の非推奨用語の置換を対象に含むかどうかを明示してください。

### スコープ宣言テンプレート

Issue 本文の「Scope」または「Acceptance Criteria」セクションに以下のいずれかを含めます:

```
[同一ファイル内の非推奨用語の置換] 含む / 含まない（後続 Issue #N で対応）
```

### 理由

段階的移行では、Forbidden Expressions への追加後もしばらくは同一ファイル内に非推奨用語が残存する期間があります。この期間中、レビュアー（Copilot など）が Forbidden Expressions と本文の矛盾を指摘し、段階的移行方針と衝突する可能性があります。スコープを明示することで、誤ったレビューコメントを防ぎます。

### 適用範囲

- Forbidden Expressions への非推奨用語追加を含むすべての Issue に適用
- 「含まない」とした場合は、非推奨用語の置換を後続 Issue で扱い、その Issue 番号を参照します
