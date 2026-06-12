# De-prescription Audit Report — Spec Skill Reasoning Steps

## Background

This report documents the findings of a spike to evaluate whether de-prescribing reasoning steps
in `skills/spec/SKILL.md` (replacing sub-step enumeration with goal+constraints presentation)
improves spec quality and token efficiency when executed by Fable 5 (`claude-fable-5`).

Scope: `skills/spec/SKILL.md` reasoning steps only. Mechanical steps (label transitions,
gh commands, file paths, ordering invariants) are not candidates for de-prescription.

Context: Issue #561. Background in `docs/reports/claude-fable-5-impact-strategy.md` §4.3.
Prerequisite #559 (`run-spec.sh --fable`) is CLOSED.

---

## Step Classification

### Mechanical Steps (not candidates — preserve as-is)

These steps have deterministic behavior and must remain prescriptive.

| Step | Role |
|------|------|
| Step 0 | ARGUMENTS parsing, SPEC_DEPTH auto-detection rule table |
| Step 1 | `gh issue view`, ISSUE_TYPE store |
| Step 2 | Worktree Entry (EnterWorktree call, init hook) |
| Step 3 | `gh-label-transition.sh $NUMBER spec` |
| Step 4 | `gh-check-blocking.sh --dry-run`, exit code handling |
| Step 5 | Config marker detection, steering doc reads |
| Step 10 (sub-checks) | Verify command sync, count alignment check, bats test name pattern check, patch-route verify command check, template reference workflow check, self-review checklist |
| Step 11 | Title drift check (title-normalizer.md delegation) |
| Step 12 | `git add`, `git commit -s` |
| Step 13 (commit) | Issue retro transfer, Phase Handoff write, `git commit -s` |
| Step 14 | Worktree Exit (ExitWorktree, merge-to-main) |
| Step 15 | Issue comment (Write + gh-issue-comment.sh) |
| Step 16 | `gh-label-transition.sh $NUMBER ready` |
| Step 17 | Opportunistic verification (module delegation) |
| Step 18 | Size re-evaluation, `get-issue-size.sh`, ProjectV2 update |
| Step 19 | Completion message, next-action-guide delegation |

### Reasoning Steps (candidates for de-prescription)

These steps involve design judgment, investigation, or analysis where prescriptive scaffolding
may impose unnecessary cognitive overhead on Fable 5.

| Step | Sub-element | Prescriptive Element |
|------|-------------|---------------------|
| Step 6 (light path) | File identification method | "directly identify... Infer... verify existence/content with Glob/Grep" |
| Step 7 | Pre-investigation table | 3-column Aspect/Content/Source table with sequential investigation order |
| Step 8 | Detection criteria table | 4-row Pattern/Example/Response table |

---

## Candidate Step Analysis

### Candidate A: Step 6 SPEC_DEPTH=light — File Identification

**Current text:**

```
- **SPEC_DEPTH=light**: skip reading `codebase-search.md`; directly identify changed files
  using Grep/Read. Infer required files from the issue body, and verify existence/content
  with Glob/Grep.
```

**De-prescription variant:**

```
- **SPEC_DEPTH=light**: skip reading `codebase-search.md`. Goal: identify all files that
  will be changed by this issue. Constraint: use file-system tools (Grep/Read/Glob);
  do not modify files in this step.
```

**Assessment:**

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Prescriptive degree | LOW | Current text is already brief; tool names are appropriate guidance |
| De-prescription impact | LOW | Removing tool hints may slightly reduce precision in Sonnet-class models |
| Fable 5 sensitivity | LOW | Fable 5 would infer correct tool usage regardless of explicit naming |
| Risk | LOW | Both variants produce the same behavior in practice |

### Candidate B: Step 7 — Pre-investigation Q&A Table

**Current text:**

