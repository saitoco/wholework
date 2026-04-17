# Literalism Audit Report: Implicit Generalization Patterns in SKILL.md

**Date**: 2026-04-17
**Scope**: 10 `skills/*/SKILL.md` files + 27 `modules/*.md` files
**Purpose**: Identify patterns that break under Claude Opus 4.7's literal interpretation model

---

## Summary

| Category | Count |
|----------|-------|
| Total findings | 16 |
| Inline rewrites applied | 9 |
| Follow-up issues created | 3 |

**Files audited**:
- Skills (10): auto, audit, code, doc, issue, merge, review, spec, triage, verify
- Modules (27): all files under `modules/`

**Detection criteria applied**:
1. Similarity-based abbreviations ("same as X", "apply the same")
2. Enumeration abbreviations ("etc.", "and so on")
3. Implicit "for each" / "repeat" without explicit enumeration
4. Inference-dependent conditions ("as appropriate", "if needed")

---

## Findings

### skills/

#### skills/issue/SKILL.md (6 findings — MEDIUM risk)

| Line | Pattern | Risk |
|------|---------|------|
| 290 | `Same as New Issue Creation Step 2.` (Existing Issue Refinement Step 4) | MEDIUM |
| 298 | `Same as New Issue Creation Step 4.` (Step 6) | MEDIUM |
| 302 | `same approach as New Issue Creation Step 5` (Step 7) | MEDIUM |
| 355 | `Run the standard sub-issue creation flow (New Issue Creation Step 8, procedures 2–8).` — step number off-by-one | MEDIUM |
| 363 | `Same as New Issue Creation Step 9.` (Step 12) | MEDIUM |
| 367 | `Same as New Issue Creation Step 10.` (Step 13) | MEDIUM |

**Issue**: All six cross-references point to steps defined earlier in the same document. A literal reader must locate those steps on each invocation. The off-by-one at line 355 is particularly fragile: the procedures 2–8 described are actually in Step 9 (Scope Assessment), not Step 8.

#### skills/review/SKILL.md (2 findings — HIGH + LOW)

| Line | Pattern | Risk |
|------|---------|------|
| 192 | `All three reviewer types use the same "wait → resolve" flow` — three types not enumerated | LOW |
| 310 | `same processing as full mode 10.2` (light mode step 10.0) — critical MUST-issue handling not repeated | HIGH |

**Issue at line 310**: Light mode step 10.0 defers entirely to full mode 10.2 for processing rules. Full mode 10.2 contains the critical requirement that MUST-labeled issues must be placed in General Comments (not section-level comments). Omitting this in light mode means a literal reader executing light mode will skip this requirement.

#### skills/triage/SKILL.md (1 finding — LOW)

| Line | Pattern | Risk |
|------|---------|------|
| 323 | `Use normalization table to convert to Value 1–5 (same table as backlog analysis)` | LOW |

**Issue**: The original text referenced an implicit cross-section normalization table. Fixed inline by adding an explicit normalization table with thresholds for each fallback level. Note: the section heading at lines 182 and 317 (`**Value scoring (same logic as backlog analysis):**`) still contains a residual cross-reference phrase; tracked for cleanup.

#### skills/doc/SKILL.md (2 findings — MEDIUM)

| Line | Pattern | Risk |
|------|---------|------|
| 253 | `using the same logic as the "Status Display" section` | MEDIUM |
| 444 | `using the same procedure as "Step 2 (Reverse-Generation Flow...)"` | MEDIUM |

**Issue**: Two cross-section references in the sync and init flows require navigating to different sections of the same large document. Under literal interpretation, the referenced procedures may be skipped. Tracked as follow-up #234.

#### skills/audit/SKILL.md (4 findings — LOW)

| Line | Pattern | Risk |
|------|---------|------|
| 397 | `Execute the same procedure as drift's Step 1` (fragility Step 1) | LOW |
| 434 | `Follow the same procedure as drift's Step 3` (fragility Step 3) | LOW |
| 572 | `same procedure as drift subcommand Step 5` (integrated Step 5) | LOW |
| 573 | `same procedure as fragility subcommand Step 5` (integrated Step 5, second item) | LOW |

**Issue**: Cross-subcommand references require navigating to a different subsection within the same large document. Under literal execution, this works only if step numbering is stable.

### modules/

#### modules/browser-adapter.md (2 findings — HIGH)

| Line | Pattern | Risk |
|------|---------|------|
| 67 | `same steps as above for Basic auth` (browser-use browser_screenshot) | HIGH |
| 87 | `same steps as above for Basic auth` (Playwright browser_screenshot) | HIGH |

**Issue**: "Same steps as above" refers to the Basic auth setup steps defined in `browser_check`, not repeated in `browser_screenshot`. Under literal interpretation, the model will look for the preceding lines and find only the screenshot-specific steps — the Basic auth configuration will be skipped entirely.

---

## Remediation

### Inline Rewrites

The following 9 locations were fixed directly in-file (simple, same-file expansion):

| File | Lines | Change |
|------|-------|--------|
| `skills/issue/SKILL.md` | 290 | Replaced `Same as New Issue Creation Step 2.` with explicit steps |
| `skills/issue/SKILL.md` | 298 | Replaced `Same as New Issue Creation Step 4.` with explicit steps |
| `skills/issue/SKILL.md` | 302 | Replaced `same approach as New Issue Creation Step 5` with explicit steps |
| `skills/issue/SKILL.md` | 355 | Fixed Step 8 → Step 9 reference and expanded sub-issue creation procedure |
| `skills/issue/SKILL.md` | 363 | Replaced `Same as New Issue Creation Step 9.` with explicit steps |
| `skills/issue/SKILL.md` | 367 | Replaced `Same as New Issue Creation Step 10.` with explicit steps |
| `skills/triage/SKILL.md` | 323 | Added normalization table inline in bulk classification section |
| `skills/review/SKILL.md` | 310 | Added explicit MUST-issue handling requirement from full mode 10.2 |
| `modules/browser-adapter.md` | 67, 87 | Expanded "same steps as above" with explicit Basic auth steps |

### Follow-up Issues

The following 3 issues were created for changes that require redesign or multi-section coordination:

| Issue | File | Pattern |
|-------|------|---------|
| #233 | `skills/audit/SKILL.md` | Expand 4 cross-subcommand "same procedure" references to inline steps |
| #234 | `skills/doc/SKILL.md` | Expand 2 cross-section references in sync/init flows |
| #235 | `skills/review/SKILL.md` | Enumerate all three reviewer types explicitly in "wait → resolve" flow description |
