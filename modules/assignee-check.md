# assignee-check

Pre-flight assignee check shared by `/issue` (existing Issue refinement), `/spec`, and `/code`. It runs before the calling skill's first side effect and, when another member is assigned to the Issue, asks whether to reassign, continue, or abort.

## Purpose

Prevent duplicate work on an Issue that another member has already taken. The check only reads the assignee, except for the explicit "reassign" choice. Setting the assignee of an unassigned Issue is not done here: the calling skill's start-of-phase label transition does it with `--assign`.

## Input

- `ISSUE_NUMBER`: the Issue number being processed
- `PHASE_NAME`: `issue`, `spec`, or `code` (used only in messages)
- `NON_INTERACTIVE`: `true` when the calling skill's ARGUMENTS contains `--non-interactive`, otherwise `false`

## Processing Steps

Run every command below from the repository root (the directory that holds `.wholework.yml`), as one simple command at a time. `gh-issue-assignee.sh` reads `auto-assign` from the current directory, and this check runs before the calling skill enters a worktree, so the current directory is the main checkout root.

### 1. Read the assignment status

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status $ISSUE_NUMBER
```

`STATUS` is the output line that, after trimming surrounding whitespace and a trailing CR, is exactly one of `unassigned`, `self`, `other`, or `unknown`. Lines that start with `Info:` or `Warning:` are messages for people, not result words. When no such line exists (the script is missing, cannot run, exits abnormally, or prints something unexpected), treat the result as "no result".

| STATUS | Action | Outcome |
|---|---|---|
| `unassigned` | Do nothing (the caller's label transition with `--assign` sets the assignee) | `continue` |
| `self` | Do nothing | `continue` |
| `unknown` | Do nothing (the helper has printed a `Warning:`) | `continue` |
| no result | Output the one line below | `continue` |
| `other` | Go to `### 2.` | the outcome of `### 2.` |

The line for "no result":

```
assignee を確認できませんでした (Issue #{ISSUE_NUMBER})。そのまま続行します
```

`other` means at least one assignee is not the executing user. Bots (Copilot and others) count as other members. When the executing user cannot be identified, any assignee makes the status `other` (the helper's contract).

### 2. Another member is assigned (STATUS is other)

`LOGINS` is the list of logins on the standard error line `Info: issue #N is assigned to: <logins>`. When that line is absent, use a phrase meaning "another member" in the messages instead. `LOGINS` is for display only and is never placed into a shell command.

- **Interactive run** (`NON_INTERACTIVE=false`): ask a single-select question with AskUserQuestion. Offer exactly these three choices, in this order and with this wording (double quotes included). Write the question text and the description of each choice in Japanese inside a code fence. When AskUserQuestion is unavailable (the call fails), handle the run the same way as a non-interactive run.

  | Choice | Action | Outcome |
  |---|---|---|
  | `"自分に付け替えて続ける"` | Run `### 3.` | `continue` |
  | `"付け替えずに続ける"` | Do nothing | `continue` |
  | `"中止"` | Output the abort notice below and end the calling skill immediately. Do not run any later step (triage, worktree entry, label transition, assignee writes, comment posting, Spec creation, and everything after them) | `abort` |

  The abort notice (two lines):

  ```
  中止しました: Issue #{ISSUE_NUMBER} は {LOGINS} にアサインされています。assignee もフェーズラベルも変更していません
  続行する場合は、担当者に確認してから /{PHASE_NAME} {ISSUE_NUMBER} を再実行してください
  ```

- **Non-interactive run** (`NON_INTERACTIVE=true`): call neither AskUserQuestion nor `reassign`. This is the skip tier of the Three-Tier Policy in `modules/ambiguity-detector.md` (a High-Stakes Decision). Output these two lines in the standard warning format and continue (outcome `continue`):

  ```
  [non-interactive mode] Skipping high-stakes action: reassigning issue #{ISSUE_NUMBER} from {LOGINS} to the executing user
  To perform this action, run `/{PHASE_NAME} {ISSUE_NUMBER}` interactively.
  ```

### 3. Reassign (only after "自分に付け替えて続ける")

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh reassign $ISSUE_NUMBER
```

Branch on the result word in the output. Whatever the result, the calling skill is not stopped (outcome `continue`).

| Result word | Meaning | Output |
|---|---|---|
| `assigned` | The executing user is now an assignee (when the helper printed a `Warning:` about a simultaneous start, show it to the user as is) | `assignee を実行ユーザーに付け替えました (Issue #{ISSUE_NUMBER})` |
| `unchanged` | There is no one left to replace (removed during the confirmation), or the executing user is already the only assignee | none |
| `disabled` | Nothing was done because `auto-assign: false` is set | `auto-assign: false のため assignee は付け替えていません。そのまま続行します` |
| `failed`, no word, or an unexpected word | The update failed (the reason is the helper's `Warning:`) | `assignee を付け替えられませんでした (理由は上の Warning を参照)。assignee は変更せず続行します` |

## Output

`continue` (the calling skill proceeds to its next step) or `abort` (only when the user chose "中止" in an interactive run; the calling skill ends without running any later step). This module has no path that sets an assignee other than `reassign`.

## Notes

### Why the check comes before any side effect

`/issue N` writes the title, Type, Size, and Value in the Step 2 triage auto-chain. `/spec` and `/code` enter a worktree in Step 2, consume comments, and sweep the work directory. Aborting after those leaves writes on another member's Issue or a leftover worktree, so the check runs first and an abort leaves nothing behind.

### Why `assign` is not called here

Assigning an unassigned Issue is done by the caller's label transition (`--assign`), which guarantees "label transition, then assignment" in one command. Assigning here would repeat the same decision twice.

### `auto-assign: false` and the autonomy tier

The check runs regardless of `auto-assign` and of the autonomy tier, because it respects an assignee that a person set by hand. Only the `reassign` write stops (result `disabled`). Callers do not re-check `HAS_AUTO_ASSIGN` (see `modules/detect-config-markers.md`), so "自分に付け替えて続ける" is offered even when `auto-assign: false` is set, and the `disabled` result is reported to the user.

### Failures never stop the phase (fail-open)

A missing helper, an unreadable result, a failed `reassign`, or an unavailable AskUserQuestion all let the phase continue. Only the user's explicit "中止" stops it. This follows the policy of #1542 that a failure of the assignee feature never blocks a phase.

### Child phases under `/auto`

Child phases started by `/auto` (`run-*.sh` always passes `--non-interactive`) print the same warning once per phase, even after the parent confirmed and chose "付け替えずに続ける". This overlap is accepted: the warning is accurate and takes one line, and suppressing it would need a new argument passed through `run-*.sh` and every SKILL.md.

### Headless runs

In a headless run only the final result of the session is kept in the wrapper log, so a warning printed midway may not be preserved (the same limitation as other non-interactive warnings; see Notes in `modules/phase-banner.md`).

### Callers

| Caller | Position |
|---|---|
| `skills/issue/SKILL.md` | Existing Issue Refinement, Step 1 |
| `skills/spec/SKILL.md` | Step 1 |
| `skills/code/SKILL.md` | Step 1 |

Add a row when a new skill starts to read this module.
