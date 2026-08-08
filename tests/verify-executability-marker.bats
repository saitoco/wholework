#!/usr/bin/env bats

# Tests for scripts/verify-executability-marker.sh
# Mocks: gh (via PATH prepend), following the same convention as
# tests/resolve-preview-ac-fallback.bats. The mock does not interpret --jq — it
# returns canned output representing what `gh issue view --json comments --jq
# '...'` would print for the *latest* type=verify-executability marker comment
# body (the sort_by(.createdAt) | .[-1] narrowing is real gh's responsibility,
# not this script's).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/verify-executability-marker.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

# --- format: executable judgment ---

@test "format: executable=true emits marker without reason" {
    run "$SCRIPT" format 42 3 true
    [ "$status" -eq 0 ]
    [[ "$output" == *"ac=3 executable=true"* ]]
    [[ "$output" != *"reason="* ]]
}

@test "format: executable=false with reason emits reason attribute" {
    run "$SCRIPT" format 42 5 false browser-required
    [ "$status" -eq 0 ]
    [[ "$output" == *"executable=false reason=browser-required"* ]]
}

@test "format: reason=capability-unavailable requires capability=" {
    run "$SCRIPT" format 42 5 false capability-unavailable
    [ "$status" -eq 1 ]

    run "$SCRIPT" format 42 5 false capability-unavailable capability=capabilities.browser
    [ "$status" -eq 0 ]
    [[ "$output" == *"reason=capability-unavailable capability=capabilities.browser"* ]]
}

@test "format: reason=other requires detail=" {
    run "$SCRIPT" format 42 7 false other
    [ "$status" -eq 1 ]

    run "$SCRIPT" format 42 7 false other detail="something unusual"
    [ "$status" -eq 0 ]
    [[ "$output" == *'reason=other detail="something unusual"'* ]]
}

@test "format: detail containing a double quote or --> is rejected" {
    run "$SCRIPT" format 42 7 false other detail='has "quote"'
    [ "$status" -eq 1 ]

    run "$SCRIPT" format 42 7 false other detail='has --> marker'
    [ "$status" -eq 1 ]
}

@test "format: capability containing a space, double quote, or --> is rejected" {
    run "$SCRIPT" format 42 5 false browser-required capability='evil --> injected'
    [ "$status" -eq 1 ]

    run "$SCRIPT" format 42 5 false browser-required capability='has "quote"'
    [ "$status" -eq 1 ]

    run "$SCRIPT" format 42 5 false browser-required capability='has space'
    [ "$status" -eq 1 ]
}

@test "format: executable=false with no reason exits 1" {
    run "$SCRIPT" format 42 5 false
    [ "$status" -eq 1 ]
}

@test "format: unknown reason slug exits 1" {
    run "$SCRIPT" format 42 5 false not-a-real-reason
    [ "$status" -eq 1 ]
}

@test "format: executable=true rejects extra reason/capability/detail arguments" {
    run "$SCRIPT" format 42 5 true browser-required
    [ "$status" -eq 1 ]
}

@test "format: non-integer issue or ac_index exits 1" {
    run "$SCRIPT" format abc 5 true
    [ "$status" -eq 1 ]

    run "$SCRIPT" format 42 abc true
    [ "$status" -eq 1 ]
}

@test "format: invalid executable value exits 1" {
    run "$SCRIPT" format 42 5 maybe
    [ "$status" -eq 1 ]
}

@test "format: missing required arguments exits 1" {
    run "$SCRIPT" format 42 5
    [ "$status" -eq 1 ]
}

# --- resolve: latest-wins snapshot ---

@test "resolve: latest-wins snapshot yields one TSV row per marker" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo '<!-- wholework-event: type=verify-executability phase=verify issue=42 ac=3 executable=true -->
<!-- wholework-event: type=verify-executability phase=verify issue=42 ac=5 executable=false reason=browser-required -->
## Acceptance Test Results'
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" resolve 42
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf '3\ttrue\t\t')" ]
    [ "${lines[1]}" = "$(printf '5\tfalse\tbrowser-required\t')" ]
}

@test "resolve: marker with capability attribute is preserved in TSV" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo '<!-- wholework-event: type=verify-executability phase=verify issue=42 ac=7 executable=false reason=capability-unavailable capability=capabilities.browser -->'
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" resolve 42
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '7\tfalse\tcapability-unavailable\tcapabilities.browser')" ]
}

@test "resolve: no marker comment yields empty output, exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo ""
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" resolve 42
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "resolve: gh failure exits 2, distinct from no-marker" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" resolve 42
    [ "$status" -eq 2 ]
}

@test "resolve: non-numeric argument exits 1" {
    run "$SCRIPT" resolve abc
    [ "$status" -eq 1 ]
}

@test "resolve: no argument exits 1" {
    run "$SCRIPT" resolve
    [ "$status" -eq 1 ]
}

# --- subcommand dispatch ---

@test "no subcommand: usage on stderr, exit 1" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "unknown subcommand: usage on stderr, exit 1" {
    run "$SCRIPT" bogus
    [ "$status" -eq 1 ]
}

@test "--help: usage on stdout, exit 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
