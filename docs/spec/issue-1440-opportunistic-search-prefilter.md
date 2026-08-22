# Issue #1440: opportunistic-search: skill=verify 候補集団の構造的過大を調査し pre-filter を検討

## Overview

L3 session `35820-1787388297` (2026-08-22) observed that `scripts/opportunistic-search.sh`'s `skill=verify` candidate population resolved SKIP in essentially every judgment across 7 `/verify` invocations in that session. This Issue asks to (1) confirm whether that high SKIP rate generalizes beyond the single originating session, and (2) if confirmed, implement at least one pre-filter in `scripts/opportunistic-search.sh` that excludes structurally-unsatisfiable candidates before the existing `gh issue view` / `emit_event` calls.

## Changed Files

- `scripts/opportunistic-search.sh`: add an XL-scope pre-filter gate, active in opportunistic mode (`--event` unset) only
- `tests/opportunistic-search.bats`: add test cases covering the new gate's include/exclude/backward-compatible/event-mode-unaffected behavior
- `modules/observation-trigger.md`: clarify that `Condition Check Gate (when=)` also gates `verify-type: opportunistic` tags (already true per `modules/verify-classifier.md`'s existing attribute table, but this section's own problem statement and examples are worded around `event=`/observation mode only); cross-reference this Issue's SKIP-rate measurement from the existing `Conditions That Cannot Be Pre-Excluded` section
- [Steering Docs sync candidate] keyword `"opportunistic-search.sh"` skipped: matched 94 files (no discriminating power) — `modules/observation-trigger.md` is listed above from direct investigation instead, not this mechanical search

## Implementation Steps

1. In `scripts/opportunistic-search.sh`, immediately after the existing `--facts <path>` resolution block that computes `FACT_TOKENS_LOWER` (the block ending with the `FACT_TOKENS_LOWER=$(jq -r '[.issues[].fact_tokens[]?] | unique | .[]' "$FACTS_PATH" ...)` assignment, right before the `resolve_run_facts()` function definition), add:
   - A new `HAS_XL_FACTS=false` variable, set to `true` only when `[ -n "$FACTS_PATH" ] && [ -f "$FACTS_PATH" ]` and `jq -e 'any(.issues[]?; .route == "xl")' "$FACTS_PATH" >/dev/null 2>&1` succeeds. Fail-open: any `jq` failure (missing `jq`, malformed JSON, empty `.issues[]`) leaves `HAS_XL_FACTS=false`, i.e. the gate stays disabled (unconditional match) — the same fail-open direction as every other `--facts`-derived gate in this script (`FACT_TOKENS_LOWER`, `when=route:` clauses). Rationale for fail-open (not fail-closed): a JSON parse glitch must never silently suppress a candidate that could otherwise be judged this run.
   - A new `XL_SCOPE_PATTERN='XL (Issue|[Ss]ub-issue)|並列.{0,20}[Ss]ub-issue|[Ss]ub-issue.{0,20}並列'` constant (ERE, matched via `grep -E`).
   - A comment explaining the rationale: a candidate whose condition text names an XL/parallel-sub-issue scenario can only be judged non-SKIP when this run's own facts show XL route processing actually occurred; excluding it otherwise avoids a guaranteed-SKIP downstream `emit_event` call. Cite Issue #1440 for the measurement backing this (→ acceptance criteria B)
2. In the same file's per-candidate condition loop, immediately after the existing `FACT_MATCHED` computation block (the block ending with `done <<< "$FACT_TOKENS_LOWER"`, right before the `# Condition check gate: skip lines whose keyword=` comment), add a new gate:
   ```bash
   # XL-scope pre-filter (opportunistic mode only): skip candidates whose condition text
   # names an XL/parallel-sub-issue scenario when this run's own facts show no XL route
   # processing occurred -- see HAS_XL_FACTS/XL_SCOPE_PATTERN above. Event mode already has
   # an equivalent, more general opt-in mechanism (when=route:xl, see
   # modules/observation-trigger.md) and is left untouched here.
   if [ -z "$EVENT_NAME" ] && [ "$HAS_XL_FACTS" = false ]; then
       if echo "$CONDITION" | grep -qE "$XL_SCOPE_PATTERN"; then
           continue
       fi
   fi
   ```
   Verify no existing `@test` in `tests/opportunistic-search.bats` relies on condition text matching `XL_SCOPE_PATTERN` without also intending exclusion (grep the test file for `XL` / `sub-issue` before finalizing) (after 1) (→ acceptance criteria B)
