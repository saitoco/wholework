English | [日本語](../ja/guide/xl-decomposition.md)

# XL Decomposition Guide

This guide explains how to use `/issue --from-decomposition-file <path>` to bulk-create sub-issues for an XL parent issue from a user-defined YAML file.

## When to Use

When you need to create 10+ sub-issues for an XL parent issue, writing them one by one via `gh issue create` takes 4–8 hours of manual work. The decomposition file mode lets you define all sub-issues in a single YAML file and create them — with parent-child relationships and blocked-by dependencies — in one command.

## Command Syntax

```
/issue --from-decomposition-file <path-to-yaml>
```

Example:

```
/issue --from-decomposition-file examples/decomposition/nuxt-to-next.yml
```

## YAML Schema

```yaml
parent: 1000           # Required: integer — the XL parent Issue number
sub_issues:            # Required: list with at least one entry
  - id: foundation                    # Required: unique string within YAML (used by blocked_by)
    title: "next-init: Next.js プロジェクト初期化 + routing 設定 + middleware 移植"  # Required
    background: |                     # Optional: omit to use TBD skeleton
      Nuxt → Next 移行の foundation phase。
    purpose: |                        # Optional: omit to use title summary
      Next.js プロジェクトをセットアップし、基盤を整備する。
    acceptance_criteria:              # Optional: omit to use "- [ ] TBD"
      - condition: Next.js プロジェクトが初期化されている
        verify: file_exists "next.config.js"
      - condition: middleware が移植されている
        verify: grep "middleware" "next.config.js"
    blocked_by: []                    # Optional: list of id strings from sub_issues

  - id: theme
    title: "next-theme: 共通レイアウト・スタイル移植"
    blocked_by: [foundation]          # This sub-issue is blocked by "foundation"

  - id: page-home
    title: "next-page: トップページを Next.js へ移植"
    blocked_by: [theme]
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `parent` | integer | Yes | XL parent Issue number |
| `sub_issues` | list | Yes | List of sub-issue entries (at least 1) |
| `sub_issues[].id` | string | Yes | Unique identifier within this YAML file; used as `blocked_by` reference key |
| `sub_issues[].title` | string | Yes | Issue title; component prefix + verb-first format recommended |
| `sub_issues[].background` | string | No | Issue background text; TBD skeleton used if absent |
| `sub_issues[].purpose` | string | No | Issue purpose text; title summary used if absent |
| `sub_issues[].acceptance_criteria` | list | No | List of `{condition, verify}` entries; `- [ ] TBD` used if absent |
| `sub_issues[].blocked_by` | list of id strings | No | Dependencies; all referenced `id` values must exist in `sub_issues` |

### Schema Validation Rules

- `parent` must be a positive integer
- `sub_issues` must contain at least one entry
- Each `id` must be unique within the YAML file
- Each `blocked_by` element must reference an `id` that exists in `sub_issues`
- Circular dependencies are detected via DFS and cause an error — no Issues are created

## Skeleton Format

When `background` or `purpose` is omitted, the following skeleton is generated:

```markdown
## 背景

(TBD — XL parent #{parent} の sub-issue として {id} を起票)

## 目的

{title summary}

## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] TBD

### Post-merge

なし
```

Users can refine each sub-issue later using `/issue <N>`.

## Behavior

1. Reads the YAML file and validates the schema (aborts if invalid)
2. Detects circular dependencies via DFS (aborts if cycle found)
3. Creates each sub-issue via `gh issue create` with a skeleton body
4. Sets the parent-child relationship via the `add-sub-issue` GraphQL mutation
5. Sets `blocked_by` relationships via the `add-blocked-by` GraphQL mutation (second pass after all Issues are created)
6. Outputs a summary: Issue numbers, titles, and dependency graph

## Scope Exclusions

The following are out of scope for this feature and handled separately:

- **LLM-based auto-decomposition**: Automatic codebase analysis to generate the YAML file is a follow-up feature
- **Re-sync on YAML update**: Updating the YAML and re-syncing sub-issues is not supported; this mode handles initial bulk creation only
- **Dependency graph visualization**: Visual graph rendering is handled by `/audit progress` (see #588)
- **YAML linting details**: Validation errors output a message only (no auto-correction)

## Example: Nuxt → Next.js Migration

See `examples/decomposition/nuxt-to-next.yml` for a complete example with 3 sub-issues demonstrating `foundation → theme → page-home` dependency chain.

## Workflow Integration

After bulk creation, each sub-issue starts at `phase/issue`. Run `/spec <N>` on each to create an implementation spec, then `/auto <N>` to execute the full development workflow.

For XL parent issues, use `/audit progress <N>` to track sub-issue completion status and blocked dependencies.
