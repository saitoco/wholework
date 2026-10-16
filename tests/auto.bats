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
# "3. **Notable judgment**" to the next numbered sub-step heading (Issue #913).
# A numbered list item is not a Markdown heading, so md_section does not apply. Like
# md_section, exits 1 when the start line is not found (Issue #1517).
notable_judgment_section() {
    awk '/^3\. \*\*Notable judgment\*\*/{found=1} found && /^4\. \*\*/{exit} found{print} END{if (!found) exit 1}' "$1"
}

@test "Notable judgment section uses jq -sc aggregation, not a raw events dump" {
    # Plain assignment (not run) so a missing section fails the test (Issue #1517)
    section="$(notable_judgment_section "$SKILL_FILE")"
    [[ "$section" == *"jq -sc"* ]] || false
    [[ "$section" != *"jq -c 'select(.session_id"* ]] || false
}

@test "Notable judgment section references all four aggregated count fields" {
    run notable_judgment_section "$SKILL_FILE"
    [[ "$output" == *"recovery_tier2_3"* ]]
    [[ "$output" == *"watchdog_kill"* ]]
    [[ "$output" == *"concurrent_commit"* ]]
    [[ "$output" == *"commit_event"* ]]
}

@test "Notable judgment section no longer references the non-existent watchdog_timeout event" {
    # Plain assignment (not run) so a missing section fails the test (Issue #1517)
    section="$(notable_judgment_section "$SKILL_FILE")"
    [[ "$section" != *"watchdog_timeout"* ]] || false
}

