English | [日本語](../ja/reports/repo-scope-audit.md)

# Repository-Boundary Filesystem Access Audit

**Issue**: #378 skills: restrict repository-boundary filesystem access during skill execution
**Date**: 2026-04-24
**Status**: Mitigated (pre-merge)

---

## Reproduction Steps

1. Launch Claude Code as a fresh session on macOS
2. Under System Settings > Privacy & Security, revoke Claude Code's "Photos", "Apple Music", and "Media & Apple Music" permissions before starting (to re-trigger the TCC prompts)
3. Enable Wholework as a plugin and open the repository
4. Run any skill (e.g., `/issue "dummy"` or `/spec 378`)
5. Observe macOS TCC prompts such as "Claude wants to access your Photos library / Apple Music / Media library" appearing during execution

---

## Root Cause

### How macOS TCC (Transparency, Consent, and Control) works

macOS TCC monitors access to these protected directories and displays an authorization dialog on first access:

- `~/Pictures/Photos Library.photoslibrary` (Photos library)
- `~/Music/` (Apple Music / music library)
- `~/Movies/` (media library)

TCC fires not only on explicit reads via Python/SQLite but also whenever **filesystem enumeration APIs such as `opendir()` / `readdir()` cross into protected paths**. Therefore, a recursive scan like `grep -r .` or `find . -name "*"` rooted in an ancestor directory that contains TCC-protected paths can trigger the prompts even without an explicit attempt to read those files.

### Evaluation of hypotheses

Static analysis produced three hypotheses:

| Hypothesis | Description | Assessment |
|------------|-------------|------------|
| a | Claude Code's Glob/Grep/Read tools invoked without an explicit scope perform broad scans | **Plausible contributor** (see below) |
| b | A `grep -rn ... .` inside a bash script runs with an unintended CWD | **Partial contributor** (see below) |
| c | Claude Code runtime behavior (e.g., Spotlight/mdfind integration) | **Probable primary cause** (see below) |

#### Hypothesis a: Glob / Grep tool invocations

`skills/doc/SKILL.md` contains the instruction:

```
Search with Glob `**/*.md` ...
```

A `Glob("**/*.md")` call without a `path` parameter uses the current working directory (CWD) as the base inside Claude Code. CWD is normally the repository root and therefore safe, but under certain skill-execution contexts it might be set outside the repository. Adding guidance in `modules/filesystem-scope.md` documents this risk.

#### Hypothesis b: The bash `grep -rn '^<<<<<<' .` call

`scripts/worktree-merge-push.sh:89` previously contained:

```bash
conflict_output=$(grep -rn '^<<<<<<' . 2>/dev/null || true)
```

This script runs from the repository root (`git rev-parse --show-toplevel`), so `.` normally equals the repo root and the scan stays inside the repository. However:

- `grep -rn` may follow symbolic links
- Object files under `.git/` also become targets
- Git submodules pointing outside the repository propagate the scan

Replacing the call with `git grep -l '^<<<<<<'` confines the search to **tracked files only**.

#### Hypothesis c: Claude Code runtime behavior (probable primary cause)

Static analysis found no explicit hardcoded references to paths outside the repository. Because the TCC prompts appear in the **early stage of any skill execution** (right when the LLM begins invoking tools, not after a specific bash command), the likely primary cause is:

- **Claude Code internal file-indexing**: Claude Code (Electron app) uses the FSEvents API to index the filesystem when a new session starts or a project is loaded. This may walk `$HOME`.
- **OS-level Glob implementation**: `Glob("**/*.md")` and similar calls enumerate the filesystem via `opendir()` / `readdir()`; if the pattern is not sufficiently bounded, the enumeration can cross TCC-protected directories.

If this hypothesis holds, skill-side fixes alone cannot fully eliminate the prompts, but the following mitigations reduce the risk:

1. Supply an explicit scope-bounded `path` to every Glob/Grep call
2. Use `git grep` in bash scripts so the scope stays limited to tracked files

---

## Offending Sites

| File | Line | Issue | Priority |
|------|------|-------|----------|
| `scripts/worktree-merge-push.sh` | 89 | `grep -rn '^<<<<<<' .` — scope spans everything under CWD | High |
| `modules/orchestration-fallbacks.md` | 176, 184 | Documentation example using `grep -rn '^<<<<<<' .` (script is fixed; the doc text is retained as historical reference) | Low |
| `skills/spec/SKILL.md` | 235 | `grep -rn 'old-name' .` — does not explicitly state the command must run from the repository root | Medium |
| `skills/doc/SKILL.md` | 333 | `Glob **/*.md` — no `path` parameter | Medium |

---

## Mitigations

### Applied (this PR)

1. **`scripts/worktree-merge-push.sh`**
   Replaced `grep -rn '^<<<<<<' .` with `git grep -l '^<<<<<<'`. Because `git grep` only scans tracked files, it cannot cross the repository boundary.

2. **`modules/filesystem-scope.md` (new)**
   Added a module that documents filesystem-access scoping guidance for Glob / Grep / Read tools and bash scripts: permitted base paths, forbidden patterns, and recommended patterns.

3. **`skills/spec/SKILL.md`**
   Annotated the rename-issue grep call (`grep -rn 'old-name' .`) to require execution from the repository root, and added a cross-reference to `modules/filesystem-scope.md`.

4. **`docs/structure.md`**
   Updated the modules count (31 → 32) and added an entry for `filesystem-scope.md`.

### Deferred (recommended follow-ups)

- Add an explicit `path` parameter to the `Glob **/*.md` call in `skills/doc/SKILL.md:333` (priority: Medium)
- Update the documentation in `modules/orchestration-fallbacks.md:184` to recommend `git grep` (priority: Low)
- File an issue against Claude Code itself for the runtime-level behavior (skills cannot fully address hypothesis c)

---

## Verification Results

### Pre-merge verification

| Item | Status | Notes |
|------|--------|-------|
| `scripts/worktree-merge-push.sh` no longer uses `grep -rn` | ✅ PASS | Switched to `git grep -l` |
| `modules/filesystem-scope.md` created | ✅ PASS | Scope-limit guidance captured |
| `skills/spec/SKILL.md` carries the scope annotation | ✅ PASS | Explicit CWD note added |
| `docs/reports/repo-scope-audit.md` exists | ✅ PASS | This file |

### Post-merge verification

Manual check that TCC prompts no longer appear in a fresh Claude Code session:

1. Revoke Claude Code's Photos, Apple Music, and Media permissions in System Settings > Privacy & Security
2. Start a fresh session and run `/issue "dummy title"`
3. Run `/code N` and `/verify N`
4. Confirm that no TCC prompts appear

**Caveat**: If hypothesis c (Claude Code runtime behavior) is the primary cause, the changes in this PR alone may not eliminate the prompts in the post-merge manual check. In that case, amend `modules/filesystem-scope.md` to note "an upstream issue against Claude Code is required" and narrow Issue #378's post-merge acceptance criteria to "documentation guidance only".
