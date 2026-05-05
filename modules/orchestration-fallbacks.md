# orchestration-fallbacks

Pattern reference catalog for fallback / retry / alternative-path handling at the orchestration layer.

## Purpose

Centralize known orchestration-level failure patterns so that any skill or script can locate the canonical recovery procedure in one place. New patterns are added by appending an entry; consumers reference the anchor (e.g., `#ff-only-merge-fallback`) without modifying their own logic.

## Input

None. Skills and modules use the "Read and follow" pattern:

```
Read modules/orchestration-fallbacks.md and apply the entry for <anchor>.
```

Shell scripts cannot "Read and follow" markdown at runtime; they maintain their existing inline logic and carry a pointer comment to the relevant entry (see "Pointer Comment Convention" below).

## Pointer Comment Convention

Shell scripts place a comment immediately above the inline fallback logic:

```bash
# See modules/orchestration-fallbacks.md#<anchor>
```

This comment does not replace the inline logic — it is a navigational aid only.

## Output

Recovery procedure for a named pattern, consumed by the calling skill or used as reference documentation.

---

## ff-only-merge-fallback

### Symptom
- `git merge <branch> --ff-only` exits non-zero
- Typical message: `fatal: Not possible to fast-forward, aborting.`

### Applicable Phases
- code (patch route — `scripts/worktree-merge-push.sh`)
- merge

### Fallback Steps
1. Log the FF failure to stderr: `echo "FF merge failed, attempting git pull --rebase origin <base>..." >&2`
2. Run `git pull --rebase origin <base-branch>` to bring the local branch up to date with remote
3. Re-attempt `git merge <worktree-branch> --ff-only`
4. If the second attempt also fails, propagate the error (do not loop)