@test "Notable judgment section helper returns status 1 with empty output when the start line is missing" {
    cat > "$BATS_TEST_TMPDIR/doc.md" <<'EOF'
3. **Notable judgement** (renamed)
   - body
4. **Fetch the Metrics section**
EOF
    run notable_judgment_section "$BATS_TEST_TMPDIR/doc.md"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# Extract the jq aggregation command embedded in the Notable judgment sub-step
# (first fenced ```bash block only — later blocks in the same sub-step cover the
# "commit events.jsonl and stop" git sequence, not the aggregation itself).
# Fails with notable_judgment_section's status when the sub-step is not found; the section
# is captured first because a pipeline would report only the second awk's status (Issue #1517).
notable_judgment_jq_command() {
    local section
    section="$(notable_judgment_section "$1")" || return
    printf '%s\n' "$section" | awk '/```bash/{p=1; next} p && /```/{exit} p'
}

@test "Notable judgment jq command helper returns status 1 with empty output when the start line is missing" {
    cat > "$BATS_TEST_TMPDIR/doc.md" <<'EOF'
3. **Notable judgement** (renamed)
   - body
4. **Fetch the Metrics section**
EOF
    run notable_judgment_jq_command "$BATS_TEST_TMPDIR/doc.md"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
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

# Tests for the batch route implementation-commit count in the Notable judgment sub-step (Issue #1533).
# The count must cover only the implementation commits of the batch target Issues, not every commit of the session.

# Extract the commit-count command embedded in the Notable judgment sub-step: the fenced bash block
# that contains "rev-list --count". The first bash block of the sub-step is the jq aggregation, so the
# block is selected by content, not by position. Exits 1 when the sub-step or the block is missing.
notable_judgment_commit_count_command() {
    local section
    section="$(notable_judgment_section "$1")" || return
    printf '%s\n' "$section" | awk '
        /```bash/ { inblk = 1; blk = ""; next }
        inblk && /```/ { inblk = 0; if (blk ~ /rev-list --count/) { printf "%s", blk; found = 1; exit } next }
        inblk { blk = blk $0 "\n" }
        END { if (!found) exit 1 }
    '
}

# Create one empty commit with a fixed committer date: batch_session_commit REPO DATE SUBJECT [BODY].
batch_session_commit() {
    local repo="$1" date="$2" subject="$3" body="${4:-}"
    if [ -n "$body" ]; then
        GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
            git -C "$repo" commit -q --allow-empty -m "$subject" -m "$body"
    else
        GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
            git -C "$repo" commit -q --allow-empty -m "$subject"
    fi
}

# Build a repo whose history mimics one /auto batch session with target Issues #1 and #2.
# Commits are created oldest first with increasing dates: `git rev-list --since` stops walking at the
# first commit older than the cutoff, so the out-of-window commit has to be the oldest one.
batch_session_repo() {
    local repo="$1"
    git init -q "$repo"
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    git -C "$repo" config commit.gpgsign false
    batch_session_commit "$repo" "2026-01-01T00:00:00Z" "chore: old work before the session (closes #1)"
    batch_session_commit "$repo" "2026-01-02T00:00:01Z" "Add design for issue #1"
    batch_session_commit "$repo" "2026-01-02T00:00:02Z" "chore: do the thing (closes #1)"
    batch_session_commit "$repo" "2026-01-02T00:00:03Z" "Add code retrospective for issue #1"
    batch_session_commit "$repo" "2026-01-02T00:00:04Z" "Issue #2: Do other thing (#77)" "* feat: x (#2)"
    batch_session_commit "$repo" "2026-01-02T00:00:05Z" "Add merge phase handoff for issue #2"
    batch_session_commit "$repo" "2026-01-02T00:00:06Z" "Add consumed comments fallback for issue #200 (verify phase)"
    batch_session_commit "$repo" "2026-01-02T00:00:07Z" "fix: unrelated prefix traps (closes #10)" "closes #20 and closes #123"
    batch_session_commit "$repo" "2026-01-02T00:00:08Z" "docs: explain closes #N magic" "Explains the closes keyword."
    batch_session_commit "$repo" "2026-01-02T00:00:09Z" "Merge pull request #78 from o/branch" "Issue #1: Do thing via merge commit"
    batch_session_commit "$repo" "2026-01-02T00:00:10Z" "feat: uppercase keyword in body" "Closes #2"
    batch_session_commit "$repo" "2026-01-02T00:00:11Z" "Issue #1: both patterns at once (closes #1)"
}

@test "Notable judgment batch route counts only implementation commits of the target Issues (Issue #1533)" {
    # Plain assignment (not run) so a missing sub-step fails the test (Issue #1517)
    section="$(notable_judgment_section "$SKILL_FILE")"
    [[ "$section" == *'closes #N'* ]] || false
    [[ "$section" == *'BATCH_LIST'* ]] || false
    [[ "$section" == *'rev-list --count'* ]] || false
    [[ "$section" == *'Add consumed comments fallback for issue'* ]] || false
    [[ "$section" == *'Add code retrospective for issue'* ]] || false
    [[ "$section" == *'Add merge phase handoff for issue'* ]] || false
    # The fallback that counted every commit since the session start must be gone
    [[ "$section" != *'git log --oneline --since="$session_start"'* ]] || false
}

@test "Notable judgment commit count counts implementation commits of the target Issues and excludes the rest (Issue #1533)" {
    local repo="$BATS_TEST_TMPDIR/batch-session"
    batch_session_repo "$repo"
    local cmd
    cmd="$(notable_judgment_commit_count_command "$SKILL_FILE")" || false

    cd "$repo"
    run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="1|2" bash -c "$cmd"
    [ "$status" -eq 0 ]
    # Counted: patch implementation (closes #1), squash merge (Issue #2:), merge-commit body line (Issue #1:),
    # uppercase "Closes #2" in a body, and a commit matching both patterns (counted once) = 5.
    # Excluded: the out-of-window commit, Spec phase records, a Consumed Comments fallback, prefix traps
    # (closes #10 / #20 / #123) and a prose mention of "closes #N".
    [ "$output" = "5" ]

    # Control: the old whole-session count over the same history is larger, so the fixture does hold
    # mechanical commits that the new count has to exclude.
    local whole
    whole="$(git rev-list --count HEAD --since="2026-01-02T00:00:00Z")"
    [ "$whole" -gt "$output" ]
}

@test "Notable judgment commit count scopes to the given target Issues only (Issue #1533)" {
    local repo="$BATS_TEST_TMPDIR/batch-session"
    batch_session_repo "$repo"
    local cmd
    cmd="$(notable_judgment_commit_count_command "$SKILL_FILE")" || false

    cd "$repo"
    # Issue #2 only: the squash merge and the uppercase "Closes #2"; "closes #20" must not match #2.
    run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="2" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
    # Issue #1 only: the patch implementation, the merge-commit body line and the both-patterns commit.
    run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="1" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "Notable judgment commit count returns 0 for an empty target list or an empty session start (Issue #1533)" {
    local repo="$BATS_TEST_TMPDIR/batch-session"
    batch_session_repo "$repo"
    local cmd
    cmd="$(notable_judgment_commit_count_command "$SKILL_FILE")" || false

    cd "$repo"
    run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    run env session_start="" BATCH_ISSUES_RE="1|2" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    # Control: without the guard, the empty alternation would count the commit that only mentions "closes #N" in prose.
    local unguarded
    unguarded="$(git rev-list --count HEAD --since="2026-01-02T00:00:00Z" -E -i --grep='closes #()([^0-9]|$)')"
    [ "$unguarded" -ge 1 ]
}

# Tests for the batch route Verify FAIL condition in the Notable judgment sub-step (Issue #1535).
# The condition must count only Issues on which /verify actually failed (a type=verify-fail marker posted
# during the session) or left an auto condition unresolved, not every Issue waiting in phase/verify.

# Extract the Verify FAIL check command embedded in the Notable judgment sub-step: the fenced bash block
# that contains "gh issue view". The first bash block of the sub-step is the jq aggregation, so the block
# is selected by content, not by position. Exits 1 when the sub-step or the block is missing.
notable_judgment_verify_fail_command() {
    local section
    section="$(notable_judgment_section "$1")" || return
    printf '%s\n' "$section" | awk '
        /```bash/ { inblk = 1; blk = ""; next }
        inblk && /```/ { inblk = 0; if (blk ~ /gh issue view/) { printf "%s", blk; found = 1; exit } next }
        inblk { blk = blk $0 "\n" }
        END { if (!found) exit 1 }
    '
}

# Install a mock gh that serves $VF_DIR/issue-<N>.json for "gh issue view <N> ..." and logs every requested
# number to $VF_DIR/calls.log. A number without a fixture file makes the mock fail, like an unreadable Issue.
verify_fail_mock_gh() {
    local dir="$1"
    mkdir -p "$dir/bin"
    cat > "$dir/bin/gh" <<'MOCK'
#!/bin/bash
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    echo "$3" >> "$VF_DIR/calls.log"
    [ -f "$VF_DIR/issue-$3.json" ] || exit 1
    cat "$VF_DIR/issue-$3.json"
    exit 0
fi
exit 1
MOCK
    chmod +x "$dir/bin/gh"
}

# Write one "gh issue view --json labels,body,comments" fixture: verify_fail_fixture DIR NUMBER LABELS_JSON BODY COMMENTS_JSON.
verify_fail_fixture() {
    jq -n --argjson labels "$3" --arg body "$4" --argjson comments "$5" \
        '{labels: $labels, body: $body, comments: $comments}' > "$1/issue-$2.json"
}

# One Issue comment whose first line is the /verify FAIL marker: verify_fail_marker_comment CREATED_AT [EXTRA_ATTRS].
verify_fail_marker_comment() {
    jq -n --arg t "$1" --arg extra "${2:-}" \
        '{createdAt: $t, body: ("<!-- wholework-event: type=verify-fail phase=verify issue=1 iteration=1" + $extra + " -->\n## /verify FAIL\n")}'
}

@test "Notable judgment batch route Verify FAIL requires a session marker or an unresolved auto condition (Issue #1535)" {
    # Plain assignment (not run) so a missing sub-step fails the test (Issue #1517)
    section="$(notable_judgment_section "$SKILL_FILE")"
    [[ "$section" == *'type=verify-fail'* ]] || false
    [[ "$section" == *'session_start'* ]] || false
    [[ "$section" == *'BATCH_LIST'* ]] || false
    [[ "$section" == *'Step 11 (b)'* ]] || false
    [[ "$section" == *'MAX_ITERATIONS_REACHED'* ]] || false
    [[ "$section" == *'`observation`, `opportunistic`, or `manual`'* ]] || false
    # The bare label check that counted every Issue waiting in phase/verify must be gone
    [[ "$section" != *'unchecked `- [ ]` at batch end'* ]] || false
}

@test "Notable judgment Verify FAIL check counts a session marker or an unresolved auto condition and skips waiting Issues (Issue #1535)" {
    local dir="$BATS_TEST_TMPDIR/vf"
    mkdir -p "$dir"
    verify_fail_mock_gh "$dir"
    local cmd
    cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

    local L_VERIFY='[{"name":"phase/verify"}]' L_DONE='[{"name":"phase/done"}]' L_CODE='[{"name":"phase/code"}]' NOC='[]'
    local OBS='- [ ] waits for the next run <!-- verify-type: observation event=auto-run session=next -->'
    local MARK_AFTER MARK_BEFORE QUOTE_INLINE QUOTE_FENCE QUOTE_LATER
    MARK_AFTER="$(verify_fail_marker_comment 2026-01-02T01:00:00Z)"
    MARK_BEFORE="$(verify_fail_marker_comment 2025-12-31T23:59:59Z)"
    QUOTE_INLINE="$(jq -n '{createdAt: "2026-01-02T02:00:00Z", body: "Design notes: the `<!-- wholework-event: type=verify-fail phase=verify issue=1 -->` marker is posted on FAIL."}')"
    QUOTE_FENCE="$(jq -n '{createdAt: "2026-01-02T02:00:01Z", body: "Quoted sample:\n\n```\n<!-- wholework-event: type=verify-fail phase=verify issue=1 iteration=1 -->\n```\n"}')"
    QUOTE_LATER="$(jq -n '{createdAt: "2026-01-02T02:00:02Z", body: "## Design Complete\n<!-- wholework-event: type=verify-fail phase=verify issue=1 iteration=1 -->\n"}')"

    # 11: a real FAIL: reopened (no phase label), marker posted after the session start
    verify_fail_fixture "$dir" 11 "$NOC" $'### Post-merge\n\n'"$OBS"$'\n' "[$MARK_AFTER]"
    # 12: waiting for an observation condition that has no verify command
    verify_fail_fixture "$dir" 12 "$L_VERIFY" $'### Post-merge\n\n'"$OBS"$'\n' "$NOC"
    # 13: waiting for an observation condition that also carries a verify command (rubric form)
    verify_fail_fixture "$dir" 13 "$L_VERIFY" $'### Post-merge\n\n- [ ] waits <!-- verify-type: observation event=auto-run --> <!-- verify: rubric "x" -->\n' "$NOC"
    # 14: an auto condition left unchecked (UNCERTAIN) next to a manual one
    verify_fail_fixture "$dir" 14 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_contains "a.md" "b" --> an auto condition\n- [ ] a manual one <!-- verify-type: manual -->\n' "$NOC"
    # 15: a marker from before the session start, Issue done and fully checked
    verify_fail_fixture "$dir" 15 "$L_DONE" $'### Post-merge\n\n- [x] <!-- verify: file_exists "a" --> done\n' "[$MARK_BEFORE]"
    # 16: the marker is only quoted (inline code, code fence, not the first line), never posted
    verify_fail_fixture "$dir" 16 "$L_DONE" $'### Post-merge\n\n- [x] ok\n' "[$QUOTE_INLINE,$QUOTE_FENCE,$QUOTE_LATER]"
    # 17: a sample checkbox with a verify command inside a code fence
    verify_fail_fixture "$dir" 17 "$L_VERIFY" $'### Post-merge\n\n- [ ] a manual one <!-- verify-type: manual -->\n\n```markdown\n- [ ] <!-- verify: file_exists "a" --> sample line\n```\n' "$NOC"
    # 18: an unchecked auto condition, but the Issue never reached phase/verify
    verify_fail_fixture "$dir" 18 "$L_CODE" $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> never verified\n' "$NOC"

    run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="11|12|13|14|15|16|17|18" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = $'#11 verify-fail-markers=1 unchecked-auto-conditions=0\n#14 verify-fail-markers=0 unchecked-auto-conditions=1' ]
    # Every target Issue was read
    [ "$(tr '\n' ' ' < "$dir/calls.log")" = "11 12 13 14 15 16 17 18 " ]

    # Control: the bare label check this condition replaces (phase/verify with any unchecked checkbox) would have
    # counted the two Issues that only wait for an observation condition.
    jq -e '(.labels | map(.name) | index("phase/verify")) != null and (.body | test("- \\[ \\]"))' "$dir/issue-12.json"
    jq -e '(.labels | map(.name) | index("phase/verify")) != null and (.body | test("- \\[ \\]"))' "$dir/issue-13.json"
}

@test "Notable judgment Verify FAIL check handles CRLF, multibyte text, null bodies, boundary timestamps and tag look-alikes (Issue #1535)" {
    local dir="$BATS_TEST_TMPDIR/vf"
    mkdir -p "$dir"
    verify_fail_mock_gh "$dir"
    local cmd
    cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

    local L_VERIFY='[{"name":"phase/verify"}]' L_NONE='[]' NOC='[]'
    local OBS='- [ ] waits for the next run <!-- verify-type: observation event=auto-run session=next -->'

    # 21: CRLF line endings and Japanese text
    verify_fail_fixture "$dir" 21 "$L_VERIFY" $'### Post-merge\r\n\r\n- [ ] <!-- verify: file_exists "x" --> 日本語の条件\r\n' "$NOC"
    # 22: null body
    jq -n --argjson labels "$L_VERIFY" '{labels: $labels, body: null, comments: []}' > "$dir/issue-22.json"
    # 23: an indented checkbox is not an acceptance condition line
    verify_fail_fixture "$dir" 23 "$L_VERIFY" $'### Post-merge\n\n- [ ] parent <!-- verify-type: manual -->\n  - [ ] <!-- verify: file_exists "a" --> nested sub-bullet\n' "$NOC"
    # 24: a marker created exactly at the session start second
    verify_fail_fixture "$dir" 24 "$L_NONE" $'### Post-merge\n\n'"$OBS"$'\n' "[$(verify_fail_marker_comment 2026-01-02T00:00:00Z)]"
    # 25: a marker with the optional deferral attributes still counts
    verify_fail_fixture "$dir" 25 "$L_NONE" $'### Post-merge\n\n'"$OBS"$'\n' "[$(verify_fail_marker_comment 2026-01-02T05:00:00Z ' deferral=true reason="pending authorization"')]"
    # 26: an explicit verify-type: auto tag is still an auto condition
    verify_fail_fixture "$dir" 26 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: grep "a" "b" --> text <!-- verify-type: auto -->\n' "$NOC"
    # 27: the words "verify-type: manual" appear inside the command text, not as a tag
    verify_fail_fixture "$dir" 27 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_contains "a.md" "verify-type: manual" --> excludes the verify-type: manual tally\n' "$NOC"
    # 28: an unresolved auto condition in Pre-merge (patch route: /verify is the first verifier)
    verify_fail_fixture "$dir" 28 "$L_VERIFY" $'### Pre-merge\n\n- [ ] <!-- verify: file_exists "y" --> pre cond\n\n### Post-merge\n\n- [x] <!-- verify: file_exists "z" --> done\n' "$NOC"
    # 29: two markers (two iterations) plus an unresolved auto condition
    verify_fail_fixture "$dir" 29 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> still open\n' "[$(verify_fail_marker_comment 2026-01-02T03:00:00Z),$(verify_fail_marker_comment 2026-01-02T04:00:00Z)]"
    # 30: a waiting tag with no closing delimiter is not a tag (Tag Extraction Rule), so the line stays an auto condition
    verify_fail_fixture "$dir" 30 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> text <!-- verify-type: manual\n' "$NOC"

    run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="21|22|23|24|25|26|27|28|29|30" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = $'#21 verify-fail-markers=0 unchecked-auto-conditions=1\n#24 verify-fail-markers=1 unchecked-auto-conditions=0\n#25 verify-fail-markers=1 unchecked-auto-conditions=0\n#26 verify-fail-markers=0 unchecked-auto-conditions=1\n#27 verify-fail-markers=0 unchecked-auto-conditions=1\n#28 verify-fail-markers=0 unchecked-auto-conditions=1\n#29 verify-fail-markers=2 unchecked-auto-conditions=1\n#30 verify-fail-markers=0 unchecked-auto-conditions=1' ]
}

@test "Notable judgment Verify FAIL check skips unreadable Issues and non-numeric entries without running them (Issue #1535)" {
    local dir="$BATS_TEST_TMPDIR/vf"
    mkdir -p "$dir"
    verify_fail_mock_gh "$dir"
    local cmd
    cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

    verify_fail_fixture "$dir" 31 '[{"name":"phase/verify"}]' $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> open\n' '[]'
    # 32 has no fixture: the mock gh fails for it, like an unreadable Issue

    run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE='31|32|3x|abc|1;2|$(id)||' bash -c "$cmd"
    [ "$status" -eq 0 ]
    [[ "$output" == *'#31 verify-fail-markers=0 unchecked-auto-conditions=1'* ]] || false
    [[ "$output" == *'Warning: could not read #32, skipped'* ]] || false
    [[ "$output" != *'#32 verify-fail'* ]] || false
    # Only all-digit entries reached gh
    [ "$(tr '\n' ' ' < "$dir/calls.log")" = "31 32 " ]
}

@test "Notable judgment Verify FAIL check disables only the marker branch without a session start and prints nothing for an empty target list (Issue #1535)" {
    local dir="$BATS_TEST_TMPDIR/vf"
    mkdir -p "$dir"
    verify_fail_mock_gh "$dir"
    local cmd
    cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

    verify_fail_fixture "$dir" 41 '[]' $'### Post-merge\n\n- [ ] waits <!-- verify-type: observation event=auto-run session=next -->\n' "[$(verify_fail_marker_comment 2026-01-02T01:00:00Z)]"
    verify_fail_fixture "$dir" 42 '[{"name":"phase/verify"}]' $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> open\n' "[$(verify_fail_marker_comment 2026-01-02T01:00:00Z)]"

    # With a session start, both Issues count
    run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="41|42" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = $'#41 verify-fail-markers=1 unchecked-auto-conditions=0\n#42 verify-fail-markers=1 unchecked-auto-conditions=1' ]

    # Without one, the marker branch is off (41 drops out) but the unresolved-auto-condition branch still applies (42 stays)
    run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="" BATCH_ISSUES_RE="41|42" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ "$output" = '#42 verify-fail-markers=0 unchecked-auto-conditions=1' ]

    # An empty target list prints nothing and does not call gh
    rm -f "$dir/calls.log"
    run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="" bash -c "$cmd"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$dir/calls.log" ]
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
