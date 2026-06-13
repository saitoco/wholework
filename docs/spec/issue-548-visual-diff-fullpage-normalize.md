# Issue #548: visual-diff-adapter fullPage and Dimension Normalization

## Overview

Extends `modules/visual-diff-adapter.md` to resolve two structural constraints identified in #543 real-world usage (saitoco/koganezawa-com#58):

1. **fullPage capture (Step 5a)**: Default changes to `fullPage=true` so the entire page is captured rather than only the visible viewport. A new `capture_mode` input parameter allows callers to opt back to viewport-only.

2. **Dimension normalization (Step 5b)**: Pads ref and impl images to a common size of max(width) × max(height) using `sharp.extend` before `pixelmatch`, eliminating "Image sizes do not match" errors when page heights differ.

3. **Normalized 3-panel composite (Step 5c)**: Updates the composite canvas to use the normalized W × H dimensions.

## Changed Files

- `modules/visual-diff-adapter.md`: add `capture_mode` to Input; update Step 5a for fullPage (default) with viewport opt-out; add dimension normalization with `sharp.extend` to Step 5b; update Step 5c canvas to use normalized dimensions; remove "Follow-on constraint (image height mismatch)" Note
- `tests/visual-diff-adapter.bats`: add test cases for fullPage, capture_mode, extend normalization, and normalized composite documentation

## Implementation Steps

1. Add `capture_mode` parameter to `## Input` section (→ AC2): value `fullpage` (default) | `viewport`; describe that default is `fullpage` and opt-out to viewport-only by setting `capture_mode=viewport`

2. Update Step 5a screenshot capture (→ AC1, AC2): add `fullPage: true` to the Playwright MCP `browser_take_screenshot` call; add fullPage flag for browser-use CLI; add a note that when `capture_mode=viewport` the `fullPage` argument is omitted (viewport-only behavior)

3. Update Step 5b diff generation to add dimension normalization before pixelmatch (after 1) (→ AC3): after loading both images, compute W = max(ref.info.width, impl.info.width) and H = max(ref.info.height, impl.info.height); use `sharp.extend` to pad each image to W × H (right and bottom padding, white background); pass normalized raw buffers with W × H dimensions to `pixelmatch`; remove the "Follow-on constraint (image height mismatch)" Note from the Notes section

4. Update Step 5c 3-panel composite to use normalized dimensions (after 3) (→ AC4): change canvas creation to `width: 3 * W, height: H`; update composite offsets to use W; note in Step 5c text that normalized dimensions are used

5. Add bats test cases to `tests/visual-diff-adapter.bats` (→ AC1–4):
   - `"visual-diff-adapter: fullPage screenshot documented"` — `grep -q "fullPage" "$ADAPTER_FILE"`
   - `"visual-diff-adapter: capture_mode opt-out documented"` — `grep -qE "capture_mode|fullpage" "$ADAPTER_FILE"`
   - `"visual-diff-adapter: dimension normalization documented"` — `grep -qE "extend|sharp.extend" "$ADAPTER_FILE"`
   - `"visual-diff-adapter: normalized composite documented"` — `grep -qE "正規化後|normalized" "$ADAPTER_FILE"`

## Verification

### Pre-merge
- <!-- verify: grep "fullPage" "modules/visual-diff-adapter.md" --> Step 5a で fullPage 撮影に対応している (adapter 文書に `fullPage` の記載がある)
- <!-- verify: grep "capture_mode\|fullpage" "modules/visual-diff-adapter.md" --> caller 側で viewport-only に切り替える手段が文書化されている
- <!-- verify: grep "extend\|pad\|max(width" "modules/visual-diff-adapter.md" --> Step 5b で寸法不一致を pad 正規化してから pixelmatch を実行する (寸法差で throw しない) ことが文書化されている
- <!-- verify: grep "正規化後\|normalized" "modules/visual-diff-adapter.md" --> Step 5c の 3-panel composite が正規化後寸法で組まれることが文書化されている
- <!-- verify: rubric "modules/visual-diff-adapter.md describes a fullPage default capture mode with a caller-side opt-out to viewport-only, and a pad-based dimension normalization (using sharp.extend to a common max(W) × max(H)) that runs before pixelmatch so that ref/impl size mismatches no longer throw" --> 仕様 (fullPage default + opt-out + pad 正規化) が rubric 基準を満たす

### Post-merge
- koganezawa-com#58 を fullPage で再走し、ページ全体の 3-panel が寸法 throw なく生成される

## Notes

