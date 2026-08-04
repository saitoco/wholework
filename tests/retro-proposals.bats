#!/usr/bin/env bats

# Tests for retro-proposals upstream routing and sanitization logic.
# Covers: sanitize regex patterns, upstream routing decision, fallback behavior.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# --- Sanitize helper functions (mirrors retro-proposals.md regex patterns) ---

sanitize_absolute_paths() {
    sed 's|/Users/[^[:space:]]*|<absolute-path>|g'
}

sanitize_issue_numbers() {
    sed 's/#[0-9][0-9]*/#<downstream-issue>/g'
}

# Routing decision function: mirrors retro-proposals.md Step 7.4 condition.
# Args: upstream classification
# Writes "upstream" or "downstream" to stdout.
route_proposal() {
    local upstream="$1"
    local classification="$2"
    if [ -n "$upstream" ] && [ "$classification" = "skill-infra" ]; then
        echo "upstream"
    else
        echo "downstream"
    fi
}

# Tier classification helper: mirrors retro-proposals.md Step 6 positive-evidence gate.
# Args: multi_file_ripple(true|false) recurrence_demonstrated(true|false) ssot_ripple(true|false)
# Returns "tier1" when at least one of the 3 signals (a)/(b)/(c) is demonstrated,
# otherwise the reversed default "tier2" (rather than the former Tier 1 default).
classify_tier() {
    local multi_file="$1"
    local recurrence="$2"
    local ssot="$3"
    if [ "$multi_file" = "true" ] || [ "$recurrence" = "true" ] || [ "$ssot" = "true" ]; then
        echo "tier1"
    else
        echo "tier2"
    fi
}

# Full routing action: calls gh issue create with appropriate flags,
# outputs routing message for upstream case.
# Args: upstream classification title body
perform_routing() {
    local upstream="$1"
    local classification="$2"
    local title="$3"
    local body="$4"

    if [ -n "$upstream" ] && [ "$classification" = "skill-infra" ]; then
        local sanitized_body
        sanitized_body="$(printf '%s' "$body" | sanitize_absolute_paths | sanitize_issue_numbers)"
        gh issue create --repo "$upstream" --title "$title" --label "retro/verify" --body "$sanitized_body"
        local issue_url="$?"
        echo "Routed to upstream $upstream; skipping downstream creation"
        return 0
    else
        gh issue create --title "$title" --label "retro/verify" --body "$body"
        return 0
    fi
}

setup() {
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$WORK_DIR" "$BIN_DIR"
    cd "$WORK_DIR"

    GH_CALLS_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
    rm -f "$GH_CALLS_LOG"

    cat > "$BIN_DIR/gh" << STUB
#!/bin/sh
echo "gh \$*" >> "$GH_CALLS_LOG"
echo "https://github.com/owner/repo/issues/99"
exit 0
STUB
    chmod +x "$BIN_DIR/gh"
    export PATH="$BIN_DIR:$PATH"
}

teardown() {
    rm -rf "$WORK_DIR" "$BIN_DIR" "$BATS_TEST_TMPDIR/gh-calls.log"
}

# --- Sanitize tests ---

@test "sanitize: absolute paths to placeholder" {
    input="See the module at /Users/dev/wholework/modules/retro-proposals.md for details"
    expected="See the module at <absolute-path> for details"
    result="$(printf '%s' "$input" | sanitize_absolute_paths)"
    [ "$result" = "$expected" ]
}

@test "sanitize: downstream issue numbers to placeholder" {
    input="Related to #123 and see also issue #456 for context"
    expected="Related to #<downstream-issue> and see also issue #<downstream-issue> for context"
    result="$(printf '%s' "$input" | sanitize_issue_numbers)"
    [ "$result" = "$expected" ]
}

# --- Routing decision tests ---

@test "routing: upstream unset falls back to downstream" {
    result="$(route_proposal "" "skill-infra")"
    [ "$result" = "downstream" ]
}

@test "routing: upstream set + skill-infra classification routes to upstream" {
    result="$(route_proposal "owner/repo" "skill-infra")"
    [ "$result" = "upstream" ]
}

@test "routing: upstream set + code classification falls back to downstream" {
    result="$(route_proposal "owner/repo" "code")"
    [ "$result" = "downstream" ]
}

# --- Integration: verify gh is called with correct flags ---

@test "routing action: upstream set + skill-infra calls gh issue create --repo" {
    run perform_routing "owner/repo" "skill-infra" "Test proposal" "Some body text"
    [ "$status" -eq 0 ]
    grep -q "gh issue create --repo owner/repo" "$GH_CALLS_LOG"
}

@test "routing action: upstream set + skill-infra outputs routed message" {
    run perform_routing "owner/repo" "skill-infra" "Test proposal" "Some body text"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Routed to upstream owner/repo"* ]]
}

@test "routing action: upstream unset calls gh issue create without --repo" {
    run perform_routing "" "skill-infra" "Test proposal" "Some body text"
    [ "$status" -eq 0 ]
    grep -q "gh issue create --title" "$GH_CALLS_LOG"
    ! grep -q -- "--repo" "$GH_CALLS_LOG"
}

@test "routing action: upstream set + skill-infra sanitizes absolute paths before upstream filing" {
    body="Fix /Users/dev/wholework/modules/retro-proposals.md"
    run perform_routing "owner/repo" "skill-infra" "Fix module" "$body"
    [ "$status" -eq 0 ]
    ! grep -q "/Users/" "$GH_CALLS_LOG"
    grep -q "<absolute-path>" "$GH_CALLS_LOG"
}

# --- Tier classification tests ---

@test "tier classification: no signal demonstrated defaults to tier2 (not tier1)" {
    result="$(classify_tier "false" "false" "false")"
    [ "$result" = "tier2" ]
}

@test "tier classification: any of (a)/(b)/(c) demonstrated returns tier1" {
    result_a="$(classify_tier "true" "false" "false")"
    result_b="$(classify_tier "false" "true" "false")"
    result_c="$(classify_tier "false" "false" "true")"
    [ "$result_a" = "tier1" ]
    [ "$result_b" = "tier1" ]
    [ "$result_c" = "tier1" ]
}
