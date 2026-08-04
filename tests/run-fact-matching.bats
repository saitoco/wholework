#!/usr/bin/env bats

# Tests for scripts/collect-run-facts.sh, scripts/scan-pending-ac.sh, and
# scripts/apply-run-fact-match.sh (see docs/spec/issue-1157-run-fact-ac-match.md).
# Mocks: gh (via PATH prepend), sibling scripts (via WHOLEWORK_SCRIPT_DIR).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
COLLECT_SCRIPT="$PROJECT_ROOT/scripts/collect-run-facts.sh"
SCAN_SCRIPT="$PROJECT_ROOT/scripts/scan-pending-ac.sh"
APPLY_SCRIPT="$PROJECT_ROOT/scripts/apply-run-fact-match.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    unset AUTO_SESSION_ID
    unset AUTO_EVENTS_LOG

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export WHOLEWORK_CONFIG_PATH=/dev/null
}

# ---------------------------------------------------------------------------
# collect-run-facts.sh
# ---------------------------------------------------------------------------

@test "collect-run-facts: no session id resolvable exits 1" {
    run bash "$COLLECT_SCRIPT" --no-github
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "collect-run-facts: missing events log yields empty issues array" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/nonexistent.jsonl"
    run bash "$COLLECT_SCRIPT" --session sess1 --no-github
    [ "$status" -eq 0 ]
    [ "$output" = '{"session_id":"sess1","issues":[]}' ]
}

@test "collect-run-facts: route/pr/phases/anomalies/fact_tokens derived from fixture events" {
    EVENTS_FILE="$BATS_TEST_TMPDIR/events.jsonl"
    cat > "$EVENTS_FILE" <<'EOF'
{"ts":"2026-08-05T00:00:00Z","issue":1150,"event":"phase_start","session_id":"sess1","phase":"code-pr"}
{"ts":"2026-08-05T00:01:00Z","issue":1150,"event":"phase_complete","session_id":"sess1","phase":"code-pr"}
{"ts":"2026-08-05T00:02:00Z","issue":1150,"event":"phase_start","session_id":"sess1","pr":1151,"phase":"review"}
{"ts":"2026-08-05T00:03:00Z","issue":1150,"event":"phase_complete","session_id":"sess1","pr":1151,"phase":"review"}
{"ts":"2026-08-05T00:04:00Z","issue":1150,"event":"watchdog_kill","session_id":"sess1"}
EOF
    export AUTO_EVENTS_LOG="$EVENTS_FILE"
    run bash "$COLLECT_SCRIPT" --session sess1 --no-github
    [ "$status" -eq 0 ]

    route=$(echo "$output" | jq -r '.issues[0].route')
    [ "$route" = "pr" ]

    pr=$(echo "$output" | jq -r '.issues[0].pr')
    [ "$pr" = "1151" ]

    code_pr_status=$(echo "$output" | jq -r '.issues[0].phases[] | select(.name=="code-pr") | .status')
    [ "$code_pr_status" = "complete" ]

    watchdog_count=$(echo "$output" | jq -r '.issues[0].anomalies.watchdog_kill')
    [ "$watchdog_count" = "1" ]

    tokens=$(echo "$output" | jq -r '.issues[0].fact_tokens | join(",")')
    [[ "$tokens" == *"pr route"* ]]
    [[ "$tokens" == *"#1151"* ]]
    [[ "$tokens" == *"watchdog_kill"* ]]
    [[ "$tokens" != *"/auto"* ]]
}

@test "collect-run-facts: --issue filters output to a single issue" {
    EVENTS_FILE="$BATS_TEST_TMPDIR/events.jsonl"
    cat > "$EVENTS_FILE" <<'EOF'
{"ts":"2026-08-05T00:00:00Z","issue":100,"event":"phase_start","session_id":"sess1","phase":"spec"}
{"ts":"2026-08-05T00:01:00Z","issue":200,"event":"phase_start","session_id":"sess1","phase":"spec"}
EOF
    export AUTO_EVENTS_LOG="$EVENTS_FILE"
    run bash "$COLLECT_SCRIPT" --session sess1 --issue 200 --no-github
    [ "$status" -eq 0 ]
    count=$(echo "$output" | jq '.issues | length')
    [ "$count" = "1" ]
    number=$(echo "$output" | jq -r '.issues[0].number')
    [ "$number" = "200" ]
}

@test "collect-run-facts: size resolved from sub_start when size_refresh absent" {
    EVENTS_FILE="$BATS_TEST_TMPDIR/events.jsonl"
    cat > "$EVENTS_FILE" <<'EOF'
{"ts":"2026-08-05T00:00:00Z","issue":300,"event":"sub_start","session_id":"sess1","size":"M"}
{"ts":"2026-08-05T00:01:00Z","issue":300,"event":"phase_start","session_id":"sess1","phase":"code-patch"}
EOF
    export AUTO_EVENTS_LOG="$EVENTS_FILE"
    run bash "$COLLECT_SCRIPT" --session sess1 --no-github
    [ "$status" -eq 0 ]
    size=$(echo "$output" | jq -r '.issues[0].size')
    [ "$size" = "M" ]
    route=$(echo "$output" | jq -r '.issues[0].route')
    [ "$route" = "patch" ]
}

# ---------------------------------------------------------------------------
# scan-pending-ac.sh
# ---------------------------------------------------------------------------

