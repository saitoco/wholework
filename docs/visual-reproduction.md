---
type: project
ssot_for:
  - visual-reproduction-methodology
---

English | [日本語](ja/visual-reproduction.md)

# Visual Reproduction Methodology

This document systematizes the principles and workflow for UI reproduction tasks — work that aligns a UI implementation with a reference (e.g., framework migration, Figma design → implementation, CMS theme migration).

## 1. Failure Modes

Three failure modes recur in real-world UI reproduction projects:

### A. Narrow PASS Criteria (Verification Scope Selection Bias)

The verifier checks a subset of elements (computed styles, specific components) and declares the subset "PASS." This is then misread as "entire layout PASS."

**Root cause**: The verifier selects what to check, creating selection bias. Elements the verifier did not choose to inspect are never validated.

### B. Spec vs. Reference Confusion (Reference Priority Violation)

The implementation follows a design document (design baseline, Figma export, CMS spec) that diverges from the live reference. The verifier treats the spec document as ground truth, but the authoritative reference differs.

**Root cause**: The reference > spec principle is violated. When the two conflict, the live reference is the source of truth.

### C. Incomplete State Coverage (State Cartesian Product Gap)

Only the default (initial load) state is verified. Bugs in interactive states (hover, menu-open, focused, error) or navigation contexts (inner page, logged-in) go undetected.

**Root cause**: State enumeration is not systematic; the verifier stops at the most visible state.

## 2. Principles

### Principle 1 — AI Vision Review Is the Primary Evidence

`visual_diff` (3-panel composite: Before / After / Diff highlight) combined with the `frontend-visual-review` sub-agent is the **primary evidence source** for UI reproduction verification. Computed style checks (`getComputedStyle`, `file_contains`) are supplements for specific critical properties only.

Rationale: Only mechanical pixel comparison followed by AI interpretation of the diff image can eliminate selection bias (Failure Mode A).

### Principle 2 — Reference Takes Priority Over Spec Documents

When the live reference URL and a spec document (design baseline, Figma spec) conflict, the **live reference URL is authoritative**.

Apply this rule at every phase:

- **Spec phase**: Derive acceptance criteria from the reference URL, not from spec documents.
- **Code phase**: When an implementation decision is unclear, check the reference URL directly.
- **Verify phase**: `visual_diff` compares against the reference URL; spec documents are not consulted to override pixel-level evidence.

### Principle 3 — State × Context: Complete Cartesian Product

Enumerate all (state × viewport) combinations and verify each one. A "PASS" declaration is only valid when the `frontend-visual-review` sub-agent explicitly outputs `zero_gaps_detected: true` for every combination in scope.

State dimensions to enumerate (non-exhaustive):

| Dimension | Examples |
|-----------|---------|
| Interaction state | default, hover, active, focus, disabled |
| Navigation context | top page, inner page, modal open |
| User state | anonymous, logged-in, admin |
| Viewport | mobile (390 px), tablet (768 px), desktop (1440 px) |

## 3. Tooling Requirements

| Tool | Role |
|------|------|
| Playwright | Capture screenshots of reference and implementation URLs at each viewport and state |
| sharp | Compose the 3-panel composite image (Before / After / Diff highlight) |
| pixelmatch | Mechanically identify per-pixel differences between reference and implementation |
| `visual_diff` verify command | Orchestrate screenshot capture → composite → `frontend-visual-review` invocation |
| `frontend-visual-review` sub-agent | Interpret the 3-panel composite and output `zero_gaps_detected: true/false` with gap enumeration |

`visual_diff` is declared in `.wholework.yml` under `capabilities.visual-diff: true`. Without this declaration, `visual_diff` returns UNCERTAIN in `/verify`.

## 4. Workflow

### Issue Phase

- Observe the live reference and the current implementation side by side.
- List initial differences (layout, color, spacing, typography) as the starting set of acceptance criteria.
- Identify the relevant viewports and states to cover.

### Spec Phase

