#!/usr/bin/env bats

# Tests for scripts/check-eager-load-capability.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-eager-load-capability.sh"

setup() {
  BATS_TMPDIR="$(mktemp -d)"
  mkdir -p "$BATS_TMPDIR/modules"
  mkdir -p "$BATS_TMPDIR/skills"
}

teardown() {
  rm -rf "$BATS_TMPDIR"
}

@test "detection: verify-patterns.md with visual-diff section heading is detected" {
  # Adapter file marks visual-diff as a known capability.
  touch "$BATS_TMPDIR/modules/visual-diff-adapter.md"

  # Contaminated verify-patterns.md with a capability section heading.
  cat > "$BATS_TMPDIR/modules/verify-patterns.md" <<'EOF'
# verify-patterns

## General Patterns

Some general content here.

## visual-diff Guidance

This section should be in a Domain file instead.
EOF

  # No Domain file exists -> should report an issue.
  run bash "$SCRIPT" --root "$BATS_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "visual-diff"
}

@test "no-issue: Domain file present suppresses output" {
  touch "$BATS_TMPDIR/modules/visual-diff-adapter.md"

  cat > "$BATS_TMPDIR/modules/verify-patterns.md" <<'EOF'
# verify-patterns

## visual-diff Guidance

Contaminated content.
EOF

  # Domain file exists -> no issue should be reported.
  mkdir -p "$BATS_TMPDIR/skills/spec"
  touch "$BATS_TMPDIR/skills/spec/visual-diff-guidance.md"

  run bash "$SCRIPT" --root "$BATS_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clean: no section heading contamination produces no output" {
  touch "$BATS_TMPDIR/modules/visual-diff-adapter.md"

  # Clean verify-patterns.md with no capability section headings.
  cat > "$BATS_TMPDIR/modules/verify-patterns.md" <<'EOF'
# verify-patterns

## General Patterns

No capability-specific headings here.

## Another Section

Still clean.
EOF

  run bash "$SCRIPT" --root "$BATS_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
