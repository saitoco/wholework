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
