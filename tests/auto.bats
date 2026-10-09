#!/usr/bin/env bats

# Tests for skills/auto/SKILL.md structural content
# Verifies route demotion spec is present in Step 3a (Issue #616)

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"

load 'helpers/markdown-section'

# Extract Step 3a section: from "### Step 3a:" to the next heading of level 3 or higher
step3a_section() {
    md_section "$1" "### Step 3a:"
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

# Extract Step 3 section: from "### Step 3:" to the next heading of level 3 or higher (Issue #1482)
step3_section() {
    md_section "$1" "### Step 3:"
}

@test "Step 3 section has phase/verify resume branch" {
    run step3_section "$SKILL_FILE"
    [[ "$output" == *'`phase/verify` label present'* ]] || false
    [[ "$output" == *"skip all four and start from verify"* ]] || false
}

@test "Step 3 section has phase/done branch that stops without running" {
    run step3_section "$SKILL_FILE"
    [[ "$output" == *'`phase/done` label present'* ]] || false
    [[ "$output" == *"nothing to run"* ]] || false
    [[ "$output" == *"auto-checkpoint.sh delete_single"* ]] || false
}

@test "Step 3 section has phase/code, phase/review, phase/merge branch delegating to reconciler" {
    run step3_section "$SKILL_FILE"
    [[ "$output" == *"phase/code"* ]] || false
    [[ "$output" == *"phase/review"* ]] || false
    [[ "$output" == *"phase/merge"* ]] || false
    [[ "$output" == *"skip the spec dispatch"* ]] || false
    [[ "$output" == *"reconcile-phase-state.sh"* ]] || false
}

@test "Step 3 section has Resume entry points table" {
    run step3_section "$SKILL_FILE"
    [[ "$output" == *"Resume entry points"* ]] || false
    [[ "$output" == *"ROUTE=pr"* ]] || false
}

@test "Step 3 section has rules common to resume branches" {
    run step3_section "$SKILL_FILE"
    [[ "$output" == *"Step 2a takes precedence"* ]] || false
    [[ "$output" == *"EFFECTIVE_STOP_AT"* ]] || false
    [[ "$output" == *"XL route"* ]] || false
}

@test "Step 3 section keeps existing phase/ready and phase/issue branches" {
    run step3_section "$SKILL_FILE"
    [[ "$output" == *'`phase/ready` label present'* ]] || false
    [[ "$output" == *'`phase/issue` label present'* ]] || false
    [[ "$output" == *"run-spec.sh"* ]] || false
}

# Extract Step 2a section: from "### Step 2a:" to the next heading of level 3 or higher
step2a_section() {
    md_section "$1" "### Step 2a:"
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

# Extract Step 2 section: from "### Step 2:" to the next heading of level 3 or higher
step2_section() {
    md_section "$1" "### Step 2:"
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

# Extract Step 5 section: from "### Step 5:" to the next heading of level 3 or higher
step5_section() {
    md_section "$1" "### Step 5:"
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

# Tests for Skill Self-Update Propagation check comparing against origin (Issue #1206)
# Uses a real git fixture (bare origin + working repo), same pattern as tests/pre-merge-check.bats.

@test "origin comparison detects skill hash divergence that local HEAD comparison misses" {
    local origin_dir="$BATS_TEST_TMPDIR/origin-auto.git"
    local repo_dir="$BATS_TEST_TMPDIR/repo-auto"
    local clone_dir="$BATS_TEST_TMPDIR/clone-auto"

    git init --bare "$origin_dir" >/dev/null 2>&1

    git init "$repo_dir" >/dev/null 2>&1
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "Test"
    git -C "$repo_dir" remote add origin "$origin_dir"

    mkdir -p "$repo_dir/skills/x"
    echo "commit A content" > "$repo_dir/skills/x/SKILL.md"
    git -C "$repo_dir" add skills/x/SKILL.md
    git -C "$repo_dir" commit -m "commit A" >/dev/null 2>&1
    git -C "$repo_dir" branch -M main
    git -C "$repo_dir" push origin main >/dev/null 2>&1
    git -C "$origin_dir" symbolic-ref HEAD refs/heads/main
    local commit_a
    commit_a=$(git -C "$repo_dir" log -1 --format=%H -- skills/x/SKILL.md)

    # A second clone advances origin with commit B without touching repo_dir's local HEAD —
    # simulates a PR merged via `gh pr merge` while this working repo's main stays behind.
    git clone "$origin_dir" "$clone_dir" >/dev/null 2>&1
    git -C "$clone_dir" config user.email "test@example.com"
    git -C "$clone_dir" config user.name "Test"
    echo "commit B content" > "$clone_dir/skills/x/SKILL.md"
    git -C "$clone_dir" add skills/x/SKILL.md
    git -C "$clone_dir" commit -m "commit B" >/dev/null 2>&1
    git -C "$clone_dir" push origin main >/dev/null 2>&1
    local commit_b
    commit_b=$(git -C "$clone_dir" log -1 --format=%H -- skills/x/SKILL.md)

    [ "$commit_a" != "$commit_b" ]

    git -C "$repo_dir" fetch origin main >/dev/null 2>&1

    local local_head_hash
    local_head_hash=$(git -C "$repo_dir" log -1 --format=%H -- skills/x/SKILL.md)
    local origin_hash
    origin_hash=$(git -C "$repo_dir" log -1 --format=%H origin/main -- skills/x/SKILL.md)

    # Local HEAD comparison alone always reports commit A — a false "no change".
    [ "$local_head_hash" = "$commit_a" ]
    # Origin comparison correctly detects the divergent commit B.
    [ "$origin_hash" = "$commit_b" ]
    [ "$local_head_hash" != "$origin_hash" ]
}
