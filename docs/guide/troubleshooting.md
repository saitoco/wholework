---
type: project
---

# 🔧 Troubleshooting

Solutions to common problems when setting up and using Wholework.

## GitHub CLI Authentication

**Symptom:** Commands fail with `gh: command not found` or `Error: authentication required`.

**Fix:**

1. Install `gh` if missing: [cli.github.com](https://cli.github.com)
2. Authenticate:
   ```bash
   gh auth login
   ```
3. Confirm authentication:
   ```bash
   gh auth status
   ```

Wholework calls `gh` internally for all Issue and PR operations. The CLI must be authenticated with permission to read and write Issues and PRs on your repository.

## Plugin Install Failure

**Symptom:** `/plugin install wholework@saitoco-wholework` fails or skills are not recognized.

**Fix:**

Run these commands in order inside Claude Code:

```
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

If skills still do not appear, restart Claude Code and try again. The plugin is cached at session start.

If you are using the development install (local clone), make sure you ran `./install.sh` after cloning:

```bash
cd /path/to/wholework
./install.sh
```

## Verify Command Failures

**Symptom:** `/verify` reports `FAIL` for one or more acceptance conditions.

**Understanding the output:**

`/verify` reports each condition with one of three statuses:

| Status | Meaning |
|--------|---------|
| `PASS` | Condition is met |
| `FAIL` | Condition is not met — implementation may be incomplete or the verify command may be miscalibrated |
| `UNCERTAIN` | Verify command syntax error or unexpected output — skip and handle manually |

**When a condition FAILs:**

1. Read the failing condition carefully
2. Check whether the implementation actually covers it
3. If the implementation is correct but the verify command is wrong, edit the `<!-- verify: ... -->` comment in the Issue body to fix the check
4. Re-run `/verify` after making changes

**Common causes:**

- The verify command checks for a string that was renamed or moved
- A file path in the verify command does not match the actual file location
- The verify command checks a section header that was worded differently in the implementation

## Phase Label Is Wrong

**Symptom:** `/auto` or a skill skips an expected step or starts at the wrong phase.

**Fix:**

Check the current `phase/*` label on the Issue:

```bash
gh issue view 42 --json labels
```

Remove the incorrect label and add the correct one:

```bash
gh issue edit 42 --remove-label "phase/verify" --add-label "phase/ready"
```

Phase label reference:

| Label | Meaning |
|-------|---------|
| `phase/issue` | Requirements refinement in progress |
| `phase/spec` | Spec being written |
| `phase/ready` | Spec complete, ready for implementation |
| `phase/code` | Implementation in progress |
| `phase/review` | PR under review |
| `phase/merge` | Merging |
| `phase/verify` | Post-merge verification |

## Getting More Help

- For usage questions and examples, see the rest of [docs/guide/](index.md)
- For architecture and contribution details, see [CONTRIBUTING.md](../../CONTRIBUTING.md)
- To report bugs or request features, open a GitHub Issue
