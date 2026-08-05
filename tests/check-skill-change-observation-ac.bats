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

@test "directory path: exit 1 with usage message, not silent exit 0" {
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "glob-form skills/*/SKILL.md reference: exit 2 and untagged line printed" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Changed Files

- `skills/*/SKILL.md` を変更する Issue すべて

## Acceptance Criteria

### Post-merge

- [ ] behavior changes as expected <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"behavior changes as expected"* ]]
}

@test "SKILL.md change without session=next, no trailing newline on last line: exit 2" {
    printf '## Changed Files\n\n- `skills/auto/SKILL.md`: add a step\n\n### Post-merge\n\n- [ ] behavior changes as expected <!-- verify-type: observation event=auto-run -->' > "$FIXTURE_DIR/issue.md"
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"behavior changes as expected"* ]]
}

@test "already-checked AC without session=next: exit 0, not re-flagged" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Changed Files

- `skills/auto/SKILL.md`: add a step

## Acceptance Criteria

### Post-merge

- [x] behavior changes as expected <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "condition text mentions session=next but tag lacks it: exit 2 (not masked by prose)" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Changed Files

- `skills/auto/SKILL.md`: add a step

## Acceptance Criteria

### Post-merge

- [ ] session=next 未付与の Issue で警告が出ることを観察する <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"session=next 未付与"* ]]
}