3. Add new `@test` cases to `tests/opportunistic-search.bats` (bash 3.2+ compatible, follow the existing `fact gate:`/`when gate:` test conventions in the same file — mock `MOCK_ISSUE_LIST`/`MOCK_ISSUE_BODY_<N>`/a `--facts` JSON temp file):
   - `XL-scope gate: XL keyword match with facts showing xl route includes the issue` — a candidate whose condition text matches `XL_SCOPE_PATTERN`, called with `/verify --facts <path>` where the facts JSON has an issue with `"route":"xl"` → candidate is returned
   - `XL-scope gate: XL keyword match with facts showing no xl route excludes the issue` — same condition text, facts JSON has no `"route":"xl"` entry → `[]`
   - `XL-scope gate: condition without XL keyword matches unconditionally regardless of facts` — a candidate whose text does not match `XL_SCOPE_PATTERN`, facts show no xl route → candidate is still returned (confirms the gate is scoped to matching text only)
   - `XL-scope gate: ignored in event mode` — same XL-keyword condition text tagged `verify-type: observation event=auto-run`, called with `--event auto-run --facts <path>` (no xl route in facts) → candidate is still returned (gate does not apply to event mode)
   Existing suite must continue to PASS alongside these new cases (after 2) (→ acceptance criteria B)
