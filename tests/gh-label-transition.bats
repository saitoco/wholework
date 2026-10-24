#!/usr/bin/env bats

# Tests for gh-label-transition.sh
# Mock external commands (gh) by placing them at the front of PATH

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/gh-label-transition.sh"
SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying gh calls
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    # Record file for verifying setup-labels.sh calls
    SETUP_LABELS_CALL_LOG="$BATS_TEST_TMPDIR/setup_labels_calls.log"
    export SETUP_LABELS_CALL_LOG

    # Default gh mock: label list returns existing phase/* labels
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    echo "phase/issue"
    echo "phase/spec"
    echo "phase/ready"
    echo "phase/code"
    echo "phase/review"
    echo "phase/verify"
    echo "phase/done"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Default setup-labels.sh mock: records calls, succeeds
    cat > "$MOCK_DIR/setup-labels.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "$SETUP_LABELS_CALL_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/setup-labels.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "help: --help shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "success: transition to code phase" {
    run bash "$SCRIPT" 123 code
    [ "$status" -eq 0 ]
    grep -q "issue edit 123" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/code" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/issue" "$GH_CALL_LOG"
}

@test "success: transition to spec phase" {
    run bash "$SCRIPT" 456 spec
    [ "$status" -eq 0 ]
    grep -q "issue edit 456" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/spec" "$GH_CALL_LOG"
}

@test "success: transition to verify phase" {
    run bash "$SCRIPT" 789 verify
    [ "$status" -eq 0 ]
    grep -q "issue edit 789" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/verify" "$GH_CALL_LOG"
}

@test "success: transition to done phase" {
    run bash "$SCRIPT" 321 done
    [ "$status" -eq 0 ]
    grep -q "issue edit 321" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/done" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/issue" "$GH_CALL_LOG"
}

@test "regression (#289): transition to done removes phase/verify" {
    run bash "$SCRIPT" 289 done
    [ "$status" -eq 0 ]
    grep -q "\-\-add-label phase/done" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/verify" "$GH_CALL_LOG"
}

@test "regression (#304): transition to verify removes phase/done" {
    run bash "$SCRIPT" 304 verify
    [ "$status" -eq 0 ]
    grep -q "\-\-add-label phase/verify" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/done" "$GH_CALL_LOG"
}

@test "success: remove all phase labels without adding (no target-phase)" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "issue edit 123" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/issue" "$GH_CALL_LOG"
    run grep "\-\-add-label" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

@test "success: all valid phases are accepted" {
    for phase in issue spec ready code review verify done; do
        run bash "$SCRIPT" 1 "$phase"
        [ "$status" -eq 0 ]
    done
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number is required"* ]]
}

@test "error: invalid issue number (non-numeric)" {
    run bash "$SCRIPT" abc code
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number must be a positive integer"* ]]
}

@test "error: invalid issue number (zero)" {
    run bash "$SCRIPT" 0 code
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number must be a positive integer"* ]]
}

@test "error: invalid target-phase" {
    run bash "$SCRIPT" 123 invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid phase"* ]]
}

@test "idempotent: target label already set skips remove+add of target" {
    # Mock gh to return phase/done as current label for 'issue view' calls
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [ "\$1" = "issue" ] && [ "\$2" = "view" ]; then
    echo "phase/done"
else
    echo "\$@" >> "$GH_CALL_LOG"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42 done
    [ "$status" -eq 0 ]
    # Should not remove phase/done (target label already present)
    run grep -- "--remove-label phase/done" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
    # Should not add phase/done again
    run grep -- "--add-label phase/done" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
    # Should still remove other phase labels
    grep -q -- "--remove-label phase/verify" "$GH_CALL_LOG"
}

