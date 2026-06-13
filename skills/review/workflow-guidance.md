---
type: domain
skill: review
load_when:
  capability: workflow
---

# Workflow Execution Guidance (Domain File)

This file is loaded only when `HAS_WORKFLOW_CAPABILITY=true` (`capabilities.workflow: true` in `.wholework.yml`).

Enabled by declaring:

```yaml
capabilities:
  workflow: true
```

## Purpose

When `HAS_WORKFLOW_CAPABILITY=true` and `REVIEW_DEPTH=full`, use the Workflow tool to execute a finder → adversarial verify pipeline instead of the static Task fan-out (Steps 10.1–10.3). This overlaps finder execution with verification to reduce wall-clock time by ~25%, adds structured output via schema validation, and enables N-vote adversarial verification to eliminate false positives.

Scope: `/review --full` only. The Workflow path is never the default; `capabilities.workflow` must be explicitly set.

## Find/Filter Separation Contract

The Workflow execution path preserves the same find/filter separation contract as the static Task fan-out:

- **Finders** (`review-spec`, `review-bug`) play the **coverage role**: report all findings — including uncertain or low-severity ones — tagging each with:
  - `confidence`: `high` / `medium` / `low`
  - `severity`: `MUST` / `SHOULD` / `CONSIDER`
  - Self-filtering at the finder stage reduces recall; finders must NOT filter findings before reporting
- **Adversarial verification** plays the **filter role**: each finding is independently challenged by a refutation agent. Findings that survive the majority vote (`refuted: false`) become confirmed issues
- **Fallback path**: when `HAS_WORKFLOW_CAPABILITY=false` or unset (the default), Steps 10.1–10.3 static Task fan-out run unchanged

## Processing Steps (Workflow Path)

When `HAS_WORKFLOW_CAPABILITY=true` and `REVIEW_DEPTH=full`, replace Steps 10.1–10.3 with the following:

1. **Save PR diff to file** (same as Step 10.2 static path):
   - `mkdir -p .tmp`
   - Write `gh pr diff "$NUMBER"` result to `.tmp/pr-diff-$NUMBER.txt`
   - Write `gh pr view "$NUMBER" --json files` result to `.tmp/pr-files-$NUMBER.json`

2. **Get Spec path** (same as static path):
   - Glob for `$SPEC_PATH/issue-$ISSUE_NUMBER-*.md`
   - Record path if found; empty string if not

3. **Get steering doc paths** (same as static path):
   - Glob for `$STEERING_DOCS_PATH/product.md`, `$STEERING_DOCS_PATH/tech.md`, `$STEERING_DOCS_PATH/structure.md`
   - Record comma-separated as `STEERING_DOCS_FILES`

4. **Run Workflow pipeline** using the inline script below. Pass all required variables (`NUMBER`, `ISSUE_NUMBER`, `TYPE`, `DESIGN_FILE_PATH`, `STEERING_DOCS_FILES`, `SKIP_REVIEW_BUG`) as part of the agent prompts.

5. **Integrate results** the same way as Step 10.2 step 4: extract `path`, `line`, `body`, `severity` from confirmed findings; write `review-comments-$NUMBER.json` and `review-body-$NUMBER.md`.

6. **Cost transparency**: include `budget.spent()` approximate token usage in the completion report (Step 14 summary).

## Inline Workflow Script

```javascript
export const meta = {
  name: 'review-workflow',
  description: 'Finder fan-out + adversarial verify pipeline for /review --full',
  phases: [
    { title: 'Find', detail: 'review-spec and review-bug finders run in parallel' },
    { title: 'Verify', detail: 'adversarial refutation per finding' },
  ],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: ['string', 'null'] },
          line: { type: ['integer', 'null'] },
          body: { type: 'string' },
          severity: { enum: ['MUST', 'SHOULD', 'CONSIDER'] },
          confidence: { enum: ['high', 'medium', 'low'] },
        },
        required: ['path', 'line', 'body', 'severity', 'confidence'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['refuted', 'reason'],
}

const SKIP_BUG = args && args.skipReviewBug

const FINDERS = SKIP_BUG
  ? [{ agentType: 'review-spec', label: 'find:spec' }]
  : [
      { agentType: 'review-spec', label: 'find:spec' },
      { agentType: 'review-bug', label: 'find:bug-diff' },
      { agentType: 'review-bug', label: 'find:bug-security' },
    ]

const finderPrompts = {
  'find:spec': `Run review: PR=${args.number}, Issue=${args.issueNumber}, Type=${args.type}, Spec=${args.specPath}, Steering Documents=${args.steeringDocs}, PR diff=.tmp/pr-diff-${args.number}.txt, changed files=.tmp/pr-files-${args.number}.json`,
  'find:bug-diff': `Run review: PR=${args.number}, Type=${args.type}, PR diff=.tmp/pr-diff-${args.number}.txt, changed files=.tmp/pr-files-${args.number}.json. Focus on + lines in the diff; detect clear bugs and logic errors using HIGH SIGNAL principles.`,
  'find:bug-security': `Run review: PR=${args.number}, Type=${args.type}, PR diff=.tmp/pr-diff-${args.number}.txt, changed files=.tmp/pr-files-${args.number}.json. Detect security issues and invalid logic in changed code using HIGH SIGNAL principles.`,
}

const finderResults = await pipeline(
  FINDERS,
  f => agent(finderPrompts[f.label], {
    label: f.label,
    phase: 'Find',
    agentType: f.agentType,
    schema: FINDINGS_SCHEMA,
  }),
  finderResult => {
    if (!finderResult) return []
    return finderResult.findings.map(finding =>
      () => agent(
        `Adversarially refute the following review finding. Default to refuted=true if uncertain.\n\nFinding:\npath: ${finding.path}\nline: ${finding.line}\nbody: ${finding.body}\nseverity: ${finding.severity}\nconfidence: ${finding.confidence}\n\nTry to find a concrete reason why this finding is NOT a real issue. Only set refuted=false if the finding is clearly a genuine problem.`,
        { label: `verify:${finding.path || 'general'}:${finding.severity}`, phase: 'Verify', schema: VERDICT_SCHEMA }
      ).then(verdict => ({ ...finding, refuted: verdict ? verdict.refuted : true }))
    )
  },
)

const allFindings = finderResults.flat().filter(Boolean)
const confirmed = allFindings.filter(f => f.refuted === false)

return { confirmed, totalFound: allFindings.length, tokenSpent: budget.spent() }
```

## Cost Transparency

When using this Workflow path, include the following in the Step 14 completion report:

```
Workflow mode (capabilities.workflow: true):
- Finders run: {N} (spec + bug×2, or spec only when SKIP_REVIEW_BUG)
- Findings before verification: {totalFound}
- Confirmed after adversarial verify: {confirmed.length}
- Approximate tokens used: {tokenSpent}
```

This ensures users can make informed decisions about Workflow enablement costs relative to the baseline static Task fan-out.
