---
type: project
---

# 🔧 Troubleshooting

Common issues and how to fix them.

## GitHub CLI Authentication

**Symptom**: Skills fail with `gh: command not found` or `HTTP 401` errors.

**Fix**:

```bash
# Check if gh is installed
gh --version

# Authenticate if needed
gh auth login

# Verify authentication
gh auth status
```

Wholework requires `gh` to be installed and authenticated with access to the target repository. If you use a GitHub App or token, ensure it has `repo` scope (Issues, PRs, Contents).

## Plugin Install Failures

**Symptom**: `/wholework:code` is not recognized, or skills show as unavailable.

**Fix**:

```
# Re-run the install steps in Claude Code
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

If the issue persists, try development install:

```bash
git clone https://github.com/saitoco/wholework.git
cd wholework
./install.sh
# Then start Claude Code with:
claude --plugin-dir /path/to/wholework
```

Check that `${CLAUDE_PLUGIN_ROOT}` is set when skills run — this is automatically set by Claude Code when using `--plugin-dir` or the marketplace install.

## Reading Verify Command Failures

**Symptom**: `/verify` reports FAIL or UNCERTAIN on an acceptance condition.

**What the output means**:

- `PASS` — The verify command succeeded; the condition is met
- `FAIL` — The verify command ran but the expected content or state was not found
- `UNCERTAIN` — The verify command could not run (syntax error, missing file, etc.)

**How to diagnose a FAIL**:

1. Look at the failing condition in the Issue — the `<!-- verify: ... -->` comment shows what was checked
2. Common types:
   - `file_exists "path/to/file"` — the file does not exist yet
   - `file_contains "path" "text"` — the file exists but is missing the expected string
   - `section_contains "path" "Section" "text"` — the section exists but is missing the string
   - `command "bash script.sh"` — the command returned a non-zero exit code

3. Fix the underlying issue and re-run `/verify N`

**If a verify command itself is wrong** (wrong file path, wrong expected string):

Run `/code N` to enter a fix cycle. During implementation, Wholework will detect and correct miscalibrated verify commands before re-running verification.

## Skill Hangs or Times Out

**Symptom**: A skill runs for a very long time without output.

**Fix**: Press Ctrl+C to stop. Check:

- Does the issue have a `size/*` label or Size set in GitHub Projects? Unsized issues prompt for user input in interactive mode.
- Is there a pending confirmation that needs a response?

For unattended runs via `/auto`, ensure the issue is triaged (has a `phase/*` or `triaged` label) before starting.

## Further Help

- Open an issue at [github.com/saitoco/wholework](https://github.com/saitoco/wholework/issues)
- Check existing issues for similar problems
