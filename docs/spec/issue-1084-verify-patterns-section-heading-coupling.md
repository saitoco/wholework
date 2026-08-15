# Issue #1084: verify-patterns: section_contains の走査範囲が実装の見出しレベルを拘束する点を明記

No `/spec` phase ran for this Size XS Issue — this file was created during the `/code` phase itself to hold the Consumed Comments / retrospective / Phase Handoff record. Requirements were read directly from the Issue body.

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — no Spec existed to deviate from; implementation followed the Issue body's Acceptance Criteria directly.

### Design Gaps/Ambiguities
- The Issue body did not specify where in `modules/verify-patterns.md` to place the new guidance. Added it as a new numbered pattern (§29, following the existing sequential-numbering convention used by §1–§28) rather than as a new row in the §1 false-positive table — the content is closer to a design-time decision procedure (with a real precedent, four alternative patterns, and a decision procedure) than a single-row false-positive gotcha.
- Cross-checked the scanning-range wording against `modules/verify-executor.md`'s actual `section_contains`/`section_not_contains` definition ("from the specified heading line to just before the next heading of the same or higher level, or end of file") rather than re-deriving it from the Issue body's paraphrase, to keep the new section consistent with the SSoT.

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Documented the coupling as a new §29 pattern in `modules/verify-patterns.md`, using the #1060 `skills/merge/SKILL.md` Step 1 / `Post-Review Re-Verification Responsibility` example already cited in the Issue body as the "real example," rather than inventing a new illustrative example.
- Provided four alternative patterns (anchor on the finer-grained heading; switch to `file_contains`; use `rubric` with a supplementary structural check per §9; explicitly document the heading-level constraint when a coarse anchor is unavoidable) plus a short decision procedure, matching the Issue's Acceptance Criteria wording ("より粒度の細かい見出しを起点にする、file_contains に切り替える、rubric を使う").
- Left the pre-existing #1060 `skills/merge/SKILL.md` heading level (h4) unchanged — the Issue's scope is documentation-only (`modules/verify-patterns.md`); retrofitting #1060 to use pattern 1 (anchoring on the finer-grained heading) is out of scope here since its own AC and implementation are already merged.

### Deferred Items
- Issue's Post-merge AC ("`section_contains` を使う AC を含む Issue を `/spec` に通し、見出しレベルの制約が設計判断として意識されることを確認する") is `verify-type: manual` — left unchecked for post-merge manual confirmation, not actionable during `/code`.

### Notes for Next Phase
- None.
