#!/usr/bin/env bats

# Tests for scripts/claude-watchdog.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/claude-watchdog.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: claude-watchdog.sh"* ]]
}

@test "normal exit 0: output and exit code pass through" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
echo "hello from command"
exit 0
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello from command"* ]]
}

@test "normal exit non-zero: exit code passes through without retry" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/invocation_count"
    echo "0" > "$COUNTER_FILE"

    cat > "$MOCK_DIR/cmd.sh" <<MOCK
#!/bin/bash
count=\$(cat "$COUNTER_FILE")
echo \$((count + 1)) > "$COUNTER_FILE"
echo "error output"
exit 42
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 42 ]
    [[ "$output" == *"error output"* ]]

    # Verify command was invoked exactly once (no retry on normal non-zero exit)
    [ "$(cat "$COUNTER_FILE")" -eq 1 ]
}

@test "watchdog timeout: command with no output is killed after WATCHDOG_TIMEOUT" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    # Should be non-zero (killed by watchdog, then retry also killed)
    [ "$status" -ne 0 ]
    [[ "$output" == *"watchdog: no output for 2s, killing process"* ]]
}

@test "retry: second invocation occurs after watchdog kill" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/invocation_count"
    echo "0" > "$COUNTER_FILE"

    cat > "$MOCK_DIR/cmd.sh" <<MOCK
#!/bin/bash
count=\$(cat "$COUNTER_FILE")
count=\$((count + 1))
echo \$count > "$COUNTER_FILE"
if [[ \$count -eq 1 ]]; then
    # First invocation: produce no output and hang — trigger watchdog
    sleep 60
else
    # Second invocation (retry): succeed normally
    echo "retry succeeded"
    exit 0
fi
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"watchdog: retrying once..."* ]]
    [[ "$output" == *"retry succeeded"* ]]

    # Verify exactly 2 invocations occurred
    [ "$(cat "$COUNTER_FILE")" -eq 2 ]
}

@test "WATCHDOG_TIMEOUT env var: custom value takes effect" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    # With WATCHDOG_TIMEOUT=2, the watchdog should fire quickly
    start_time=$(date +%s)
    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # Should complete well under 30 seconds (default 600s would take much longer)
    [ "$elapsed" -lt 30 ]
    [ "$status" -ne 0 ]
}

@test "no retry: watchdog fires only once on second hang" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/invocation_count"
    echo "0" > "$COUNTER_FILE"

    cat > "$MOCK_DIR/cmd.sh" <<MOCK
#!/bin/bash
count=\$(cat "$COUNTER_FILE")
count=\$((count + 1))
echo \$count > "$COUNTER_FILE"
# Both invocations hang — watchdog fires twice but only retries once
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -ne 0 ]

    # Verify exactly 2 invocations (original + 1 retry), no more
    [ "$(cat "$COUNTER_FILE")" -eq 2 ]
}
