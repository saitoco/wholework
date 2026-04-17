English | [日本語](../ja/reports/claude-opus-4-7-optimization-strategy.md)

# Claude Opus 4.7 Optimization Strategy for Wholework

**Report date**: 2026-04-17
**Author**: Automated analysis session
**Scope**: Distributable components (skills, agents, modules, scripts) and Steering Documents
**Status**: Proposal — see "Candidate Issues" section for execution plan

## 1. Executive Summary

Claude Opus 4.7 ships with a new default effort level (`xhigh`), adaptive-thinking-only semantics (fixed `budget_tokens` returns 400), stricter instruction literalism, more conservative subagent spawning, reduced tool-call cadence, and high-resolution vision support (up to 2,576 px). Because Wholework orchestrates Claude Code via `claude -p --model <id> --effort <level>` and relies on parallel sub-agents for its `/issue` (L/XL) and `/review` phases, the upgrade path is low-risk at the runtime layer but carries meaningful behavioral risks in two places:

1. **Sub-agent fan-out**: `/issue` spawns `issue-scope / issue-risk / issue-precedent` in parallel, and `/review` spawns `review-bug / review-spec` in parallel. Opus 4.7 is biased against spawning — we must make the parallel-spawn intent explicit in the SKILL bodies to preserve current behavior.
2. **Literal instruction following**: SKILL.md files sometimes rely on implicit generalization (e.g., "do the same for other files of this kind"). Opus 4.7 will stop generalizing silently. Ambiguities must be promoted to explicit instructions.

Everything else (API removals, prefill, temperature/top_p/top_k) is already non-issue for Wholework because we invoke the CLI, not the API directly.

The optimization work is organized into four priorities (P0 urgent, P1 high, P2 medium, P3 low) producing **12 candidate issues** listed in §7.

## 2. Key Claude Opus 4.7 Changes

### 2.1 Breaking API changes (CLI users unaffected unless flags are used)

| Change | Applies to Wholework? | Notes |
|---|---|---|
| `thinking: {type: "enabled", budget_tokens: N}` returns 400 | No | We do not pass `--thinking budget:N`. Adaptive thinking is steered via `--effort`. |
| `temperature` / `top_p` / `top_k` non-default → 400 | No | We never set sampling params in CLI invocations. |
| Assistant-message prefill → 400 | No | We do not prefill. |
| Thinking display defaults to `omitted` | Partial | Only affects how `claude -p` streams progress. UX consideration only. |
| New tokenizer (1.0–1.35× more tokens for same text) | **Yes** | `max_tokens` headroom and any char-based heuristics need review. |
| `output_format` deprecated → `output_config.format` | No (CLI abstracts this) | |

### 2.2 Behavior changes (relevant to Wholework)

| Behavior | Relevance to Wholework | Optimization lever |
|---|---|---|
| Response length calibrates to task complexity | Verbose `/auto` progress scaffolds may become redundant | Remove "summarize every N tool calls" instructions; rely on built-in progress updates |
| More literal instruction following | Many SKILL.md steps rely on implicit generalization (e.g., "apply the same pattern to similar files") | Promote implicit patterns to explicit steps; add concrete file lists where appropriate |
| More direct tone / fewer validation phrases | User-facing skill output (terminal messages) may feel blunter | Acceptable for internal output; audit user-facing completion reports |
| Built-in progress updates in agentic traces | Better interim status during `/auto` long runs | Remove custom "print status every 3 tool calls" scaffolding where present |
| **Fewer sub-agents spawned by default** | **Direct impact on `/issue` L/XL and `/review` parallel phases** | Add explicit "spawn these N subagents in parallel in a single message" instructions |
| Stricter effort calibration (especially at `low`) | `run-merge.sh` uses `low`; `run-verify.sh` uses `medium` | Verify these phases still complete adequately; may need upgrade to `medium`/`high` |
| Fewer tool calls by default | `/spec` relies on codebase search (Grep/Glob/Read); `/review` relies on `git diff` tools | Add explicit tool-usage guidance: "use Grep/Read thoroughly to cover the change scope" |
| Cybersecurity safeguards tightened | Security review (`review-bug` checks for shell injection / secrets) may see refusals | Pre-emptive monitoring; apply to Cyber Verification Program if blocked |
| High-resolution image support (2,576 px, 4,784 image tokens max) | `browser-adapter` / `lighthouse-adapter` / `/verify` screenshot flows | Remove client-side scale-factor conversion; update screenshot resolution defaults; rebudget for 3× image tokens |

