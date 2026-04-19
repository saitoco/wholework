# Issue #253: tech: fork-context / model-effort matrix / 言及箇所に /auto, /audit, /doc スキルを追加

## Overview

`docs/tech.md` の 2 つのテーブル（fork-context、Phase-specific model and effort matrix）と Architecture Decisions セクションに `/auto`, `/audit`, `/doc` スキルのメタデータが欠落している。これらのスキルは実装済みだが、Steering Documents との coverage drift が生じている。3 箇所の gap（S1/S2/S3）を一括修正し、`docs/ja/tech.md` にも同期する。

## Changed Files

- `docs/tech.md`:
  - S1: fork-context table に `auto`, `audit`, `doc` 行を追加
  - S2: "Phase-specific model and effort matrix" テーブルに `auto (skill)`, `audit (skill)`, `doc (skill)` エントリを追加（verify (skill) 行の直後）
  - S3: Architecture Decisions セクションに `/doc` skill の独立言及を追加（`/auto` スキル bullet の直後）
- `docs/ja/tech.md`:
  - fork-context table に `auto`, `audit`, `doc` 行を追加（Japanese 表記で）
  - model-effort matrix に `auto（skill）`, `audit（skill）`, `doc（skill）` エントリを追加（triage（skill）行の直後）
  - Architecture Decisions セクションに `/doc` skill 独立言及を追加

## Implementation Steps

1. `docs/tech.md` fork-context table（"Fork decision per skill" 表の末尾 `verify` 行の直後）に 3 行追加:
   - `| auto | No | Parent orchestrator runs in the user's Claude Code session; each child phase runs as an independent \`claude -p\` process via \`run-*.sh\` |`
   - `| audit | No | Drift and fragility detection runs in user's session; no prior-phase bias to avoid |`
   - `| doc | No | Document management runs in user's session; no prior-phase bias to avoid |`
   （→ 受入条件 1, 2, 3）

2. `docs/tech.md` model-effort matrix（`verify (skill)` 行の直後、`**Opus 4.7 effort calibration**` ブロックの前）に 3 行追加:
   - `| auto (skill) | orchestration | Sonnet | — | Parent orchestrator; runs in the user's Claude Code session inline (no \`run-*.sh\` wrapper). Each child phase runs via \`run-*.sh\` with phase-specific effort. Effort not set at the skill level |`
   - `| audit (skill) | audit | Sonnet | — | Drift/fragility detection and stats; Sonnet sufficient. Invoked inline (no \`run-*.sh\` wrapper), so effort is not set |`
   - `| doc (skill) | doc | Sonnet | — | Document management; Sonnet sufficient. Invoked inline (no \`run-*.sh\` wrapper), so effort is not set |`
   （→ 受入条件 4, 5）

3. `docs/tech.md` Architecture Decisions セクションの `/auto` スキル bullet（"- **`/auto` skill**: ..."）の直後に `/doc` 独立言及 bullet を追加:
   - `- **\`/doc\` skill**: Project foundation document management. Manages Steering Documents (\`product.md\`, \`tech.md\`, \`structure.md\`) and Project Documents. Key operations: \`sync\` (bidirectional normalization and drift detection; \`--deep\` for extended codebase analysis), \`init\` (initial setup wizard), \`add\` / \`project\` (document registration), \`translate {lang}\` (multi-language translation generation). Complements \`/audit\`: \`/doc sync\` proposes documentation-side fixes; \`/audit drift\` generates Issues for code-side fixes.`
   （→ 受入条件 6）

4. `docs/ja/tech.md` に Step 1〜3 と対応する日本語変更を適用（after Steps 1-3）:
   - fork-context table の末尾 `verify | 必要 |...` 行の直後に `auto`, `audit`, `doc` 行を追加（日本語表記: `| auto | 不要 | ...`）
   - model-effort matrix の `triage（skill）` 行の直後に `auto（skill）`, `audit（skill）`, `doc（skill）` エントリを追加
   - `/auto` スキル bullet の直後に `/doc` 独立言及 bullet を追加（日本語）

## Verification

### Pre-merge

- <!-- verify: grep "| auto |" "docs/tech.md" --> fork-context テーブルに `/auto` 行が存在する
- <!-- verify: grep "| audit |" "docs/tech.md" --> fork-context テーブルに `/audit` 行が存在する
- <!-- verify: grep "| doc |" "docs/tech.md" --> fork-context テーブルに `/doc` 行が存在する
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "audit" --> model-effort matrix に `/audit` 関連の行が存在する
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "doc" --> model-effort matrix に `/doc` 関連の行が存在する
- <!-- verify: grep "/doc" "docs/tech.md" --> `docs/tech.md` 全体で `/doc` への言及が 1 箇所以上存在する

### Post-merge

- 再度 `/doc sync --deep` を実行し、fork-context/model-effort matrix 関連の Skill Coverage Gap drift が検出されないことを確認
- `docs/ja/tech.md` が `docs/tech.md` の更新内容を反映していることを確認（`/code` skill の `docs/ja/` sync check で自動対応されるが、最終目視確認）

## Notes

- 検証コマンド数が light テンプレートの上限 5 に対して 6 件（Issue body 全 AC を verbatim コピーしたため）
- `docs/ja/tech.md` の model-effort matrix は既に英語版から drift 済み（`merge（skill）`, `verify（skill）` が欠落）。本 Issue スコープは `/auto`, `/audit`, `/doc` 追加のみとし、既存 drift の修正は別途 Issue 対応とする
- fork-context verify コマンドは `grep "| auto |"` 形式（Issue Auto-Resolved Ambiguity Points に記載の通り、テーブル行マッチパターンを採用）
