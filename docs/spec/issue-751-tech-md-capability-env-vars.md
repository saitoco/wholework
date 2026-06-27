# Issue #751: tech.md — Capability Env Var Convention and Built-in Capability List

## Overview

`detect-config-markers.md` maps `capabilities.*` keys in `.wholework.yml` to runtime environment variables. However, the env vars set by this mapping (`HAS_BROWSER_CAPABILITY`, `HAS_VISUAL_DIFF_CAPABILITY`, `HAS_WORKFLOW_CAPABILITY`, `MCP_TOOLS`) are not documented in `docs/tech.md` `## Environment Variables`. Operators cannot confirm the active capability state from `tech.md` alone.

Add the capability env var naming convention (`capabilities.{name}` → `HAS_{UPPERCASE_NAME}_CAPABILITY`) and the four built-in capability entries to `docs/tech.md`, with `docs/ja/tech.md` synced accordingly.

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — AC4 env var changed from `HAS_MCP_CAPABILITY` → `MCP_TOOLS` because `detect-config-markers.md` maps `capabilities.mcp` to `MCP_TOOLS` (comma-separated list), not `HAS_MCP_CAPABILITY`. The dynamic mapping excludes `capabilities.mcp`.

## Changed Files

- `docs/tech.md`: add capability env vars subsection to `## Environment Variables` — bash 3.2+ not applicable (documentation only)
- `docs/ja/tech.md`: sync Japanese mirror — add `## 環境変数` capability entries in Japanese

## Implementation Steps

1. In `docs/tech.md` `## Environment Variables`, add a subsection header `### Capability Flags` after the existing `WHOLEWORK_*` table, followed by:
   - Explanation sentence: "The following variables are set by `detect-config-markers.md` from `.wholework.yml` `capabilities.*` keys. Built-in capabilities use the fixed mappings below; any user-defined `capabilities.{name}: true` key is dynamically mapped to `HAS_{UPPERCASE_NAME}_CAPABILITY`."
   - A table with rows: `HAS_BROWSER_CAPABILITY`, `HAS_VISUAL_DIFF_CAPABILITY`, `HAS_WORKFLOW_CAPABILITY`, `MCP_TOOLS` (→ acceptance criteria AC1–AC6)

2. In `docs/ja/tech.md` `## 環境変数`, add the corresponding Japanese-language subsection `### Capability フラグ` with the same structure translated (→ docs/ja/ sync obligation)

## Verification

### Pre-merge

- <!-- verify: grep "HAS_BROWSER_CAPABILITY" "docs/tech.md" --> tech.md に HAS_BROWSER_CAPABILITY が記載
- <!-- verify: grep "HAS_VISUAL_DIFF_CAPABILITY" "docs/tech.md" --> HAS_VISUAL_DIFF_CAPABILITY 記載
- <!-- verify: grep "HAS_WORKFLOW_CAPABILITY" "docs/tech.md" --> HAS_WORKFLOW_CAPABILITY 記載
- <!-- verify: grep "MCP_TOOLS" "docs/tech.md" --> MCP_TOOLS が記載 (capabilities.mcp の実際の env var は HAS_MCP_CAPABILITY ではなく MCP_TOOLS)
- <!-- verify: rubric "capabilities.* → HAS_*_CAPABILITY マッピング規約が tech.md で説明されている" --> 命名規約が明示されている
- <!-- verify: section_contains "docs/tech.md" "## Environment Variables" "capabilities" --> Environment Variables セクションに capability の記述が含まれる

### Post-merge

なし

## Notes

- `MCP_TOOLS` は dynamic mapping の除外対象 (`capabilities.mcp` → `MCP_TOOLS` の固定マッピング)。`HAS_MCP_CAPABILITY` は設定されない — auto-resolved from Issue Retrospective comment.
- `HAS_INVOICE_API_CAPABILITY` はユーザー定義 capability の naming convention 例示 (`environment-adaptation.md:40`) であり、組み込み capability ではないため一覧に含めない。
- docs/ja/ の Japanese verify pattern 注意: `section_contains` の Japanese section heading (`## 環境変数`) は英語パターンと異なるため、verify コマンドは英語ソース (`docs/tech.md`) のみを対象にする。
