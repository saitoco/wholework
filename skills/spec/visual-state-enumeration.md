---
type: domain
skill: spec
domain: visual-reproduction
load_when:
  capability: visual-diff
---

# Visual State Enumeration (Domain File)

Prerequisite: Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` before reading this file and have `HAS_VISUAL_DIFF_CAPABILITY` already fetched.

This file is only loaded when `HAS_VISUAL_DIFF_CAPABILITY=true`. Enabled by declaring `capabilities:\n  visual-diff: true` in `.wholework.yml`.

## Purpose

Scaffold systematic state enumeration for UI reproduction Issues. Generates a `## State Enumeration` section in the Spec covering the full Cartesian product of `(viewport × page × interactive_state × navigation_context)`, then auto-generates `visual_diff` verify command AC entries for each combination.

This eliminates the "state coverage blind spot" failure mode: building a verify plan from only the `default` state (idle / scroll-top) and discovering `menu-open`, `active-link`, or viewport-specific bugs only after PR merge.

## Input

- `HAS_VISUAL_DIFF_CAPABILITY=true` (declared in `.wholework.yml`)
- Issue body: target pages, interaction flows, and any state hints

## Processing Steps

### Step 1: Resolve State List

Resolve the state list using a 3-tier priority order:

**Priority 1 — Project-local Domain file (highest)**

Glob `.wholework/domains/spec/visual-state-enumeration.md`. If the file exists, extract the state list from its frontmatter or body list. The file may declare states in either format:

```yaml
# frontmatter format
states:
  - default
  - hover
  - focus
  - menu-open
  - active-link
```

```markdown
<!-- body list format -->
- default
- hover
- focus
- menu-open
- active-link
```

Use the extracted list and skip Priority 2 and 3.

**Priority 2 — AskUserQuestion (interactive mode only)**

If no project-local file exists and the skill is running in interactive mode (no `--non-interactive` flag), ask:

> Which interactive states should be covered? (Select all that apply, or enter custom states)

Offer the bundled default list as pre-selected options.

If running in `--non-interactive` mode, skip to Priority 3.

**Priority 3 — Bundled default list**

```
default    (initial page load, no interaction)
hover      (pointer over interactive element)
focus      (keyboard focus on interactive element)
menu-open  (navigation drawer or dropdown expanded)
```

### Step 2: Resolve Viewport List

Resolve the viewport list following the same 3-tier order as Step 1.

Project-local override format (`.wholework/domains/spec/visual-state-enumeration.md`):

```yaml
viewports:
  - 390
  - 768
  - 1440
```

Bundled default:

```
390   (mobile — iPhone 14)
1440  (desktop)
```

Add `768` (tablet) when the Issue body mentions tablet breakpoints or the design system declares distinct tablet styles. This conditional applies only when Priority 1 (project-local override) and Priority 2 (AskUserQuestion) are both skipped; a project-local viewport declaration takes precedence and is used as-is.

### Step 3: Extract Pages and Navigation Contexts from Issue Body

Read the Issue body and extract:

- **Pages**: URLs or route paths the reproduction covers (e.g., `/`, `/about`, `/blog`)
- **Navigation contexts**: Link states relevant to the page (e.g., `none` for pages without nav highlighting, `home-active` when on the home page, `about-active` when on the about page)

When the Issue body does not specify pages, default to the root page `/` with navigation context `none`.

### Step 4: Generate `## State Enumeration` Section

Append the following section to the Spec being built. Use the resolved lists from Steps 1–3.

```markdown
## State Enumeration

### Viewports
- {resolved viewport list, one per line as `- {px}`}

### Pages
- {extracted pages, one per line as `- {route}`}

### Interactive States
- {resolved state list, one per line as `- {state}: {description}`}

### Navigation Contexts
- {extracted nav contexts, one per line as `- {context}: {description}`}

### State Mapping
<!-- Document the action sequence required to reach each interactive state -->
{state label}: {action sequence description}
{state label}: {action sequence description}
```

### Step 5: Auto-generate AC Entries

For each combination in `viewport × page × interactive_state × navigation_context`, emit one AC entry in the Spec's `## Acceptance Criteria > Pre-merge` section:

```html
<!-- verify: visual_diff "{{ref_url}}{page}" "{{base_url}}{page}" --viewports="{viewport}" --states="{state}" -->
```

**Collapsing rules** (reduce entry count before emitting):

1. **Viewport collapse**: When multiple viewports share the same state and navigation context for a page, combine into one entry: `--viewports="390,1440"`.
2. **State collapse**: When all navigation contexts for a page and viewport share the same state behavior, collapse navigation contexts into a single representative entry.
3. **Page collapse**: When all pages share the same state and viewport combination without page-specific variation, combine into one multi-page entry if `visual_diff` supports it; otherwise emit one entry per page.

Apply collapsing conservatively — when in doubt, emit separate entries to preserve explicit coverage.

**Placeholder convention**:
- `{{ref_url}}`: Replaced by the reference URL at verify time (declared in `.wholework.yml` or Issue body)
- `{{base_url}}`: Replaced by the implementation URL at verify time (resolved via `LOCAL_BASE_URL` or `http://localhost:3000`)

**State label convention**: State labels in `--states=` are opaque identifiers (see `skills/spec/visual-diff-guidance.md` § State Label Convention). Navigation context is encoded into the state label where distinct visual behavior is expected (e.g., `menu-open@home-active` represents the `menu-open` state while the home navigation link is active). Document the action sequence for each combined label in the `### State Mapping` subsection generated in Step 4.

### Step 6: Output

The generated content is incorporated into the Spec at two locations:

1. A new `## State Enumeration` section (from Step 4) — placed after `## Implementation Steps` and before `## Verification`
2. AC entries (from Step 5) — appended to the `## Acceptance Criteria > Pre-merge` list

After generating, inform the user:

> State Enumeration scaffold generated: {N} viewports × {M} pages × {P} states × {Q} nav contexts = {total} combinations → {emitted} AC entries (after collapsing).
