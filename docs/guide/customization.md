---
type: project
ssot_for:
  - customization-entry-points
---

English | [日本語](../ja/guide/customization.md)

# 🛠️ Customization

Wholework adapts to your project through three layers of configuration: `.wholework.yml` for feature flags, `.wholework/domains/` for skill-phase instructions, and adapters for tool integration.

## `.wholework.yml`

Create a `.wholework.yml` file at your project root to enable optional features and configure paths.

```yaml
# .wholework.yml

# Review tool integrations (all disabled by default)
copilot-review: true        # Wait for GitHub Copilot review before merging
claude-code-review: true    # Wait for Claude Code Review before merging
coderabbit-review: true     # Wait for CodeRabbit review before merging
review-bug: false           # Disable bug-detection agent in /review

# Session title auto-rename when /auto is invoked
session-auto-rename: true   # Rename session title to issue number and title when /auto N is invoked

# Post-skill verification
opportunistic-verify: true  # Run quick verify commands at skill completion

# Skill improvement proposals
skill-proposals: true       # Generate Wholework improvement issues during /verify

# Steering hint (enabled by default; set to false to opt out)
steering-hint: false        # Suppress the "/doc init" hint shown when steering docs are missing

# Custom paths (defaults shown)
spec-path: docs/spec              # Where specs are stored
steering-docs-path: docs          # Where steering documents live

# Production URL for browser-based verify commands
production-url: https://yourapp.example.com

# Watchdog timeout (default: 2700 seconds)
# Claude's extended thinking time on Size L+ tasks (especially Opus with high effort)
# can produce silent periods exceeding 2700 seconds. Set to 3600 for meta-development.
watchdog-timeout-seconds: 3600

# Per-phase overrides (optional; take precedence over watchdog-timeout-seconds)
# watchdog-timeout-spec-seconds: 1800
# watchdog-timeout-code-seconds: 4680
# watchdog-timeout-review-seconds: 2600
# watchdog-timeout-merge-seconds: 600
# watchdog-timeout-issue-seconds: 600

# Patch lock timeout for main-branch push (default: 300 seconds; lock is held only during git merge + push)
patch-lock-timeout: 300

# Paths excluded from dirty-file detection during /verify
# Supported: dir/** prefix match; simple bash globs (*, ?, [...]) for full-path match
# Not supported: intermediate ** (e.g. a/**/b) or negation patterns (!)
verify-ignore-paths:
  - vault/**
  - vault/.obsidian/**

# Permission mode for /auto subprocess (default: auto)
# "auto" uses --permission-mode auto with allow rules template (see docs/guide/auto-mode-template.json)
# "bypass" uses --dangerously-skip-permissions (legacy / opt-out)
permission-mode: auto

# Autonomy tier: how far skills may write GitHub state and fire follow-on loops (default: L1)
# L1 = advisory only (safest), L2 = assisted (main workflow + seed), L3 = unattended (CronCreate allowed)
# autonomy: L2

# XL sub-issue parallel execution concurrency cap (default: 5)
# auto-max-concurrent: 5

# Verify reopen loop limit (default: 3, max: 20)
# Stops the verify-reopen cycle after N failures; Issue stays in phase/verify for human judgment
verify-max-iterations: 3

# Auto-retry on verify FAIL (opt-in; requires autonomy: L2 or L3)
# When enabled, /verify automatically re-fires /code and retries after a FAIL,
# up to max_iterations times or until budget_tokens is estimated exhausted.
# auto-retry-on-fail:
#   enabled: true
#   max_iterations: 3
#   budget_tokens: 500000
#   route_override: auto

# Auto-file improvement Issues when orchestration-recoveries.md symptom count exceeds threshold
# (opt-in; requires autonomy: L2 or L3)
# recoveries-auto-fire:
#   enabled: true
#   threshold: 3

# Optional capabilities
capabilities:
  browser: true             # Enable Playwright-based verify commands
  workflow: true            # Enable Workflow-based multi-agent execution in /review --full
  pr-preview: true          # Declare that PRs produce a preview URL (enables pre-merge-preview AC tier)

# Website project settings: force PR route and stop before auto-merge
# (orthogonal to autonomy: tier — controls pipeline reach, not decision autonomy)
# always-pr: true           # Force pr route regardless of Size (XS/S also get branch + PR)
# auto-stop-at: review      # Stop /auto after review phase; run /merge manually
```