- Use the state enumeration scaffold from `skills/spec/visual-state-enumeration.md` to systematically derive the full (state × viewport) set.
- Write acceptance criteria primarily as `visual_diff` verify commands:

  ```html
  <!-- verify: visual_diff "https://ref.example.com/page" "{{base_url}}/page"
       --viewports="390,1440" --states="default,menu-open" -->
  ```

- Supplement with `getComputedStyle`-based `command` checks only for critical individual properties.

### Code Phase

- Implement the fix against the reference URL (not spec documents).
- After each significant change, take a quick screenshot of both URLs to catch regressions early.

### Verify Phase

- Run `visual_diff` for every (state × viewport) combination in scope.
- A combination is PASS only when `frontend-visual-review` outputs `zero_gaps_detected: true`.
- A PASS declaration for the entire task requires `zero_gaps_detected: true` across **all** combinations.

## 5. Anti-patterns

### Anti-pattern 1 — Declaring All PASS Without `zero_gaps_detected: true`

**Problematic**: "All 6 checks PASS" declared after reviewing computed styles for selected elements.

**Why it fails**: No AI agent explicitly stated `zero_gaps_detected: true`. The checks cover only selected elements; the rest of the layout is unverified (Failure Mode A).

**Correct**: Each `visual_diff` run must include an explicit `zero_gaps_detected: true` output from `frontend-visual-review`. The PASS declaration is only valid after all (state × viewport) combinations yield this output.

### Anti-pattern 2 — Prioritizing Spec Documents Over the Reference

**Problematic**: "The design baseline says font-size: 16px, so I kept it at 16px even though the reference renders 14px."

**Why it fails**: The reference takes precedence (Principle 2). If the live reference renders 14px, the implementation must match 14px regardless of what the spec document says.

**Correct**: Compare against the reference URL directly. If the reference and spec document conflict, note the discrepancy in the Spec body and follow the reference.

### Anti-pattern 3 — Verifying Only the Default State

**Problematic**: `visual_diff` run for `--states="default"` only; interactive states (menu-open, focused, error) not tested.

**Why it fails**: Bugs in non-default states go undetected until they surface in production (Failure Mode C).

**Correct**: Enumerate all (state × viewport) combinations in the Spec phase using `visual-state-enumeration.md`. Run `visual_diff` for every combination.

## 6. Exemplar References

The following illustrates a well-formed `visual_diff` acceptance criterion for a generic framework migration task. All URLs and names are fictional.

**Scenario**: Migrating `example-shop.com` from WordPress to Next.js. The reference is the live WordPress site.

**Spec excerpt** (abbreviated):

```markdown
## Acceptance Criteria

### Pre-merge

- [ ] <!-- verify: visual_diff "https://example-shop.com/" "{{base_url}}/"
         --viewports="390,768,1440" --states="default" -->
     Home page visual parity across all viewports
- [ ] <!-- verify: visual_diff "https://example-shop.com/products/widget"
         "{{base_url}}/products/widget"
         --viewports="390,1440" --states="default,image-zoomed" -->
     Product detail page including zoom state
- [ ] <!-- verify: visual_diff "https://example-shop.com/" "{{base_url}}/"
         --viewports="390" --states="nav-open" -->
     Mobile navigation drawer visual parity

State mapping:
- `default`: page at initial load, no user interaction
- `image-zoomed`: product image clicked, zoom overlay active
- `nav-open`: mobile hamburger icon tapped, navigation drawer visible
```

**Verify output example** (expected for PASS):

```
visual_diff: Home page (default, 390px) — zero_gaps_detected: true
visual_diff: Home page (default, 768px) — zero_gaps_detected: true
visual_diff: Home page (default, 1440px) — zero_gaps_detected: true
visual_diff: Product detail (default, 390px) — zero_gaps_detected: true
visual_diff: Product detail (image-zoomed, 390px) — zero_gaps_detected: true
visual_diff: Product detail (default, 1440px) — zero_gaps_detected: true
visual_diff: Product detail (image-zoomed, 1440px) — zero_gaps_detected: true
visual_diff: Nav drawer (nav-open, 390px) — zero_gaps_detected: true
```

All 8 combinations yield `zero_gaps_detected: true` → full PASS declaration is valid.