### 2.3 New capabilities to evaluate

| Capability | Status | Potential Wholework use |
|---|---|---|
| `xhigh` effort level (default for coding in Claude Code) | GA | Adopt for spec (replace `max`?), re-evaluate across matrix |
| Task budgets (`task-budgets-2026-03-13`) | Beta | Cap per-phase token spend in `/auto` long runs |
| Ultrareview command | New | Consider as `--ultra` option for `/review` deep-dive reviews |
| Enhanced file-system memory | Improvement | Spec-as-memory pattern benefits; no immediate action |
| `output_config.task_budget` | Beta | API-level budget hint for self-pacing |
| `xhigh` + adaptive thinking + interleaved thinking (automatic) | GA | Default behavior — no opt-in required |

### 2.4 Effort-level recalibration guidance (from Anthropic)

| Level | Anthropic guidance | Wholework current usage |
|---|---|---|
| `max` | Test for intelligence-demanding tasks; risk of overthinking | `run-spec.sh` (spec phase) |
| `xhigh` (new default) | Best for most coding / agentic use cases | Not yet adopted |
| `high` | Minimum for intelligence-sensitive use cases | `run-code.sh`, `run-review.sh`, `run-issue.sh` |
| `medium` | Cost-sensitive; reduced intelligence | `run-verify.sh` |
| `low` | Short / scoped / latency-sensitive only — strict scoping | `run-merge.sh` |

## 3. Current Wholework Surface Area

### 3.1 Model and effort matrix (from `docs/tech.md`, authoritative SSoT)

| Component | Phase | Model | Effort | Hardcoded location |
|---|---|---|---|---|
| `run-spec.sh` | spec | Sonnet (Opus via `--opus` for L) | `max` | `scripts/run-spec.sh` L10, L15 |
| `run-code.sh` | code | Sonnet | `high` | `scripts/run-code.sh` L136–140 |
| `run-review.sh` | review | Sonnet | `high` | `scripts/run-review.sh` |
| `run-issue.sh` | issue | Sonnet | `high` | `scripts/run-issue.sh` |
| `run-verify.sh` | verify | Sonnet | `medium` | `scripts/run-verify.sh` |
| `run-merge.sh` | merge | Sonnet | `low` | `scripts/run-merge.sh` |
| `review-bug` agent | review (sub-agent) | Opus | inherited | `agents/review-bug.md` frontmatter |
| `review-spec` agent | review (sub-agent) | Opus | inherited | `agents/review-spec.md` frontmatter |
| `review-light` agent | review (sub-agent) | Sonnet | inherited | `agents/review-light.md` frontmatter |
| `issue-scope` agent | issue L/XL (sub-agent) | Opus | inherited | `agents/issue-scope.md` frontmatter |
| `issue-risk` agent | issue L/XL (sub-agent) | Opus | inherited | `agents/issue-risk.md` frontmatter |
| `issue-precedent` agent | issue L/XL (sub-agent) | Opus | inherited | `agents/issue-precedent.md` frontmatter |
| `triage` skill | triage | Sonnet | — | inline (no runner) |

### 3.2 Opus usage concentration

Opus is used in:
- `run-spec.sh --opus` for L-size specs (explicit `claude-opus-4-6` model ID at `scripts/run-spec.sh:15`)
- 5 sub-agents via `model: opus` alias in YAML frontmatter

**Alias resolution**: Agents specify `model: opus` (not a specific version). Claude Code resolves `opus` to the current latest Opus, so sub-agents will automatically pick up Opus 4.7 once installed. Only `run-spec.sh` has a hardcoded `claude-opus-4-6` string that must be updated.

### 3.3 Parallel sub-agent fan-out points (Opus 4.7 conservative-spawn risk)

| Skill | Step | Sub-agents spawned | Current instruction style |
|---|---|---|---|
| `/issue` | 11a (L/XL only) | `issue-scope`, `issue-risk`, `issue-precedent` (3×) | Explicit `Task(...)` triple block — good baseline, but uses "Launch 3 agents in parallel" phrasing |
| `/review` | varies | `review-bug`, `review-spec` (2×) or `review-light` (1×) | To be confirmed |

### 3.4 Scaffolding that may be redundant with Opus 4.7

- Phase banners (`scripts/phase-banner.sh` — `print_start_banner`, `print_end_banner`) — runtime-level, keep as-is (outside model reasoning).
- Retrospective comments at Step N of every skill — keep, this is explicit Spec-as-memory persistence, not a progress-update scaffold.
- Explicit "summarize after X" instructions — audit needed.

