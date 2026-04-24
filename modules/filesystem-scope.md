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

### Prohibited Patterns

| Pattern | Risk | Fix |
|---------|------|-----|
| `grep -rn . .` or `grep -rn '<pat>' .` starting from repo root without `--include` | Scans `.git/`, binary files, and any symlinked external path | Use `git grep` or add `--include='*.sh'` |
| `find . -name ...` without `-maxdepth` | Crosses repo boundary via symlinks | Add `-maxdepth N` or use `git ls-files` |
| `Glob("**/*.md")` without `path` argument | Claude Code Glob tool defaults to CWD; if CWD drifts above repo root, scope expands | Always pass explicit `path` scoped to repo |
| `Grep(pattern)` without `path` argument | Same as Glob risk | Always pass `path` pointing to a repo subdirectory |

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
