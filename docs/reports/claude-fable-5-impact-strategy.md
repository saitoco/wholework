English | [日本語](../ja/reports/claude-fable-5-impact-strategy.md)

# Claude Fable 5 Impact Analysis & Strategy for Wholework

**Report date**: 2026-06-12
**Author**: Automated analysis session
**Model launched**: Claude Fable 5 / Claude Mythos 5 — 2026-06-09 ([announcement](https://www.anthropic.com/news/claude-fable-5-mythos-5))
**Scope**: Wholework's reason to exist under a Mythos-class model, plus distributable components (skills, agents, scripts) and Steering Documents
**Status**: Proposal — see "Candidate Issues" (§8) for an execution plan

> ⚠️ **Suspension Notice (2026-06-13)**: Fable 5 (`claude-fable-5`) is currently suspended by Anthropic under a government directive. API access will likely return an error. Suspension duration is unknown but not expected to be long-term. The analysis and candidate issues below remain valid for when access resumes. To restore: remove this notice and the matching suspension warning in `scripts/run-spec.sh`.

**Companion**: builds on `docs/reports/claude-opus-4-7-optimization-strategy.md`

## 1. Executive Summary

Claude Fable 5 is the first **Mythos-class** model offered for general use — a tier Anthropic places *above* the Opus class. It is state-of-the-art on nearly all capability benchmarks, with its lead growing the longer and more complex the task. The headline behaviors that matter to Wholework: it works autonomously for longer than any prior Claude, it self-verifies its own work at high effort, parallel sub-agents are now *dependable* (and best driven asynchronously), and it performs notably better when given a file-based **memory surface** to write learnings to.

The instinctive worry is existential: *if one model call can autonomously perform a codebase-wide migration in a day, does a six-phase issue→spec→code→review→merge→verify scaffold still earn its keep?*

**Our conclusion is that Wholework's reason to exist is strengthened, not weakened, by Fable 5 — provided it repositions and re-tunes.** Wholework was never primarily a "make the model smarter" scaffold; it is a **governance, traceability, and verification harness** that externalizes work onto GitHub Issues/PRs/Labels so humans, future sessions, and teams can see, gate, and audit it. A more autonomous model has a *larger blast radius*, which raises — not lowers — the value of acceptance criteria, review gates, post-merge verification, and an audit trail. Strikingly, Anthropic's own recommended way to deploy Fable 5 (state boundaries explicitly, ground progress claims against tool results, run a verification harness, give it a memory surface) describes the Wholework design philosophy almost line for line. Wholework's "Spec as cross-phase memory" and `/verify` post-merge acceptance loop are exactly the patterns Anthropic now prescribes.

That said, several of Wholework's assumptions were tuned for older models and now mis-fire:

1. **Literal filter-following in review** — `review-bug` is prompted to "flag only confirmed bugs, minimize false positives." Fable 5 (and already Opus 4.8) honors that self-filter *literally*, which can depress measured recall even as underlying bug-finding improves. Wholework already has a downstream verification stage, so the self-filter in the finder prompt now fights its own architecture (§4.1, C1).
2. **Watchdog vs. long turns** — Fable 5's single requests on hard tasks can run many minutes; the 1800s no-stdout watchdog default will fire more often (§4.2, C2).
3. **Over-prescriptive prompts** — Anthropic warns prior-model step-by-step scaffolding *reduces* Fable 5 output quality. Wholework's SKILL.md files are deliberately prescriptive; a selective de-prescription audit (reasoning steps, not mechanical steps) is needed (§4.3, C5).
4. **Early-stop / boundary drift in autonomous runs** — Fable 5 can occasionally end a turn with a statement of intent but no tool call, or take unrequested adjacent actions; the autonomous `run-*.sh` GUARD_PREFIX should add the anti-early-stop and boundary reminders Anthropic recommends (§4.4, C3).

Plus a hard adoption reality: Fable 5 is **$10/$50 per MTok** (2× Opus 4.8, ~3.3× Sonnet 4.6), is **gated to usage credits on subscription plans after 2026-06-22**, and is **unavailable under zero-data-retention orgs** (requires 30-day retention). Adoption must therefore be **selective and opt-in**, not a default model swap (§3.3, §5.2).

Work is organized into four priorities producing **9 candidate issues** (§8).

## 2. Does Wholework still have a reason to exist?

This is the question the report exists to answer, so we answer it before the mechanics.

### 2.1 The threat, stated honestly

Fable 5's launch evidence is genuinely disruptive to a phase-splitting workflow engine:

- Stripe compressed a two-month, 50M-line Ruby migration into a single day.
- Customers report apps that "took a hundred prompts a year ago" being one-shot.
- At highest effort the model "reflects on and validates its own work," enabling "highly autonomous operations."
- It sustains focus across millions of tokens and improves outputs using its own notes.

Two specific pressures follow:

- **Scaffold dissolution.** Several of Wholework's phase boundaries were originally motivated by context-rot avoidance and capacity — a motivation `docs/tech.md` already concedes has "largely diminished since 1M context GA." A model that holds context across millions of tokens and self-verifies erodes the *technical* rationale for cutting work into six fresh `claude -p` processes.
- **A converging first-party product.** Anthropic's **Managed Agents** now ships **Outcomes** (`user.define_outcome` + a gradeable rubric → an iterate → grade → revise loop). That is conceptually the same shape as Wholework's acceptance-criteria → code → `/verify` loop, but server-managed. This is the closest thing to a direct competitor Wholework has had.

We should not wave these away.

### 2.2 Why the reason to exist holds — and grows

Wholework's value was never the orchestration cleverness; it is everything *around* the model call:

| Need | Does a more capable model remove it? | Effect of Fable 5 |
|---|---|---|
| Requirements capture (Issue, acceptance criteria) | No — the model is better at *executing* intent, not at deciding *what* the org wants | Neutral-to-positive: better at inferring intent when given the "why" |
| Human review gates at the right granularity | No — a larger blast radius needs gates *more* | **Positive**: Fable 5 takes "unrequested-but-adjacent actions" and asks more often; well-placed gates absorb both |
| Post-merge verification | No — autonomy without verification is the dangerous combination | **Positive**: Anthropic explicitly recommends a verification harness; `/verify` *is* one |
| Audit trail (Issues/PRs/Labels/retros) | No — auditability is a team/compliance need, orthogonal to model IQ | **Positive**: more autonomous work → more need to reconstruct what happened |
| Cross-session memory | No | **Strongly positive**: Fable 5 "performs notably better" with a memory surface; Spec-as-memory is exactly that |

The alignment is not a coincidence of framing. Anthropic's Fable 5 deployment guidance reads as a checklist Wholework already satisfies:

- *"Give it a memory surface … store one lesson per file … record corrections and confirmed approaches."* → Wholework's **Retrospective-into-Spec** accumulation.
- *"Make self-verification explicit … fresh-context verifier sub-agents outperform self-critique."* → Wholework's **`/verify`** (post-merge, fork) and **review-bug → verification sub-agent** two-stage filter.
- *"State boundaries explicitly … report findings and stop … don't apply a fix until asked."* → Wholework's **`/issue` (What) vs `/spec` (How)** boundary and **non-interactive three-tier policy** (auto-resolve / skip / hard-error).
- *"Give the reason, not just the request."* → The Spec's **Background / Purpose** sections carry intent into execution.

In other words, the more capable and autonomous the model, the more the *deployment surface* Wholework provides is the thing that makes it safe to point at a real repository. The orchestration is the commodity; the **governance and verification harness is the moat**.

### 2.3 Where the moat must be defended

Against Managed Agents + Outcomes specifically, Wholework's durable differentiators are:

1. **GitHub-native artifacts** — the record of work is Issues, PRs, Labels, and review threads that a team already lives in, not an opaque server session.
2. **Subscription / OAuth auth** — `run-*.sh` runs on the Claude Code subscription path; Managed Agents requires API keys and Anthropic-hosted containers.
3. **Incremental adoption** — a team can adopt `/review` alone, or `/verify` alone, without committing to a full hosted-agent stack.
4. **Human review gates as first-class** — Outcomes grade against a rubric autonomously; Wholework inserts *human* approval at Issue, PR, and AC-confirmation points.

The strategic move (§5.1) is to **lead with this positioning**: Wholework is the governance-and-verification harness that makes highly-autonomous coding agents safe to run on a real GitHub repo — not "an issue-driven workflow" competing on orchestration cleverness.

**Verdict:** Keep building. Re-tune for Fable 5's behavior, adopt the model selectively where long-horizon reasoning pays, and reposition the messaging around governance + verification rather than orchestration.

## 3. Key Claude Fable 5 changes (relevant to Wholework)

### 3.1 Behavioral shifts

| Behavior | Relevance to Wholework | Lever |
|---|---|---|
| **Longer autonomous turns** (single requests can run many minutes at high effort) | Directly stresses `claude-watchdog.sh` (1800s no-stdout kill) | Raise default / lean on increased narration / progress echoes (§4.2) |
| **Self-verification at high effort** | Complements `/verify` and the review two-stage filter; reduces reliance on re-verify ceremonies | Document; consider lighter re-verify when on Fable 5 |
| **Parallel sub-agents are dependable; async preferred** | `/issue` L/XL and `/review` fan-outs; currently spawn-and-block | Keep single-message spawn; explore async orchestration (§4.5) |
| **Memory surface boosts performance** | Validates Spec-as-memory; opportunity to strengthen the pattern | Reinforce retrospective discipline (§5.4) |
| **More user-facing narration by default** | More stdout between tool calls → *helps* the watchdog; but verbose wrap-ups | Net positive for watchdog; trim verbosity only if noisy |
| **Asks more often / takes adjacent actions** | Autonomous `run-*.sh` runs can stall on questions or over-reach | Add boundary + small-decisions-don't-ask reminders to GUARD_PREFIX (§4.4) |
| **Occasional early stop** (intent stated, no tool call) | Breaks non-interactive completion; reconcile must catch it | Add anti-early-stop reminder; reconcile already partially mitigates (§4.4) |
| **Literal filter-following** | `review-bug`'s "HIGH SIGNAL only / minimize false positives" self-filter lowers recall | Decouple find-from-filter (§4.1) |
| **Prior-model prompts often too prescriptive** | Wholework SKILL.md is highly step-by-step | Selective de-prescription audit (§4.3) |
| **Context anxiety when shown a token countdown** | Only relevant if Task Budgets are ever adopted (currently N/A for OAuth CLI) | No action; note for future |

### 3.2 API-surface changes (CLI users mostly unaffected)

Wholework invokes the **Claude Code CLI** (`claude -p --model … --effort …`), not the API, so most breaking changes are non-issues — but two behaviors leak through the CLI:

| Change | Applies to Wholework? | Note |
|---|---|---|
| Thinking always on; `budget_tokens`/`thinking:disabled` 400 | No | CLI manages thinking; effort is steered via `--effort` |
| Sampling params removed | No | Never set in CLI invocations |
| `refusal` stop reason via cyber/bio classifiers | **Indirectly** | A security-review query may be handled by Opus 4.8 fallback instead of Fable 5 (§4.6) |
| Tokenizer | No change vs Opus 4.7/4.8 | Same tokenizer; token counts roughly unchanged from the current Opus baseline |
| 30-day data retention required | **Yes (adoption gate)** | ZDR orgs cannot use Fable 5 at all (§3.3) |

### 3.3 Adoption constraints (the cost reality)

| Constraint | Detail | Implication for Wholework |
|---|---|---|
| **Price** | $10 input / $50 output per MTok — 2× Opus 4.8, ~3.3× Sonnet 4.6 | Cannot be a default; reserve for high-leverage phases |
| **Subscription gating** | Included on Pro/Max/Team only through 2026-06-22; usage credits required after | `run-*.sh` default (OAuth/subscription) loses free Fable 5 access in days; opt-in flag, not default |
| **Data retention** | Requires 30-day retention; unavailable under ZDR | Adoption must degrade gracefully for ZDR users |
| **Safeguards** | <5% of sessions fall back to Opus 4.8 (cyber/bio/distillation classifiers) | Security-review phases are the most exposed (§4.6) |
| **CLI alias** | Model string is `claude-fable-5`; a short `fable` alias in Claude Code CLI is unverified | Verify before wiring into `run-spec.sh` |

## 4. Impact analysis (concrete)

### 4.1 review-bug: decouple finding from filtering (highest-value change)

`agents/review-bug.md` is prompted around a **self-filtering** principle: "flag only confirmed bugs … minimize false positives … report only problems that genuinely require fixes." Wholework's `/review` Step 10–10.3 architecture *already* runs a separate downstream verification sub-agent pass (Opus, parallel, up to 10 issues) to filter false positives.

The Opus 4.7/4.8 code-review guidance — which applies all the more to Fable 5 — is explicit: when a review prompt says "only report high-severity" or "be conservative," the newer models follow it *literally*, investigating just as thoroughly but then *declining to report* sub-threshold findings. Precision rises; **measured recall falls** even though bug-finding improved. Wholework's finder prompt is thus fighting its own two-stage architecture: it self-filters at the find step, *then* filters again downstream.

**Fix:** Decouple. Instruct `review-bug` to report every finding with a confidence + severity tag and explicitly tell it that a downstream stage does the filtering ("your job here is coverage, not filtering"). Keep the existing verification sub-agents as the filter. This is a pure prompt change to `agents/review-bug.md` (and a matching note in `review-light.md`), applies to **Opus 4.8 today** regardless of Fable 5 adoption, and is the single highest-value item in this report.

### 4.2 Watchdog vs. Fable 5's long turns

`scripts/watchdog-defaults.sh` sets `WATCHDOG_TIMEOUT_DEFAULT=1800` (30 min of no stdout → kill). `docs/reports/watchdog-recovery-strategy.md` already documents that Sonnet's long-thinking around PR-body composition can exceed this; the adopted fix was progress echoes (Approach D) + reconcile Stage 2 (Approach C).

Fable 5 lengthens the silent windows further: single hard requests run many minutes, and a phase chains many requests. Two countervailing facts:

- **Worse:** longer per-step thinking → longer stdout gaps → more spurious 1800s kills.
- **Better:** Fable 5 narrates more by default — *if* that interim text reaches `claude -p` stdout, it resets the watchdog.

**Action:** Spike the watchdog behavior under Fable 5 before changing defaults. If narration does not reliably reach stdout, raise `WATCHDOG_TIMEOUT_DEFAULT` (e.g. 1800 → 2700) and/or extend the Approach-D progress echoes to more long-silent sections (spec design, review synthesis). Keep the per-project `watchdog-timeout-seconds` knob as the escape hatch.

### 4.3 Prompt de-prescription (careful, selective)

Anthropic: *"Prompts and skills written for prior models are often too prescriptive for Fable 5 and reduce output quality … A/B with the older step-by-step scaffolding removed."* Wholework's SKILL.md files are deliberately step-by-step — that is the workflow engine.

The resolution is to separate two kinds of steps:

- **Mechanical steps** (label transitions, `gh` commands, file paths, ordering invariants) — these *must* stay prescriptive; they are determinism, not reasoning. Do not touch.
- **Reasoning steps** (how to design a spec, how to assess risk, how to find bugs) — these are where Fable 5's over-prescription penalty bites. Candidates for de-prescription: state the goal and constraints, let the model reason, rather than enumerating sub-steps.

This is a **spike-and-measure** item, not a blanket rewrite, and must run *only* if/when Fable 5 is actually adopted for a phase (otherwise it would degrade Sonnet/Opus behavior, which prefers the explicit steps).

### 4.4 Autonomous-run reliability: boundaries + early stop

`run-*.sh` prepend a `GUARD_PREFIX` ("follow the skill steps to completion … do not hand off to other skills"). Fable 5 adds two failure modes the prefix does not yet address:

- **Early stop** — ending a turn with "I'll now run X" but no tool call. Anthropic's recommended autonomous reminder ("…check your last paragraph; if it is a plan or a promise, do that work now with tool calls…") maps directly onto `run-*.sh`'s non-interactive execution.
- **Adjacent over-reach** — taking unrequested actions (backup branches, drafting messages). The boundary reminder ("when the user is describing a problem … report findings and stop … check the evidence supports the specific action before changing state") complements the existing three-tier non-interactive policy.

**Action:** Extend `GUARD_PREFIX` (or a sourced reminder block) with the anti-early-stop and boundary reminders. Low cost, improves `/auto` completion reliability immediately, and is harmless on Sonnet/Opus.

### 4.5 Async sub-agents (forward-looking)

Wholework's `/issue` L/XL (Step 11a) and `/review` Step 10 already fan out via single-message `Task(...)` spawns — the conservative-spawn mitigation added for Opus 4.7. Two updates:

- The parenthetical rationale "(Opus 4.7 may otherwise serialize the spawns)" is now version-stale. Opus 4.8 spawns *fewer* sub-agents; Fable 5 makes them *dependable* and rewards delegation. The single-message-spawn instruction stays (still correct), but the rationale should be generalized.
- Fable 5 specifically rewards **asynchronous** sub-agents that keep context and communicate with the orchestrator, vs. spawn-and-block. The Task tool in skill context is spawn-and-block by nature, so this is **forward-looking** — it aligns with the multi-agent roadmap (`[[project_multi_agent_support]]`) and the adapter-chain pattern, not an immediate change.

### 4.6 Cyber-classifier exposure on security review

`review-bug.md` explicitly checks shell injection, secrets, and "LLM-to-Shell pattern migration risks." Fable 5's cyber classifier may route such queries to Opus 4.8 fallback (or, on the API, refuse). Via the Claude Code CLI the fallback to Opus 4.8 is automatic and transparent — far less disruptive than an API refusal — but it means **the security portion of a Fable 5 review may silently be answered by Opus 4.8**, not Fable 5. This is not a blocker; it is a monitoring item, and it slightly weakens the case for adopting Fable 5 specifically for `review-bug` (a phase where its security analysis is partly out of scope anyway).

## 5. Strategic recommendations

### 5.1 Reposition the messaging (P1)

Update `docs/product.md` Vision/Differentiation and the user guide to lead with **governance + verification**, not orchestration. The thesis: *as coding agents get more autonomous, the value moves from "who runs the loop" to "who captures requirements, gates the changes, verifies the result, and keeps the audit trail." Wholework is that harness, GitHub-native, on your subscription, adoptable one phase at a time.* Name Managed Agents + Outcomes as the adjacent first-party option and articulate the four durable differentiators (§2.3).

### 5.2 Selective, opt-in Fable 5 adoption (P1)

Do **not** make Fable 5 a default anywhere. Add a `--fable` opt-in to `run-spec.sh` (the single highest-leverage phase: design quality, long-horizon, errors propagate), gated behind a clear cost/retention warning. Keep Sonnet/Opus defaults for all mechanical and high-volume phases. Document: $10/$50 cost, post-2026-06-22 credit gating on subscription, and ZDR incompatibility with graceful degradation. Recommend (but cannot force) Fable 5 for the inline `/auto` orchestrator in the user's own session, where long-horizon coherence pays most.

### 5.3 Find-from-filter decoupling in review (P0)

Ship §4.1 independent of Fable 5 adoption — it improves recall on **Opus 4.8 today**.

### 5.4 Reinforce Spec-as-memory (P2)

Fable 5 validates the pattern. Make retrospective discipline explicit in skill bodies (one lesson per entry, record corrections *and* confirmed approaches, link related entries, don't duplicate what the repo records) and surface "consult the Spec retrospectives before starting" guidance in `/code` and `/spec`.

### 5.5 Refresh the model-effort matrix SSoT (P1)

`docs/tech.md` (`ssot_for: model-effort-matrix`) says sub-agent `opus` aliases "auto-resolve to Opus 4.7" — stale; with Opus 4.8 released, `opus` → 4.8. Update the matrix and the "Opus 4.7 effort calibration" note to cover Opus 4.8 + Fable 5, add a Fable 5 row/notes (where it may be opted in, its cost/retention constraints), and note that the `opus` alias does **not** resolve to Fable 5 (a separate tier requiring an explicit model string).

## 6. Impact summary table

| Area | Risk/Opportunity | Priority |
|---|---|---|
| review-bug self-filter vs. literal following | Recall regression (Opus 4.8 today, Fable 5 more) | P0 |
| Watchdog vs. long Fable 5 turns | Spurious 1800s kills | P1 |
| Messaging / positioning | Strategic relevance vs. Managed Agents | P1 |
| Selective Fable 5 opt-in (spec) | Quality gain at controlled cost | P1 |
| model-effort matrix SSoT staleness | Documentation drift (opus→4.8) | P1 |
| Autonomous-run boundaries/early-stop | `/auto` completion reliability | P2 |
| Prompt de-prescription | Quality if Fable 5 adopted | P2 |
| Spec-as-memory reinforcement | Aligns with prescribed pattern | P2 |
| Cyber-classifier fallback monitoring | Security-review coverage | P3 |
| Async sub-agents | Future multi-agent direction | P3 |

## 7. Migration checklist (Wholework-specific)

- [ ] `agents/review-bug.md` / `review-light.md`: decouple find-from-filter (report all with confidence+severity; filtering is downstream)
- [ ] Spike `claude-watchdog.sh` stdout cadence under Fable 5; raise `WATCHDOG_TIMEOUT_DEFAULT` and/or add progress echoes if needed
- [ ] Verify the Claude Code CLI `--model` string/alias for Fable 5 before wiring `run-spec.sh`
- [ ] `run-spec.sh`: add `--fable` opt-in with cost/retention warning; degrade gracefully for ZDR
- [ ] `GUARD_PREFIX`: add anti-early-stop + boundary reminders for autonomous runs
- [ ] `docs/tech.md` model-effort matrix: `opus`→4.8, add Fable 5 row/notes, fix stale "4.7" auto-resolve note
- [ ] `docs/product.md` + guide: reposition around governance + verification; name Managed Agents/Outcomes
- [ ] `/code` + `/spec`: reinforce "consult Spec retrospectives first" memory-surface guidance
- [ ] Generalize the "(Opus 4.7 may serialize spawns)" rationale in `/issue` 11a and `/review` 10
- [ ] Add a monitoring note for cyber-classifier fallback on `review-bug` security checks

## 8. Candidate Issues (execution plan)

All follow the Wholework Standard Format (Background / Purpose / Acceptance Criteria, Pre-merge and Post-merge split where applicable). CI/test-touching items are Size M minimum (`[[feedback_ci_sensitive_size_m]]`).

| # | Title (Japanese) | Priority | Est. Size | Phase impact |
|---|---|---|---|---|
| C1 | review-bug の find/filter 分離（literal filter-following 対策、Opus 4.8 でも有効） | urgent | M | review |
| C2 | Fable 5 long-turn 対応: watchdog タイムアウト/進捗 echo の spike と再調整 | high | M | auto/code/spec |
| C3 | 自律実行の GUARD_PREFIX に early-stop/boundary リマインダ追加 | high | S | auto, all run-*.sh |
| C4 | docs/tech.md model-effort-matrix を Opus 4.8 / Fable 5 対応で更新 | high | S | docs |
| C5 | run-spec.sh に `--fable` opt-in 追加（コスト/retention 警告付き、ZDR graceful degrade） | high | M | spec |
| C6 | docs/product.md・guide を governance+verification 軸へリポジショニング | high | M | docs |
| C7 | プロンプト de-prescription 監査（reasoning steps のみ、Fable 5 採用時に spike） | medium | M | all skills |
| C8 | Spec-as-memory 強化（retrospective 規律の明示、/code・/spec ガイダンス） | medium | S | code, spec |
| C9 | 並列 spawn 説明の世代非依存化 + cyber-classifier fallback 監視メモ | low | S | issue, review |

### Ordering rationale

- **C1** ships first and independent of Fable 5 — it fixes a recall regression present on Opus 4.8 *today*.
- **C2, C3** are reliability fixes for autonomous runs; both are harmless on Sonnet/Opus and can land before any Fable 5 adoption.
- **C4, C6** are documentation/positioning; C4 unblocks correct guidance, C6 is the strategic reframe.
- **C5** is the actual Fable 5 wiring; depends on the CLI-alias verification in the checklist.
- **C7** runs only if/when C5 lands and Fable 5 is in use for a phase.
- **C8, C9** are low-risk reinforcements.

## 9. Non-goals

- No API-layer migration (the codebase calls the Claude Code CLI, not the API; `refusal`/`fallbacks`/`thinking` handling is the CLI's job).
- No blanket model swap to Fable 5 — cost, subscription gating, and ZDR constraints make a default swap wrong.
- No removal of phase boundaries — the scaffold dissolution pressure (§2.1) is real but the governance value (§2.2) outweighs it; revisit only if a future model + first-party product makes the GitHub-native harness redundant.
- No `ANTHROPIC_MODEL` env-var removal — the CLI `-p` mode workaround (claude-code#22362) is still needed.

## 10. References

- [Claude Fable 5 and Claude Mythos 5 launch](https://www.anthropic.com/news/claude-fable-5-mythos-5)
- `docs/reports/claude-opus-4-7-optimization-strategy.md` (companion; the prior-model recalibration)
- `docs/reports/sonnet-effort-recalibration.md`, `task-budgets-spike.md`, `ultrareview-spike.md`, `watchdog-recovery-strategy.md`
- `docs/tech.md` §Architecture Decisions (SSoT for model-effort-matrix)
- `docs/product.md` §Vision / §Differentiation / §Future Direction

---

*This report proposes the Issues in §8. Each is expected to be created on the Wholework GitHub repository with the appropriate `phase/*` label and Priority set on the Wholework GitHub Project.*