## 4. Impact Analysis

### 4.1 High-impact areas

| Area | Risk | Mitigation |
|---|---|---|
| `/issue` L/XL parallel investigation quality | Sub-agents spawn less eagerly → fallback to single-agent path more often | Make Step 11a's "Launch 3 agents in parallel" a non-negotiable imperative; add "in a single message with 3 Task calls" explicit phrasing |
| `/review` parallel review quality | Same risk as above for review-bug/review-spec | Same mitigation |
| `run-spec.sh --opus` with `max` effort | Potential overthinking with Opus 4.7 diminishing-returns caveat | Evaluate `xhigh` for Opus spec; keep `max` for experiments |
| `run-merge.sh` with `low` effort | Opus 4.7 at low strictly scopes to what was asked; risk of under-thinking merge conflicts | Verify merge phase still handles edge cases (conflicts, CI waits); bump to `medium` if regressions surface |
| Browser screenshot verification | 3× image tokens per full-res screenshot | Downsample before sending if fidelity not needed, or budget accordingly |

### 4.2 Low-impact areas

- `run-code.sh` / `run-review.sh` / `run-issue.sh` at `high` — already above the "minimum high" recommendation. No urgent action.
- Sub-agent Opus alias — auto-upgrades to 4.7 without code change.
- Prompt caching, 1M context, PDF support, Files API — all unchanged.

### 4.3 Unknown-impact areas (needs benchmarking)

- Wholework workflow end-to-end cost delta under 4.7 tokenizer (+0–35% tokens).
- Quality delta for `/review` bug-detection recall (+10% claimed by Anthropic for code review).
- Subagent-spawn regression on Opus 4.7 vs. 4.6 for identical prompts.

## 5. Strategic Recommendations

### 5.1 Immediate actions (P0 / urgent)

1. **Model ID upgrade**: Update `scripts/run-spec.sh` hardcoded `claude-opus-4-6` → `claude-opus-4-7`. Verify `model: opus` alias in agents resolves to 4.7 in Claude Code.
2. **Sub-agent spawn explicitness**: Audit `/issue` Step 11a and `/review` skill for parallel-spawn instructions. Add unambiguous "in a single message with N Task calls" phrasing.

### 5.2 Near-term actions (P1 / high)

3. **Add `xhigh` support to `run-spec.sh`**: New `--xhigh` flag (or make `xhigh` the default for Opus spec, replacing `max`).
4. **Update `docs/tech.md` model-effort-matrix SSoT**: Add `xhigh` column, reflect Opus 4.7 upgrade, document the effort-level guidance.
5. **Audit SKILL.md literalism**: Scan all SKILL.md for implicit-generalization patterns; promote to explicit enumerations.
6. **Audit SKILL.md for redundant progress-update scaffolding**: Remove "summarize after X tool calls" if present.

### 5.3 Value-add actions (P2 / medium)

7. **High-resolution screenshot support**: Update `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` for 2,576 px defaults; remove scale-factor conversion; document 3× image-token cost.
8. **Task budgets (beta) spike**: Evaluate `task-budgets-2026-03-13` for `/auto` orchestration bounds.
9. **Ultrareview integration**: Evaluate `ultrareview` as `--ultra` depth mode for `/review`.
10. **Migration guide for adopters**: Publish `docs/guide/opus-4-7-migration.md` explaining behavior changes and prompt tweaks for Wholework adopters.

### 5.4 Optimization / future (P3 / low)

11. **Tokenizer audit**: Scan Wholework skills/scripts for character-length or token-count assumptions that break under the 1.0–1.35× new-tokenizer output.
12. **End-to-end benchmark**: Re-baseline cost and quality across the 6 phases on Opus 4.7 vs. 4.6 for a reference issue. Publish findings in `docs/stats/` or a new `docs/benchmarks/` directory.

## 6. Migration Checklist (Wholework-specific)