@test "scan-pending-ac: only unchecked post-merge lines are candidates; verify-type defaults to manual" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number": 500, "body": "## Acceptance Criteria\n\n### Pre-merge\n\n- [x] pre item 1\n- [ ] pre item 2\n\n### Post-merge\n\n- [ ] plain manual condition, no tag\n- [x] already checked post item\n- [ ] <!-- verify-type: observation event=auto-run --> observation condition\n\n## Related\n"}]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCAN_SCRIPT"
    [ "$status" -eq 0 ]

    count=$(echo "$output" | jq 'length')
    [ "$count" = "2" ]

    first_idx=$(echo "$output" | jq -r '.[0].ac_index')
    [ "$first_idx" = "3" ]
    first_vtype=$(echo "$output" | jq -r '.[0].verify_type')
    [ "$first_vtype" = "manual" ]

    second_vtype=$(echo "$output" | jq -r '.[1].verify_type')
    [ "$second_vtype" = "observation" ]
}

@test "scan-pending-ac: --facts token filter excludes non-matching candidates" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number": 600, "body": "### Post-merge\n\n- [ ] condition mentioning pr route explicitly\n- [ ] unrelated condition text\n"}]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    FACTS_FILE="$BATS_TEST_TMPDIR/facts.json"
    echo '{"session_id":"s1","issues":[{"number":1,"fact_tokens":["pr route"]}]}' > "$FACTS_FILE"

    run bash "$SCAN_SCRIPT" --facts "$FACTS_FILE"
    [ "$status" -eq 0 ]
    count=$(echo "$output" | jq 'length')
    [ "$count" = "1" ]
    condition=$(echo "$output" | jq -r '.[0].condition')
    [[ "$condition" == *"pr route"* ]]
}

@test "scan-pending-ac: gh failure fails open with empty array" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCAN_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "scan-pending-ac: --max-candidates truncates and reports a stderr note" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number": 700, "body": "### Post-merge\n\n- [ ] condition one\n- [ ] condition two\n- [ ] condition three\n"}]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCAN_SCRIPT" --max-candidates 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"truncated"* ]]
    count=$(echo "$output" | grep '^\[' | jq 'length')
    [ "$count" = "1" ]
}

# ---------------------------------------------------------------------------
# apply-run-fact-match.sh — AC5's 3 paths: detect / negative / ambiguous fallback
# ---------------------------------------------------------------------------

@test "apply-run-fact-match: satisfied + L3 -> action=auto-check (detection path)" {
    AUTONOMY_TIER=L3 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict satisfied --dry-run
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "action=auto-check" ]
}

@test "apply-run-fact-match: not_satisfied + L3 -> action=none, no Recommend line (negative path)" {
    AUTONOMY_TIER=L3 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict not_satisfied --dry-run
    [ "$status" -eq 0 ]
    [ "$output" = "action=none" ]
    [[ "$output" != *"Recommend:"* ]]
}

@test "apply-run-fact-match: ambiguous + L3 -> action=advisory + Recommend line (fallback path)" {
    AUTONOMY_TIER=L3 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict ambiguous --evidence "unclear" --dry-run
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "action=advisory" ]
    [[ "${lines[1]}" == "Recommend: /verify 42"* ]]
    [[ "${lines[1]}" == *"unclear"* ]]
}

@test "apply-run-fact-match: satisfied + L1 -> action=advisory (tier gate)" {
    AUTONOMY_TIER=L1 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict satisfied --dry-run
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "action=advisory" ]
}

@test "apply-run-fact-match: unknown verdict falls back to ambiguous with stderr warning" {
    AUTONOMY_TIER=L3 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict bogus --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: unknown verdict"* ]]
    [[ "$output" == *"action=advisory"* ]]
}

@test "apply-run-fact-match: missing --issue exits 1" {
    run bash "$APPLY_SCRIPT" --ac 3 --verdict satisfied --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "apply-run-fact-match: missing --ac exits 1" {
    run bash "$APPLY_SCRIPT" --issue 42 --verdict satisfied --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "apply-run-fact-match: auto-check without --dry-run checks the checkbox and posts an audit-trail comment" {
    cat > "$MOCK_DIR/gh-issue-edit.sh" <<MOCK
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/edit-calls.log"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-issue-edit.sh"

    cat > "$MOCK_DIR/gh-issue-comment.sh" <<MOCK
#!/bin/bash
echo "\$1" >> "$BATS_TEST_TMPDIR/comment-calls.log"
cat "\$2" >> "$BATS_TEST_TMPDIR/comment-calls.log"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-issue-comment.sh"

    AUTONOMY_TIER=L3 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict satisfied --evidence "PR #1151 merged"
    [ "$status" -eq 0 ]
    [ "$output" = "action=auto-check" ]

    [ -f "$BATS_TEST_TMPDIR/edit-calls.log" ]
    grep -q "42 --checkbox 3 --check" "$BATS_TEST_TMPDIR/edit-calls.log"

    [ -f "$BATS_TEST_TMPDIR/comment-calls.log" ]
    grep -q "type=run-fact-ac-match phase=run-fact-match issue=42 ac=3 verdict=satisfied" "$BATS_TEST_TMPDIR/comment-calls.log"
    grep -q "PR #1151 merged" "$BATS_TEST_TMPDIR/comment-calls.log"
}

@test "apply-run-fact-match: dry-run performs no L0 writes even when action=auto-check" {
    cat > "$MOCK_DIR/gh-issue-edit.sh" <<MOCK
#!/bin/bash
echo "called" >> "$BATS_TEST_TMPDIR/edit-calls.log"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-issue-edit.sh"

    AUTONOMY_TIER=L3 run bash "$APPLY_SCRIPT" --issue 42 --ac 3 --verdict satisfied --dry-run
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/edit-calls.log" ]
}
