# filesystem-scope

## Purpose

Prevent skill execution from accessing filesystem locations outside the repository root.
Broad recursive scans (Glob `**`, `grep -rn .`, `find .`) starting from an unconstrained base
can traverse OS-protected directories (e.g., `~/Pictures/Photos Library.photoslibrary`,
`~/Music/`), triggering macOS TCC (Transparency, Consent, and Control) permission prompts.

This module documents the constraints and approved patterns for all file I/O in skills,
modules, and scripts.

## Constraints

### Allowed Base Paths

All file I/O during skill execution MUST originate from one of:

| Base | Example |
|------|---------|
| Repository root or a subdirectory | `docs/`, `scripts/`, `.github/` |
| Worktree directory | `.claude/worktrees/<name>/` |
| `${CLAUDE_PLUGIN_ROOT}` | Plugin-owned files only |
| Single named config file under `$HOME` | `~/.wholework/config.yml` (exact path, no traversal) |
| Script-private scratch under `$TMPDIR` | bare `mktemp` / `mktemp -d` inside a bundled script — see Temporary Files below |

### Prohibited Patterns

| Pattern | Risk | Fix |
|---------|------|-----|
| `grep -rn . .` or `grep -rn '<pat>' .` starting from repo root without `--include` | Scans `.git/`, binary files, and any symlinked external path | Use `git grep` or add `--include='*.sh'` |
| `find . -name ...` without `-maxdepth` | Crosses repo boundary via symlinks | Add `-maxdepth N` or use `git ls-files` |
| `Glob("**/*.md")` without `path` argument | Claude Code Glob tool defaults to CWD; if CWD drifts above repo root, scope expands | Always pass explicit `path` scoped to repo |
| `Grep(pattern)` without `path` argument | Same as Glob risk | Always pass `path` pointing to a repo subdirectory |

### Temporary Files

Where a temporary file lives depends on who creates it and whether its path leaves the creating process (examples, not exhaustive):

| Creator | Placement | Rule |
|---------|-----------|------|
| Skill / module procedure (an LLM-executed step) | `.tmp/` in the project (gitignored) | Create with the Write tool after `mkdir -p .tmp`, or `mktemp .tmp/<name>-XXXXXX` when a shell snippet must create it. Never `/tmp/` — this is the Non-Goal in `docs/product.md` |
| Bundled script — path handed back to the caller, or file read/removed by a later tool call | `.tmp/` (absolute `$PWD/.tmp/` path) | The path outlives the script, so it stays inside the project like any LLM-created file. Put the `X` run at the very end of the template (BSD `mktemp` does not randomize it otherwise) |
| Bundled script — credential-bearing scratch file | `.tmp/` | Project-local and owner-only (`mktemp` creates mode 600); remove it right after use so secrets stay out of the shared `$TMPDIR` |
| Bundled script — private scratch file | `$TMPDIR` via bare `mktemp` / `mktemp -d` (no template; default `/tmp`) | Out of scope of the Non-Goal. Created, consumed, and removed within one script invocation, and never exposed to an LLM tool call. Remove it before exit (`trap ... EXIT` or an explicit `rm`). Use `mktemp -d` when the scratch space must stay outside the working tree (e.g. the ephemeral detached git worktree in `scripts/pre-merge-check.sh`) |

Why private scratch is out of scope: the Non-Goal keeps files that Claude creates, or hands from one tool call to the next, inside the project (gitignored, inspectable, covered by worktree isolation). A bundled script's private scratch file never crosses a tool-call boundary, and a uniquely named `mktemp` file avoids the collisions that fixed `/tmp/` names cause between concurrent sessions. A hard kill (SIGKILL) skips every cleanup path: a leftover in `$TMPDIR` can be reclaimed by the OS, whereas a leftover in `.tmp/` would persist in the project.

## Approved Patterns

### Bash scripts — use `git grep` for tracked-file search

```bash
# Scan conflict markers — tracked files only
git grep -l '^<<<<<<' 2>/dev/null

# Find files containing a keyword — tracked files only
git grep -l 'keyword' -- '*.sh' 2>/dev/null

# Enumerate all tracked files and pipe to xargs
git ls-files | xargs grep -l 'pattern' 2>/dev/null
```

### Bash scripts — use explicit paths with `find`

```bash
# Limit recursive descent
find scripts/ -maxdepth 2 -name '*.sh'

# Absolute path from repo root (requires REPO_ROOT)
find "${REPO_ROOT}/scripts" -name '*.bats'
```

### Bash scripts — temporary files

```bash
# Private scratch file: bare mktemp (default $TMPDIR), removed by the script itself
scratch="$(mktemp)"
trap 'rm -f "$scratch"' EXIT

# Path handed back to the caller: project-local, absolute, X run at the very end
mkdir -p .tmp
out_file="$(mktemp "$PWD/.tmp/<name>-XXXXXX")"
echo "$out_file"
```

### LLM skills — use scoped Glob and Grep calls

```markdown
# Glob: always provide path= scoped to repo
Glob("**/*.md", path="docs")          # Good — scoped to docs/
Glob("*.sh", path="scripts")           # Good — scoped to scripts/

# Grep: always provide path= or use type filter
Grep(pattern="keyword", path="scripts")   # Good
Grep(pattern="keyword", type="sh")        # Good
```

## Implementation Reference

- `scripts/worktree-merge-push.sh` — uses `git grep` for conflict marker detection
- `modules/orchestration-fallbacks.md` — documents conflict marker detection using `git grep -l '^<<<<<<'` (consistent with `worktree-merge-push.sh`)
- `skills/spec/SKILL.md` — rename-issue grep uses `.` as CWD; must be run from repo root
- `skills/code/stale-test-check.md` — uses `git grep -n` to scan tracked test files only (compliant with this module)
- `skills/code/SKILL.md` — Step 7 steering docs existence check uses Glob with explicit `path="$STEERING_DOCS_PATH"` (compliant with this module)
- `modules/codebase-analysis.md` — entry point, dependency, test, and docstring Glob/Grep calls use explicit `path` argument pointing to the target directory (compliant with this module)
- `modules/doc-checker.md` — `$STEERING_DOCS_PATH` document candidate listing uses `Glob("*.md", path="$STEERING_DOCS_PATH")` form (compliant with this module)
- `scripts/resolve-preview-env.sh` — creates credential-bearing temp files under an absolute `$PWD/.tmp/` template and hands the path back to its caller (compliant with Temporary Files)
- `scripts/pre-merge-check.sh` — `mktemp -d` host directory for an ephemeral detached git worktree, kept outside the repository working tree; the other bare-`mktemp` scratch files in `scripts/` (enumerate with `git grep -nE '\$\(mktemp( -d)?\)' -- scripts/`) follow the same private-scratch rule (examples)
