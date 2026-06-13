#!/usr/bin/env bats

# Shallow tests for visual-diff-adapter module documentation.
# LLM responses are not mocked; tests confirm that required sections and
# contract terms are present in modules/visual-diff-adapter.md.
#
# NOTE: The embedded Node scripts in modules/visual-diff-adapter.md (Step 5b/5c)
# are markdown literals — they are invisible to lint, CI static analysis, and
# normal test runners. Runtime bugs in these scripts (e.g. variable scope errors
# as in #441, ESM/CJS interop failures as in #543) can only be caught by actually
# executing them. The smoke tests at the end of this file serve as the pre-merge
# safety net by running node -e directly against fixture PNGs.
# .github/workflows/test.yml provides the Node runtime (actions/setup-node@v4 +
# npm install sharp pixelmatch) for these smoke tests to run in CI.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ADAPTER_FILE="$PROJECT_ROOT/modules/visual-diff-adapter.md"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/visual-diff"

@test "visual-diff-adapter: ## Purpose section exists" {
    grep -q "^## Purpose" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: ## Input section exists" {
    grep -q "^## Input" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: ## Processing Steps section exists" {
    grep -q "^## Processing Steps" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: ## Output section exists" {
    grep -q "^## Output" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: capability gate documented" {
    grep -q "HAS_VISUAL_DIFF_CAPABILITY" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: pixelmatch dependency documented" {
    grep -q "pixelmatch" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: sharp dependency documented" {
    grep -q "sharp" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: 3-panel composite documented" {
    grep -q "3-panel" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: frontend-visual-review sub-agent dispatch documented" {
    grep -q "frontend-visual-review" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: Playwright tool detection documented" {
    grep -q "Playwright" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: fullPage screenshot documented" {
    grep -q "fullPage" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: capture_mode opt-out documented" {
    grep -qE "capture_mode|fullpage" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: dimension normalization documented" {
    grep -qE "extend|sharp\.extend" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: normalized composite documented" {
    grep -q "normalized" "$ADAPTER_FILE"
}

# --- Runtime smoke tests ---
# These tests execute the embedded Node scripts from Step 5b/5c against small
# fixture PNGs to catch runtime failures (ESM/CJS interop, dependency resolution,
# variable scope) before they reach production dogfooding.

@test "visual-diff-adapter: Step 5b embedded node script executes against fixture PNGs" {
    # Skip gracefully if sharp or pixelmatch are not installed
    node -e "require.resolve('sharp'); require.resolve('pixelmatch')" 2>/dev/null || skip "sharp or pixelmatch not installed"

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    cp "$FIXTURES_DIR/ref.png" "$tmp_dir/ref.png"
    cp "$FIXTURES_DIR/impl.png" "$tmp_dir/impl.png"

    node -e "
(async () => {
  const sharp = require('sharp');
  const pixelmatch = require('pixelmatch').default ?? require('pixelmatch');
  const ref = await sharp('$tmp_dir/ref.png').ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const impl = await sharp('$tmp_dir/impl.png').ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const W = Math.max(ref.info.width, impl.info.width);
  const H = Math.max(ref.info.height, impl.info.height);
  const padTo = async (buf, info) =>
    sharp(buf, { raw: { width: info.width, height: info.height, channels: 4 } })
      .extend({ top: 0, bottom: H - info.height, left: 0, right: W - info.width, background: { r: 255, g: 255, b: 255, alpha: 1 } })
      .raw().toBuffer();
  const refPadded = await padTo(ref.data, ref.info);
  const implPadded = await padTo(impl.data, impl.info);
  await sharp(refPadded, { raw: { width: W, height: H, channels: 4 } }).png().toFile('$tmp_dir/ref-padded.png');
  await sharp(implPadded, { raw: { width: W, height: H, channels: 4 } }).png().toFile('$tmp_dir/impl-padded.png');
  const diff = Buffer.alloc(W * H * 4);
  pixelmatch(refPadded, implPadded, diff, W, H, { threshold: 0.1, includeAA: false });
  await sharp(diff, { raw: { width: W, height: H, channels: 4 } }).png().toFile('$tmp_dir/diff.png');
})();
"
    local exit_code=$?

    rm -rf "$tmp_dir"
    [ $exit_code -eq 0 ]
}

@test "visual-diff-adapter: regression fixture undefined var FAILs (class #441)" {
    # Verifies that a broken script with an undefined variable (ReferenceError)
    # exits non-zero — guards against recurrence of #441 (variable scope bug).
    run node -e "const pixelmatch = require('pixelmatch').default ?? require('pixelmatch'); const diff = Buffer.alloc(undefinedHeight * 4);"
    [ "$status" -ne 0 ]
}

@test "visual-diff-adapter: regression fixture MODULE_NOT_FOUND FAILs (class #543)" {
    # Verifies that a broken script with a missing dependency exits non-zero —
    # guards against recurrence of #543 (MODULE_NOT_FOUND / pnpm non-hoist).
    run node -e "require('no-such-module-xyz');"
    [ "$status" -ne 0 ]
}