@test "idempotent: target label not set uses normal remove+add flow" {
    # Mock gh to return a different label for 'issue view' calls
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [ "\$1" = "issue" ] && [ "\$2" = "view" ]; then
    echo "phase/verify"
elif [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    # Return all phase/* labels so auto-bootstrap is not triggered
    echo "phase/issue"; echo "phase/spec"; echo "phase/ready"
    echo "phase/code"; echo "phase/review"; echo "phase/verify"; echo "phase/done"
else
    echo "\$@" >> "$GH_CALL_LOG"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42 done
    [ "$status" -eq 0 ]
    # Should add phase/done
    grep -q -- "--add-label phase/done" "$GH_CALL_LOG"
    # Should remove phase/verify
    grep -q -- "--remove-label phase/verify" "$GH_CALL_LOG"
}

@test "regression: target label not included in remove list during normal transition (else branch)" {
    # Mock gh to return phase/spec as current label for 'issue view' calls
    # This simulates the bug scenario: transitioning from phase/spec to phase/ready
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [ "\$1" = "issue" ] && [ "\$2" = "view" ]; then
    echo "phase/spec"
elif [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    # Return all phase/* labels so auto-bootstrap is not triggered
    echo "phase/issue"; echo "phase/spec"; echo "phase/ready"
    echo "phase/code"; echo "phase/review"; echo "phase/verify"; echo "phase/done"
else
    echo "\$@" >> "$GH_CALL_LOG"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42 ready
    [ "$status" -eq 0 ]
    # Should add phase/ready
    grep -q -- "--add-label phase/ready" "$GH_CALL_LOG"
    # Should NOT remove phase/ready (target label must be excluded from remove list)
    run grep -- "--remove-label phase/ready" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
    # Should still remove the previous phase label
    grep -q -- "--remove-label phase/spec" "$GH_CALL_LOG"
}

# --- Auto-bootstrap tests ---

@test "bootstrap: setup-labels.sh triggered when target phase/* label missing from repo" {
    # gh mock: label list returns empty (no phase labels in repo), issue view returns ""
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    echo ""
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 99 code
    [ "$status" -eq 0 ]
    # Confirm setup-labels.sh ran by checking label create appears in call log
    grep -q "label create" "$GH_CALL_LOG"
    # Confirm gh-label-transition.sh still added the target label
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
}

@test "bootstrap: setup-labels.sh NOT triggered when target phase/* label already exists in repo" {
    # Default mock already returns all phase/* labels from label list
    run bash "$SCRIPT" 99 code
    [ "$status" -eq 0 ]
    # No label create calls - setup-labels.sh was not triggered
    run grep "label create" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
    # Target label still added to the issue
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
}

@test "error: gh issue edit failure exits with code 1 and Error message" {
    # gh mock: label list succeeds, issue view returns nothing, issue edit fails
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    echo "phase/issue"
    echo "phase/spec"
    echo "phase/ready"
    echo "phase/code"
    echo "phase/review"
    echo "phase/verify"
    echo "phase/done"
    exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "view" ]; then
    exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "edit" ]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123 code
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "bootstrap: gh-label-transition.sh continues with warning when setup-labels.sh fails" {
    # gh mock: label list returns empty (triggers bootstrap), label create fails
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [ "\$1" = "label" ] && [ "\$2" = "create" ]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 99 code
    # Must exit 0 (continues despite bootstrap failure)
    [ "$status" -eq 0 ]
    # Target label still added to the issue
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
}

# --- --assign (opt-in assignee update) ---

# gh stub that routes label, assignee-read, user and write calls separately
write_assign_gh_mock() {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    echo "phase/code"
    exit 0
fi
if [ "\$1" = "api" ] && [ "\$2" = "user" ]; then
    echo "me"
    exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "view" ]; then
    case "\$*" in
        *assignees*)
            n=0
            [ -f "$BATS_TEST_TMPDIR/view_count" ] && n=\$(cat "$BATS_TEST_TMPDIR/view_count")
            n=\$((n + 1))
            echo "\$n" > "$BATS_TEST_TMPDIR/view_count"
            if [ "\$n" -ge 2 ]; then
                echo '{"assignees":[{"id":"U_dummy","login":"me","name":"Me","databaseId":1}]}'
            else
                echo '{"assignees":[]}'
            fi
            ;;
    esac
    exit 0
fi
case "\$*" in
    *"-X POST"*)
        [ "\${MOCK_WRITE_FAIL:-}" = "1" ] && exit 1
        echo '{}'
        exit 0
        ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

@test "assign: no --assign flag never touches assignees" {
    write_assign_gh_mock
    run bash "$SCRIPT" 99 code
    [ "$status" -eq 0 ]
    ! grep -q -- "assignees" "$GH_CALL_LOG"
    ! grep -q -- "api" "$GH_CALL_LOG"
}

@test "assign: --assign updates the assignee after the label update" {
    write_assign_gh_mock
    run bash "$SCRIPT" 99 code --assign
    [ "$status" -eq 0 ]
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
    grep -q -- "-X POST" "$GH_CALL_LOG"
    label_line=$(grep -n -- "--add-label phase/code" "$GH_CALL_LOG" | head -1 | cut -d: -f1)
    post_line=$(grep -n -- "-X POST" "$GH_CALL_LOG" | head -1 | cut -d: -f1)
    [ "$label_line" -lt "$post_line" ]
}

@test "assign: --assign leaves the stdout of the label transition unchanged" {
    write_assign_gh_mock
    run --separate-stderr bash "$SCRIPT" 99 code --assign
    [ "$status" -eq 0 ]
    [[ "$output" != *"assigned"* ]] || false
}

@test "assign: --assign is accepted before the positional arguments" {
    write_assign_gh_mock
    run bash "$SCRIPT" --assign 99 code
    [ "$status" -eq 0 ]
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
    grep -q -- "-X POST" "$GH_CALL_LOG"
}

@test "assign: assignee API failure does not fail the label transition" {
    write_assign_gh_mock
    export MOCK_WRITE_FAIL=1
    run --separate-stderr bash "$SCRIPT" 99 code --assign
    [ "$status" -eq 0 ]
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
    [[ "$stderr" == *"Warning: failed to update the assignee of issue #99"* ]]
}

@test "assign: a crashing assignee helper does not fail the label transition" {
    write_assign_gh_mock
    cat > "$MOCK_DIR/gh-issue-assignee.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh-issue-assignee.sh"
    WHOLEWORK_SCRIPT_DIR="$MOCK_DIR" run --separate-stderr bash "$SCRIPT" 99 code --assign
    [ "$status" -eq 0 ]
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
    [[ "$stderr" == *"Warning: assignee update for issue #99 failed"* ]]
}

@test "assign: a missing assignee helper does not fail the label transition" {
    write_assign_gh_mock
    WHOLEWORK_SCRIPT_DIR="$MOCK_DIR" run --separate-stderr bash "$SCRIPT" 99 code --assign
    [ "$status" -eq 0 ]
    grep -q -- "--add-label phase/code" "$GH_CALL_LOG"
}

@test "assign: label update failure skips the assignee update" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
    echo "phase/code"
    exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "edit" ]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 99 code --assign
    [ "$status" -eq 1 ]
    ! grep -q -- "-X POST" "$GH_CALL_LOG"
    ! grep -q -- "api" "$GH_CALL_LOG"
}

@test "assign: --assign without a target phase is a usage error" {
    write_assign_gh_mock
    run --separate-stderr bash "$SCRIPT" 99 --assign
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--assign requires a target phase"* ]]
    [ ! -s "$GH_CALL_LOG" ]
}

@test "assign: --assign alone reports the missing issue number" {
    run --separate-stderr bash "$SCRIPT" --assign
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"issue number is required"* ]]
}

@test "help: --help documents --assign" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--assign"* ]] || false
}
