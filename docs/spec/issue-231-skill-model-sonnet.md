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
