#!/usr/bin/env bats

# Structure guard for the bounded wait and the degradation record in skills/review/SKILL.md
# (Issue #1551, follow-up of #1481 / #1522).
#
# Claude Code starts an Agent/Task sub-agent in the background when `run_in_background` is left
# out, also in headless `claude -p`; the launch call then returns only an acknowledgment. The
# PR #1549 review left it out of all five launches and gave up on the result files after about
# 75 seconds. SKILL.md now (1) passes `run_in_background=false` on every Step 10 launch, (2) waits
# once per fan-out, for at most 480 seconds, through scripts/wait-subagent-results.sh before it
# substitutes for a sub-agent, and (3) records every degradation in a fixed-format line.
# These tests fail when any of the three is dropped.
#
# The tests validate documentation text only; no LLM response is mocked.

load 'helpers/markdown-section'

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REVIEW_SKILL="$PROJECT_ROOT/skills/review/SKILL.md"
WAIT_SCRIPT="$PROJECT_ROOT/scripts/wait-subagent-results.sh"

# launches_without_foreground FILE
#   Reads a Markdown file (normally the Step 10 section) and checks every `Task(` launch example,
#   from the line holding `Task(` to the closing `)` line. Prints "LINE:text" of each launch
#   whose example has no `run_in_background=false`.
#   Status: 0 = every launch carries it (and at least 5 launches exist), 1 = some launch lacks
#   it, 2 = FILE missing or empty, or fewer than 5 launches found (fail closed, so a renamed
#   heading or a rewritten example block never passes as "all launches are covered").
launches_without_foreground() {
    local file="$1" out="" count=0
    if [ ! -s "$file" ]; then
        echo "launches_without_foreground: $file is missing or empty" >&2
        return 2
    fi
    out="$(awk '
        /^[ \t]*Task\(/ { inlaunch = 1; has = 0; start = NR; text = $0; count++; next }
        inlaunch && /^[ \t]*\)[ \t]*$/ {
            if (!has) printf "%d:%s\n", start, text
            inlaunch = 0
            next
        }
        inlaunch && /run_in_background=false/ { has = 1 }
        END { printf "COUNT:%d\n", count }
    ' "$file")"
    count="${out##*COUNT:}"
    out="$(printf '%s\n' "$out" | grep -v '^COUNT:' || true)"
    if [ "$count" -lt 5 ]; then
        echo "launches_without_foreground: only $count Task( launch(es) found in $file" >&2
        return 2
    fi
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
        return 1
    fi
    return 0
}

# step10_file: write the Step 10 section of SKILL.md to a temp file and print its path.
step10_file() {
    local f="$BATS_TEST_TMPDIR/step10.md" section
    section="$(md_section "$REVIEW_SKILL" "## Step 10:")"
    [ -n "$section" ]
    printf '%s\n' "$section" > "$f"
    printf '%s\n' "$f"
}

