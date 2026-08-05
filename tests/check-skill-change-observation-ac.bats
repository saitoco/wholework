#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for check-skill-change-observation-ac.sh
# Verifies session=next detection for observation ACs when the Issue body
# changes skills/*/SKILL.md:
#   exit 0 — no skills/*/SKILL.md reference, or all matching observation ACs
#            already carry session=next
#   exit 1 — usage error (missing argument or unreadable file)
#   exit 2 — one or more observation AC lines lack session=next

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REAL_SCRIPT="$PROJECT_ROOT/scripts/check-skill-change-observation-ac.sh"

setup() {
    FIXTURE_DIR="$BATS_TEST_TMPDIR"
}

write_fixture() {
    local path="$1"
    cat > "$path"
}

@test "no SKILL.md reference: exit 0 and no output even without session=next" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Changed Files

- `scripts/foo.sh`: add a helper

## Acceptance Criteria

### Post-merge

- [ ] something happens <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "SKILL.md change without session=next: exit 2 and untagged line printed" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Changed Files

- `skills/auto/SKILL.md`: add a step

## Acceptance Criteria

### Post-merge

- [ ] behavior changes as expected <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"behavior changes as expected"* ]]
}

@test "SKILL.md change with session=next already assigned: exit 0" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Changed Files

- `skills/auto/SKILL.md`: add a step

## Acceptance Criteria

### Post-merge

- [ ] behavior changes as expected <!-- verify-type: observation event=auto-run session=next -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "no argument: exit 1 with usage message" {
    run bash "$REAL_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "nonexistent path: exit 1 with usage message" {
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/does-not-exist.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
