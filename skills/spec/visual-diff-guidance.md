---
type: domain
skill: spec
domain: visual-reproduction
load_when:
  capability: visual-diff
---

# Visual Diff Guidance (Domain File)

Prerequisite: Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` before reading this file and have `HAS_VISUAL_DIFF_CAPABILITY` already fetched.

This file is only loaded when `HAS_VISUAL_DIFF_CAPABILITY=true`. Enabled by declaring `capabilities:\n  visual-diff: true` in `.wholework.yml`.

## Purpose

Provides guidance for writing `visual_diff` verify commands in Spec files. Covers application scenarios, comparison with related verify commands, and Spec-time conventions for `visual_diff` arguments.

## When to Use `visual_diff`

### Primary Application Scenarios

Use `visual_diff` as the **primary** verify command for UI reproduction cases:

- **Framework migration**: Migrating an existing site to a new framework (e.g., WordPress → Next.js, jQuery → React) where layout fidelity to the original must be preserved
- **Figma design → implementation**: Implementing a UI from Figma specs where pixel-accurate reproduction of the reference design is required
- **CMS theme migration**: Replacing or updating a CMS theme where the visual output must match the previous theme across viewports and states

The key characteristic of these cases: a **reference URL** (live site, staging, or design artifact) exists and the **implementation URL** must visually match it.

For a complete methodology covering all three failure modes (narrow PASS criteria, spec vs. reference confusion, incomplete state coverage), see [docs/visual-reproduction.md](../../docs/visual-reproduction.md).

### Problem `visual_diff` Solves

Without `visual_diff`, AI verification of UI reproduction relies on `file_contains`, `getComputedStyle`-based `command` checks, and `browser_screenshot` (single URL subjective review). These approaches share a common weakness: **verification scope selection bias** — the AI confirms elements it chose to check, but cannot guarantee coverage of the entire layout. Regressions in unchecked areas pass silently.

`visual_diff` eliminates this bias by using `pixelmatch` to mechanically identify *every* pixel that differs between reference and implementation, then delegating interpretation to the `frontend-visual-review` sub-agent.

## Comparison with Related Verify Commands

### `visual_diff` vs. `getComputedStyle`-based `command` checks

| Aspect | `command "node -e getComputedStyle..."` | `visual_diff` |
|--------|----------------------------------------|---------------|
| Coverage | Individual elements (caller-selected) | Entire rendered layout |
| Bias | Selection bias (checks only what caller specifies) | Mechanically exhaustive (pixelmatch) |
| Use | Precision validation of a specific property | Comprehensive regression guard |
| Required tool | Node.js only | Playwright/browser-use + sharp + pixelmatch |

**Recommendation**: Use `getComputedStyle` checks as **supplements** for specific critical properties (e.g., exact font-size, z-index of an overlay). Use `visual_diff` as the **primary** comprehensive check.

### `visual_diff` vs. `rubric`

| Aspect | `rubric` | `visual_diff` |
|--------|----------|---------------|
| Input | git diff + Issue body | 3-panel images (Before / After / Diff highlight) |
| Scope | Semantic / textual correctness | Visual layout correctness |
| Output | PASS/FAIL on acceptance criteria intent | PASS/FAIL on pixel-level visual parity |
| Bias | Can be biased toward the implementation's own choices | Externally anchored to reference URL |

Use `rubric` for semantic correctness (e.g., "the PR adds the required configuration option"). Use `visual_diff` for visual correctness (e.g., "the migrated page looks identical to the original").

### `visual_diff` vs. `browser_screenshot`

| Aspect | `browser_screenshot "url" "description"` | `visual_diff "ref" "impl" --viewports --states` |
|--------|------------------------------------------|--------------------------------------------------|
| URLs | 1 (implementation only) | 2 (reference + implementation) |
| Coverage | Subjective AI visual review | Mechanically exhaustive pixel diff + AI interpretation |
| Scope | What the AI notices | Every highlighted pixel |
| Use case | Quick subjective check of a single page | Reproduction fidelity verification against a reference |

Use `browser_screenshot` for quick subjective checks where no external reference exists. Use `visual_diff` when an authoritative reference URL exists and reproduction fidelity is required.

## Writing `visual_diff` Acceptance Criteria in Specs

### Required Arguments (all mandatory, no defaults)

```html
<!-- verify: visual_diff "ref_url" "impl_url" --viewports="390,1440" --states="default,menu-open" -->
```

- **ref_url**: Reference URL (live site, staging, or design preview). Must be accessible at verify time.
- **impl_url**: Implementation URL (local dev server, preview deployment). Must be accessible at verify time. Use `{{base_url}}` placeholder if the URL varies by environment.
- **--viewports**: Comma-separated viewport widths in px. Choose viewports that represent key breakpoints for the design (e.g., `390` for mobile, `1440` for desktop).
- **--states**: Comma-separated state labels. These are **opaque labels** — the adapter treats them as strings only. Document what action sequence reaches each state in the Spec body or in a comment adjacent to the verify command.

### State Label Convention (opaque labels)

State labels are opaque identifiers. The caller (sub-agent invocation context) is responsible for defining what navigation or interaction steps correspond to each label. When writing Specs, document state semantics explicitly:

```markdown
<!-- verify: visual_diff "https://ref.example.com" "{{base_url}}" --viewports="390,1440" --states="default,menu-open" -->
State mapping:
- `default`: page at initial load, no user interaction
- `menu-open`: mobile hamburger menu tapped, nav drawer visible
```

State enumeration scaffolding (how to systematically identify which states to test) is addressed in Issue #438.

### Viewport Selection Guidelines

- Include at least one mobile viewport (e.g., `390` for iPhone 14) and one desktop viewport (e.g., `1440`)
- Add a tablet viewport (`768`) if the design has distinct tablet breakpoints
- Match viewports to the design system's declared breakpoints when available

### Capability Declaration Requirement

Before adding `visual_diff` verify commands to a Spec, confirm the project's `.wholework.yml` declares:

```yaml
capabilities:
  visual-diff: true
```

Without this declaration, `visual_diff` returns UNCERTAIN in `/verify` (capability gate in adapter-resolver). Add the declaration to `.wholework.yml` as part of the same PR that introduces `visual_diff` verify commands.
