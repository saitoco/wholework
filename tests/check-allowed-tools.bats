#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/check-allowed-tools.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/mocks"
}

@test "check-allowed-tools: exits 1 with stderr warning when allowed-tools mismatch detected" {
    cat > "$MOCK_DIR/validate-skill-syntax.py" <<'EOF'
#!/usr/bin/env python3
import sys
print("error: 本文中に参照されたスクリプト 'my-script.sh' が allowed-tools の Bash(...) パターンに含まれていません")
print("1 error(s) found")
sys.exit(1)
EOF
    chmod +x "$MOCK_DIR/validate-skill-syntax.py"

    run --separate-stderr "$SCRIPT" skills/
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Warning: allowed-tools mismatch"* ]]
}

@test "check-allowed-tools: exits 0 when no mismatches detected" {
    cat > "$MOCK_DIR/validate-skill-syntax.py" <<'EOF'
#!/usr/bin/env python3
print("0 error(s) found")
EOF
    chmod +x "$MOCK_DIR/validate-skill-syntax.py"

    run "$SCRIPT" skills/
    [ "$status" -eq 0 ]
}

@test "check-allowed-tools: exits 0 when validator is absent" {
    run "$SCRIPT" skills/
    [ "$status" -eq 0 ]
}
