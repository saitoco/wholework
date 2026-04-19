#!/usr/bin/env bats

# Tests for get-verify-permission.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-verify-permission.sh"

setup() {
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "Permission: always_allow returned for handler with always_allow declaration" {
    cat > "$WORK_DIR/handler.md" <<'EOF'
# my-handler verify command handler

**Permission:** always_allow

## Purpose

Read-only check.
EOF
    run bash "$SCRIPT" "$WORK_DIR/handler.md"
    [ "$status" -eq 0 ]
    [ "$output" = "always_allow" ]
}

@test "Permission: always_ask returned for handler with always_ask declaration" {
    cat > "$WORK_DIR/handler.md" <<'EOF'
# my-handler verify command handler

**Permission:** always_ask

## Purpose

External call.
EOF
    run bash "$SCRIPT" "$WORK_DIR/handler.md"
    [ "$status" -eq 0 ]
    [ "$output" = "always_ask" ]
}

@test "Permission: always_ask is default when declaration is missing" {
    cat > "$WORK_DIR/handler.md" <<'EOF'
# my-handler verify command handler

**Safe mode:** compatible

## Purpose

No permission field.
EOF
    run bash "$SCRIPT" "$WORK_DIR/handler.md"
    [ "$status" -eq 0 ]
    [ "$output" = "always_ask" ]
}

@test "Permission: always_ask returned when file does not exist" {
    run bash "$SCRIPT" "$WORK_DIR/nonexistent.md"
    [ "$status" -eq 0 ]
    [ "$output" = "always_ask" ]
}

@test "Permission: always_ask returned for empty file path argument" {
    run bash "$SCRIPT" ""
    [ "$status" -eq 0 ]
    [ "$output" = "always_ask" ]
}
