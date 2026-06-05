# Issue #521: verify-classifier: Clarify expected_value Convention When Converting gh pr checks to gh run list

## Overview

When converting `github_check "gh pr checks" "<job-name>"` to the patch-route-compatible `gh run list` form,
the `expected_value` must also be changed from the job name (e.g., `"Run bats tests"`) to `"success"`.
`gh run list` outputs a run-level table (STATUS / conclusion / TITLE / WORKFLOW / BRANCH) and does NOT
include job names — keeping the job name as expected_value will never match and will cause a false FAIL
even when CI is green.

This rule is not currently explicit in the guidance docs. Issue #517 surfaced the risk when `/code`
performed the conversion but left the job name as expected_value. Both `modules/verify-classifier.md`
and `skills/verify/SKILL.md` Step 5 show the correct `"success"` form in examples, but neither
explicitly states that the expected_value must change. `skills/spec/SKILL.md` Step 10's auto-fix
template is also missing `"success"` in the replacement form.

## Changed Files

- `modules/verify-classifier.md`: add explicit note in "Patch Route CI Verification Note" section
  — expected_value must change from job name to `"success"` (gh run list does not output job names)
- `skills/verify/SKILL.md`: add explicit note after Step 5 Before/After example
  — expected_value must change; gh run list is run-level, not job-level
- `skills/spec/SKILL.md`: fix patch-route auto-fix replacement form to include `"success"` expected_value

## Implementation Steps

1. Update `modules/verify-classifier.md` "Patch Route CI Verification Note" section (→ AC1):
   After the code block showing the correct form, add a note:
   > Note: when converting from `github_check "gh pr checks" "JOB_NAME"`, **also replace the expected_value**
   > from the job name to `"success"`. `gh run list` outputs a run-level table (STATUS / conclusion / TITLE / WORKFLOW / ...)
   > and does not include job names — specifying a job name as expected_value will never match and will always FAIL.

2. Update `skills/verify/SKILL.md` Step 5 "Example replacement" block (→ AC1):
   After the Before/After code block (`# Before` / `# After`), add:
   > Note: the expected_value must change from job name to `"success"`. `gh run list` outputs run-level rows
   > with no job name column — keeping the job name causes false FAIL even when CI is green.

3. Update `skills/spec/SKILL.md` "Patch route verify command check" replacement instruction (→ AC1):
   Change `replace each with \`github_check "gh run list --limit=1 --json conclusion --jq '.[0].conclusion'"\``
   to include `"success"` as the expected_value:
   `replace each with \`github_check "gh run list --limit=1 --json conclusion --jq '.[0].conclusion'" "success"\`
   (change expected_value from job name to "success" — gh run list outputs run-level conclusion, not job names;
   add --workflow=<filename> if there are multiple workflow files under .github/workflows/)`

## Verification

### Pre-merge

- <!-- verify: rubric "verify の patch-route 変換ガイダンス（modules/verify-classifier.md / skills/verify/SKILL.md Step 5 / skills/issue/spec-test-guidelines.md のいずれか該当箇所）に、github_check の gh pr checks→gh run list 変換時は expected_value をジョブ名から run conclusion (success) へ変更する必要がある（gh run list はジョブ名を出力しないため）旨が明記されている" --> 変換時の expected_value 規約が明文化されている
- <!-- verify: grep "gh run list" modules/verify-classifier.md --> verify-classifier.md に gh run list 変換の記述がある
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI が green（正しい gh run list 形式の self-demonstration）

### Post-merge

- 次に patch route Issue の CI 検証 AC を生成する際、`gh run list` 形式で expected_value=`success`（ジョブ名でない）が使われているか確認

## Notes

- The root cause of Issue #517's miscalibration was `skills/spec/SKILL.md` Step 10's auto-fix template
  missing `"success"` as the explicit expected_value in the replacement form. Step 3 above fixes this.
- `gh run list` command output is run-level (one row per workflow run), not job-level. Job names only
  appear in `gh run view <run-id> --json jobs`. This distinction is the core reason expected_value
  must be `"success"` (run conclusion) rather than a job name.
- No bats tests needed: these are documentation-only changes to `.md` files.
- `skills/spec/SKILL.md` is not in the issue AC rubric check locations, but fixing the auto-fix
  template directly prevents the root cause of the miscalibration.

## Code Retrospective

### Deviations from Design
- Used `feat:` commit prefix instead of `chore:` (Issue Type is Task → `chore:` per mapping table). The commit was created before running `get-issue-type.sh` — incorrect ordering of Step 11.

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added explicit **Note** paragraphs to both `modules/verify-classifier.md` and `skills/verify/SKILL.md` rather than modifying existing text, to minimize diff noise while making the rule prominent.
- Fixed `skills/spec/SKILL.md` auto-fix template to include `"success"` as the explicit second argument, closing the root-cause gap from Issue #517.
- Kept changes minimal (3 files, doc-only) — no code logic changes needed.

### Deferred Items
- None. All three spec-identified files were updated.

### Notes for Next Phase
- All 3 pre-merge AC conditions verified PASS (rubric, grep, CI green).
- This is a patch route commit — no PR exists; `/verify` will run directly on main after push.
- Post-merge AC is opportunistic: check next patch-route Issue's CI verify AC for `expected_value="success"` form.
