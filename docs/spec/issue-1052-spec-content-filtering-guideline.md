# Issue #1052: spec: 大量アセット追加時の content filtering 回避ガイドラインを追加

XS patch route のため `/spec` フェーズを経ておらず、本ファイルは `/verify` の improvement proposal パイプラインが issue retrospective を収集できるようにするために作成された (`skills/auto/SKILL.md` Step 4b)。実装は `f3743d46` (`chore: verify-patterns: add bulk asset ingestion content-filtering guideline (closes #1052)`) を参照。

## Issue Retrospective

### 実行モード

`--non-interactive` (三層ポリシー: auto-resolve / skip / hard-error) で実行。

### 曖昧ポイントの自動解決 (Auto-Resolve Log)

- **ガイドライン追加先ファイル: `modules/verify-patterns.md` に一本化** — reason: 元の AC2 (`grep` verify command) が既に `modules/verify-patterns.md` を検証対象に固定しており、同ファイルは既存の §1–§26 が spec 設計ガイドライン (Implementation Steps 記述パターン) を番号付きセクションとして蓄積する慣例を持つ (§7, §16, §19 等が類例)。また `skills/spec/SKILL.md` の Step 10 (Create Spec) は既に `modules/verify-patterns.md` を複数箇所で参照する構成になっており、同ファイルへの追加だけで `/spec` の設計ガイドラインへの反映として機能する。AC1 (rubric) の文言を「spec スキルまたは verify-patterns」から `modules/verify-patterns.md` 明記に修正し、AC1/AC2 間の対象ファイル不整合を解消した。
  - Other candidates: `skills/spec/SKILL.md` への直接追記 (Step 10 が既に長く、これ以上の肥大化を避けるため見送り)、両ファイルへの重複追記 (メンテナンスコスト増のため見送り)
- **「関連」節の worktree 中断復帰の話をスコープ外として維持** — reason: 本 Issue の Purpose は「大量アセット追加時の content filtering 回避ガイドライン追加」に限定されており、`modules/worktree-lifecycle.md` の変更は独立した改善提案であるため、AC化はせず情報提供コメントのまま残した。
  - Other candidates: 本 Issue の AC に追加 (スコープ拡大により Size 判定・実装範囲に影響するため見送り)

### AC 変更の理由

- AC1 (rubric) の文言を「spec スキルまたは verify-patterns」→「modules/verify-patterns.md」に修正。理由は上記の自動解決ログの通り。文言修正のみで、検証の意図・厳格さは変わらない。
- AC2 (grep) は変更なし。

### その他の判断

- Size XS のためサブIssue分割は評価不要 (非対話モードでも high-stakes decision として一律スキップ対象)。
- Blocked-by 関係は検出されなかった (`gh-check-blocking.sh` exit 0)。
- Background 内の事実主張 (content filtering インシデントの記述) はコードベース照合対象パターン (生成/呼び出し/依存の主張) に該当せず、advisory チェックはスキップした。
