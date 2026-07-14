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
- `git fetch . <from-branch>:<base-branch>` exits non-zero
- Typical messages: `fatal: refusing to fetch into branch 'refs/heads/<base>' checked out at ...` (exit 128, base is checked out somewhere) or `! [rejected] ... (non-fast-forward)` (exit 1, not a fast-forward)

### Applicable Phases
- code (patch route — `scripts/worktree-merge-push.sh`)
- merge
- auto (`run-auto-sub.sh`'s recovery-record push, 5 sites — lock+push-only mode variant, no `--from` branch)

### Fallback Steps
0. Immediately after `acquire_lock` (before the `--from` merge block): run `git fetch origin <base-branch>` as best-effort — failure emits a warning to stderr but does not abort. This ensures that subsequent ref-fetch and rebase steps reference an up-to-date `origin/<base-branch>` ref rather than a stale local snapshot.
1. **Primary path**: run `git fetch . "<from-branch>:<base-branch>"` — a checkout-less ref-to-ref fetch within the same repository. Git itself refuses this when `<base-branch>` is checked out in any worktree (exit 128) or when it would not be a fast-forward (exit 1), so success means `<base-branch>` was fast-forwarded without touching the shared directory's working tree or HEAD.
2. If the ref-fetch fails, check whether the shared directory itself has `<base-branch>` checked out (`git rev-parse --abbrev-ref HEAD`):
   - If it matches `<base-branch>`: this is the one case ref-fetch is expected to reject on its own target. Run `git merge <from-branch> --ff-only` in place (safe, since the shared directory genuinely is `<base-branch>`). Failure here aborts with exit 1 and an explicit "resolve manually" message.
   - If it does not match `<base-branch>` (a true divergence, or another session's foreign checkout): continue to step 3. Do **not** fall back to a bare `git rebase`/`git merge` against the shared directory's current HEAD — that would reintroduce the checkout-dependent defect this fallback exists to close.
3. Run `git merge-base --is-ancestor "origin/<base-branch>" "<from-branch>"` to check whether the worktree branch already contains `origin/<base-branch>` as an ancestor:
   - Exit 0 (ancestor): log "is-ancestor=true; skipping rebase" to stderr and skip to step 6 directly — the silent `git rebase` no-op path is eliminated
   - Exit non-0 (not ancestor) or command error: fall through to step 4
4. Detect the worktree path for FROM_BRANCH via `git worktree list --porcelain | awk -v b="refs/heads/<from>" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}'`
5. If a worktree path is found: run `git -C <worktree-path> rebase origin/<base-branch>` (rebase from inside the checked-out worktree, which avoids touching the shared directory and avoids the "already checked out" error); on conflict, run `git -C <worktree-path> rebase --abort 2>/dev/null || true` and exit 1. If no worktree path is found (branch not checked out in any worktree), exit 1 with an explicit "resolve manually" message — a bare `git rebase <base> <from>` is not used, since it would implicitly check out `<from-branch>` in the shared directory, the same defect class this fallback closes.
6. On successful rebase (or is-ancestor skip): re-attempt `git fetch . "<from-branch>:<base-branch>"` (not a third bare `git merge --ff-only` — the ref-fetch keeps this retry checkout-less too); failure propagates via `set -e`

### Escalation
- If the ref-fetch in step 1 fails for a reason other than the shared directory holding `<base-branch>` checked out (step 2's non-matching branch), and no worktree is found for `<from-branch>` in step 5, abort with a non-zero exit and output an error message requesting manual resolution
- If the rebase in step 5 encounters conflicts, abort rebase and exit 1 — hand off to recovery sub-agent (#316) or request human intervention
- Automatic rebase is attempted only once; no further looping after step 6 failure
- Push retry loop (max 3): after all merge/rebase steps complete, `git push origin <base>` failures trigger a `git fetch origin <base>` followed by a retry-scoped rebase, then `git push` — up to 3 times. On the 3rd failure, abort with exit 1 and "Manual push required." message. Rebase conflict during retry aborts with exit 1 (policy D maintained — no auto-resolve). When `<from-branch>` is set, the retry-scoped rebase is checkout-less: it locates the worktree for `<from-branch>` the same way as step 4 (`git worktree list --porcelain` + awk) and runs `git -C <worktree-path> rebase origin/<base>` there, followed by `git fetch . "+<from-branch>:<base-branch>"` (**force refspec**, unlike step 1/6's non-force ref-fetch) to update local `<base-branch>` without touching the shared directory's checkout; if no worktree is found, abort with exit 1 and "resolve manually" rather than falling back to a bare rebase. The force refspec is required here specifically because the retry-scoped rebase re-anchors `<from-branch>` onto the freshly-fetched `origin/<base-branch>`, leaving local `<base-branch>` (still holding whatever value the primary merge path set earlier in this run) no longer an ancestor of the rebased tip — a non-force fetch would then be rejected as non-fast-forward, defeating the retry. Overwriting the stale local `<base-branch>` ref here is the intended outcome, not a bypass of the ff-only guarantee the primary path relies on. When `<from-branch>` is unset (lock+push-only mode, where the caller's current branch already is `<base-branch>`), the retry keeps the bare `git rebase origin/<base>` — this mode has no other branch to rebase, and the primary merge block above is itself skipped entirely under the same condition, so the asymmetry is intentional.

### Rationale
- Inline logic in `scripts/worktree-merge-push.sh`
- `git fetch . <from>:<base>` is preferred over `git pull --rebase origin <base>` as the primary path because it never depends on, or mutates, the shared directory's current checkout — git's own ref-fetch safety checks (checked-out-branch refusal, non-fast-forward refusal) reproduce `--ff-only` safety guarantees without ever touching working tree state. This closes the defect reported in #961, where the old `git pull --rebase origin <base>` fallback ran unconditionally against whatever branch the shared directory happened to have checked out, silently rebasing an unrelated session's in-progress branch
- Step 3 (base-diverged rebase) added in #522: when local base is already in sync with origin but the worktree branch was forked before a concurrent merge advanced base, the ref-fetch is rejected as non-fast-forward and a worktree-branch rebase is required
- `git -C <worktree-path> rebase` is preferred over a bare `git rebase <base> <branch>` when the branch is checked out in a worktree, because a bare rebase implicitly checks out `<branch>` in the shared directory — the same checkout-dependent defect class this fallback closes; the non-worktree bare-rebase fallback was removed in #961 for the same reason
- Step 0 (fetch-after-lock) added in #853: in parallel session environments, the `origin/<base>` ref may be stale at lock acquisition time; an explicit fetch immediately after the lock is acquired ensures all subsequent ref comparisons use current remote state
- Step 3 (is-ancestor check) added in #853: when `git rebase` reports "Current branch is up to date" (is-ancestor=true) but the local main ref differs, the subsequent ref-fetch still fails silently; the explicit is-ancestor check detects this and skips directly to the ref-fetch retry, eliminating the silent no-op path
- Push retry loop added in #853: in parallel session environments a concurrent session may push between the worktree rebase and the local push, causing a non-fast-forward push failure; the retry loop (max 3, fetch+rebase+push each iteration) resolves this without requiring human intervention
- Push retry loop aligned with the checkout-less design in #970: the retry-scoped rebase reused a bare `git rebase origin/<base>` against the shared directory's current HEAD, which is the same checkout-dependent defect class #961 closed for the primary merge path — it just went unnoticed because #961's Changed Files scoped out this loop. #970 brings the retry rebase in line with step 5's worktree-scoped rebase whenever `<from-branch>` is available, leaving the bare rebase only for the `<from-branch>`-unset lock+push-only mode where no other branch exists to rebase
- See also: #314 (phase state reconciler), #308 (orchestration improvement series), #517 (incident that triggered #522), #853 (parallel session race hardening), #961 (checkout-less ref-fetch replacement for the `git pull --rebase` fallback, and removal of the non-worktree bare-rebase branch), #970 (checkout-less rewrite of the push-retry loop's rebase, closing the gap #961 left out of scope), #986 (applied this push retry pattern to `run-auto-sub.sh`'s 5 recovery-record write paths via the shared `_push_with_retry()` helper, the lock+push-only mode variant of this fallback)

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
   - **Unrelated files** (e.g., editor swap files, incidental modifications to unrelated paths): stage and commit or stash the files, then retry verify via `/verify <issue-num>`; notify the operator of the stashed/committed files
   - **Related files** (unexpected edits to issue-specific implementation files): abort the verify run and investigate why uncommitted changes remain before retrying
3. After cleanup, re-run `/verify <issue-num>`

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

## review-completion-false-negative

### Symptom
- `run-review.sh` exits with non-zero and the wrapper log contains `"matches_expected":false` and `"phase":"review"` but neither `Review Response Summary` nor `レビュー回答サマリ` appears in the log
- `scripts/detect-wrapper-anomaly.sh` emits pattern: `review-completion-false-negative`
- Likely cause: LLM omitted the `<!-- review-summary -->` marker and used a non-standard (localized) heading not covered by existing fallback signatures

### Applicable Phases
- review

### Fallback Steps
0. `run-review.sh` already attempts an automated fallback post before this catalog entry is reached: on exit 0 + `matches_expected:false`, it calls `scripts/post-fallback-review-summary.sh <PR>`, which posts a `<!-- review-summary -->`-marked Response Summary only when a prior review containing "Acceptance Criteria Verification Results" is found for the PR, then re-checks completion. The manual steps below are needed only when that automated fallback also failed (guard evidence not found, or `gh pr comment` itself failed).
1. Re-run `reconcile-phase-state.sh review --pr <N>` to check whether a cache-related false negative caused the mismatch; if the result flips to `matches_expected:true`, continue normally
2. Run `gh pr view <N> --comments` to inspect PR comments directly; check whether a summary-style comment exists (any heading containing "review", "summary", "サマリ", "レビュー", etc.)
3. If a summary comment exists but `<!-- review-summary -->` marker is absent: edit the comment via `gh api repos/{owner}/{repo}/issues/comments/<comment-id> -f body="<!-- review-summary -->\n<original-body>"` to prepend the marker, then re-run `reconcile-phase-state.sh review --pr <N>` to confirm `matches_expected:true`. If the heading is a localized variant not covered by existing fallback signatures, open a follow-up Issue to add the regex to `scripts/reconcile-phase-state.sh`
4. If no summary comment is found in the PR: the review skill did not complete — re-run `/review <PR>` to regenerate the review comment

### Escalation
- Recovery sub-agent (#316) can be invoked when the root cause is unclear or none of the fallback steps resolve the mismatch

### Rationale
- First observed during Issue #528 implementation: PR #544 had a review summary comment with heading `## レビューレスポンスサマリー` (not covered by existing fallback signatures) and the `<!-- review-summary -->` marker was absent; `reconcile-phase-state.sh` returned `matches_expected:false` and `run-review.sh` exited non-zero; Tier 2 `detect-wrapper-anomaly.sh` returned empty output (pattern not cataloged)
- Issue #528 introduced `<!-- review-summary -->` as the primary signature in `modules/phase-state.md`, resolving the root cause; this catalog entry serves as the safety net when LLM omits the marker and uses a non-standard heading simultaneously
- Exclusivity with `reconciler-header-mismatch`: the `elif` chain in `scripts/detect-wrapper-anomaly.sh` ensures that logs containing `Review Summary` are caught by `reconciler-header-mismatch` first; `review-completion-false-negative` fires only when that pattern does not match
- Suppression on recovery (#932): if the same log later contains a `"matches_expected":true` line (e.g. after `post-fallback-review-summary.sh` recovers the phase), the `review-completion-false-negative` condition is skipped entirely — the same reconcile-first-authority principle used by the `EXIT_CODE=0` silent-no-op branch, applied here to avoid reporting an anomaly for a phase that has already recovered

---

## code-completed-no-pr

### Symptom
- `run-code.sh` exits with code 143 (watchdog kill) and the wrapper log contains a line matching `reconcile-phase-state result:` with `"matches_expected":false` and `"phase":"code-pr"`
- `scripts/detect-wrapper-anomaly.sh` emits pattern: `code-completed-no-pr`
- The worktree branch contains commits (implementation was completed) but no open PR exists for that branch

### Applicable Phases
- code (PR route)

### Fallback Steps
1. Identify the worktree branch: `git branch | grep "worktree-code+issue-N"` (where N is the issue number)
2. Check out the worktree branch: `git checkout worktree-code+issue-N`
3. Rebase onto the latest main to incorporate any concurrent patches: `git rebase origin/main`
4. Push the branch to the remote: `git push origin worktree-code+issue-N`
5. Create the PR: `gh pr create --title "Issue #N: <summary>" --base main --body "..."`
6. Continue with `/review <PR-number>` to proceed to the review phase

### Escalation
- If `git rebase` encounters conflicts, resolve each conflict manually, then `git rebase --continue`; if conflicts cannot be resolved safely, abort with `git rebase --abort` and request human intervention
- If the worktree directory has already been cleaned up (`.claude/worktrees/` entry is absent), recover commits from `git reflog` or the orphaned worktree branch
- Recovery sub-agent (#316) can be invoked when the root cause of the anomaly is unclear or the rebase conflicts are complex

### Rationale
- First observed in Issue #385: watchdog kill after all commits were complete but before `gh pr create` was executed; the parent session manually ran rebase + push + PR creation
- `reconcile-phase-state.sh` `_completion_code_pr()` returns `matches_expected:false` only when the expected PR is absent (the sole mismatch case); combined with `"phase":"code-pr"` in the JSON output, this uniquely identifies the code-completed-no-pr scenario
- `run-code.sh` now logs `reconcile-phase-state result:` (added in #415) so Tier 2 can detect this pattern from the wrapper log; prior to this change, `_reconcile_out` was silently discarded and Tier 2 would return empty output (unknown pattern)
- The `code-completed-no-pr` check precedes `watchdog-kill` in the detector to win the first-match-wins priority, since both signatures can co-occur in the same log
- Suppression on recovery (#981): if the same log later contains a `"matches_expected":true` line for phase code-pr (e.g. after `code_retry_fire`'s exec-based retry succeeds), the `code-completed-no-pr` condition is skipped entirely — the same reconcile-first-authority principle applied to `review-completion-false-negative` (#932), extended here to the code-pr phase

---

## mid-run-api-error

### Symptom
- forked session (`claude -p`) exits with non-zero exit code mid-run
- Log contains API connection/error patterns: `APIConnectionError`, `Request timed out`,
  `overloaded_error`, or `529.*Overload`
- Issue state: OPEN, phase label may be missing or inconsistent

### Applicable Phases
- Any phase running via `run-*.sh` (spec, code, review, merge, verify)

### Fallback Steps
1. Run `reconcile-phase-state.sh <phase> <issue> --check-completion` and parse the JSON output
2. If `matches_expected: true`: phase completed before the API error; override to success and continue
3. If `matches_expected: false`:
   a. Inspect restoration hints from `actual` JSON:
      - `spec_file`: spec file path if found (indicates spec phase completed; existing field)
      - `hint_recent_commit`: recent commit referencing the issue (indicates code was committed)
      - `hint_pr_state`: PR state if a PR exists for the issue
   b. Restore the phase label based on hints:
      - `spec_file` is null: spec not created; restore `phase/spec` label and retry spec
      - `spec_file` present, no PR, no recent commit: spec done, label lost; restore `phase/ready`
      - hint_recent_commit present (commit without PR): code committed; restore `phase/code`
      - hint_pr_state is OPEN: PR exists; restore `phase/review` or `phase/merge`
   c. Retry the failed phase once via the corresponding `run-*.sh <issue_number>`

### Escalation
- If retry fails again with an API error: stop with stop-and-report; persistent API failure requires manual intervention
- If retry fails with a different error: escalate to Tier 3 (recovery sub-agent)
- Maximum 1 retry per API error occurrence; no further looping

### Rationale
- Introduced in #500: forked sessions failing mid-run due to API connection errors left issues in
  OPEN state with missing phase labels; `reconcile-phase-state.sh` Tier 1 could not fully restore
  state because labels were absent
- `reconcile-phase-state.sh` enhancement (#500) adds restoration hints to mismatch output,
  enabling the parent session to restore the correct phase label before retrying
- See also: #483 (parent XL issue), #314 (reconcile-phase-state), #313 (wrapper anomaly detector)

---

## code-base-conflict

### Symptom
- `run-code.sh` exits 0 (code phase completed) but outputs to stderr: `Warning: code phase completed but PR #<N> has conflicts with base`
- PR diff (merge-base based) shows only this Issue's changes correctly — the warning indicates base advanced concurrently, not that the PR diff is contaminated

### Applicable Phases
- code (PR route)

### Fallback Steps
1. Run `git fetch origin main` to bring your local state up to date with the latest base branch
2. Run `git checkout worktree-code+issue-<N>` to check out the worktree branch for this issue
3. Run `git merge-tree --write-tree origin/main HEAD` to identify conflicting files and inspect the conflict content
4. If the conflicting changes are **directly orthogonal** (e.g., independent argument additions, unrelated line edits in the same file): run `git merge origin/main`, resolve each conflict by integrating both changes, then `git push`
5. If the conflicting changes are **functionally overlapping** (e.g., both branches implement the same feature differently): escalate to the parent session to decide which implementation to adopt before merging
6. After conflict resolution, run `/merge <PR>` to proceed with the merge phase

### Escalation
- If the conflicts cannot be resolved safely (unclear which change takes precedence, complex multi-file entanglement): escalate to recovery sub-agent (#316) for diagnosis and resolution guidance
- If `git merge origin/main` itself fails with unexpected errors, abort with `git merge --abort` and request human intervention

### Rationale
- First observed in Issue #541: a concurrent session merged a different Issue to main while the code phase was running, causing a shared source file's function signature to conflict; the parent session manually ran `git merge-tree` to identify the conflict, confirmed orthogonal changes, and resolved by integration
- The warning is emitted by `scripts/run-code.sh` after the reconcile check block — EXIT_CODE is not changed (the implementation itself is complete); the warning is informational to enable resolution before `/merge`
- `scripts/gh-pr-merge-status.sh` is reused (no new API call logic) to detect `mergeable: false, reason: conflicts`
- See also: #483 (forked→single session migration reducing parallel execution risk), #465 (code normal-exit completion check), #535 (push branch recovery at watchdog kill)

---

## async-external-commit

### Symptom
- `run-auto-sub.sh` Tier 1 (`reconcile-phase-state.sh code-patch <issue> --check-completion`) returns `"matches_expected":false` with diagnosis `no commit with closes #N found on origin/main`
- The implementation artifact physically exists and the phase label has advanced to `phase/verify` or later
- The only commit for this Issue was made by an external tool (e.g., Obsidian Git) in the format `vault backup: <timestamp>` — the commit message does not contain `closes #N`

### Applicable Phases
- code (patch route — `_completion_code_patch` in `scripts/reconcile-phase-state.sh`)

### Fallback Steps
- No manual intervention required. `_completion_code_patch` includes a built-in three-stage check:
  1. Primary: `git log origin/main --grep="closes #${ISSUE_NUMBER}"` (existing check)
  2. Operate marker (when primary finds nothing): `_operate_signal_ts` checks for an execution-log/execution-plan marker comment on the Issue, confirming a diff-less operate route completion (`modules/phase-state.md` § "Operate Route Completion Signature")
  3. Label/state fallback (when both above find nothing): `gh issue view "$ISSUE_NUMBER" --json labels` and `--json state` to confirm `phase/verify`, `phase/done`, or `CLOSED` state
- If either fallback stage confirms completion, `_completion_code_patch` returns `matches_expected:true` automatically, preventing Tier 3 sub-agent escalation

### Escalation
- If both the git log check and the phase label / state fallback fail to confirm completion, the reconciler returns `matches_expected:false` and Tier 2 / Tier 3 escalation proceeds normally
- If the `gh` API call fails (network error, rate limit), `labels` and `state` are empty strings; the fallback condition evaluates to false and falls through to the existing mismatch path — no silent false-positive

### Rationale
- Introduced in Issue #461: patch Issues whose only artifact is an external-tool auto-commit (no `closes #N` in commit message) caused systematic false-negatives in `_completion_code_patch`, triggering unnecessary Tier 3 sub-agent spawning on every orchestrator re-run
- Mirrors the two-stage pattern already used in `_completion_spec` (spec file presence + ready-or-later label), keeping the reconciler consistent
- `phase/verify` is set by `/review` skill after merge confirmation, making it a reliable proxy for code-patch completion when the commit does not carry `closes #N`
- See also: Issue #461 (introducing this fallback), Issue #460 (`git_committed` verify command), Issue #462 (`verify-patterns.md` recommended pattern)

---

## json-mode-silent-hang

### Symptom
- `run-*.sh` exits with code 143 (watchdog SIGTERM)
- Wrapper log contains: `watchdog: still waiting (json mode), silent for <N>s`
- No output from the `claude -p` process after launching in json mode
- Typical cause: transient API delay or session init stall

### Applicable Phases
- Any phase running via `run-*.sh` (spec, code, review, merge, verify)

### Fallback Steps
1. Retry the failed phase once via the corresponding `run-*.sh <issue_number>` script
2. Monitor the retry's output for signs of normal progress within the first 60 seconds
3. If the retry succeeds, continue the normal workflow

### Escalation
- If the retry also exits 143 with the same `still waiting (json mode)` pattern, escalate to Tier 3 (recovery sub-agent)
- Maximum 1 automatic retry attempt per occurrence; no further looping
- If the retry fails with a different error, escalate to Tier 3 for diagnosis

### Rationale
- First observed in a downstream project: `run-code.sh` launched `claude -p` in json mode but received no output for 1800s (watchdog timeout), then was terminated with SIGTERM (exit 143); Tier 3 orchestration-recovery diagnosed as "transient API delay or session init stall" and issued action=retry, which succeeded
- `scripts/claude-watchdog.sh` line 71 emits `watchdog: still waiting (json mode)` to stderr when no output is received in json mode; `run-*.sh` wrapper logs capture this
- The AND condition (exit 143 AND `still waiting (json mode)` in log) uniquely identifies this pattern vs. the more generic `watchdog-kill` (which fires on any watchdog timeout); `json-mode-silent-hang` is placed before `watchdog-kill` in the detector to win first-match-wins priority
- Cataloged in Issue #684 based on Tier 3 recovery success; retry once is the correct first response for transient stalls

---

## baseline-failure

### Symptom
- `run-merge.sh` exits non-zero before launching `claude -p`, with message: `Error: pre-merge-check.sh detected a new FAILURE (not pre-existing on base branch)`
- `pre-merge-check.sh` exits 2 (NEW_FAILURE): the check passes on the base branch but fails on the PR head branch
- Typical cause: a commit on the PR head branch introduced a new forbidden expression or other check violation

### Applicable Phases
- merge (run-merge.sh baseline pre-merge gate — before claude invocation)

### Fallback Steps
1. Identify the failing check: run `scripts/pre-merge-check.sh <pr-number>` manually and read the NEW_FAILURE output line
2. Switch to the PR branch: `git checkout <head-ref>`
3. Run the failing check locally: `bash scripts/check-forbidden-expressions.sh` (or the relevant check script)
4. Fix the violation in the implementation files (e.g., replace the forbidden expression with the approved alternative)
5. Commit the fix with DCO sign-off: `git commit -s -m "fix: resolve forbidden expression in <file>"`
6. Push the fix to the PR branch: `git push origin <head-ref>`
7. Re-run `/merge <pr-number>` to retry the merge phase

### Escalation
- If the failure is a pre-existing violation that was incorrectly classified as NEW_FAILURE (unexpected): inspect both branches manually with `bash scripts/check-forbidden-expressions.sh` and compare; if this is a misclassification, report as a bug in `pre-merge-check.sh`
- If `pre-merge-check.sh` exits 1 (env error: ref resolution, fetch, or worktree failure), `run-merge.sh` proceeds fail-open — the merge is not blocked; investigate the env error separately

### Rationale
- Introduced in #719: `/auto` merge phase encountered a pre-existing Forbidden Expressions FAILURE on main (`docs/spec/issue-710-blocked-by-workflow.md`) and `--non-interactive` auto-resolve policy silently continued; without baseline diff, there was no machine-readable distinction between pre-existing and new failures
- `pre-merge-check.sh` runs both base and head branches in ephemeral worktrees and classifies the result (NEW_FAILURE / PRE_EXISTING / FIXED / CLEAN); only exit 2 (NEW_FAILURE) blocks the merge
- env error (exit 1) is fail-open because blocking all merges due to check infrastructure failure is a worse outcome than proceeding with the existing GitHub merge-state gates and human review
- See also: #702 (triggering incident — Forbidden Expressions pre-existing FAILURE auto-resolved in merge), #704 (autonomy tier matrix)

---

## code-patch-silent-no-op

### Symptom
- `run-code.sh` exits 1; wrapper log contains `"silent no-op"` warning
- `reconcile-phase-state.sh code-patch <issue> --check-completion` confirms `commits_found:false`
- Claude exited 0 (no crash, no watchdog kill) but produced no commit on origin/main

### Applicable Phases
- code (patch route)

### Fallback Steps
1. Retry `run-code.sh <issue> --patch` once (skipped when `run-code.sh`'s built-in `auto-retry-on-fail` has already exhausted its retries, to avoid double-retry)
2. After the retry (or skip), check `matches_expected` via `reconcile-phase-state.sh code-patch <issue> --check-completion`. If `false` → escalate to Tier 3

### Escalation
- If the retry (or skip) is followed by `matches_expected:false` from the completion check, escalate to Tier 3 (recovery sub-agent) — this also covers the case where the retry itself exits 0 but is itself a silent no-op (Issues #895, #904)
- Do not retry more than once automatically; a second silent no-op may indicate a structural issue requiring human investigation

### Exception Condition

When `reconcile-phase-state.sh --check-completion` returns `"matches_expected":true`, `detect-wrapper-anomaly.sh` skips the silent-no-op entry entirely, regardless of `commits_found`. This covers the async external commit recognition pattern: a skill detects that the target Issue was already implemented in a prior PR and transitions directly to `phase/verify` without creating a new commit. The reconciler's phase-label and state checks confirm completion (`matches_expected:true`), so no anomaly entry is warranted.

For the `merge` phase specifically, `detect-wrapper-anomaly.sh` additionally runs an independent live check (`gh pr view <PR> --json state -q '.state'`) before falling through to the log/git-log-based checks above. If the PR state is confirmed `MERGED`, the silent-no-op entry is skipped regardless of wrapper log content or local git history. This is necessary because a squash merge lands on `origin/main` via the GitHub API and the local working tree is not automatically fetched, making the log-based and git-log-based checks unreliable for this phase (Issue #916). If the `gh pr view` call fails (API error, rate limit) or the state is not `MERGED`, detection falls through to the existing logic (fail-safe, not fail-open).

For the `review` phase, `detect-wrapper-anomaly.sh` similarly runs an independent live check (`gh pr view <PR> --json reviews --jq '.reviews[].body'`) before falling through to the log/git-log-based checks above. If any posted Review (from the current or a prior cycle) contains the heading "Acceptance Criteria Verification Results", the silent-no-op entry is skipped regardless of wrapper log content or local git history. This does not verify that the matched Review is free of unresolved MUST issues, nor that it originated from the current phase invocation — it only confirms that a `/review` run completed enough to post its standard heading. If the `gh pr view` call fails or no matching Review is found, detection falls through to the existing logic (fail-safe, not fail-open; Issue #927).

See also: `#async-external-commit` (reconcile-first authority — `matches_expected:true` takes precedence over `commits_found` in anomaly detection).

### Rationale
- First observed in Issues #658 and #489; cataloged in Issue #727
- When `reconcile-phase-state.sh` confirms `commits_found:false`, the working tree is known-clean and a single retry is always safe on the patch route (no partial commit can exist)
- Handling this in Tier 2 avoids the overhead of spawning a Tier 3 `claude -p` recovery sub-agent for a pattern that is trivially safe to retry
- Exception Condition added in Issue #771: the AND condition on `commits_found:true` was too strict, causing false positives when the reconciler confirmed completion via phase-label state rather than git commit presence

---

## wrapper-retry-on-kill

### Symptom
- A `run-*.sh` wrapper's child process (claude invocation or child runner script) exits with code `137` (SIGKILL) or `143` (SIGTERM) within the early-kill window (< `WHOLEWORK_RETRY_ON_KILL_MAX_SEC`, default 300s)
- Typical cause: external resource pressure, OOM kill, or scheduler intervention during the first 60–180s of execution
- Distinguishable from watchdog hang-kill (which fires after elapsed >= `WATCHDOG_TIMEOUT` >= 600s, always outside the 300s window)

### Applicable Phases
- Any phase whose runner is `run-issue.sh`, `run-spec.sh`, `run-code.sh`, or `run-auto-sub.sh`
- Layer A: claude invocation inside leaf wrappers (run-issue.sh, run-spec.sh, run-code.sh)
- Layer B: child runner invocation inside `run-auto-sub.sh run_phase_with_recovery()`

### Fallback Steps
1. `scripts/retry-on-kill.sh` `run_with_retry_on_kill()` detects exit code 137 or 143 and measures elapsed time
2. If elapsed < `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` (default 300s): log to stderr `"retry-on-kill: command killed (exit N) after Ms (< Ks); auto-retrying once"`, set `_RETRY_ON_KILL_FIRED=true`, and retry the command once
3. If retry succeeds (exit 0): normal wrapper flow continues; `run-auto-sub.sh` records a `wrapper-retry-on-kill success` entry to `docs/reports/orchestration-recoveries.md`
4. If elapsed >= threshold (Branch C): no retry — this is a watchdog hang-kill handled by the parent `json-mode-silent-hang` pattern

### Escalation
- If retry also exits 137 or 143 (Branch D): log `"retry-on-kill: retry also killed; escalating to recovery/manual"` and return the kill exit code to the caller
- Leaf wrappers (run-issue/spec/code): the kill exit code propagates to the parent `/auto` session for manual recovery
- `run-auto-sub.sh`: the kill exit code reaches `run_phase_with_recovery()` which proceeds to Tier 1/2/3 adaptive recovery
- Automatic retry is 1 time only; no further looping

### Rationale
- Introduced in Issue #807: `/auto --batch` sessions observed `run-issue.sh` being killed at 60–120s (before watchdog could fire at >= 600s); manual retry succeeded on the second attempt; this mechanism automates that pattern at the wrapper level
- Implementation uses shared sourceable helper `scripts/retry-on-kill.sh` (same pattern as `watchdog-defaults.sh`, `guard-prefix.sh`) sourced by all 4 wrapper scripts
- Threshold 300s ensures non-overlap with watchdog hang-kill (minimum watchdog timeout is merge phase at 600s); see `scripts/watchdog-defaults.sh` for phase-specific values
- Complementary to `json-mode-silent-hang` (which handles watchdog-timeout kills via parent-session retry); these two patterns cover orthogonal elapsed-time ranges (< 300s vs >= 600s)
- Pointer comment `# See modules/orchestration-fallbacks.md#wrapper-retry-on-kill` is placed immediately above the `run_with_retry_on_kill` call in each script

---

## external-kill-parent-respawn

### Symptom
- A background `run-*.sh` wrapper (invoked via `claude -p` from a parent `/auto` session) stops producing output and never returns, with no `Exit code:` trailer line in `.tmp/wrapper-out-$NUMBER-$PHASE.log`
- `.tmp/auto-events.jsonl` has no `wrapper_exit` event for the phase, and no backfilled `phase_complete` event either — the `_maybe_emit_phase_complete()` EXIT trap fires on exit 0/143 but never ran, meaning the wrapper's own process (not just its leaf `claude -p` child) was killed before its trap could execute
- Not a watchdog timeout: observed silent windows (e.g. "silent for 480s", "silent for 1260s") are well under the phase's configured watchdog timeout
- Not a jetsam/OOM kill: `/Library/Logs/DiagnosticReports/` and `~/Library/Logs/DiagnosticReports/` show no matching `JetsamEvent-*` report for the kill window
- Elapsed time to kill is not fixed (observed range: roughly 2–22 minutes across 7 occurrences)

### Applicable Phases
- Any phase launched as a background wrapper by the parent `/auto` session: `run-auto-sub.sh`, `run-code.sh`, `run-spec.sh`, `run-review.sh`, `run-merge.sh`

### Fallback Steps
1. Detect the signature above (see `skills/auto/SKILL.md` Step 6 "External kill pre-check (before Tier 1)")
2. Respawn the same `run-*.sh` with the same arguments — the `phase/*` label (SSoT) and the `code_phase_milestone` checkpoint restore existing progress, so the respawn resumes rather than restarting from scratch
3. After the respawned phase completes, record the recovery via `#manual-recovery-spec-write` below, using recovery type `respawn`

### Escalation
- None — the parent session is the only actor able to observe and act on this kill (see Rationale); there is no deeper tier to escalate to

### Rationale
- Introduced in Issue #1005: investigation of session 37830 (2026-07-13) `events.jsonl` found that killed phases have neither a `wrapper_exit` event nor a backfilled `phase_complete` event, confirming the wrapper process itself (including its EXIT trap) was terminated, not merely its leaf `claude -p` child
- This makes `retry-on-kill.sh`'s Layer B (`run_with_retry_on_kill()` running inside `run-auto-sub.sh`) structurally unable to fire: it executes inside the same process group that gets killed, so it cannot observe or react to its own termination — see `wrapper-retry-on-kill` above for the process-group-internal case this pattern cannot cover
- Because the wrapper cannot self-detect or self-recover, the parent `/auto` session is the only recovery-capable actor; this is a deliberate design constraint, not an implementation gap
- Root cause of the external kill itself remains an open hypothesis (Claude Code harness background-task lifecycle vs. terminal/shell process-group kill vs. unknown); see `docs/reports/external-kill-investigation.md`

---

## manual-recovery-spec-write

### Symptom
- Parent session manually called `worktree-merge-push.sh`, `gh pr create`, or `run-*.sh` to recover a sub-issue from a kill or mid-run failure — independent of Tier 1/2/3 automatic recovery
- The sub-issue Spec's `## Auto Retrospective` section does not have a recovery entry for this manual intervention

### Applicable Phases
- code, review, merge (XL sub-issue parent session manual recovery); also the `external-kill-parent-respawn` pattern above

### Fallback Steps
1. After the manual recovery action completes successfully, run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE EXIT_CODE
   ```
   where `RECOVERY_TYPE` is a short string describing the action taken (e.g., `push-only`, `pr-create`, `review-rerun`, `respawn`) and `EXIT_CODE` is the original wrapper exit code, or `unknown` if it could not be observed
2. Before doing anything, the subcommand resolves the *main* repository root (via `git worktree list --porcelain`, falling back to `git rev-parse --show-toplevel` then `pwd`) and `cd`s there, so all writes below land on main even when the subcommand is invoked from a non-main worktree CWD (see #1005 — a `--write-manual-recovery` call made from a code worktree CWD previously pushed its record to that worktree's PR branch instead of main)
3. The subcommand then writes to three places, each with a distinct consumer:
   - `_write_manual_recovery_to_spec()`: appends a `### Manual recovery (PHASE)` entry to the sub-issue Spec's `## Auto Retrospective` section (consumed by `/verify` Step 12's skip-judgment)
   - `_write_manual_recovery_to_recoveries_log()`: appends a `## <date> UTC: manual-recovery-<type>` (H2) entry to `docs/reports/orchestration-recoveries.md` (consumed by `scripts/collect-recovery-candidates.sh` frequency detection and `recoveries-auto-fire`)
   - `emit_event "manual_intervention" ...`: appends a `manual_intervention` event to `.tmp/auto-events.jsonl` (consumed by the L3 session retrospective's `Parent session manual interventions` Metrics row)
4. The open-PR guard (`gh pr list --search "closes #ISSUE" --state open`) applies **only** to the Spec write in step 3's first bullet — a self-induced merge conflict risk exists only there, since the open PR's branch may also touch the same Spec file (#890). The recoveries log and event writes proceed unconditionally: `orchestration-recoveries.md` is not touched by PR branches, and the event log has no merge-conflict surface at all

### Escalation
- If any individual write fails (commit/push failure for the Spec or recoveries-log write), a WARNING is logged to stderr for that write and execution continues to the remaining writes — a failure in one of the three recording paths is non-fatal to the others

### Rationale
- Introduced in Issue #822: `_write_tier2_recovery_to_spec()` and `_write_tier3_recovery_to_spec()` (Issue #800) only cover automatic recovery paths; manual recovery by the parent session left `## Auto Retrospective` incomplete, requiring verify-session manual supplementation
- Symmetric with Tier 2/3 paths: same `## Auto Retrospective` section, same `### <type> recovery (phase)` heading format
- `/verify` Step 12's skip-judgment now includes `### Manual recovery` entries as "already recorded" (alongside Tier 2/Tier 3), eliminating the need for manual supplementation
- Extended in Issue #1005 to also write `docs/reports/orchestration-recoveries.md` and emit a `manual_intervention` event: the Spec-only write left cross-Issue frequency detection and session Metrics permanently at zero, since parent-session-driven recovery happens entirely outside the Tier 1/2/3 machinery that feeds those other two consumers
- Hardened in Issue #1012: both `_write_manual_recovery_to_spec()` and `_write_manual_recovery_to_recoveries_log()` now call `_pull_ff_only()` (a fast-forward-only `git pull`) at the start of their read/write/commit sequence, so a local main left behind by an un-pulled prior merge no longer causes the subsequent commit's push to be rejected non-fast-forward and the recovery record to be lost

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

### Tier 2 bash path: Spec Auto Retrospective write

When `run-auto-sub.sh` runs the Tier 2 path (`apply-fallback.sh` succeeds), the recovery record is written not only to `docs/reports/orchestration-recoveries.md` (via Step 4a Source 1 in the parent `/auto` session) but also to the affected sub-issue's Spec file (`docs/spec/issue-N-*.md`) `## Auto Retrospective` section immediately at recovery time (bash path, not LLM path).

Mechanism:
- `apply-fallback.sh` outputs structured metadata (symptom-short / phase / fallback action / result) to stdout on success; internal echo statements go to stderr
- `run-auto-sub.sh` captures this stdout into a temp file (`_fallback_meta_file`) and calls `_write_tier2_recovery_to_spec()` when the file is non-empty
- `_write_tier2_recovery_to_spec()` appends the metadata to the Spec's `## Auto Retrospective` section and commits/pushes immediately

This write happens during the sub-issue execution phase, before the parent `/auto` Step 4a runs. When Step 4a Source 1 (`fallback-catalog`) runs later, the sub-issue Spec Auto Retrospective is already up to date. The parent session's Step 4a writes `orchestration-recoveries.md` as the session-level SSoT; the Spec write here serves the per-Issue paper trail.

### Manual path: Spec Auto Retrospective write

When the parent session performs a manual recovery (e.g., `worktree-merge-push.sh` re-run, `gh pr create` manual call, or `run-*.sh` re-execution), there is no automatic bash path to write the recovery record. The operator must explicitly call:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE
```

This invokes `_write_manual_recovery_to_spec()`, which first checks for an open PR linked to the issue and, if none exists, appends a `### Manual recovery (PHASE)` entry to the sub-issue Spec's `## Auto Retrospective` section and commits/pushes immediately — symmetric with the Tier 2 and Tier 3 bash paths described below. If an open PR exists for the issue, the write and commit/push are skipped to avoid a self-induced merge conflict with that PR's branch (#890); a warning is logged and the operator should retry after the PR merges. `/verify` Step 12 treats `### Manual recovery` entries as "already recorded" and skips redundant retrospective writing.

See also: `modules/orchestration-fallbacks.md#manual-recovery-spec-write`

### Tier 3 bash path: Spec Auto Retrospective write

When `run-auto-sub.sh` runs the Tier 3 path (`spawn-recovery-subagent.sh` succeeds), the recovery record is written not only to `docs/reports/orchestration-recoveries.md` (committed by the bash block immediately after sub-agent success) but also to the affected sub-issue's Spec file (`docs/spec/issue-N-*.md`) `## Auto Retrospective` section — symmetrically with Tier 2.

Mechanism:
- `spawn-recovery-subagent.sh` writes recovery details to `orchestration-recoveries.md`; the bash block in `run_phase_with_recovery()` commits and pushes that file immediately
- `_write_tier3_recovery_to_spec()` is then called with `"$issue" "$phase" "$exit_code"` to build a minimal entry from those variables and append it to the Spec's `## Auto Retrospective` section, committing and pushing in turn
- The entry includes date, issue/phase, source (`spawn-recovery-subagent.sh`), wrapper exit code, outcome, and a pointer to `orchestration-recoveries.md` for full details

This write establishes the same per-Issue paper trail as Tier 2 (`_write_tier2_recovery_to_spec()`), enabling `/verify` Step 12's skip-judgment logic to treat Tier 3 recovery as "already recorded" without requiring manual supplementation in the verify retrospective.
