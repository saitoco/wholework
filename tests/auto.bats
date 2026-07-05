#!/usr/bin/env bats

# Tests for skills/auto/SKILL.md structural content
# Verifies route demotion spec is present in Step 3a (Issue #616)

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"

# Extract Step 3a section: from "### Step 3a:" to the next "### " heading
step3a_section() {
    awk '/^### Step 3a:/{found=1} found && /^### / && !/^### Step 3a:/{exit} found{print}' "$1"
}

@test "Step 3a section contains route demotion" {
    run step3a_section "$SKILL_FILE"
    [[ "$output" == *"route demotion"* ]]
}

@test "Step 3a section contains Post-spec route demotion log message" {
    run step3a_section "$SKILL_FILE"
    [[ "$output" == *"Post-spec route demotion"* ]]
}

@test "Step 3a section contains ALWAYS_PR demotion suppression" {
    run step3a_section "$SKILL_FILE"
    [[ "$output" == *"ALWAYS_PR"* ]]
}

# Extract Step 2a section: from "### Step 2a:" to the next "### " heading
step2a_section() {
    awk '/^### Step 2a:/{found=1} found && /^### / && !/^### Step 2a:/{exit} found{print}' "$1"
}

@test "Step 2a fix-cycle section exists in SKILL.md" {
    run step2a_section "$SKILL_FILE"
    [ -n "$output" ]
}

@test "Step 2a section contains fix-cycle keyword" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"fix-cycle"* ]]
}

@test "Step 2a section describes skipping issue and spec phases" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"run-issue.sh"* ]] || [[ "$output" == *"issue/spec"* ]]
    [[ "$output" == *"run-code.sh"* ]]
}

@test "Step 2a section references verify-fail marker" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"verify-fail"* ]]
}

@test "Step 2a section contains last_merge_ts merge-time cross-check" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"last_merge_ts"* ]]
}

# Tests for auto-stop-at / --stop-at support (Issue #783)

@test "SKILL.md contains stop-at keyword" {
    grep -qE "stop-at|stop_at" "$SKILL_FILE"
}

@test "SKILL.md contains auto-stop-at keyword" {
    grep -q "auto-stop-at" "$SKILL_FILE"
}

@test "SKILL.md contains EFFECTIVE_STOP_AT variable" {
    grep -q "EFFECTIVE_STOP_AT" "$SKILL_FILE"
}

# Extract Step 2 section: from "### Step 2:" to the next "### " heading
step2_section() {
    awk '/^### Step 2:/{found=1} found && /^### / && !/^### Step 2:/{exit} found{print}' "$1"
}

@test "Step 2 section describes stop-at flag parsing" {
    run step2_section "$SKILL_FILE"
    [[ "$output" == *"stop-at"* ]]
}

@test "Step 2 section lists valid stop-at enum values spec, code, review, merge" {
    run step2_section "$SKILL_FILE"
    [[ "$output" == *"spec"* ]]
    [[ "$output" == *"code"* ]]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"merge"* ]]
}

# Extract Step 5 section: from "### Step 5:" to the next "### " heading
step5_section() {
    awk '/^### Step 5:/{found=1} found && /^### / && !/^### Step 5:/{exit} found{print}' "$1"
}

@test "Step 5 section contains next-action guidance for stop-at" {
    run step5_section "$SKILL_FILE"
    [[ "$output" == *"/merge"* ]] || [[ "$output" == *"Next"* ]]
}

@test "Step 5 section contains STOPPED_AT variable reference" {
    run step5_section "$SKILL_FILE"
    [[ "$output" == *"STOPPED_AT"* ]]
}

# Extract Notable judgment sub-step (L3 auto-retrospective step 3): from
# "3. **Notable judgment**" to the next numbered sub-step heading (Issue #913)
notable_judgment_section() {
    awk '/^3\. \*\*Notable judgment\*\*/{found=1} found && /^4\. \*\*/{exit} found{print}' "$1"
}

@test "Notable judgment section uses jq -sc aggregation, not a raw events dump" {
    run notable_judgment_section "$SKILL_FILE"
    [[ "$output" == *"jq -sc"* ]]
    [[ "$output" != *"jq -c 'select(.session_id"* ]]
}

@test "Notable judgment section references all four aggregated count fields" {
    run notable_judgment_section "$SKILL_FILE"
    [[ "$output" == *"recovery_tier2_3"* ]]
    [[ "$output" == *"watchdog_kill"* ]]
    [[ "$output" == *"concurrent_commit"* ]]
    [[ "$output" == *"commit_event"* ]]
}

@test "Notable judgment section no longer references the non-existent watchdog_timeout event" {
    run notable_judgment_section "$SKILL_FILE"
    [[ "$output" != *"watchdog_timeout"* ]]
}

# Extract the jq aggregation command embedded in the Notable judgment sub-step
# (first fenced ```bash block only — later blocks in the same sub-step cover the
# "commit events.jsonl and stop" git sequence, not the aggregation itself)
notable_judgment_jq_command() {
    awk '/^3\. \*\*Notable judgment\*\*/{found=1} found && /^4\. \*\*/{exit} found{print}' "$1" \
        | awk '/```bash/{p=1; next} p && /```/{exit} p'
}

@test "Notable judgment jq aggregation produces zeroed counts on an empty events file" {
    empty_events="$BATS_TEST_TMPDIR/events-empty.jsonl"
    : > "$empty_events"
    cmd=$(notable_judgment_jq_command "$SKILL_FILE" | sed "s#\"\$SESSION_DIR/events.jsonl\"#'$empty_events'#")
    run bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = '{"recovery_tier2_3":0,"watchdog_kill":0,"concurrent_commit":0,"commit_event":0}' ]
}

@test "Notable judgment jq aggregation counts matching events and ignores unrelated ones" {
    fixture_events="$BATS_TEST_TMPDIR/events-fixture.jsonl"
    cat > "$fixture_events" <<'EOF'
{"event":"recovery","tier":"1","result":"recovered"}
{"event":"recovery","tier":"2","result":"recovered"}
{"event":"recovery","tier":"3","result":"recovered"}
{"event":"watchdog_kill"}
{"event":"watchdog_kill"}
{"event":"concurrent_commit_detected"}
{"event":"phase_start","phase":"code"}
EOF
    cmd=$(notable_judgment_jq_command "$SKILL_FILE" | sed "s#\"\$SESSION_DIR/events.jsonl\"#'$fixture_events'#")
    run bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = '{"recovery_tier2_3":2,"watchdog_kill":2,"concurrent_commit":1,"commit_event":0}' ]
}
