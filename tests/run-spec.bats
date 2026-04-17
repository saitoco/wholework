#!/usr/bin/env bats

# Tests for run-spec.sh
# Mocks: claude, claude-watchdog.sh, phase-banner.sh, gh (via MOCK_DIR + WHOLEWORK_SCRIPT_DIR)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-spec.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    # Mock claude: log flags, model, effort, ANTHROPIC_MODEL, CLAUDECODE, ARGUMENTS
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "ARGS_COUNT=$#" >> "$CLAUDE_CALL_LOG"
for arg in "$@"; do
    case "$arg" in
        -p) echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG" ;;
        --model) echo "FLAG_MODEL=1" >> "$CLAUDE_CALL_LOG" ;;
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
        --effort) echo "FLAG_EFFORT=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
# Extract ARGUMENTS line from prompt (arg after -p)
FOUND_P=0
for arg in "$@"; do
    if [[ $FOUND_P -eq 1 ]]; then
        echo "PROMPT_CONTAINS_ARGUMENTS=$(echo "$arg" | grep -o 'ARGUMENTS:.*' | head -1)" >> "$CLAUDE_CALL_LOG"
        break
    fi
    [[ "$arg" == "-p" ]] && FOUND_P=1
done
# Extract model value (arg after --model)
FOUND_MODEL=0
for arg in "$@"; do
    if [[ $FOUND_MODEL -eq 1 ]]; then
        echo "MODEL_VALUE=$arg" >> "$CLAUDE_CALL_LOG"
        break
    fi
    [[ "$arg" == "--model" ]] && FOUND_MODEL=1
done
# Extract effort value (arg after --effort)
FOUND_EFFORT=0
for arg in "$@"; do
    if [[ $FOUND_EFFORT -eq 1 ]]; then
        echo "EFFORT_VALUE=$arg" >> "$CLAUDE_CALL_LOG"
        break
    fi
    [[ "$arg" == "--effort" ]] && FOUND_EFFORT=1
done
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    # Mock claude-watchdog.sh: pass through to the real claude mock in PATH
    cat > "$MOCK_DIR/claude-watchdog.sh" <<'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/claude-watchdog.sh"

    # Mock phase-banner.sh (sourced by run-spec.sh)
    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
MOCK

    # Mock gh for phase-banner title/url lookups
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
    if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
        echo "test issue title"
    elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
        echo "https://github.com/test/repo/issues/123"
    fi
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Create default SKILL.md with valid frontmatter at $BATS_TEST_TMPDIR/skills/spec/SKILL.md
    # run-spec.sh resolves: SKILL_FILE="${SCRIPT_DIR}/../skills/spec/SKILL.md"
    # With WHOLEWORK_SCRIPT_DIR=$MOCK_DIR, SCRIPT_DIR=$MOCK_DIR, so path is:
    # $MOCK_DIR/../skills/spec/SKILL.md = $BATS_TEST_TMPDIR/skills/spec/SKILL.md
    mkdir -p "$BATS_TEST_TMPDIR/skills/spec"
    cat > "$BATS_TEST_TMPDIR/skills/spec/SKILL.md" <<'SKILL'
---
type: skill
---
# Spec Skill Body
This is the skill body content used for testing.
SKILL
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-spec.sh <issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "error: unknown option is rejected" {
    run bash "$SCRIPT" 123 --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --unknown"* ]]
}

@test "success: default model is sonnet" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "MODEL_VALUE=sonnet" "$CLAUDE_CALL_LOG"
    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
}

@test "success: default effort is max" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=max" "$CLAUDE_CALL_LOG"
}

@test "success: --dangerously-skip-permissions is passed" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "success: --opus switches model to opus" {
    run bash "$SCRIPT" 123 --opus
    [ "$status" -eq 0 ]
    grep -q "MODEL_VALUE=opus" "$CLAUDE_CALL_LOG"
    grep -q "ANTHROPIC_MODEL=opus" "$CLAUDE_CALL_LOG"
}

@test "error: SKILL.md not found when file is absent" {
    rm -f "$BATS_TEST_TMPDIR/skills/spec/SKILL.md"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"SKILL.md not found"* ]]
}

@test "error: frontmatter not found when SKILL.md has no --- delimiter" {
    cat > "$BATS_TEST_TMPDIR/skills/spec/SKILL.md" <<'SKILL'
# No frontmatter here
Just a body with no frontmatter delimiter.
SKILL
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"frontmatter not found"* ]]
}

@test "success: ARGUMENTS contains issue number with --non-interactive" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: CLAUDECODE env var is unset for claude subprocess" {
    export CLAUDECODE="parent-session-id"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "CLAUDECODE=__UNSET__" "$CLAUDE_CALL_LOG"
}

@test "success: --opus default effort is xhigh" {
    run bash "$SCRIPT" 123 --opus
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=xhigh" "$CLAUDE_CALL_LOG"
}

@test "success: --opus --max explicit effort is max" {
    run bash "$SCRIPT" 123 --opus --max
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=max" "$CLAUDE_CALL_LOG"
}
