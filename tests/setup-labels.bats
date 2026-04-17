#!/usr/bin/env bats

# Tests for setup-labels.sh
# Uses WHOLEWORK_SCRIPT_DIR to redirect gh-graphql.sh calls to a mock directory.
# The gh mock handles label operations only; environment detection is controlled
# by placing a gh-graphql.sh mock under MOCK_DIR.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/setup-labels.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    # Default gh-graphql.sh mock: returns 1 (all GitHub features available)
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "1"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    # Default gh mock: handles label list and create operations (no api graphql handling)
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_CALL_LOG"
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    echo ""
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# Helper: count gh label create calls in log
count_label_creates() {
    grep -c 'label create' "$GH_CALL_LOG" 2>/dev/null || echo 0
}

# Helper: check if a label appears in create calls
label_created() {
    grep -q "label create $1" "$GH_CALL_LOG" 2>/dev/null
}

# --- Environment: Projects + Issue Types both available ---
# Only always-group labels (11) should be created

@test "env=full: only always-group labels created when all features available" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(count_label_creates)" -eq 12 ]
}

@test "env=full: phase/* labels all present" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "phase/issue"
    label_created "phase/spec"
    label_created "phase/ready"
    label_created "phase/code"
    label_created "phase/review"
    label_created "phase/verify"
    label_created "phase/done"
}

@test "env=full: always-group non-phase labels present" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "triaged"
    label_created "retro/verify"
    label_created "retro/code"
    label_created "audit/drift"
    label_created "audit/fragility"
}

@test "env=full: fallback-group type/* labels NOT created when Issue Types available" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    run grep "label create type/" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

@test "env=full: fallback-group size/* labels NOT created when Size field available" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    run grep "label create size/" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

# --- Environment: all features unavailable ---
# All 11 always + 17 fallback = 28 labels

@test "env=none: all 29 labels created when no features available" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "0"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(count_label_creates)" -eq 29 ]
}

@test "env=none: fallback type/* labels created when Issue Types unavailable" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "0"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "type/bug"
    label_created "type/feature"
    label_created "type/task"
}

@test "env=none: fallback size/* labels created when Size field unavailable" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "0"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "size/XS"
    label_created "size/S"
    label_created "size/M"
    label_created "size/L"
    label_created "size/XL"
}

@test "env=none: fallback value/* labels created when Value field unavailable" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "0"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "value/1"
    label_created "value/5"
}

@test "env=none: fallback priority/* labels created when Priority field unavailable" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "0"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "priority/urgent"
    label_created "priority/high"
    label_created "priority/medium"
    label_created "priority/low"
}

# --- Idempotency: existing labels are not re-created without --force ---

@test "idempotent: existing label is skipped without --force" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_CALL_LOG"
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    echo "phase/issue"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # phase/issue must NOT appear in create calls
    run grep "label create phase/issue " "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

@test "idempotent: non-existing label is created even when others exist" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_CALL_LOG"
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    echo "phase/issue"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    label_created "phase/spec"
}

# --- --force flag ---

@test "--force: existing labels are created with --force flag" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_CALL_LOG"
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    echo "phase/issue"
    echo "phase/spec"
    echo "phase/ready"
    echo "phase/code"
    echo "phase/review"
    echo "phase/verify"
    echo "phase/done"
    echo "triaged"
    echo "retro/verify"
    echo "retro/code"
    echo "audit/drift"
    echo "audit/fragility"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --force
    [ "$status" -eq 0 ]
    # All 12 always-group labels must be created with --force
    [ "$(count_label_creates)" -eq 12 ]
    [ "$(grep -c -- '--force' "$GH_CALL_LOG")" -eq 12 ]
}

@test "--force: --force flag is NOT used without the option" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    run grep -- '--force' "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

# --- --no-fallback flag ---

@test "--no-fallback: only always-group labels created even when features unavailable" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
echo "0"
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT" --no-fallback
    [ "$status" -eq 0 ]
    [ "$(count_label_creates)" -eq 12 ]
    run grep "label create type/" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

# --- gh-graphql.sh (detection) failure handling ---

@test "env-detect-fail: gh-graphql.sh failure treated as unavailable (fallback created)" {
    cat > "$MOCK_DIR/gh-graphql.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh-graphql.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # When detection fails, fallback labels should be created
    label_created "type/bug"
    label_created "size/XS"
}

# --- Error propagation ---

@test "error: gh label create failure propagates" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    echo ""
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
}

# --- Correct colors ---

@test "colors: all 7 phase/* labels use 1B4F8A" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(grep -- '--color 1B4F8A' "$GH_CALL_LOG" | grep 'phase/' | wc -l | tr -d ' ')" -eq 7 ]
}

@test "colors: triaged uses 0E8A16" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "label create triaged" "$GH_CALL_LOG"
    grep -q "0E8A16" "$GH_CALL_LOG"
}

# --- Completion message ---

@test "output: completion message includes count" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Label setup complete"* ]]
    [[ "$output" == *"12"* ]]
}
