# visual-diff adapter

Visual difference verification adapter.

## Purpose

Provides a tool-agnostic abstraction layer for executing visual difference verification commands (`visual_diff`). Captures screenshots of reference and implementation URLs for each viewport × state combination, generates pixel-level diff highlights via `pixelmatch`, composites 3-panel images (Before / After / Diff highlight) via `sharp`, and delegates structured gap enumeration to the `frontend-visual-review` sub-agent.

Caller: `modules/verify-executor.md` (via `modules/adapter-resolver.md`)

## Input

The following information is passed from the caller:

- **Command type**: `visual_diff`
- **ref_url**: Reference URL (e.g., live production site)
- **impl_url**: Implementation URL (e.g., local dev server or preview)
- **viewports**: Comma-separated viewport widths in px (e.g., `390,1440`). All values required; no defaults.
- **states**: Comma-separated interactive state labels (opaque labels; e.g., `default,menu-open`). All values required; no defaults. State label → action sequence mapping is the caller's responsibility.

## Processing Steps

### Step 1: Capability Declaration Check

Check whether `HAS_VISUAL_DIFF_CAPABILITY` is `true` (resolved by `adapter-resolver.md` via `detect-config-markers.md`).

- **`HAS_VISUAL_DIFF_CAPABILITY` is `false` or not set**: Return UNCERTAIN. State in detail: "capability `visual-diff` is not declared in `.wholework.yml`. Add `capabilities:\n  visual-diff: true` to enable visual diff verification."
- **`HAS_VISUAL_DIFF_CAPABILITY` is `true`**: Proceed to next step.

### Step 2: URL Security Check

Read `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md` and execute the URL security constraint check for **both** `ref_url` and `impl_url`. Return UNCERTAIN if constraints are not met for either URL (include detailed reason and which URL failed).

### Step 3: Tool Detection

Detect available tools in the following priority order.

**Browser automation tool** (first found is used):

| Priority | Tool | Detection Method |
|---------|------|----------------|
| 1 | browser-use CLI | Run `command -v browser-use` in Bash; detected if exit code is 0 |
| 2 | Playwright MCP | Use ToolSearch with `select:mcp__plugin_playwright_playwright__browser_navigate`; detected if available |
| 3 | Not detected | Neither of the above available |

**Image processing tools** (both required):

- `sharp`: Run `node -e "require.resolve('sharp')"` in Bash; detected if exit code is 0
- `pixelmatch`: Run `node -e "require.resolve('pixelmatch')"` in Bash; detected if exit code is 0

**When browser automation tool not detected**: Return UNCERTAIN. State in detail: "No browser automation tool detected (browser-use CLI: not installed, Playwright MCP: unavailable). At least one is required for visual_diff."

**When `sharp` or `pixelmatch` not detected**: Return UNCERTAIN. State in detail which packages are missing and how to install them: "`npm install sharp pixelmatch`".

### Step 4: Basic Authentication Setup

If Basic authentication is required for preview or production environments, get credentials from environment variables:

- `PREVIEW_BASIC_USER`: Basic authentication username
- `PREVIEW_BASIC_PASS`: Basic authentication password

If these environment variables are set, attach authentication credentials in Step 5's screenshot capture. Do NOT output credential values in logs or verification result notes (mask as `****`). If environment variables are not set, connect without authentication.

### Step 5: 3-Panel Composite Execution (default)

Generate a 3-panel composite (Before / After / Diff highlight) for each (viewport × state) combination and delegate to the `frontend-visual-review` sub-agent.

#### 5a. Screenshot Capture

For each combination of (viewport, state):

1. Generate a unique run ID: `run_id=$(date +%s%N | head -c 12)` (or use a random suffix)
2. Create temp directory: `mkdir -p .tmp/visual-diff-${run_id}/`
3. Navigate the browser to the state specified by the `state` label (the caller is responsible for defining what action sequence corresponds to each state label)
4. Capture reference screenshot at `ref_url` at the specified viewport width:
   - Save to `.tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png`
5. Capture implementation screenshot at `impl_url` at the same viewport width:
   - Save to `.tmp/visual-diff-${run_id}/${viewport}-${state}-impl.png`
6. Use Basic auth credentials from Step 4 if set (do not embed in URL; use `Authorization` header)

**browser-use CLI screenshot steps:**

1. Open page: `browser-use open "<url>"`
2. Set viewport width (if supported): `browser-use eval "document.documentElement.style.width='${viewport}px'"`
3. Capture: `browser-use screenshot ".tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png"`
4. Close: `browser-use close`

**Playwright MCP screenshot steps:**

1. Resize viewport: use `browser_resize` with `width=${viewport}`
2. Navigate: `browser_navigate` to the URL
3. Capture: `browser_take_screenshot` and save to the temp path
4. Close: `browser_close`