### Escalation
- If `git pull --rebase` itself fails (e.g., rebase conflict), abort with a non-zero exit and output an error message requesting manual conflict resolution
- If two consecutive FF-merge failures occur, hand off to recovery sub-agent (#316) or request human intervention

### Rationale
- Inline logic in `scripts/worktree-merge-push.sh` (lines 81–85)
- `git pull --rebase` is preferred over `git merge origin/<base>` to preserve a linear history
- See also: #314 (phase state reconciler), #308 (orchestration improvement series)

---

## verify-sync-retry

### Symptom
- `/verify` skill exits non-zero on the first attempt
- Local branch is behind remote main (e.g., a concurrent patch was merged between the verify run and the current state)

### Applicable Phases
- verify (via `scripts/run-auto-sub.sh` `run_verify_with_retry`)

### Fallback Steps
1. Run `run-verify.sh <issue-num>` (first attempt)
2. On failure: log `verify FAILED: syncing with git pull --ff-only and retrying (1/1)`
3. Run `git pull --ff-only`; if this fails, report as FAIL without retry
4. Re-run `run-verify.sh <issue-num>` (second attempt, maximum 1 retry)
5. Propagate the result of the second attempt regardless of outcome

### Escalation
- If `git pull --ff-only` fails (diverged history), report FAIL immediately without retrying verify
- If the second verify attempt also fails, mark the Issue `phase/verify` and await human judgment (verify loop cap applies: `verify-max-iterations` in `.wholework.yml`, default 3)
- Persistent verify failures after the retry cap escalate to recovery sub-agent (#316) when available

### Rationale
- Inline logic in `scripts/run-auto-sub.sh` `run_verify_with_retry()` (lines 40–61)
- The 1-retry design is intentional: more retries mask genuine failures; `verify-max-iterations` provides the outer cap
- See also: #308 (orchestration improvement series)

---

## gh-pr-list-head-glob

### Symptom
- `gh pr list --head "*issue-N-*"` (glob pattern) returns no results even though matching PRs exist
- `gh` CLI does not support glob/wildcard expansion in `--head`; the filter is applied as a literal string match

### Applicable Phases
- code (PR route — branch lookup)
- merge

### Fallback Steps
1. Drop the `--head` glob filter and instead fetch all open PRs: `gh pr list --state open --json number,headRefName`
2. Filter client-side with a substring match: `| jq '.[] | select(.headRefName | contains("issue-N"))'`
3. Return the matched PR number(s) for downstream use

### Escalation
- If multiple PRs match the substring pattern, select the most recently created one (highest PR number) and log a warning
- If no PR is found after client-side filtering, treat as "no PR exists" and proceed accordingly

### Rationale
- Fixed in #311: `gh pr list --head` does not support glob; client-side filtering is the canonical workaround
- Cataloged here to prevent recurrence; the fix is already applied in affected scripts

---

## ci-flake-retry

### Symptom
- A CI check fails with a transient error unrelated to the code change (e.g., network timeout, runner capacity issue, external service outage)
- Typical signals: check name contains "flake" in the error message, or the same check passes on re-run without any code change

### Applicable Phases
- code (after PR creation — waiting for CI)
- merge (pre-merge CI gate)

### Fallback Steps
1. Identify the failing check name via `gh pr checks <pr-num>`
2. Confirm the failure is transient (no code change between runs, error message indicates infrastructure issue)
3. Re-trigger the check: `gh run rerun <run-id> --failed` (requires appropriate permissions)
4. Wait for the re-triggered run to complete: `scripts/wait-ci-checks.sh <pr-num>`
5. If the re-triggered run passes, continue the normal workflow

### Escalation
- Maximum 1 automatic re-trigger attempt per CI run
- If the check fails again after re-trigger, treat as a genuine failure and require human investigation before proceeding
- Do not re-trigger checks that fail due to code-related errors (test failures, lint errors, syntax errors)

### Rationale
- CI flake is a known pattern in shared infrastructure; retrying once is a standard mitigation
- Runtime integration (automatic re-trigger from `run-*.sh`) is deferred to a follow-up Issue; see #315 (catalog entry) for context
- `scripts/wait-ci-checks.sh` already handles the wait logic; re-trigger is the missing piece

---

## dco-signoff-missing-autofix

### Symptom
- DCO check fails on a PR with message: `commit <sha> is missing Signed-off-by line`
- `scripts/detect-wrapper-anomaly.sh` outputs: `ANOMALY: DCO sign-off missing on commit <sha>`

### Applicable Phases
- code (commit phase — missing `-s` on `git commit`)
- merge (pre-merge DCO gate)

### Fallback Steps
1. Identify the commit(s) missing `Signed-off-by` via `git log --format="%H %s" | head -N`
2. For the most recent commit: `git commit --amend -s --no-edit`
3. Force-push the amended commit to the PR branch: `git push origin HEAD --force-with-lease`
4. Confirm DCO check passes: `gh pr checks <pr-num> | grep dco`

### Escalation
- If multiple commits in the PR history are missing sign-off, amend each commit via interactive rebase: `git rebase -i HEAD~N` (set each to `reword`, then add `Signed-off-by` manually)
- If force-push is blocked by branch protection, request human intervention to temporarily adjust branch rules
- Automatic auto-fix trigger from `detect-wrapper-anomaly.sh` is deferred to a follow-up Issue; this entry serves as the procedure reference

### Rationale
- DCO detection implemented in `scripts/detect-wrapper-anomaly.sh` (#313)
- Auto-fix runtime integration deferred; `git commit --amend -s --no-edit` is the correct single-commit fix
- DCO `Signed-off-by` is required on all commits per `CONTRIBUTING.md` and `.github/workflows/dco.yml`
- See also: #313 (wrapper anomaly detector)

---

## conflict-marker-residual

### Symptom
- `git grep -l '^<<<<<<'` finds tracked files containing conflict marker lines (`<<<<<<<`, `=======`, `>>>>>>>`)
- Indicates an incomplete merge or rebase resolution

### Applicable Phases
- code (patch route — pre-push check in `scripts/worktree-merge-push.sh`)
- merge

### Fallback Steps
1. Run `git grep -l '^<<<<<<' 2>/dev/null` to identify files containing conflict markers
2. Open each file and resolve the conflict manually by choosing the correct version
3. Stage the resolved files: `git add <file>`
4. Complete the merge or rebase: `git merge --continue` or `git rebase --continue`
5. Re-run the conflict marker check to confirm all markers are cleared
6. Proceed with `git push origin <base-branch>`

### Escalation
- If conflict markers are found in generated files (e.g., lock files, auto-generated code), regenerate rather than manually resolving
- If the conflict is in a critical file (e.g., `CLAUDE.md`, `plugin.json`) and the correct resolution is unclear, abort the push and request human review
- Recovery sub-agent (#316) can be invoked for unknown conflict patterns

### Rationale
- Inline detection in `scripts/worktree-merge-push.sh` (lines 87–91)
- Pushing conflict markers to the main branch is a hard failure; the check is a mandatory pre-push gate
- See also: #314 (phase state reconciler), #308 (orchestration improvement series)

---

## dirty-working-tree

### Symptom
- `/verify` outputs `VERIFY_FAILED` and `Cannot run verify because there are uncommitted changes`
- `scripts/detect-wrapper-anomaly.sh` emits pattern: `dirty-working-tree`

### Applicable Phases
- verify

### Fallback Steps
1. Run `git status` to list uncommitted files in the working tree
2. Determine whether each uncommitted file is related to the current issue:
   - **Unrelated files** (e.g., editor swap files, incidental modifications to unrelated paths): stage and commit or stash the files, then retry verify via `run-verify.sh <issue-num>`; notify the operator of the stashed/committed files
   - **Related files** (unexpected edits to issue-specific implementation files): abort the verify run and investigate why uncommitted changes remain before retrying
3. After cleanup, re-run `run-verify.sh <issue-num>`

### Escalation
- If the uncommitted changes cannot be safely classified as related or unrelated, escalate to recovery sub-agent (#316) for diagnosis
- If the dirty working tree recurs after cleanup, inspect whether a prior skill phase left uncommitted edits and report as a new anomaly

### Rationale
- First observed in Issue #393 retrospective: anomaly detector returned empty output because this pattern was not cataloged, blocking Tier 2 automatic recovery
- `scripts/detect-wrapper-anomaly.sh` (pattern: `dirty-working-tree`) now detects the `VERIFY_FAILED` + `uncommitted` co-occurrence and emits this catalog anchor for Tier 2 lookup

---

## reconciler-header-mismatch

### Symptom
- `run-review.sh` logs `reconcile-phase-state result:` with `"matches_expected":false` and `Review Response Summary` in the wrapper log
- `scripts/detect-wrapper-anomaly.sh` emits pattern: `reconciler-header-mismatch`

### Applicable Phases
- review

### Fallback Steps
1. Inspect the PR comment on the Issue's associated PR to check whether `## Review Response Summary` is present
2. If the header is missing: re-run `/review` for the PR to regenerate the review comment with the expected header
3. If the header is present but uses a different casing or wording (e.g., `## Review Summary` instead of `## Review Response Summary`): check `modules/phase-state.md` for the canonical expected signature and align the skill output with it
4. After the header is corrected, re-run `reconcile-phase-state.sh` to confirm `matches_expected:true`

### Escalation
- If the review skill consistently outputs a different header than what `modules/phase-state.md` specifies, update the phase-state signature to match the actual skill output and open a follow-up Issue to track the drift
- Recovery sub-agent (#316) can be invoked when the root cause of the header mismatch is unclear

### Rationale
- First observed in Issue #386: after watchdog timeout, `reconcile-phase-state.sh` returned `matches_expected:false` because `## Review Response Summary` was absent from the PR comment
- `_reconcile_out` was not written to the wrapper log, preventing Tier 2 pattern detection; `run-review.sh` now logs `reconcile-phase-state result:` in the else branch
- `scripts/detect-wrapper-anomaly.sh` (pattern: `reconciler-header-mismatch`) detects the `matches_expected:false` + `Review Response Summary` co-occurrence for Tier 2 lookup

---

## Operational Notes

This catalog is consumed by:

- **#319** (3-tier adaptive recovery hook for `run-auto-sub.sh`) — Tier 2 references this catalog for known pattern lookup before escalating to Tier 3
- **#316** (recovery sub-agent) — uses this catalog as reference information for known patterns; unknown patterns (not listed here) are escalated to the recovery sub-agent
- **#318** (learning loop) — `retro/verify` labels and orchestration anomaly observations are proposed as new catalog entries via the learning loop; the entry-addition workflow defined here is the target format

When a new fallback pattern is discovered:
1. Add an entry following the schema above (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale)
2. Add a pointer comment in the affected script(s): `# See modules/orchestration-fallbacks.md#<anchor>`
3. Reference the discovering Issue or retrospective in the Rationale section
