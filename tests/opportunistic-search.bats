#!/usr/bin/env bats

# Tests for opportunistic-search.sh
# Mock gh issue list / gh issue view

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/opportunistic-search.sh"

setup() {
    cd "$PROJECT_ROOT"

    export MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Default gh mock (can be overridden per test)
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# gh issue list --label "phase/verify" --state closed --search "..." --json number --limit 300
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    printf '%s\n' "$@" >> "$MOCK_DIR/gh-list-args.txt"
    echo "${MOCK_ISSUE_LIST:-[]}"
    exit 0
fi
# gh issue view N --json body -q .body
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    ISSUE_NUM="$3"
    VARNAME="MOCK_ISSUE_BODY_${ISSUE_NUM}"
    echo "${!VARNAME}"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    # collect-run-facts.sh mock (used by when gate tests via WHOLEWORK_SCRIPT_DIR)
    cat > "$MOCK_DIR/collect-run-facts.sh" << 'MOCK_EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$MOCK_DIR/collect-run-facts-args.txt"
echo "${MOCK_RUN_FACTS:-}"
MOCK_EOF
    chmod +x "$MOCK_DIR/collect-run-facts.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: unknown option" {
    run bash "$SCRIPT" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "error: multiple skill names" {
    run bash "$SCRIPT" /issue /spec
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "dry-run: returns the same non-empty result as without --dry-run" {
    export MOCK_ISSUE_LIST='[{"number": 700}]'
    export MOCK_ISSUE_BODY_700='- [ ] /issue skill creates Issue after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    without_dry_run="$output"

    run bash "$SCRIPT" /issue --dry-run
    [ "$status" -eq 0 ]
    with_dry_run="$output"

    [ "$with_dry_run" = "$without_dry_run" ]
    echo "$with_dry_run" | jq -e 'length == 1' > /dev/null
    echo "$with_dry_run" | jq -e '.[0].number == 700' > /dev/null
}

@test "dry-run: works with --dry-run before skill name" {
    export MOCK_ISSUE_LIST='[{"number": 701}]'
    export MOCK_ISSUE_BODY_701='- [ ] /spec skill creates file after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" --dry-run /spec
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 701' > /dev/null
}

@test "success: no issues found returns empty array" {
    export MOCK_ISSUE_LIST="[]"
    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "population limit: reaching --limit emits a truncation warning on stderr" {
    export MOCK_ISSUE_LIST="$(jq -n '[range(1;301) | {number: .}]')"
    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached --limit 300"* ]]
}

@test "search filter: --event mode requests the observation search text" {
    export MOCK_ISSUE_LIST="[]"
    run bash "$SCRIPT" --event auto-run
    [ "$status" -eq 0 ]
    grep -q "verify-type: observation in:body" "$MOCK_DIR/gh-list-args.txt"
}

@test "search filter: skill mode requests the opportunistic search text" {
    export MOCK_ISSUE_LIST="[]"
    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    grep -q "verify-type: opportunistic in:body" "$MOCK_DIR/gh-list-args.txt"
}

@test "success: issue with matching condition is returned" {
    export MOCK_ISSUE_LIST='[{"number": 100}]'
    export MOCK_ISSUE_BODY_100='- [ ] /issue skill creates Issue after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    result="$output"
    echo "$result" | jq -e 'length == 1' > /dev/null
    echo "$result" | jq -e '.[0].number == 100' > /dev/null
    [[ "$(echo "$result" | jq -r '.[0].condition')" == *"/issue"* ]]
}

@test "filter: checked condition is excluded" {
    export MOCK_ISSUE_LIST='[{"number": 101}]'
    export MOCK_ISSUE_BODY_101='- [x] /issue skill creates Issue after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "filter: skill name mismatch is excluded" {
    export MOCK_ISSUE_LIST='[{"number": 102}]'
    export MOCK_ISSUE_BODY_102='- [ ] /spec skill creates Spec after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "success: multiple conditions from multiple issues" {
    export MOCK_ISSUE_LIST='[{"number": 200},{"number": 201}]'
    export MOCK_ISSUE_BODY_200='- [ ] /spec skill creates file after execution <!-- verify-type: opportunistic -->'
    export MOCK_ISSUE_BODY_201='- [ ] /spec skill creates file after execution <!-- verify-type: opportunistic -->
- [x] /spec skill updates list after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /spec
    [ "$status" -eq 0 ]
    result="$output"
    echo "$result" | jq -e 'length == 2' > /dev/null
}

@test "output: condition text strips checkbox markup and HTML comments" {
    export MOCK_ISSUE_LIST='[{"number": 300}]'
    export MOCK_ISSUE_BODY_300='- [ ] /code skill can be verified after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /code
    [ "$status" -eq 0 ]
    condition="$(echo "$output" | jq -r '.[0].condition')"
    [[ "$condition" != *"- [ ]"* ]]
    [[ "$condition" != *"<!-- verify-type:"* ]]
    [[ "$condition" == *"/code skill can be verified after execution"* ]]
}

@test "event filter: --event matches observation conditions with matching event" {
    export MOCK_ISSUE_LIST='[{"number": 400}]'
    export MOCK_ISSUE_BODY_400='- [ ] Next /review --full auto-checks this condition <!-- verify-type: observation event=pr-review-full -->'

    run bash "$SCRIPT" --event pr-review-full
    [ "$status" -eq 0 ]
    result="$output"
    echo "$result" | jq -e 'length == 1' > /dev/null
    echo "$result" | jq -e '.[0].number == 400' > /dev/null
}

@test "event filter: --event excludes opportunistic conditions" {
    export MOCK_ISSUE_LIST='[{"number": 401}]'
    export MOCK_ISSUE_BODY_401='- [ ] /review skill creates review after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" --event pr-review-full
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "event filter: --event excludes non-matching event name" {
    export MOCK_ISSUE_LIST='[{"number": 402}]'
    export MOCK_ISSUE_BODY_402='- [ ] Next /auto auto-checks this condition <!-- verify-type: observation event=auto-run -->'

    run bash "$SCRIPT" --event pr-review-full
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "event filter: --event with dry-run returns the same non-empty result as without --dry-run" {
    export MOCK_ISSUE_LIST='[{"number": 702}]'
    export MOCK_ISSUE_BODY_702='- [ ] Next /review --full auto-checks this condition <!-- verify-type: observation event=pr-review-full -->'

    run bash "$SCRIPT" --event pr-review-full
    [ "$status" -eq 0 ]
    without_dry_run="$output"

    run bash "$SCRIPT" --event pr-review-full --dry-run
    [ "$status" -eq 0 ]
    with_dry_run="$output"

    [ "$with_dry_run" = "$without_dry_run" ]
    echo "$with_dry_run" | jq -e 'length == 1' > /dev/null
    echo "$with_dry_run" | jq -e '.[0].number == 702' > /dev/null
}

@test "context gate: keyword found in context file includes the issue" {
    export MOCK_ISSUE_LIST='[{"number": 500}]'
    export MOCK_ISSUE_BODY_500='- [ ] Verify enum coverage <!-- verify-type: observation event=pr-review-full keyword=enum -->'
    echo "This spec defines an enum for status codes." > "$BATS_TEST_TMPDIR/context-has-enum.md"

    run bash "$SCRIPT" --event pr-review-full --context-file "$BATS_TEST_TMPDIR/context-has-enum.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 500' > /dev/null
}

@test "context gate: keyword absent from context file excludes the issue" {
    export MOCK_ISSUE_LIST='[{"number": 501}]'
    export MOCK_ISSUE_BODY_501='- [ ] Verify enum coverage <!-- verify-type: observation event=pr-review-full keyword=enum -->'
    echo "This spec covers formatting only." > "$BATS_TEST_TMPDIR/context-no-enum.md"

    run bash "$SCRIPT" --event pr-review-full --context-file "$BATS_TEST_TMPDIR/context-no-enum.md"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "context gate: AC without keyword= matches unconditionally even with --context-file" {
    export MOCK_ISSUE_LIST='[{"number": 502}]'
    export MOCK_ISSUE_BODY_502='- [ ] Next /review --full auto-checks this condition <!-- verify-type: observation event=pr-review-full -->'
    echo "Irrelevant content." > "$BATS_TEST_TMPDIR/context-any.md"

    run bash "$SCRIPT" --event pr-review-full --context-file "$BATS_TEST_TMPDIR/context-any.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 502' > /dev/null
}

@test "context gate: keyword= present but no --context-file matches unconditionally" {
    export MOCK_ISSUE_LIST='[{"number": 503}]'
    export MOCK_ISSUE_BODY_503='- [ ] Verify enum coverage <!-- verify-type: observation event=pr-review-full keyword=enum -->'

    run bash "$SCRIPT" --event pr-review-full
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 503' > /dev/null
}

@test "context gate: nonexistent --context-file path disables gate with a warning" {
    export MOCK_ISSUE_LIST='[{"number": 504}]'
    export MOCK_ISSUE_BODY_504='- [ ] Verify enum coverage <!-- verify-type: observation event=pr-review-full keyword=enum -->'

    run bash "$SCRIPT" --event pr-review-full --context-file "$BATS_TEST_TMPDIR/does-not-exist.md" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning:"*"does-not-exist.md"*"not found"* ]]
    echo "$output" | grep -v "^Warning" | jq -e 'length == 1' > /dev/null
    echo "$output" | grep -v "^Warning" | jq -e '.[0].number == 504' > /dev/null
}

@test "context gate: keyword= with no space before --> is extracted without trailing dashes" {
    export MOCK_ISSUE_LIST='[{"number": 505}]'
    export MOCK_ISSUE_BODY_505='- [ ] Verify enum coverage <!-- verify-type: observation event=pr-review-full keyword=enum--> '
    echo "This spec defines an enum for status codes." > "$BATS_TEST_TMPDIR/context-has-enum-2.md"

    run bash "$SCRIPT" --event pr-review-full --context-file "$BATS_TEST_TMPDIR/context-has-enum-2.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 505' > /dev/null
}

@test "config gate: enabled config key includes the issue" {
    export MOCK_ISSUE_LIST='[{"number": 600}]'
    export MOCK_ISSUE_BODY_600='- [ ] Verify demotion is suppressed <!-- verify-type: observation event=auto-run config=some-flag -->'
    echo "some-flag: true" > "$BATS_TEST_TMPDIR/config-enabled.yml"
    export WHOLEWORK_CONFIG_PATH="$BATS_TEST_TMPDIR/config-enabled.yml"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_CONFIG_PATH
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 600' > /dev/null
}

@test "config gate: disabled config key excludes the issue" {
    export MOCK_ISSUE_LIST='[{"number": 601}]'
    export MOCK_ISSUE_BODY_601='- [ ] Verify demotion is suppressed <!-- verify-type: observation event=auto-run config=some-flag -->'
    export WHOLEWORK_CONFIG_PATH=/dev/null

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_CONFIG_PATH
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "config gate: AC without config= matches unconditionally" {
    export MOCK_ISSUE_LIST='[{"number": 602}]'
    export MOCK_ISSUE_BODY_602='- [ ] Verify demotion is suppressed <!-- verify-type: observation event=auto-run -->'
    export WHOLEWORK_CONFIG_PATH=/dev/null

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_CONFIG_PATH
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 602' > /dev/null
}

@test "when gate: run facts route matches includes the issue" {
    export MOCK_ISSUE_LIST='[{"number": 700}]'
    export MOCK_ISSUE_BODY_700='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":700,"route":"operate","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 700' > /dev/null
}

@test "when gate: run facts route mismatch excludes the issue" {
    export MOCK_ISSUE_LIST='[{"number": 701}]'
    export MOCK_ISSUE_BODY_701='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":701,"route":"pr","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "when gate: AC without when= matches unconditionally" {
    export MOCK_ISSUE_LIST='[{"number": 702}]'
    export MOCK_ISSUE_BODY_702='- [ ] Next /auto auto-checks this condition <!-- verify-type: observation event=auto-run -->'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 702' > /dev/null
}

@test "when gate: undeterminable run facts fail open with a warning" {
    export MOCK_ISSUE_LIST='[{"number": 703}]'
    export MOCK_ISSUE_BODY_703='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    unset MOCK_RUN_FACTS
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run 2>&1
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning:"*"run facts"* ]]
    echo "$output" | grep -v "^Warning" | jq -e 'length == 1' > /dev/null
    echo "$output" | grep -v "^Warning" | jq -e '.[0].number == 703' > /dev/null
}

@test "when gate: unknown axis fails open with a warning" {
    export MOCK_ISSUE_LIST='[{"number": 704}]'
    export MOCK_ISSUE_BODY_704='- [ ] pr-state observed <!-- verify-type: observation event=auto-run when=pr-state:open -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":704,"route":"pr","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run 2>&1
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: unknown when= axis 'pr-state'"* ]]
    echo "$output" | grep -v "^Warning" | jq -e 'length == 1' > /dev/null
    echo "$output" | grep -v "^Warning" | jq -e '.[0].number == 704' > /dev/null
}

@test "when gate: comma-separated AND excludes when one clause fails" {
    export MOCK_ISSUE_LIST='[{"number": 705}]'
    export MOCK_ISSUE_BODY_705='- [ ] batch recovery observed <!-- verify-type: observation event=auto-run when=mode:batch,recovery-tier:2 -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"batch","issues":[{"number":705,"route":"pr","recovery_tiers":[1]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "when gate: --facts-file explicit designation bypasses collect-run-facts.sh" {
    export MOCK_ISSUE_LIST='[{"number": 706}]'
    export MOCK_ISSUE_BODY_706='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    # MOCK_RUN_FACTS deliberately mismatches route:operate (facts.json below is the only source
    # that matches). If --facts-file were silently ignored and collect-run-facts.sh's mock
    # consulted instead, the result would be [] instead of a match on #706 — making this
    # assertion decisive proof of bypass rather than just "a result was returned".
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":706,"route":"pr","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    echo '{"session_id":"s1","mode":"single","issues":[{"number":706,"route":"operate","recovery_tiers":[]}]}' > "$BATS_TEST_TMPDIR/facts.json"

    run bash "$SCRIPT" --event auto-run --facts-file "$BATS_TEST_TMPDIR/facts.json"
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 706' > /dev/null
}

@test "when gate: --session is forwarded to collect-run-facts.sh --session" {
    export MOCK_ISSUE_LIST='[{"number": 710}]'
    export MOCK_ISSUE_BODY_710='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":710,"route":"operate","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run --session "12345-1786000000"
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    grep -q -- "--session" "$MOCK_DIR/collect-run-facts-args.txt"
    grep -q -- "12345-1786000000" "$MOCK_DIR/collect-run-facts-args.txt"
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 710' > /dev/null
}

@test "when gate: --facts-file takes priority over --session when both are given" {
    export MOCK_ISSUE_LIST='[{"number": 711}]'
    export MOCK_ISSUE_BODY_711='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    # MOCK_RUN_FACTS deliberately mismatches route:operate — if --session were consulted
    # instead of --facts-file, the result would be [] instead of a match on #711.
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":711,"route":"pr","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    echo '{"session_id":"s1","mode":"single","issues":[{"number":711,"route":"operate","recovery_tiers":[]}]}' > "$BATS_TEST_TMPDIR/facts.json"

    run bash "$SCRIPT" --event auto-run --facts-file "$BATS_TEST_TMPDIR/facts.json" --session "12345-1786000000"
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [ ! -f "$MOCK_DIR/collect-run-facts-args.txt" ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 711' > /dev/null
}

@test "when gate: no --session and no --facts-file calls collect-run-facts.sh with no arguments" {
    export MOCK_ISSUE_LIST='[{"number": 712}]'
    export MOCK_ISSUE_BODY_712='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":712,"route":"operate","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [ -f "$MOCK_DIR/collect-run-facts-args.txt" ]
    ! grep -q -- "--session\|--facts-file" "$MOCK_DIR/collect-run-facts-args.txt"
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 712' > /dev/null
}

@test "when gate: when= appearing in AC prose text (outside the tag) does not corrupt gate matching" {
    export MOCK_ISSUE_LIST='[{"number": 707}]'
    export MOCK_ISSUE_BODY_707='- [ ] AC text that quotes when=route:operate as an example <!-- verify-type: observation event=auto-run when=route:operate -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":707,"route":"operate","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 707' > /dev/null
}

@test "when gate: glob metacharacters in a when= value are treated as a literal (no pathname expansion)" {
    export MOCK_ISSUE_LIST='[{"number": 708}]'
    export MOCK_ISSUE_BODY_708='- [ ] wildcard axis value observed <!-- verify-type: observation event=auto-run when=route:* -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[{"number":708,"route":"operate","recovery_tiers":[]}]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run 2>&1
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    # A literal "*" never equals the facts' route value "operate", so the clause fails and the
    # issue is excluded — it must NOT expand to the CWD's file list (which would emit multiple
    # "malformed when= clause" warnings, one per matched filename).
    [ "$(echo "$output" | grep -c "malformed when= clause")" -le 1 ]
    [ "$(echo "$output" | grep -v "^Warning")" = "[]" ]
}

@test "when gate: mode resolved with empty issues fails open on the route axis instead of silently excluding" {
    export MOCK_ISSUE_LIST='[{"number": 709}]'
    export MOCK_ISSUE_BODY_709='- [ ] operate route observed <!-- verify-type: observation event=auto-run when=route:operate -->'
    export MOCK_RUN_FACTS='{"session_id":"s1","mode":"single","issues":[]}'
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    run bash "$SCRIPT" --event auto-run 2>&1
    unset WHOLEWORK_SCRIPT_DIR
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning:"*"no per-issue context"* ]]
    echo "$output" | grep -v "^Warning" | jq -e 'length == 1' > /dev/null
    echo "$output" | grep -v "^Warning" | jq -e '.[0].number == 709' > /dev/null
}

@test "session=next declaration does not affect event= dispatch matching" {
    export MOCK_ISSUE_LIST='[{"number": 603}]'
    export MOCK_ISSUE_BODY_603='- [ ] Next-session skill self-update observed <!-- verify-type: observation event=auto-run session=next -->'

    run bash "$SCRIPT" --event auto-run
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1' > /dev/null
    echo "$output" | jq -e '.[0].number == 603' > /dev/null
}

@test "event filter: unknown event emits warning and falls back" {
    export MOCK_ISSUE_LIST='[{"number": 403}]'
    export MOCK_ISSUE_BODY_403='- [ ] /review skill creates review after execution <!-- verify-type: opportunistic -->'

    # Merge stderr into stdout so the warning is captured in $output
    run bash "$SCRIPT" --event unknown-event-xyz /review 2>&1
    [ "$status" -eq 0 ]
    # Warning must be emitted for unknown event
    [[ "$output" == *"Warning: unknown event 'unknown-event-xyz'"* ]]
    # Fallback to opportunistic mode finds the matching issue
    echo "$output" | grep -v "^Warning" | jq -e 'length == 1' > /dev/null
    echo "$output" | grep -v "^Warning" | jq -e '.[0].number == 403' > /dev/null
}
