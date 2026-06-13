# Issue #581: verify: Manual AC Post-Merge Tracking Mechanism Design

## Overview

### Problem Statement

When `/verify` completes with unchecked `verify-type: manual` post-merge conditions (especially conditions requiring real environment changes such as capability setting + execution in another project, production deployment confirmation, external API integration tests), the tracking becomes scattered. While the Issue remains in `phase/verify` via label transition, once the Issue is closed, "when to verify" and "who verified it" information disperses.

Specific example (#575): AC11 (`capabilities.workflow: true` + `/review --full` roundtrip in a different project) could not be confirmed in the same session due to the structural difficulty of "execution project = verification target project." While retaining `phase/verify` works for short-term follow-up, it is insufficient for tracking across the Issue lifecycle.

### Design Decision (ADR)

**Adopted: Option D** — Introduce `verify-type: observation event=<name>` as a new `verify-type` classification.

When the specified named event occurs (e.g., `event=pr-review-full`, `event=issue-583-merge`), the system automatically re-evaluates the condition. This provides:

- High traceability (explicit "when to verify")
- No Issue noise (vs. Option A's per-condition sub-Issue creation)
- Auto-consumable (event-driven re-evaluation vs. manual re-run)
- Foundation for meaningful `phase/verify` retention metrics — distinguishes "genuine WIP" from "awaiting observation" (#588)
- Gradual migration path from `verify-type: opportunistic` (unknown event values → warning + opportunistic fallback)

**Implementation is delegated to Issue #583** (`verify-type: observation event=<name>` grammar, syntax in verify commands, event definitions, per-skill firing points).

### Options Evaluated

| Option | Summary | Pros | Cons | Verdict |
|--------|---------|------|------|---------|
| **A. Sub-Issue Auto-Creation** | On `/verify` completion, create follow-up Issue per unchecked manual condition with `retro/verify` label | Highest traceability; rides Issue lifecycle | Issue noise; multiple manual conditions cause chain creation | Rejected |
| **B. Integrate with retro/verify flow** | Treat unchecked manual conditions as Improvement Proposals in existing retro-proposals flow | High integration with existing mechanism | Semantically different from improvement proposals; conflation degrades discoverability of both | Rejected |
| **C. Spec retrospective deferred section** | Record in `## Deferred Manual Verification` in Spec; visualization only | Minimal change | No active tracking; contradicts disposable Spec policy (`docs/tech.md § Spec-first`) | Rejected |
| **D. New verify-type: observation** | Introduce `verify-type: observation event=<name>`; auto-re-evaluate when named event fires | High traceability + no Issue noise + auto-consumable | Implementation cost (event type conventions, firing point definitions per skill) | **Adopted** |

### Rejected Alternatives

- **B (retro/verify integration)**: `retro/verify` label is for improvement proposals; conflating it with "unverified acceptance conditions" conflates two semantically distinct concepts, degrading the discoverability of both.
- **C (Spec deferred section)**: Spec is disposable (per `docs/tech.md § Spec-first`); long-term tracking in Spec contradicts this policy. Issue lifecycle is the more consistent home for tracking state.
- **A (pure form)**: Creating a sub-Issue per condition generates noise; observations tend to cluster by project/environment rather than by individual condition. Option D achieves the same traceability via event-driven re-evaluation at lower operational cost.

## Changed Files

- `docs/spec/issue-581-verify-manual-tracking.md`: new file — this document (serves as both the Spec and the ADR)

## Implementation Steps

1. This Spec file is the implementation artifact. The ADR content (problem statement, options comparison table, adopted decision, rationale, and rejected alternatives) is recorded in this document. No additional source files require changes. Implementation of the `verify-type: observation` grammar and event-firing mechanism is delegated to #583. (→ AC1, AC2, AC3, AC4)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/spec/issue-581-verify-manual-tracking.md" --> 設計決定文書 (Spec) が存在する
- <!-- verify: grep "Option D\|verify-type: observation\|採用方針" "docs/spec/issue-581-verify-manual-tracking.md" --> 採用方針 (Option D / verify-type: observation) が Spec に記載されている
- <!-- verify: grep "Rejected alternatives\|rejected\|不採用" "docs/spec/issue-581-verify-manual-tracking.md" --> Rejected alternatives (B / C / A 純粋形) の不採用理由が Spec に記載されている
- <!-- verify: rubric "docs/spec/issue-581-verify-manual-tracking.md records the ADR with: problem statement (manual verify-type tracking), 4 options (A/B/C/D) with pros/cons, the adopted option (D = verify-type: observation event=<name>) with rationale, and rejected alternatives with reasoning — and explicitly defers implementation to #583" --> ADR 形式 (problem / options / decision / rationale / rejected) が rubric 基準を満たし、実装は #583 に委譲することが明記されている

### Post-merge

- #583 の実装が本 ADR の方針 (Option D = verify-type: observation event=<name>) に沿っていることを #583 マージ時に確認 <!-- verify-type: observation event=issue-583-merge -->

## Notes

**Dual purpose of this file**: This document serves simultaneously as the Wholework Spec (implementation plan) and as the ADR (Architecture Decision Record) for the tracking mechanism design decision. The "implementation" of Issue #581 is the creation of this document itself.

**Relation to #583**: This Issue (design decision) → #583 (implementation). Not a parent-child relationship; logical sequential ordering. #583's implementation of `verify-type: observation event=<name>` should reference this document as the decision basis.

**Relation to #588**: Option D adoption is a prerequisite for meaningful `phase/verify` retention metrics. With `verify-type: observation`, the system can distinguish "genuine WIP (FAIL not yet fixed)" from "awaiting observation (conditions pending specific event)" — enabling the audit stats in #588 to report these separately.

**verify-type: observation trigger mechanism (deferred to #583)**: Events are named strings (e.g., `issue-583-merge`, `pr-review-full`). When an event fires, `/verify` (or `opportunistic-search.sh --event`) re-evaluates all conditions tagged with matching `event=<name>`. Unknown event names fall back to `opportunistic` classification with a warning.
