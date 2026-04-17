# Issue #231: skills/merge と skills/verify の frontmatter に model: sonnet を追加

## Issue Retrospective

### Scope Decisions (from conversation)

- **対象 skill は merge / verify の 2 つに限定** — 根拠: `merge` は機械的操作 (低 effort)、`verify` は checkbox 判定中心 (medium effort) で、両者とも Opus の能力を必要としない。`issue` / `spec` / `code` / `review` は Size 依存や柔軟性が必要なため本 Issue のスコープ外
- **effort: frontmatter は対象外** — 根拠: Skill frontmatter での effort 指定は公式ドキュメントで未確認。別途確認が必要
- **context: fork が既に指定されている** — `model: sonnet` 追加により fork 時のモデルも Sonnet で固定。対話セッションが Opus 4.7 でも fork 内は Sonnet で動作

### Auto-Resolved Ambiguity Points

- **`run-*.sh` 側の変更は不要** — `scripts/validate-skill-syntax.py:16` で `model` は有効フィールドとして認識されており、`run-merge.sh` / `run-verify.sh` は既に `--model sonnet` 指定済み。skill frontmatter 追加のみで SSoT が統一される

### AC 設計根拠

- `file_contains` で両 skill への追加を検証
- `section_contains "docs/tech.md" "Phase-specific model and effort matrix"` で matrix への両 skill エントリ追加を検証 (既に triage (skill) のエントリが存在するため、同形式で追加)
- `github_check "Validate skill syntax"` で CI による frontmatter 妥当性を確認

### Triage

- Type: Task
- Priority: medium (SSoT 整合の性質上、緊急性は低いが戦略レポート §2.4 に沿う)
- Size: XS (2 skill × 1 行 + docs/tech.md 2 行追加)
- Value: 2 (Impact=0 / Alignment=3; コスト最適化・SSoT 整合)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 設計は的確。`file_contains` / `section_contains` / `github_check` の組み合わせで全条件が自動検証可能な形式になっており、verify 実行がスムーズだった
- スコープ絞り込み（merge/verify のみ）の根拠が明示されており、実装範囲の誤解が生じなかった

#### design
- N/A（設計フェーズなし。XS サイズのため spec → code 直結）

#### code
- パッチルート（main 直コミット）で処理。単一コミット `c83ba4e`、diff 4 行（3 ファイル）と非常にクリーン
- fixup/amend なし。一発でクローズ

#### review
- パッチルートのため formal review なし。CI（Validate skill syntax）が唯一のゲート
- CI は全 4 ジョブ成功（Run bats tests / macOS shell compatibility / Forbidden Expressions check / Validate skill syntax）

#### merge
- パッチルート（PR なし）。`closes #231` をコミットメッセージに含めて直接クローズ
- 問題なし

#### verify
- 全 5 条件が PASS。条件 5 (`github_check "gh run list"`) がパッチルートでも有効に機能した
- Post-merge opportunistic 条件（Opus 4.7 での動作確認）は手動検証待ち

### Improvement Proposals
- N/A
