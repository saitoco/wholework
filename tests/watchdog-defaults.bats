#!/usr/bin/env bats

# Tests for scripts/watchdog-defaults.sh

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "sourcing sets WATCHDOG_TIMEOUT_DEFAULT=2700" {
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; echo \$WATCHDOG_TIMEOUT_DEFAULT"
    [ "$status" -eq 0 ]
    [ "$output" = "2700" ]
}

@test "load_watchdog_timeout sets WATCHDOG_TIMEOUT from get-config-value.sh" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo "3600"
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR'; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "3600" ]
}

@test "load_watchdog_timeout falls back to default on non-numeric value" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo "abc"
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 2>/dev/null; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "2700" ]
}

@test "load_watchdog_timeout falls back to default on negative value" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo "-1"
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 2>/dev/null; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "2700" ]
}

@test "load_watchdog_timeout prints warning to stderr on invalid value" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo "abc"
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"* ]]
}

@test "load_watchdog_timeout uses phase-specific default when phase is spec" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 'spec' 2>/dev/null; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "1800" ]
}

@test "load_watchdog_timeout uses WATCHDOG_TIMEOUT_MERGE_DEFAULT when phase is merge" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 'merge' 2>/dev/null; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "600" ]
}

@test "load_watchdog_timeout uses phase yml key when set" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo "900"
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 'spec'; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "load_watchdog_timeout falls back to global yml key when phase key is unset" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
if [ "$1" = "watchdog-timeout-spec-seconds" ]; then
  echo ""
else
  echo "3600"
fi
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 'spec'; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "3600" ]
}

@test "load_watchdog_timeout without phase argument uses WATCHDOG_TIMEOUT_DEFAULT" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 2>/dev/null; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "2700" ]
}

@test "load_watchdog_timeout uses WATCHDOG_TIMEOUT_CODE_DEFAULT=3600 when phase is code" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    run bash -c "source '$SCRIPT_DIR/watchdog-defaults.sh'; load_watchdog_timeout '$MOCK_DIR' 'code' 2>/dev/null; echo \$WATCHDOG_TIMEOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "3600" ]
}