All keys are optional. If `.wholework.yml` does not exist, all settings use their defaults.

### Available Keys

This table is the **single source of truth (SSoT)** for all `.wholework.yml` configuration keys. Update this table when adding or changing keys.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `copilot-review` | boolean | `false` | Wait for GitHub Copilot review before merging |
| `claude-code-review` | boolean | `false` | Wait for Claude Code Review before merging |
| `coderabbit-review` | boolean | `false` | Wait for CodeRabbit review before merging |
| `review-bug` | boolean | `true` | Run bug-detection agent in `/review` |
| `opportunistic-verify` | boolean | `false` | Run quick verify commands at skill completion |
| `skill-proposals` | boolean | `false` | Generate Wholework improvement issues during `/verify` |
| `session-auto-rename` | boolean | `false` | Rename session title to issue number and title when `/auto N` is invoked |
| `steering-hint` | boolean | `true` | Show `/doc init` hint when steering docs are missing |
| `production-url` | string | `""` | Production URL for browser-based verify commands |
| `spec-path` | string | `docs/spec` | Where specs are stored |
| `steering-docs-path` | string | `docs` | Where steering documents live |
| `capabilities.browser` | boolean | `false` | Enable Playwright-based verify commands |
| `capabilities.workflow` | boolean | `false` | Enable Workflow-based multi-agent execution in `/review --full` (opt-in; falls back to static Task fan-out when unset) |
| `capabilities.pr-preview` | boolean | `false` | Declare PR preview availability; URL/UX ACs are classified as pre-merge-preview and executed at `/review` when the `PREVIEW_URL` env variable is set. Skipped in `/verify` post-merge to prevent double verification, unless `/review`'s latest `type=preview-ac-unverified` marker lists the AC as unverified, in which case `/verify` falls back to a production-URL check. |
| `capabilities.mcp` | list | `[]` | MCP tool names available to skills |
| `capabilities.{name}` | boolean | `false` | Dynamic capability mapping (e.g., `capabilities.invoice-api: true`) |
| `watchdog-timeout-seconds` | integer | `2700` | Watchdog timeout in seconds before killing a silent `claude -p` process. Claude's extended thinking time on Size L+ tasks (especially Opus with high effort) can produce silent periods exceeding 2700 seconds; set to `3600` for meta-development or Size L+ work. Values ≤0 fall back to the default. |
| `watchdog-timeout-spec-seconds` | integer | `""` (falls back to `1800`) | Per-phase watchdog timeout override for `/spec`. Priority: this key > `watchdog-timeout-seconds` > `1800`. |
| `watchdog-timeout-code-seconds` | integer | `""` (falls back to `4680`) | Per-phase watchdog timeout override for `/code`. Priority: this key > `watchdog-timeout-seconds` > `4680`. |
| `watchdog-timeout-review-seconds` | integer | `""` (falls back to `2600`) | Per-phase watchdog timeout override for `/review`. Priority: this key > `watchdog-timeout-seconds` > `2600`. |
| `watchdog-timeout-merge-seconds` | integer | `""` (falls back to `600`) | Per-phase watchdog timeout override for `/merge`. Priority: this key > `watchdog-timeout-seconds` > `600`. |
| `watchdog-timeout-issue-seconds` | integer | `""` (falls back to `600`) | Per-phase watchdog timeout override for `/issue`. Priority: this key > `watchdog-timeout-seconds` > `600`. |
| `patch-lock-timeout` | integer | `300` | Lock acquisition timeout in seconds for `git merge --ff-only` + `git push origin main` (the only protected critical section). The default is generous since the lock is held only for seconds. Increase only if push consistently fails to acquire. Values ≤0 or non-numeric fall back to `300`. To override per-run without editing `.wholework.yml` (emergency use), set the `WHOLEWORK_PATCH_LOCK_TIMEOUT` env var; priority: env var > this key > `300`. |
| `permission-mode` | string | `"auto"` | Permission mode for `/auto` subprocess. `auto` enables `--permission-mode auto` with allow rules template (see `docs/guide/auto-mode-template.json`); `bypass` uses `--dangerously-skip-permissions` (legacy / opt-out). |
| `verify-max-iterations` | integer | `3` | Limit verify-reopen loop iterations; stops at N failures and leaves Issue in `phase/verify` for human judgment. Values ≤0, >20, or non-numeric fall back to `3`. |
| `auto-max-concurrent` | integer | `5` | Maximum concurrent sub-issue executions in XL parallel route. Applies to each level of the dependency graph. Values ≤0 or non-numeric fall back to `5`. |
| `retro-proposals-upstream` | string | `""` | Upstream repository (`owner/repo`) for routing Skill infrastructure improvement proposals from `/verify` retrospectives. When set, such proposals are sanitized (regex strips absolute paths and downstream issue numbers; LLM removes business-context terms) and filed to this repository; downstream filing is skipped. Unset means downstream filing as before (backward-compatible). |
| `verify-ignore-paths` | list | `[]` | Glob patterns (block list) of paths to exclude from dirty-file detection in `/verify`. Supported: `dir/**` prefix match (any file inside a directory), simple bash globs (`*`, `?`, `[...]`) for full-path match. Not supported: intermediate `**` (e.g. `a/**/b`) or negation patterns (`!`). Files matching any pattern are silently ignored and reported on stderr. Unset means no exclusions. |
| `autonomy` | string | `L1` | Autonomy tier governing which L2→L1 loop-firing paths skills may use. `L1` Report (advisory only) / `L2` Assisted (in-loop + seed) / `L3` Unattended (full, including CronCreate). See [docs/guide/autonomy.md](autonomy.md). |
| `auto-retry-on-fail.enabled` | boolean | `false` | Enable automatic `/code` re-fire + `/verify` retry on FAIL (requires `autonomy: L2` or `L3`). When `false` (or autonomy is `L1`), only advisory guidance is printed. |
| `auto-retry-on-fail.max_iterations` | integer | `3` | Maximum number of auto-retry iterations before stopping and returning to the user. Values ≤0 or non-numeric fall back to `3`. |
| `auto-retry-on-fail.budget_tokens` | integer | `500000` | Approximate token budget for auto-retry iterations. Initial implementation uses iteration count only; budget tracking is a future improvement. Values ≤0 or non-numeric fall back to `500000`. |
| `auto-retry-on-fail.route_override` | string | `"auto"` | Route for auto-retry. `auto`: Size-based (XS/S → `--patch`; M/L → `--pr`; XL → skip/manual); `patch`: always `--patch`; `pr`: always `--pr`. |
| `recoveries-auto-fire.enabled` | boolean | `false` | Auto-file improvement Issues when orchestration-recoveries.md symptom count exceeds threshold (requires `autonomy: L2` or `L3`). When `false` or autonomy is `L1`, prints a recommendation instead. |
| `recoveries-auto-fire.threshold` | integer | `3` | Symptom occurrence count threshold for auto-filing. Values ≤0 or non-numeric fall back to `3`. |
| `next-cycle-seed.enabled` | boolean | `false` | Enable next-cycle candidate seeding after batch completion. Emits `.tmp/next-cycle.json` with `audit/*` Issues created during the batch session (requires `autonomy: L2` or `L3`). When `false` or autonomy is `L1`, prints a recommendation instead. |
| `always-pr` | boolean | `false` | Force pr route (branch + PR) regardless of Size. XS/S Issues that would normally commit directly to main are routed through a PR instead. When `--patch` is also specified, `--patch` is ignored (a warning is printed) and pr route is used. Orthogonal to `autonomy:` tier (controls pipeline route, not decision autonomy). |
| `auto-stop-at` | string | `"verify"` | Declare the phase after which `/auto` should stop. Valid values: `spec`, `code`, `review`, `merge`, `verify`. Default `verify` runs the full pipeline. Use `review` for website projects where merge = publish and human gate before deploy is required. Per-invocation override: `--stop-at=<phase>`. Orthogonal to `autonomy:` tier. |

