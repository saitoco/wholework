# Issue #865: docs: /audit の 5 サブコマンドを tech.md model-effort matrix と product.md Terms に列挙

## Overview

`/audit` スキルには `drift` / `fragility` / `stats` / `progress` / `auto-session` の 5 サブコマンドが存在するが、
`docs/tech.md` の Phase-specific model and effort matrix では 3 系統のみ言及、`docs/product.md` § Terms には `/audit`
独立エントリが存在しない。両 SSoT 文書を更新してサブコマンドの discover-ability を向上させる。

## Changed Files

- `docs/tech.md`: `audit (skill)` 行の Rationale 列を 5 サブコマンド全列挙に拡張 — bash 非対象 (doc only)
- `docs/product.md`: § Terms に `/audit` 新規エントリを追加 (`/auto` 行の直後) — bash 非対象 (doc only)
- `docs/ja/tech.md`: 同上の日本語翻訳ミラーを更新 — bash 非対象 (doc only)
- `docs/ja/product.md`: 同上の日本語翻訳ミラーに `/audit` エントリを追加 — bash 非対象 (doc only)

## Implementation Steps

1. `docs/tech.md` L102: `audit (skill)` 行 Rationale 列を次の文言に置換  
   変更前: `Drift/fragility detection and stats; Sonnet sufficient. Invoked inline (no \`run-*.sh\` wrapper), so effort is not set`  
   変更後: `Drift detection (\`drift\`), fragility analysis (\`fragility\`), project health stats (\`stats\`), XL sub-issue progress (\`progress\`), /auto session retrospective (\`auto-session\`); Sonnet sufficient. Invoked inline (no \`run-*.sh\` wrapper), so effort is not set`  
   (→ 受入条件 1)

2. `docs/product.md` L158: `/auto` 行の直後に新規行を挿入  
   ```
   | `/audit` | Composite skill for project-health detection. Subcommands: `/audit drift` (documentation ↔ code drift, auto-generates Issues), `/audit fragility` (structural fragility detection), `/audit stats` (Issue throughput / composition / First-try success aggregation, optionally `--retention` for phase/verify and Icebox dwell), `/audit progress` (XL sub-issue progress snapshot), `/audit auto-session` (existing data-layer report or fallback generation from `.tmp/auto-events.jsonl`). | /audit Skill | `/audit` |
   ```
   (→ 受入条件 2)

3. `docs/ja/tech.md` L100: `audit（skill）` 行 Rationale 列を次の文言に置換 (after 1)  
   変更前: `ドリフト・脆弱性検出と統計、Sonnet で十分。インライン実行（\`run-*.sh\` ラッパーなし）のため effort は設定しない`  
   変更後: `drift 検出 (\`drift\`)・脆弱性解析 (\`fragility\`)・プロジェクト健全性統計 (\`stats\`)・XL サブ Issue 進捗 (\`progress\`)・/auto セッションレトロスペクティブ (\`auto-session\`); Sonnet で十分。インライン実行 (\`run-*.sh\` ラッパーなし) のため effort は設定しない`

4. `docs/ja/product.md` L150: `/auto` 行の直後に新規行を挿入 (after 2)  
   ```
   | `/audit` | プロジェクト健全性検出のための複合スキル。サブコマンド: `/audit drift` (ドキュメント ↔ コードドリフト、Issue 自動生成)、`/audit fragility` (構造的脆弱性検出)、`/audit stats` (Issue スループット / 構成 / First-try 成功率集計、`--retention` でフェーズ/verify と Icebox 滞留メトリクスを追加)、`/audit progress` (XL サブ Issue 進捗スナップショット)、`/audit auto-session` (`.tmp/auto-events.jsonl` からのデータレイヤーレポートまたはフォールバック生成)。 | /audit Skill | `/audit` |
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "docs/tech.md の Phase-specific model and effort matrix 内 audit (skill) 行の Rationale 列に、drift / fragility / stats / progress / auto-session の 5 サブコマンドがすべて言及されている" --> <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "auto-session" --> `docs/tech.md` model-effort matrix の `audit (skill)` 行に `progress` / `auto-session` を含む全 5 サブコマンドが列挙されていること
- <!-- verify: rubric "docs/product.md の Terms 表内 /audit エントリ Definition 列に、drift だけでなく fragility / stats / progress / auto-session の 4 サブコマンドへの言及が含まれている" --> <!-- verify: section_contains "docs/product.md" "## Terms" "auto-session" --> `docs/product.md` § Terms に `/audit` エントリが新規追加され、全 5 サブコマンドが言及されていること

### Post-merge

- 次回 `/doc sync --deep` narrative drift check で `/audit` サブコマンドの Partial Description / Missing Coverage が解消されていること

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: product.md の `/audit` エントリは「拡張」ではなく「新規追加」(独立エントリ) と確定。`/auto` 前例に沿う。/ https://github.com/saitoco/wholework/issues/865#issuecomment-4831024099

## Notes

- AC verify command は Issue 本文からそのまま転記 (rubric + section_contains の 2 段構成)
- `docs/ja/` ミラー更新は translation-workflow.md の義務に従い Step 3-4 として追加 (AC には含まれないが必須)
- 表現案は提案 (Issue Notes 記載); Spec フェーズで「1 文/sub-command」形式に簡潔化済み
- Auto-resolve (継承): `/audit` 独立エントリ追加は `Drift` エントリ拡張より discoverability が高く `/auto` 前例に沿う — issue retrospective コメントで確認済み