# paragraph_from FILE PREFIX
#   Prints the lines from the one that starts with PREFIX up to (not including) the next line
#   that starts with "**Stop.**" or a heading, so a paragraph that contains a code fence is
#   returned whole.
paragraph_from() {
    awk -v prefix="$2" '
        !found && index($0, prefix) == 1 { found = 1; print; next }
        found && (index($0, "**Stop.**") == 1 || $0 ~ /^#+ /) { exit }
        found { print }
        END { if (!found) exit 1 }
    ' "$1"
}

# --- Launch mode -----------------------------------------------------------------------------

@test "every Step 10 Task launch example passes run_in_background=false" {
    local f
    f="$(step10_file)"
    run launches_without_foreground "$f"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "the launch detector reports a launch example that lacks run_in_background=false" {
    local f mutant
    f="$(step10_file)"
    mutant="$BATS_TEST_TMPDIR/mutant.md"
    awk '!dropped && /run_in_background=false,/ { dropped = 1; next } { print }' "$f" > "$mutant"
    cmp -s "$f" "$mutant" && false
    run launches_without_foreground "$mutant"
    echo "$output"
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "the Edge Case Pre-check launch sentence passes run_in_background=false" {
    local section line
    section="$(md_section "$REVIEW_SKILL" "### Parser/Validator Edge Case Pre-check")"
    [ -n "$section" ]
    line="$(printf '%s\n' "$section" | grep -a '^3\. For each matching file' || true)"
    [ -n "$line" ]
    [[ "$line" == *'run_in_background=false'* ]] || false
}

@test "the Launch mode paragraph says that leaving the parameter out selects the background" {
    local section para
    section="$(md_section "$REVIEW_SKILL" "### Sub-agent Names and Stop")"
    [ -n "$section" ]
    para="$(printf '%s\n' "$section" | grep -a '^\*\*Launch mode\.\*\*' || true)"
    [ -n "$para" ]
    [[ "$para" == *'run_in_background=false'* ]] || false
    [[ "$para" == *'in the background when the parameter is left out'* ]] || false
    [[ "$para" == *'Async agent launched successfully'* ]] || false
}

# --- Wait limit ------------------------------------------------------------------------------

@test "the Wait limit paragraph states the limit, the single call, and both reasons" {
    local section para
    section="$(md_section "$REVIEW_SKILL" "### Sub-agent Names and Stop")"
    [ -n "$section" ]
    printf '%s\n' "$section" > "$BATS_TEST_TMPDIR/names-and-stop.md"
    para="$(paragraph_from "$BATS_TEST_TMPDIR/names-and-stop.md" '**Wait limit.**')"
    [ -n "$para" ]
    [[ "$para" == *'480'* ]] || false
    [[ "$para" == *'wait-subagent-results.sh 480'* ]] || false
    [[ "$para" == *'timeout: 540000'* ]] || false
    [[ "$para" == *'once'* ]] || false
    [[ "$para" == *'wait-limit-exceeded'* ]] || false
    [[ "$para" == *'wait-not-run'* ]] || false
}

@test "the wait limit in SKILL.md fits inside the script's clamp and the Bash tool timeout" {
    local limit clamp ms
    limit="$(grep -a -o 'wait-subagent-results\.sh [0-9][0-9]*' "$REVIEW_SKILL" | head -n 1 | sed -E 's/.* //')"
    [ -n "$limit" ]
    clamp="$(grep -a -E '^MAX_TIMEOUT_SEC=' "$WAIT_SCRIPT" | head -n 1 | sed -E 's/.*=//')"
    [ -n "$clamp" ]
    ms="$(grep -a -o 'timeout: [0-9][0-9]*' "$REVIEW_SKILL" | sed -E 's/.* //' | sort -n | tail -n 1)"
    [ -n "$ms" ]
    [ "$limit" -le "$clamp" ]
    [ $((ms / 1000)) -gt "$limit" ]
    [ "$ms" -le 600000 ]
}

@test "allowed-tools lets /review run the wait script" {
    local front
    front="$(awk '/^---$/ { n++; next } n == 1 { print } n >= 2 { exit }' "$REVIEW_SKILL")"
    [ -n "$front" ]
    [[ "$front" == *'${CLAUDE_PLUGIN_ROOT}/scripts/wait-subagent-results.sh:*'* ]] || false
}

# --- Degradation record ----------------------------------------------------------------------

@test "Sub-agent Result Fallback defines the fixed degradation line format" {
    local section
    section="$(md_section "$REVIEW_SKILL" "### Sub-agent Result Fallback")"
    [ -n "$section" ]
    [[ "$section" == *'- Sub-agent degradation: {label} ({aspect}): {disposition}; reason={reason}; waited={N}s'* ]] || false
    [[ "$section" == *'Sub-agent fallback'* ]] || false
}

@test "the Review Response Summary template and the Retrospective carry the degradation record" {
    local step14 retro
    step14="$(md_section "$REVIEW_SKILL" "## Step 14:")"
    [ -n "$step14" ]
    [[ "$step14" == *'### Sub-agent Degradation'* ]] || false
    [[ "$step14" == *'omit the Sub-agent Degradation section'* ]] || false
    retro="$(md_section "$REVIEW_SKILL" "## Retrospective")"
    [ -n "$retro" ]
    [[ "$retro" == *'Sub-agent degradation:'* ]] || false
    [[ "$retro" == *'### Recurring issues'* ]] || false
}

# --- Consistency -----------------------------------------------------------------------------

@test "the pre-#1551 sentence that treated the substitution time as the grace period is gone" {
    local section
    section="$(md_section "$REVIEW_SKILL" "### Sub-agent Result Fallback")"
    [ -n "$section" ]
    [[ "$section" != *'which is what gives its result file time to appear'* ]] || false
}

@test "'Never wait for a result' appears exactly once (the Issue premise marker counts it)" {
    run grep -a -c 'Never wait for a result' "$REVIEW_SKILL"
    [ "$output" = "1" ]
}

@test "the launch detector fails closed on a missing, empty, or launch-less file" {
    run launches_without_foreground "$BATS_TEST_TMPDIR/does-not-exist.md"
    [ "$status" -eq 2 ]
    : > "$BATS_TEST_TMPDIR/empty.md"
    run launches_without_foreground "$BATS_TEST_TMPDIR/empty.md"
    [ "$status" -eq 2 ]
    printf 'Task(\n  run_in_background=false,\n)\n' > "$BATS_TEST_TMPDIR/one.md"
    run launches_without_foreground "$BATS_TEST_TMPDIR/one.md"
    [ "$status" -eq 2 ]
}