4. In `modules/observation-trigger.md`'s `## Condition Check Gate (when=)` section, add a short paragraph (after the existing "Declarable axes" table, before "**Arguments table addition**") stating that this gate applies uniformly to `verify-type: opportunistic` tags as well as `verify-type: observation event=...` tags — consistent with `modules/verify-classifier.md`'s existing `scripts/opportunistic-search.sh` attribute row (`verify-type: opportunistic` + `keyword=`/`config=`/`when=`) — even though this section's own problem statement and worked examples are `event=`-centric. In the `## Conditions That Cannot Be Pre-Excluded` section, add one bullet or closing sentence citing Issue #1440's measurement (SKIP rate ~99% across 22 sessions for `skill=verify` opportunistic candidates; investigation found each surviving candidate describes a distinct narrow precondition, reinforcing that dispatch-and-let-SKIP is this population's expected steady state, not a defect) (parallel with 1, 2, 3) (→ acceptance criteria A, B)

## Verification

### Pre-merge
- <!-- verify: rubric "Specの Notes セクションに、skill=verify の opportunistic-search 候補の SKIP 率が複数セッションにわたって測定され、その結果 (高いことが確認された、または再現しなかった) が記録されている" --> SKIP 率の複数セッション測定結果が Spec の Notes に記録されている
- <!-- verify: rubric "SKIP 率が高いことが確認された場合、scripts/opportunistic-search.sh に構造的に判定不能な候補を事前に除外するフィルタが実装されている" --> XL-scope pre-filter が scripts/opportunistic-search.sh に実装されている

### Post-merge

なし

## Notes

### SKIP rate measurement (acceptance criteria A)

Measured directly from committed `docs/sessions/*/events.jsonl` (session-scoped, durable copies of `.tmp/auto-events.jsonl` — see `docs/structure.md`). `.tmp/auto-events.jsonl` itself currently holds only this session's own 1 line and 0 `opportunistic_verify_result` events, so it cannot answer a "multiple sessions" question on its own; the committed per-session files are the equivalent analysis the AC's parenthetical explicitly allows for.

- **Overall** (all skills, all sessions with recorded events): 6560/6757 `opportunistic_verify_result` events resolved SKIP (**97%**).
- **`skill=/verify` specifically**: 3259/3265 events resolved SKIP (**99.8%**), spanning **22 distinct sessions** from 2026-08-07 to 2026-08-22. 20 of the 22 sessions were 100% SKIP; the remaining 2 were 96%/99%.
- **Finding: CONFIRMED.** The near-100% SKIP rate observed in the originating session (`35820-1787388297`) is not session-specific noise — it is the steady-state behavior of `skill=verify` opportunistic-search candidates across three weeks of production sessions.
- 8 historical non-SKIP (`PASS`) events exist for `skill=/verify` opportunistic mode (0.25% of 3265). Cross-referencing each against its own session's `phase_start` issue set: only 1 of 8 (`#1407` in session `91663-1787272961`) was itself an Issue the session had processed; the other 7 PASSed on Issues the session never touched. This matters for the design decision below.

### Investigated pre-filter directions (acceptance criteria B)

All three literal-pattern directions from the Issue's Proposal were checked against the live population (119 Issues carrying an unresolved `verify-type: opportunistic` condition; 102 unresolved opportunistic AC lines across them, fetched and scoped to `## Post-merge` the same way `opportunistic-search.sh` itself scopes):

| Direction | Real hits in live population | Notes |
|---|---|---|
| 1. Repository-scope (different repo named in condition text) | 0/102 | No candidate names another repository. The Background's "tofas repo" example was not found verbatim in the current population — likely illustrative, or drawn from a since-resolved/different-mode candidate in the originating session, not a literal quote from a still-open condition. |
| 2. XL-only scope (condition requires XL/parallel-sub-issue scenario, session facts show no XL processing) | 2/102 (`#319`, `#140`) | Both real, unambiguous XL-parallel-sub-issue conditions. **Adopted** (Implementation Steps 1-2). Neither currently mentions any of the 5 calling skill names (`/issue`/`/spec`/`/code`/`/review`/`/verify` — they mention `/auto`, which never calls `opportunistic-search.sh` directly), so today's measured live effect on `skill=/verify`'s own candidate count is 0. Implemented anyway because it is real (non-zero), categorically safe (see rejected alternative below), and directly the Issue's own suggested direction; it will suppress this exact waste pattern the moment such a condition is ever authored against a calling skill. |
| 3. User-confirmation-required (condition requires literal human confirmation) | ~1/102 (broadened search: `#494`, "目視確認") | Also does not mention any calling skill name (targets `/issue`). Near-zero yield is structurally expected: conditions requiring human confirmation are supposed to be tagged `verify-type: manual`, not `opportunistic`, per `modules/verify-classifier.md`'s existing classification criteria — the `opportunistic` population is pre-filtered against this category by construction. **Not implemented**: no evidence of real, current waste from this category to justify the change. |

**Rejected alternative** (own investigation, not from the Issue's Proposal): excluding an opportunistic candidate whenever its own Issue number is absent from the current run's `--facts` `issues[].number` — a direct adaptation of `modules/run-fact-matching.md`'s Rule 1 (Issue #1321), which the Issue's Proposal direction 2 explicitly suggested evaluating. Empirically invalidated: of the 8 historical `skill=/verify` opportunistic PASS events, 7 were for Issues the firing session never itself processed (see measurement above) — this filter would have silently discarded 7 of 8 known-good real judgments. Rejected as unsafe. The asymmetry with Rule 1 (where Issue-absence is the dominant explanatory factor, 56% share) is explained by a difference in what the two mechanisms' conditions assert: run-fact-matching's candidates assert claims about a specific Issue's own processing; `opportunistic-search.sh`'s `verify-type: opportunistic` candidates by design assert general, skill-repeatable behavioral claims that a later, unrelated Issue's `/verify` run can legitimately confirm (the mechanism's whole reason to exist) — Issue-identity is not a valid proxy for satisfiability here.

### Design grounding: `when=` already applies to opportunistic mode

`modules/verify-classifier.md`'s existing attribute reference table already documents `verify-type: opportunistic` + `when=` as a supported combination, and the `opportunistic-search.sh` code itself gates `keyword=`/`config=`/`when=` unconditionally (no `$EVENT_NAME` check) — only the `--facts` token-relevance *reorder* (a separate, non-excluding mechanism) is opportunistic-mode-only. This means Issue authors already have a general, tested-after-Implementation-Step-3 tool (`when=route:xl`, `when=mode:batch`, etc.) available for marking future opportunistic conditions with a context precondition, without waiting on this Issue's narrow auto-detecting keyword pattern. `modules/observation-trigger.md`'s own `Conditions That Cannot Be Pre-Excluded` section already documents, as accepted project philosophy, that most narrow single-scenario conditions are not expected to be pre-excludable and that dispatch-and-SKIP is correct — this Issue's measurement is added there as a second, independent data point (skill=verify opportunistic mode, not just the observation-mode measurements that section already cites).

### Issue-type classification (fail-safe critical / audit-type checks)

- **Fail-safe critical**: `scripts/opportunistic-search.sh` is not a merge gate or an accept/reject validator, but it does already use `fail_open()`-equivalent patterns (`|| true`, `2>/dev/null`) throughout. The new `HAS_XL_FACTS` gate follows the same fail-open convention on parse failure (see Implementation Step 1) for consistency, not because the script itself is judged fail-safe critical.
- **Audit/investigation-type**: judged **no** — this Issue's core deliverable is a code change (a pre-filter), not a per-item classification report consumed by a later automated process. The investigation above (candidate sampling, hit-counting) was conducted to ground that code change, not as the Issue's own artifact.

### Auto-Resolve Log (non-interactive mode)

- Carried over from `/issue`'s own Auto-Resolve Log (see Consumed Comments below): the "multiple sessions" threshold for acceptance criteria A was deliberately left undefined in the Issue body, deferring to whatever this Spec's own measurement produced. Resolved: 22 sessions (see measurement above) — well beyond any reasonable reading of "multiple."

## Code Retrospective

### Deviations from Design
- None. All 4 Implementation Steps were applied as written: the `HAS_XL_FACTS`/`XL_SCOPE_PATTERN` gate and per-candidate `continue` check landed at the exact anchor points the Spec specified in `scripts/opportunistic-search.sh`; the 4 new `tests/opportunistic-search.bats` cases use the same test names and scenario shapes listed in Implementation Step 3; the `modules/observation-trigger.md` paragraph and closing-sentence additions landed at the exact section anchors in Implementation Step 4.

### Design Gaps/Ambiguities
- None found during implementation. The Spec's own Notes section had already resolved the two open questions (SKIP-rate confirmation, pre-filter direction selection) before this phase started, so no new ambiguity surfaced.

### Rework
- None.

### Smoke Test
- N/A — Spec has no `## Smoke Test` section.

## Consumed Comments

- saito (MEMBER, first-class): `/issue 1440 --non-interactive` Issue Retrospective comment (2026-08-22T15:17:30Z) — confirms Background facts were codebase-verified, AC checkbox/format checks passed, no open blockers, no title drift, and records the Auto-Resolve Log for the "multiple sessions" threshold deferred to this Spec's own measurement (see Auto-Resolve Log above). https://github.com/saitoco/wholework/issues/1440#issuecomment-5381115897
- No new comments since last phase (code phase cutoff: 2026-08-22T15:44:41Z, the `phase/ready` label assignment timestamp).

## review retrospective

### Spec vs. implementation divergence patterns

- Not an implementation deviation, but a Spec-authoring gap: Implementation Step 1 explicitly specified `jq -e 'any(.issues[]?; .route == "xl")'`, and the `/code` phase implemented it exactly as written. The bug (checking `.route` instead of `.size` for XL-ness) originated in the Spec itself — `collect-run-facts.sh`'s actual schema (`route: pr|patch|operate|unknown`, `size: XS/S/M/L/XL`) was never cross-checked against the field name chosen for the new gate before it was written into the Implementation Steps. `/review`'s own Parser/Validator Edge Case Pre-check (real script execution against fixture inputs) did not catch this either, since it exercises the new code's behavior given its own inputs correctly — the bug is a field-name/schema mismatch invisible to black-box execution testing and only surfaced via the review-light agent's independent cross-reference against `collect-run-facts.sh`'s source and `modules/run-fact-matching.md`'s documented schema. Future Specs introducing a new `--facts`-derived gate should explicitly cite the producing script's field names/enum values in the Implementation Step text (not just "route" as a bare word), and `/spec`'s own investigation phase should grep the actual producer script's field names before finalizing a jq query against it.

### Recurring issues

- None found — this is the first instance of a Spec-originated field-name mismatch surfacing in `/review` for this repository as far as this session's context shows.

### Acceptance criteria verification difficulty

- AC1's `rubric` verify command references "Spec の Notes セクション" content, but `modules/verify-executor.md`'s rubric grader input scope explicitly excludes Spec files (Issue=WHAT / Spec=HOW separation). This AC is structurally unverifiable via `rubric` as authored — `/review`'s Step 8 correctly classified it UNCERTAIN rather than PASS, even though the referenced content is genuinely present in the Spec. This is a real, if narrow, blind spot in how "investigation/measurement" style acceptance criteria interact with the rubric mechanism's designed Spec exclusion. Recommend: a future Issue to establish a documented convention for ACs whose primary evidence is Spec-only investigation output (e.g., require the Issue body or PR body to carry a copy/summary of the measurement instead of the Spec, or introduce an explicit opt-in mechanism analogous to the `rubric` "files explicitly named" exception that can name a Spec file for this narrow case).
- Separately: `scripts/check-language-convention.py`'s CJK exclusion only strips double-quoted string content, not single-quoted. A legitimate non-prose usage (a bash regex literal that must contain Japanese characters as data, not accidental transcription) was flagged and required a quoting-style change to pass CI. Not a blocking issue for this PR (fixed inline), but a candidate for a small checker enhancement (extend the exclusion to single-quoted strings too) if this pattern recurs.

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Fixed both MUST issues found: (1) `HAS_XL_FACTS` checked the wrong facts JSON field (`.route == "xl"` instead of `.size == "XL"`) — corrected per `collect-run-facts.sh`'s actual schema, with the 4 new bats fixtures updated to match; (2) `Language Convention check` CI failure — `XL_SCOPE_PATTERN` switched from single- to double-quoted bash string literal (no semantic change) so `check-language-convention.py`'s CJK exclusion applies.
- AC1's rubric verdict recorded as UNCERTAIN (not reverted from its existing `[x]` checked state) despite being structurally unverifiable via the rubric grader's documented Spec-exclusion rule, since the underlying content was independently confirmed true by direct Spec inspection and reverting a `/code`-checked box over a mechanism technicality was judged more disruptive than valuable; flagged as a SHOULD-level verify-command-quality finding instead.
- The pre-existing greedy-`sed` comment-stripping bug found via edge-case execution (line 413) was left unfixed as out-of-scope for this diff (CONSIDER-level, recommended as a follow-up Issue) since it is not part of this PR's own new lines.

### Deferred Items
- Follow-up Issue candidate: replace `scripts/opportunistic-search.sh`'s greedy `sed 's/ *<!--.*-->//g'` (line 413) with a non-greedy or iterative per-comment-span strip, so condition text between two separate HTML comments on the same Issue body line is not silently discarded.
- Follow-up Issue candidate: establish a documented convention for `rubric` acceptance criteria whose primary evidence lives only in the Spec (currently structurally unverifiable, see AC1 above).

### Notes for Next Phase
- `/merge` should find both Pre-merge AC checkboxes in their pre-existing state (AC1 unchecked note applies only to `/review`'s own verification table, not to the Issue body checkbox, which was left unchanged — see AC verification results in the posted PR review for the full explanation) and both MUST review findings resolved in commit `bb14b688`.
- Full bats suite (2005/2005) and `check-language-convention.py` both pass on the current PR branch tip after the fix commit.