For the full reference including implementation details and YAML parsing rules, see [`modules/detect-config-markers.md`](../../modules/detect-config-markers.md).

### Website project recommended settings

For projects where the main branch is the production branch (merge = publish), use `always-pr` and `auto-stop-at` together to run `/auto` safely:

```yaml
# Website project recommended settings
always-pr: true       # All changes go through PR regardless of Size
auto-stop-at: review  # Stop after AI review; human reviews PR then runs /merge manually
```

This combination enables the full `/auto` orchestration (issue → spec → code → review) while keeping the merge = publish step under human control. After `/auto` stops at `review`, the user checks the preview URL, reviews the AI review comments, then runs `/merge <issue-number>` to publish.

Note: `always-pr` and `auto-stop-at` are orthogonal to the `autonomy:` tier. The `autonomy:` tier controls which GitHub state writes and loop-firing paths are permitted; `always-pr` controls the PR route; `auto-stop-at` controls the pipeline reach.

### AC verification tiers

Wholework classifies acceptance criteria into three verification tiers:

| Tier | When executed | Typical ACs |
|------|--------------|-------------|
| **pre-merge-local** | `/review` safe mode (always) | File existence, text containment, code quality, test results |
| **pre-merge-preview** | `/review` when `PREVIEW_URL` is set | `http_status`, `html_check`, `api_check`, `http_header`, `http_redirect`, `browser_check`, `browser_screenshot`, `lighthouse_check` |
| **post-merge-production** | `/verify` full mode | Production deployment confirmation, production-only behavior |