```markdown
**Pre-investigation (for each unresolved item):**

Refer to `ambiguity-detector.md`'s "Sources to investigate" column and investigate sequentially:

| Aspect       | Content                                  | Source                                       |
|-------------|------------------------------------------|----------------------------------------------|
| Existing patterns | Similar implementations/conventions | Project source code (Grep/Read)           |
| Past knowledge    | Retrospectives from similar issues/specs | `$SPEC_PATH/*.md`. Skip if absent       |
| Trade-offs        | Pros and cons of each option         | Codebase + Steering Docs                 |

Format Q&A based on investigation results (with recommendation if found, with "no related
patterns" note if not found).
```

**De-prescription variant:**

```markdown
**Pre-investigation (for each unresolved item):**

Goal: gather sufficient context to make a design recommendation. Constraint: ground
recommendations in observable codebase patterns, past retrospectives (check `$SPEC_PATH/*.md`
if available), and documented trade-offs. Format as Q&A with a recommendation when found;
note absence of patterns when not found.
```

**Assessment:**

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Prescriptive degree | MEDIUM | Table structure is useful scaffolding for systematic investigation |
| De-prescription impact | MEDIUM | Removing table may cause models to skip past-retrospective lookup |
| Fable 5 sensitivity | MEDIUM | Fable 5 handles goal-oriented guidance well; `$SPEC_PATH/*.md` pointer preserved |
| Risk | MEDIUM | Losing the "Past knowledge" row label may cause under-use of retrospective knowledge |

### Candidate C: Step 8 — Uncertainty Detection Criteria Table

**Current text:**

```markdown
**Detection criteria (examples):**

| Pattern                             | Example                             | Response                                  |
|------------------------------------|-------------------------------------|-------------------------------------------|
| Unverified external API/spec dependency | Claude Code hooks target tool list | Check official docs via WebFetch       |
| Assumptions about timing/ordering  | stdout destination, hook timing     | Verify with prototype or note as uncertain |
| Environment-dependent behavior     | OS, shell, version differences      | Note target environment; verify with tests |
| Implicit assumptions in existing code | Permission pattern matching rules | Check code/docs; note if unclear        |
```

**De-prescription variant:**

```markdown
**Detection criteria:**

Goal: identify technical uncertainties that would require verification before safe
implementation. Constraint: focus on claims that cannot be confirmed from the codebase alone
(external APIs, environment-specific behavior, timing/ordering, implicit assumptions).
For each item, document a verification method and the affected implementation steps.
```

**Assessment:**

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Prescriptive degree | MEDIUM | The 4 patterns and examples are genuine recognition aids |
| De-prescription impact | MEDIUM-HIGH | Removing examples may cause under-detection of uncertainty patterns |
| Fable 5 sensitivity | HIGH | Fable 5 is most likely to benefit here; less likely to miss uncertainty categories |
| Risk | MEDIUM | If Fable 5 phases coexist with Sonnet phases, reduction in explicit patterns could degrade quality for non-Fable phases |

---

## A/B Test Methodology (Planned — Not Executed)

**Target issues:** 2 closed Issues of Size M or L with non-trivial spec requirements.

**Execution protocol:**
1. Select 2 closed Issues; run `bash scripts/run-spec.sh <N> --fable` with current
   `skills/spec/SKILL.md` (baseline); record spec quality and token usage
2. Create `.tmp/SKILL-deprescription.md` applying Candidates B and C (higher-impact)
3. Temporarily swap: `cp .tmp/SKILL-deprescription.md skills/spec/SKILL.md`
4. Run `bash scripts/run-spec.sh <N> --fable` for the same Issues (de-prescription)
5. Restore: `git checkout skills/spec/SKILL.md`
6. Delete `.tmp/SKILL-deprescription.md`

**Quality metrics:**

| Metric | Measurement Method |
|--------|--------------------|
| Completeness | All acceptance criteria from Issue body covered in spec? |
| Accuracy | Implementation steps correct and non-redundant? |
| Conciseness | Fewer tokens output without information loss? |

**Why not executed in this implementation:**

This audit ran in `--non-interactive` autonomous mode (invoked by `run-code.sh` as a
`claude -p` subprocess). Two constraints prevented A/B execution:

1. **Cost policy**: Fable 5 (`claude-fable-5`) costs $10/$50 per MTok — approximately
   2× Opus 4.8 and 3.3× Sonnet 4.6. Initiating high-cost model invocations without
   explicit user authorization is a high-stakes action that the auto-resolve policy defers
   rather than auto-executes.

2. **Nested subprocess complexity**: spawning `run-spec.sh --fable` (which itself invokes
   `claude -p`) inside an already-running `claude -p` invocation produces layered subprocess
   chains whose context isolation behavior is not fully characterized.

**Recommendation for follow-up:** Run the A/B test interactively per the execution protocol
above. Priority: Candidates B and C (medium/high Fable 5 sensitivity). Candidate A may be
skipped given its low impact rating.

---

## Conclusion

**Decision: Not adopted**

`skills/spec/SKILL.md` is **unchanged** in this PR.

### Rationale

1. **No empirical improvement data**: the A/B test was not executed due to constraints
   documented above. Adopting de-prescription without confirmed improvement data would be
   premature — the Issue and Spec both require confirmed improvements before updating SKILL.md.

2. **Risk asymmetry**: Candidates B and C carry a real risk of degrading spec quality if
   the prescriptive examples provide essential recognition scaffolding even for Fable 5.
   Candidate A's impact is too small to justify a change alone.

3. **Conservative policy**: the distributable-first improvement principle (see `docs/tech.md`)
   requires that changes to `skills/spec/SKILL.md` benefit all Wholework users. Without A/B
   evidence, a change that might degrade quality for Sonnet-class users is not justifiable.

### Path to adoption

If future interactive A/B testing confirms quality improvement:
- Apply Candidate B first (lowest risk among medium-impact candidates)
- Evaluate Candidate C independently
- Apply only to the verified subset; do not bundle unverified candidates

---

## Appendix: De-prescription Variant Snippets

These snippets are provided for direct use in future A/B testing without re-derivation.

### Candidate A

Replace in Step 6:
```
directly identify changed files using Grep/Read. Infer required files from the issue body,
and verify existence/content with Glob/Grep.
```
With:
```
Goal: identify all files that will be changed by this issue. Constraint: use file-system
tools (Grep/Read/Glob); do not modify files in this step.
```

### Candidate B

Replace in Step 7 (`**Pre-investigation (for each unresolved item):**` block):

The 3-column investigation table and sequential instruction. Replace with:
```
Goal: gather sufficient context to make a design recommendation. Constraint: ground
recommendations in observable codebase patterns, past retrospectives (check
`$SPEC_PATH/*.md` if available), and documented trade-offs. Format as Q&A with a
recommendation when found; note absence of patterns when not found.
```

### Candidate C

Replace in Step 8 (`**Detection criteria (examples):**` block):

The 4-row Pattern/Example/Response table. Replace with:
```
**Detection criteria:**

Goal: identify technical uncertainties that would require verification before safe
implementation. Constraint: focus on claims that cannot be confirmed from the codebase
alone (external APIs, environment-specific behavior, timing/ordering, implicit
assumptions). For each item, document a verification method and the affected
implementation steps.
```
