---
type: domain
skill: verify
domain: lighthouse
load_when:
  capability: lighthouse
---

# Lighthouse Guidance (Domain File)

This file is only loaded when `capabilities.lighthouse: true` is declared in `.wholework.yml`.

## Purpose

Provides guidance for using `lighthouse_check` verify commands. Covers differentiation from related commands and application scenarios.

## `lighthouse_check` Command Details

### Differentiators

`lighthouse_check` is specialized for Lighthouse performance and quality score verification:

- **Execution**: Only executed in full mode. Delegates to `lighthouse-adapter.md` via adapter-resolver, which handles CLI auto-detection
- **Safe mode**: Returns UNCERTAIN (to prevent external command execution risk). Intended for use with `/verify` (full mode only)
- **vs. `command`**: Use `lighthouse_check` instead of `command "lighthouse ..."` — provides structured score comparison, 120-second timeout, and CLI auto-detection via the adapter layer
- **vs. `build_success`**: `build_success` verifies exit code; `lighthouse_check` verifies Lighthouse score thresholds (category + min_score)

### When to Use

Use `lighthouse_check` when the acceptance condition requires verifying a minimum Lighthouse score in a specific category (`performance`, `accessibility`, `best-practices`, `seo`).

### Capability Declaration Requirement

Before adding `lighthouse_check` verify commands to an Issue or Spec, confirm the project's `.wholework.yml` declares:

```yaml
capabilities:
  lighthouse: true
```

Without this declaration, `lighthouse_check` returns UNCERTAIN in `/verify` (capability gate in `modules/adapter-resolver.md`). Add the declaration to `.wholework.yml` as part of the same PR that introduces `lighthouse_check` verify commands.