- No conflicts detected: the existing Notes section in `visual-diff-adapter.md` already identifies the height-mismatch issue as a follow-on from #543, confirming this Issue's scope.
- `capture_mode` parameter name aligns with existing inputs (`viewports`, `states`); implementation may use a slightly different naming as long as the opt-out mechanism is documented. The AC2 verify pattern `capture_mode\|fullpage` (BRE alternation) tolerates either `capture_mode` as a keyword or `fullpage` as a literal value string.
- AC3 verify `grep "extend\|pad\|max(width"` will match because: `extend` appears in `sharp.extend` API usage; `pad` in the description; `max(width` as notation for `Math.max(ref.info.width, impl.info.width)` mirroring the Issue body phrasing.
- The `browser-use` CLI fullPage support may need a note if `--full-page` flag is unavailable; document the equivalent approach or note as unsupported in that case.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash-merged PR #607 directly (mergeable=true, CI=success, review=approved) — no conflict resolution needed
- BASE_BRANCH=main confirmed so `closes #548` will auto-close Issue #548 upon merge
- Worktree `merge/pr-607` created for Phase Handoff write isolation

### Deferred Items
- Post-merge verification: koganezawa-com#58 を fullPage で再走し、ページ全体の 3-panel が寸法 throw なく生成されることを確認 (記載済み Post-merge AC)
- None other — all pre-merge ACs verified by review phase prior to merge

### Notes for Next Phase
- verify phase should run pre-merge verify commands (grep fullPage, capture_mode, extend/pad, normalized composite) against the squash-merged main
- AC1–AC4 are all grep-based checks on `modules/visual-diff-adapter.md` — low flake risk
- Post-merge AC (koganezawa-com#58 re-run) requires external repo access; may be SKIP if environment unavailable

## Code Retrospective

### Deviations from Design

- Step 5c canvas width computation: Spec said `width: 3 * W` using the normalized W. Implementation used `W` from re-reading the diff file metadata (`{ width: W, height: H } = await sharp(diff).metadata()`) rather than carrying W from Step 5b. This indirection is functionally identical but avoids passing W as a variable across bash heredoc boundaries.
- browser-use CLI fullPage note: Added explicit fallback note ("if browser-use version does not support --full-page, fall back to omitting the flag") as the Spec's Notes section anticipated this uncertainty. Aligns with Spec Note about browser-use CLI fullPage support.

### Design Gaps/Ambiguities

- The Spec did not specify whether the `padTo` helper should be defined inline or extracted. Implemented as an inline async arrow function in the Node.js `-e` snippet for simplicity — no external helper file needed for a single-file module change.
- `browser_take_screenshot` `fullPage` parameter form: The Spec listed `fullPage: true` but did not clarify whether the Playwright MCP tool accepts a named `fullPage` parameter or a positional boolean. Documented as `fullPage: true` (keyword argument form), which is the standard Playwright API shape.

### Rework

- None. Implementation proceeded directly from the Spec without rework.

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Step 5c composite referenced original unpadded `ref.png`/`impl.png` instead of padded variants. The Spec stated "3-panel composite は正規化後寸法で組む" but only covered the canvas dimensions (W×H); it did not explicitly specify that Before/After panel inputs must also be padded files. The AC4 verify command (`grep "正規化後\|normalized"`) passed on the canvas description alone, masking that panel inputs were unpadded.
- Root pattern: Spec described the *canvas* normalization correctly but omitted a callout that the *input* images for ref/impl panels must also be the padded variants. Future specs for multi-step normalization pipelines should explicitly state which files are consumed at each downstream step.

### Recurring Issues

- Japanese string literal in test source code (`grep -qE "正規化後|normalized"` in `.bats`). CLAUDE.md specifies "Source code: English" but test strings mirrored the Japanese grep pattern from Issue body AC text. Avoid copying Japanese AC text directly into source-code assertions — translate to English equivalents.
- No repeated issue patterns across aspects in this PR.

### Acceptance Criteria Verification Difficulty

- All 5 pre-merge ACs were grep/rubric-based and auto-verified cleanly (0 UNCERTAIN, 0 POST-MERGE in pre-merge section).
- The rubric AC5 ("fullPage default + opt-out + pad normalization") was broad enough to PASS despite the Step 5c unpadded-input gap — the rubric checked policy documentation, not code-path completeness. Future rubric conditions should include "all downstream steps use padded outputs" when a normalization pipeline is introduced.

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- Fixed Step 5c composite: refPadded/implPadded now saved as `ref-padded.png`/`impl-padded.png` in Step 5b; Step 5c references these padded files so all three panels share W×H dimensions.
- SHOULD issue (Step 5c unpadded reference) and CONSIDER issue (Japanese in test) both resolved in a single commit on the PR branch.
- No policy changes detected; AC text and verify commands remain valid after fixes.

### Deferred Items

- post-merge manual AC: koganezawa-com#58 re-run with fullPage to confirm no dimension throw — caller's responsibility, not covered by adapter unit tests.
- browser-use `--full-page` flag availability: actual verification requires a live browser-use installation.

### Notes for Next Phase

- CI re-run expected after review-feedback commit (849ea89) — all jobs should PASS.
- No MUST issues; PR is ready to merge after CI confirms green.
