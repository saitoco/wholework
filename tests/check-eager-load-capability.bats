#!/usr/bin/env bats

# Direct unit tests for scripts/check-eager-load-capability.sh
# Covers: empty Glob, verify-executor.md detection, domain file suppression, multi-capability detection.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-eager-load-capability.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/modules"
  mkdir -p "$BATS_TEST_TMPDIR/skills"
}

@test "empty Glob: no adapter files exits 0 with no output" {
  # No *-adapter.md files exist under modules/ -> capabilities is empty -> exit 0, no output.
  run bash "$SCRIPT" --root "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detection: adapter with contaminated verify-executor.md reports issue" {
  # Adapter file marks browser as a known capability.
  touch "$BATS_TEST_TMPDIR/modules/browser-adapter.md"

  # verify-executor.md (second target file) contains a capability section heading.
  cat > "$BATS_TEST_TMPDIR/modules/verify-executor.md" <<'EOF'
# verify-executor

## General

## browser Guidance

This section should live in a Domain file.
EOF

  # No Domain file -> ISSUE line should be emitted for verify-executor.md.
  run bash "$SCRIPT" --root "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "browser"
  echo "$output" | grep -q "verify-executor.md"
}

@test "no-issue: domain file presence suppresses detection" {
  touch "$BATS_TEST_TMPDIR/modules/visual-diff-adapter.md"

  cat > "$BATS_TEST_TMPDIR/modules/verify-patterns.md" <<'EOF'
# verify-patterns

## visual-diff Guidance

Contaminated content.
EOF

  # Domain file exists under skills/ -> no ISSUE should be reported.
  mkdir -p "$BATS_TEST_TMPDIR/skills/spec"
  touch "$BATS_TEST_TMPDIR/skills/spec/visual-diff-guidance.md"

  run bash "$SCRIPT" --root "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "multi: two adapters both contaminating verify-patterns.md report two ISSUE lines" {
  # Two adapter files -> two capabilities.
  touch "$BATS_TEST_TMPDIR/modules/visual-diff-adapter.md"
  touch "$BATS_TEST_TMPDIR/modules/browser-adapter.md"

  # Both capability section headings present in verify-patterns.md.
  cat > "$BATS_TEST_TMPDIR/modules/verify-patterns.md" <<'EOF'
# verify-patterns

## visual-diff Guidance

Content that should be in a Domain file.

## browser Guidance

Content that should also be in a Domain file.
EOF

  # No Domain files -> two ISSUE lines expected.
  run bash "$SCRIPT" --root "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  issue_count="$(echo "$output" | grep -c "^ISSUE:")"
  [ "$issue_count" -eq 2 ]
}
