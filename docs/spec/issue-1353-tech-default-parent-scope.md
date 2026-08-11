# Issue #1353: tech: model-effort-matrix の "Default parent" が指す対象を明示し対話セッションのモデル規定との誤読を解消

No `/spec` phase ran for this Size XS Issue — this file was created during the `/code` phase itself to hold the Consumed Comments / retrospective / Phase Handoff record. Requirements were read directly from the Issue body.

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — no Spec existed to deviate from; implementation followed the Issue body's Acceptance Criteria and Notes directly.

### Design Gaps/Ambiguities
- The Issue body's own investigation table undercounted skills without `model:` frontmatter: it claimed only `merge`/`verify` pin `model:` while "`auto` ほか 6 skill" lack it, but a direct check (`awk` over each `skills/*/SKILL.md` frontmatter) found `triage` also pins `model: sonnet`, and only `audit`/`auto`/`doc` (not 6 skills) actually have neither a `run-*.sh` wrapper nor `model:` frontmatter. The added clarification in `docs/tech.md` avoids repeating this inaccurate count — it names concrete example skills (`merge`, `triage`, `verify`) rather than asserting an exact "N skill" figure.

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Kept the "Default parent" term as-is and added a clarifying paragraph immediately after its definition, rather than renaming the term throughout the codebase — the Issue's own Auto-Resolved Ambiguity Points left this choice to implementation judgment, and a rename would touch #628/#877/#878/#903/#914/#1062 and their downstream reports, out of scope for a Size XS fix.
- Placed the clarification once, before the phase/effort table, rather than adding inline footnotes to each later mention (e.g. the `#1062` "Opus 5 default parent evaluation — deferred" note) — the term's scope is now defined at first use and later mentions inherit that scope.

### Deferred Items
- `docs/tech.md:121`'s "Opus 5 default parent evaluation — deferred (`#1062`)" note still uses the bare term without its own inline clarification. Left as-is: the Issue's Notes section suggested reviewing it "naturally" alongside this fix but did not require it, and the new scope paragraph already governs all later uses of the term within the same section.

### Notes for Next Phase
- None.