#### 5b. Diff Highlight Generation

For each (viewport, state) pair, run a Node.js script via Bash to generate the diff highlight image using `pixelmatch`:

```bash
node -e "
const fs = require('fs');
const { PNG } = require('pngjs');
const pixelmatch = require('pixelmatch');
const refData = PNG.sync.read(fs.readFileSync('.tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png'));
const implData = PNG.sync.read(fs.readFileSync('.tmp/visual-diff-${run_id}/${viewport}-${state}-impl.png'));
const { width, height } = refData;
const diff = new PNG({ width, height });
pixelmatch(refData.data, implData.data, diff.data, width, height, { threshold: 0.1, includeAA: false });
fs.writeFileSync('.tmp/visual-diff-${run_id}/${viewport}-${state}-diff.png', PNG.sync.write(diff));
"
```

#### 5c. 3-Panel Composite Generation

Composite the three images (Before / After / Diff highlight) side by side using `sharp`:

```bash
node -e "
const sharp = require('sharp');
sharp({
  create: { width: 3 * ${viewport}, height: implHeight, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 1 } }
}).composite([
  { input: '.tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png', left: 0, top: 0 },
  { input: '.tmp/visual-diff-${run_id}/${viewport}-${state}-impl.png', left: ${viewport}, top: 0 },
  { input: '.tmp/visual-diff-${run_id}/${viewport}-${state}-diff.png', left: 2 * ${viewport}, top: 0 }
]).toFile('.tmp/visual-diff-${run_id}/${viewport}-${state}-3panel.png', (err) => { if (err) { console.error(err); process.exit(1); } });
"
```

The resulting 3-panel image layout: `[ Before (ref) | After (impl) | Diff highlight ]`

#### 5d. Frontend Visual Review Sub-Agent Invocation

Collect all 3-panel images and spawn the `frontend-visual-review` sub-agent via Task:

```
Task(
  subagent_type: "frontend-visual-review",
  prompt: JSON.stringify({
    comparison_images: [list of .tmp/visual-diff-${run_id}/*-3panel.png paths],
    image_format: "3-panel",
    panel_layout: "Before | After | Diff highlight",
    viewports: [parsed viewport widths as integers],
    states: [parsed state labels as strings],
    context: "visual_diff verification for ref_url vs impl_url"
  })
)
```

#### 5e. Result Mapping

Map the sub-agent's structured output to PASS / FAIL / UNCERTAIN:

- `zero_gaps_detected: true` (and `gaps` array is empty) → **PASS**
- `gaps` array is non-empty → **FAIL** (include gap count and severity breakdown in details)
- Sub-agent returns error or output cannot be parsed → **UNCERTAIN** (include raw output in details)

#### 5f. Cleanup

Remove temp images after result mapping:

```bash
rm -f .tmp/visual-diff-${run_id}/*.png
rmdir .tmp/visual-diff-${run_id}/ 2>/dev/null || true
```

### Step 6: Return Result

Return the execution result as one of:

- **PASS**: No visual gaps detected between reference and implementation across all viewports and states
- **FAIL**: Visual gaps detected (include total gap count, severity counts `must`/`should`/`nit`, and per-gap details from sub-agent output)
- **UNCERTAIN**: Cannot be automatically determined (capability not declared, tool not detected, URL security constraint violation, screenshot capture error, pixelmatch/sharp execution error, sub-agent output unparseable; include detailed reason)

## Output

- **Result**: PASS / FAIL / UNCERTAIN
- **Details**: Description of verification result. For FAIL, include structured gap list from `frontend-visual-review` sub-agent output (viewport, state, element_description, gap_type, severity for each gap).

## Token Budget

3-panel images at 1440 px viewport width can be wide (up to 4320 × height px before compositing). Apply downsampling via `sharp` before passing to the sub-agent when token budget is constrained:

- For layout and color checks: resize long edge to 1280 px before compositing
- For pixel-level detail: use full resolution (up to 2576 px long edge on Claude Opus 4.7)

See `modules/browser-adapter.md` Token budget section for per-image cost estimates.

## Notes

- `pixelmatch` uses a default threshold of 0.1 (10% per-pixel color tolerance). This balances anti-aliasing insensitivity with meaningful diff detection. If a project requires a different threshold, override via `.wholework/adapters/visual-diff-adapter.md`.
- State label → action sequence mapping is the **caller's responsibility**. The adapter treats state labels as opaque strings. Callers must describe what navigation/interaction steps to perform to reach each state.
- 3-panel default is the bundled implementation. Projects needing side-by-side only, odiff-based diff, or ROI cropping can override via `.wholework/adapters/visual-diff-adapter.md` using the existing 3-layer resolution.