**Enabling pre-merge-preview:**

Set `capabilities.pr-preview: true` in `.wholework.yml`. When `/issue` creates or refines an Issue with URL/UX-based verify commands, those ACs are placed in the `### Pre-merge (auto-verified)` section with a `<!-- ac-tier: preview -->` tag and a `--when="test -n \"$PREVIEW_URL\""` guard.

**Resolving `PREVIEW_URL`:**

The `PREVIEW_URL` environment variable must be exported before invoking `/review`. Wholework does not resolve it automatically — this is the responsibility of your CI pipeline or a project-side script. For example:

```bash
# In CI (e.g., GitHub Actions) — set before running /review
export PREVIEW_URL="https://my-pr-123.example-preview.com"
```

**Behavior summary:**

- `PREVIEW_URL` set at `/review` time: preview-tier ACs are executed against the preview URL.
- `PREVIEW_URL` not set: preview-tier ACs are SKIPPED (the `--when` guard fires) and remain unchecked for human follow-up.
- At `/verify` (post-merge): `ac-tier: preview` ACs are skipped by default to prevent double verification. `/review` posts a `type=preview-ac-unverified` marker comment on every run that has at least one `ac-tier: preview` AC in Pre-merge — listing the indices left UNCERTAIN this run, or the sentinel `ac=none` when all preview-tier ACs were verified. `/verify` always resolves only the single most-recent such marker (latest-wins), so a later `/review` run (e.g., after a fix cycle) that clears a previously UNCERTAIN AC is reflected correctly instead of leaving an earlier, now-stale marker as the reference. For any AC still listed as unverified in that latest marker, `/verify` falls back — verifying against `production-url` if configured, or recording an explicit "unverified" warning if not — instead of silently marking it as SKIPPED. To also verify against production regardless of this fallback, duplicate the AC in the `### Post-merge` section without the tag.

## `.wholework/domains/`

Domain files let you add project-specific instructions to individual skill phases without modifying Wholework itself.

Create Markdown files under `.wholework/domains/{skill}/`:

```
.wholework/
└── domains/
    ├── spec/          # Loaded by /spec
    ├── code/          # Loaded by /code
    └── review/        # Loaded by /review
```

For example, to tell `/spec` about your project's API conventions, create `.wholework/domains/spec/api-conventions.md`:

```markdown
# API Conventions

All new endpoints must follow REST naming: GET /resources, POST /resources, GET /resources/:id.
Authentication via Bearer token is required on all routes.
```

When `/spec` runs, it reads all `.md` files in `.wholework/domains/spec/` and incorporates them as constraints. This keeps your project-specific rules out of `CLAUDE.md` and in a structured location.

## Adapters

Wholework uses an adapter pattern to abstract tool access (browser automation, CI checks, external services). Adapters resolve in priority order:

1. **Project-local** — `.wholework/adapters/` in your repository
2. **User-global** — `~/.wholework/adapters/` shared across all your projects
3. **Bundled** — Default adapters included with Wholework

This means you can override any built-in adapter for your project without forking Wholework. A project-local adapter in `.wholework/adapters/` shadows the bundled version.

For details on writing custom adapters and verify command handlers, see [docs/guide/adapter-guide.md](adapter-guide.md).

## Steering Documents

Steering Documents (`docs/product.md`, `docs/tech.md`, `docs/structure.md`) are the primary way to give Wholework deep project context. Skills read them automatically when present.

Run `/doc init` to generate an initial set from your codebase. Run `/doc sync` to keep them in sync as your project evolves.

---

← [User Guide](index.md)
