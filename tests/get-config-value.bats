#!/usr/bin/env bats

# Tests for get-config-value.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-config-value.sh"

setup() {
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "help: --help outputs usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"get-config-value.sh"* ]]
    [[ "$output" == *"spec-path"* ]]
}

@test "no .wholework.yml: returns empty string when no default" {
    run bash "$SCRIPT" spec-path
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "no .wholework.yml: returns provided default" {
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "docs/spec" ]
}

@test "key exists: returns value without quotes" {
    cat > .wholework.yml << 'EOF'
spec-path: "custom/specs"
EOF
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "custom/specs" ]
}

@test "key exists: returns value without single quotes" {
    cat > .wholework.yml << 'EOF'
spec-path: 'custom/specs'
EOF
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "custom/specs" ]
}

@test "key exists: returns unquoted value" {
    cat > .wholework.yml << 'EOF'
spec-path: custom/specs
EOF
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "custom/specs" ]
}

@test "key absent: returns default value" {
    cat > .wholework.yml << 'EOF'
production-url: "https://example.com"
EOF
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "docs/spec" ]
}

@test "steering-docs-path key: returns value" {
    cat > .wholework.yml << 'EOF'
steering-docs-path: "custom/docs"
EOF
    run bash "$SCRIPT" steering-docs-path "docs"
    [ "$status" -eq 0 ]
    [ "$output" = "custom/docs" ]
}

@test "steering-docs-path absent: returns default docs" {
    cat > .wholework.yml << 'EOF'
spec-path: custom/specs
EOF
    run bash "$SCRIPT" steering-docs-path "docs"
    [ "$status" -eq 0 ]
    [ "$output" = "docs" ]
}

@test "comment lines are ignored" {
    cat > .wholework.yml << 'EOF'
# This is a comment
# spec-path: ignored/comment
spec-path: real/path
EOF
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "real/path" ]
}

@test "inline comment: comment is stripped from value" {
    printf 'k1: v1  # comment\nk2: v2\n' > .wholework.yml
    run bash "$SCRIPT" k1
    [ "$status" -eq 0 ]
    [ "$output" = "v1" ]
}

@test "no trailing newline: last line key is read" {
    printf 'k1: v1  # comment\nk2: v2' > .wholework.yml
    run bash "$SCRIPT" k2
    [ "$status" -eq 0 ]
    [ "$output" = "v2" ]
}

@test "empty .wholework.yml: returns default" {
    touch .wholework.yml
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "docs/spec" ]
}

@test "multiple keys: correct key is extracted" {
    cat > .wholework.yml << 'EOF'
production-url: "https://example.com"
spec-path: "custom/specs"
steering-docs-path: "custom/docs"
opportunistic-verify: true
EOF
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "custom/specs" ]

    run bash "$SCRIPT" steering-docs-path "docs"
    [ "$status" -eq 0 ]
    [ "$output" = "custom/docs" ]

    run bash "$SCRIPT" production-url ""
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.com" ]
}

@test "WHOLEWORK_CONFIG_PATH: custom path is used when set" {
    custom_config="$BATS_TEST_TMPDIR/custom-config.yml"
    echo 'spec-path: custom/from-env' > "$custom_config"
    export WHOLEWORK_CONFIG_PATH="$custom_config"
    run bash "$SCRIPT" spec-path "docs/spec"
    unset WHOLEWORK_CONFIG_PATH
    [ "$status" -eq 0 ]
    [ "$output" = "custom/from-env" ]
}

@test "WHOLEWORK_CONFIG_PATH: falls back to default when path is non-regular file" {
    export WHOLEWORK_CONFIG_PATH="/dev/null"
    run bash "$SCRIPT" spec-path "docs/spec"
    unset WHOLEWORK_CONFIG_PATH
    [ "$status" -eq 0 ]
    [ "$output" = "docs/spec" ]
}

@test "WHOLEWORK_CONFIG_PATH: reads CWD .wholework.yml when unset" {
    cat > .wholework.yml << 'EOF'
spec-path: from-cwd-config
EOF
    unset WHOLEWORK_CONFIG_PATH
    run bash "$SCRIPT" spec-path "docs/spec"
    [ "$status" -eq 0 ]
    [ "$output" = "from-cwd-config" ]
}
