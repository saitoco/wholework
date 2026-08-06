#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for check-ac-checkbox-format.sh
# Verifies checkbox-format detection for ### Pre-merge / ### Post-merge
# condition lines:
#   exit 0 — no Pre-merge/Post-merge section, or every condition line is
#            already checkbox format
#   exit 1 — usage error (missing argument or unreadable file)
#   exit 2 — one or more non-checkbox condition lines detected

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REAL_SCRIPT="$PROJECT_ROOT/scripts/check-ac-checkbox-format.sh"

setup() {
    FIXTURE_DIR="$BATS_TEST_TMPDIR"
}

write_fixture() {
    local path="$1"
    cat > "$path"
}

@test "all conditions checkbox format: exit 0 and no output" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] file exists <!-- verify: file_exists "foo.sh" -->

### Post-merge

- [ ] behavior changes as expected <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "plain bullet under Post-merge: exit 2 and line printed" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Acceptance Criteria

### Post-merge

- behavior changes as expected <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"behavior changes as expected"* ]]
}

@test "plain bullet under Pre-merge: exit 2 and line printed" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Acceptance Criteria

### Pre-merge (auto-verified)

- file exists <!-- verify: file_exists "foo.sh" -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"file exists"* ]]
}

@test "plain bullet with no verify-type marker at all: exit 2" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Acceptance Criteria

### Post-merge

- something happens with no marker at all
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"something happens with no marker at all"* ]]
}

@test "no Pre-merge/Post-merge section in body: exit 0" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Background

Some plain bullet not under any Pre-merge/Post-merge section.

- this is not a condition line
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "already-checked checkbox is not flagged" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Acceptance Criteria

### Post-merge

- [x] behavior changes as expected <!-- verify-type: observation event=auto-run -->
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/issue.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "plain bullet outside section boundary (after next heading) is not detected" {
    write_fixture "$FIXTURE_DIR/issue.md" <<'EOF'
## Acceptance Criteria

### Post-merge

- [ ] properly formatted condition <!-- verify-type: manual -->

## Related

- this plain bullet is outside Post-merge and must not be flagged
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