- [ ] `scripts/run-spec.sh` line 15: `claude-opus-4-6` → `claude-opus-4-7`
- [ ] Verify `model: opus` alias in `agents/{review-bug,review-spec,issue-scope,issue-risk,issue-precedent}.md` resolves to 4.7 after Claude Code update
- [ ] `docs/tech.md` §Architecture Decisions § Effort optimization strategy / Phase-specific model and effort matrix: update to reflect Opus 4.7 and `xhigh` option
- [ ] `/issue` SKILL.md Step 11a: verify parallel-spawn instruction is explicit and single-message
- [ ] `/review` SKILL.md: verify parallel-spawn instruction for review-bug/review-spec is explicit and single-message
- [ ] Audit remaining SKILL.md for implicit-generalization patterns (literalism readiness)
- [ ] Audit SKILL.md for redundant progress-update scaffolding
- [ ] `modules/browser-adapter.md` / `modules/lighthouse-adapter.md`: update for 2,576 px support
- [ ] Evaluate `task_budget` beta adoption for `/auto`
- [ ] Publish user-facing migration guide (`docs/guide/opus-4-7-migration.md`)
- [ ] Re-baseline end-to-end cost / quality benchmarks

## 7. Candidate Issues (execution plan)

12 candidate issues, prioritized. All follow the Wholework Standard Format (Background / Purpose / Acceptance Criteria with Pre-merge and Post-merge split where applicable).

| # | Title (Japanese) | Priority | Est. Size | Phase impact |
|---|---|---|---|---|
| C1 | `run-spec.sh` の Opus モデル ID を claude-opus-4-7 へ更新 | urgent | XS | spec |
| C2 | 並列 sub-agent 起動指示の明示化 (Opus 4.7 保守的スポーン対策) | high | S | issue, review |
| C3 | `run-spec.sh` に xhigh effort 選択肢を追加 | high | S | spec |
| C4 | docs/tech.md model-effort-matrix を Opus 4.7 / xhigh 対応で更新 | high | S | docs |
| C5 | SKILL.md の暗黙的一般化パターン監査 (literalism 対応) | high | M | all skills |
| C6 | SKILL.md の冗長な進捗更新 scaffolding 監査と削除 | medium | S | all skills |
| C7 | browser-adapter / lighthouse-adapter の高解像度 (2576px) 対応 | medium | M | verify |
| C8 | `/auto` に task_budgets (beta) 導入スパイク | medium | M | auto |
| C9 | `/review` に ultrareview オプション (--ultra) 導入検討 | medium | M | review |
| C10 | Wholework 利用者向け Opus 4.7 移行ガイドの公開 | medium | S | docs/guide |
| C11 | 新 tokenizer (1.0–1.35×) 対応の文字数 / token 前提監査 | low | S | scripts/modules |
| C12 | Opus 4.7 vs 4.6 でのエンドツーエンドベンチマーク | low | M | benchmarks |

### 7.1 Issue ordering rationale

- **C1** before everything else — without the model ID update, `run-spec.sh --opus` keeps calling 4.6. Fastest win, smallest blast radius.
- **C2** independent of C1 — prompt-level change, can land in parallel. Highest behavior-risk item.
- **C3 + C4** naturally couple — tech.md SSoT update follows adoption of xhigh in run-*.sh. Can land as one PR or split.
- **C5** medium-to-large audit; safe to parallelize with C2 since different files.
- **C6** low-risk cleanup; can follow C5 or land independently.
- **C7** moderate — touches verify adapters. Independent of model-ID upgrade.
- **C8, C9, C10** independent spikes/explorations; no ordering constraint.
- **C11, C12** optimization work; safe to defer.

## 8. Non-goals

- No API-layer migration (temperature/top_p/top_k, prefill, extended thinking budget) — Wholework uses CLI only.
- No Sonnet-model upgrade — this report only covers Opus 4.7. Sonnet 4.6 remains the default for orchestrators.
- No `advisor_20260301` beta exploration — already flagged as a follow-up in tech.md; not Opus-4.7-specific.
- No `ANTHROPIC_MODEL` env-var removal — current workaround for CLI `-p` mode bug (claude-code#22362) is still needed.

## 9. References

- [Claude Opus 4.7 Launch](https://www.anthropic.com/news/claude-opus-4-7)
- [Best Practices for Using Claude Opus 4.7 with Claude Code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- [Claude Migration Guide (platform.claude.com)](https://platform.claude.com/docs/en/about-claude/models/migration-guide#migrating-to-claude-opus-4-7)
- Wholework `docs/tech.md` §Architecture Decisions (SSoT for model-effort-matrix)
- Wholework `docs/product.md` §Future Direction (workflow optimization 3 axes)

---

*This report proposes the Issues listed in §7. Each proposed Issue is expected to be created on the Wholework GitHub repository with `phase/issue` label applied and the indicated Priority set on the Wholework GitHub Project (#35).*
