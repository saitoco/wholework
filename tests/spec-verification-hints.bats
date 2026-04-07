#!/usr/bin/env bats

# Tests for acceptance check generation logic in the /issue skill
# Validates false positive patterns (multiline content, negation contexts)

setup() {
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- grep single-line match constraint tests ---

@test "grep: FAIL on multiline JSON schema" {
    # Multi-line JSON schema
    cat > "$TEST_DIR/multiline.json" <<'EOF'
{
  "new_title": "component: description",
  "type": "Feature",
  "size": "M"
}
EOF

    # grep "new_title.*type.*size" FAILS (keys are not on the same line)
    run grep "new_title.*type.*size" "$TEST_DIR/multiline.json"
    [ "$status" -ne 0 ]
}

@test "file_contains: PASS on multiline content with individual keywords" {
    cat > "$TEST_DIR/multiline.json" <<'EOF'
{
  "new_title": "component: description",
  "type": "Feature",
  "size": "M"
}
EOF

    # file_contains (grep -F) validates individual keywords
    run grep -F "new_title" "$TEST_DIR/multiline.json"
    [ "$status" -eq 0 ]
    run grep -F "type" "$TEST_DIR/multiline.json"
    [ "$status" -eq 0 ]
    run grep -F "size" "$TEST_DIR/multiline.json"
    [ "$status" -eq 0 ]
}

# --- file_not_contains negation context false positive tests ---

@test "file_not_contains: FALSE POSITIVE on negation context" {
    # Negation context: "do not use Task subagent"
    cat > "$TEST_DIR/negation.md" <<'EOF'
Task subagent should not be used here.
EOF

    # file_not_contains "Task subagent" produces a false positive (FAIL)
    run grep -F "Task subagent" "$TEST_DIR/negation.md"
    [ "$status" -eq 0 ]  # string is found (incorrectly treated as "not removed")
}

@test "file_not_contains: CORRECT PATTERN with verb+particle" {
    cat > "$TEST_DIR/correct.md" <<'EOF'
Task subagent should not be used here.
EOF

    # verb+noun "delegate to subagent" is not present (PASS)
    run grep -F "delegate to subagent" "$TEST_DIR/correct.md"
    [ "$status" -ne 0 ]

    # verb+noun "subagent is used" is not present (PASS)
    run grep -F "subagent is used" "$TEST_DIR/correct.md"
    [ "$status" -ne 0 ]
}

@test "file_not_contains: FAIL when verb+particle exists" {
    cat > "$TEST_DIR/exists.md" <<'EOF'
Delegate each Issue to a subagent.
EOF

    # verb+noun "delegate to subagent" is present (FAIL)
    run grep -F "subagent" "$TEST_DIR/exists.md"
    [ "$status" -eq 0 ]
}
