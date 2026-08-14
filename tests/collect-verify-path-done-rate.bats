#!/usr/bin/env bats

# Tests for scripts/collect-verify-path-done-rate.sh (see
# docs/spec/issue-1352-audit-batch-sweep-done-rate.md).
#
# gh mock convention: same as tests/rank-verify-backlog.bats (PATH prepend,
# a mock `gh` script matching `gh issue list`).
# events.jsonl fixture convention: same as
# tests/collect-opportunistic-retire-candidates.bats (a docs/sessions/{SID}/
# events.jsonl file under a temp directory). Because the script under test
# hardcodes the "docs/sessions" path (no directory argument, per the Spec's
# `[--limit N]`-only usage), tests run from a fresh $BATS_TEST_TMPDIR rather
# than $PROJECT_ROOT, so the real repository's docs/sessions/ is never read.

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/collect-verify-path-done-rate.sh"

setup() {
    export MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    cd "$BATS_TEST_TMPDIR"
}

_mock_gh_issue_list() {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [[ "\$1" == "issue" && "\$2" == "list" ]]; then
  cat <<'JSON'
$1
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"
}

_write_events() {
    local session="$1"
    mkdir -p "docs/sessions/$session"
    cat > "docs/sessions/$session/events.jsonl"
}

@test "batch-verify-dispatch marker: counted in batch-sweep processed and done" {
    _mock_gh_issue_list '[
  {"number": 100, "labels":[{"name":"phase/done"}], "comments":[{"body":"<!-- wholework-event: type=batch-verify-dispatch phase=audit issue=100 -->\nSelected by batch sweep."}]},
  {"number": 101, "labels":[], "comments":[{"body":"<!-- wholework-event: type=batch-verify-dispatch phase=audit issue=101 -->\nSelected by batch sweep."}]}
]'

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE $'^batch-sweep\t2\t1\t50\\.0%$'
}

@test "observation-trigger marker: counted in observation-dispatch, not in batch-sweep (path mixup regression)" {
    _mock_gh_issue_list '[
  {"number": 200, "labels":[{"name":"phase/done"}], "comments":[{"body":"<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=200 event=foo -->\nRun /verify."}]}
]'

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE $'^observation-dispatch\t1\t1\t100\\.0%$'
    echo "$output" | grep -qE $'^batch-sweep\t0\t0\tN/A$'
}

@test "opportunistic_verify_result events: unique issue count in opportunistic-verify, cross-checked against phase/done" {
    _mock_gh_issue_list '[
  {"number": 300, "labels":[{"name":"phase/done"}], "comments":[]},
  {"number": 301, "labels":[], "comments":[]}
]'
    _write_events "session-a" <<'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":300,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-02T10:00:00Z","issue":300,"event":"opportunistic_verify_result","skill":"/code","result":"PASS","ac_index":"1"}
{"ts":"2026-08-01T10:00:00Z","issue":301,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"2"}
FIXTURE_EOF

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE $'^opportunistic-verify\t2\t1\t50\\.0%$'
}

@test "empty set for a path -> rate is N/A (no division by zero)" {
    _mock_gh_issue_list '[
  {"number": 400, "labels":[], "comments":[]}
]'

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE $'^batch-sweep\t0\t0\tN/A$'
    echo "$output" | grep -qE $'^observation-dispatch\t0\t0\tN/A$'
    echo "$output" | grep -qE $'^opportunistic-verify\t0\t0\tN/A$'
}

@test "gh failure -> all three paths fail-open (processed=0 done=0 rate=N/A), exit 0" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"
    _write_events "session-a" <<'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":500,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
FIXTURE_EOF

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "batch-sweep	0	0	N/A
observation-dispatch	0	0	N/A
opportunistic-verify	0	0	N/A" ]
}

@test "opportunistic-verify issue not present in gh issue list is excluded with a stderr warning" {
    _mock_gh_issue_list '[
  {"number": 600, "labels":[{"name":"phase/done"}], "comments":[]}
]'
    _write_events "session-a" <<'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":600,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-01T10:00:00Z","issue":999,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
FIXTURE_EOF

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE $'^opportunistic-verify\t1\t1\t100\\.0%$'
    [[ "$stderr" == *"1 opportunistic-verify Issue number(s) not found"* ]]
}

@test "an Issue counted in multiple paths simultaneously (paths are not mutually exclusive)" {
    _mock_gh_issue_list '[
  {"number": 700, "labels":[{"name":"phase/done"}], "comments":[{"body":"<!-- wholework-event: type=batch-verify-dispatch phase=audit issue=700 -->\nx"}, {"body":"<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=700 event=foo -->\ny"}]}
]'

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE $'^batch-sweep\t1\t1\t100\\.0%$'
    echo "$output" | grep -qE $'^observation-dispatch\t1\t1\t100\\.0%$'
}

@test "--limit hitting the cap prints a stderr warning" {
    _mock_gh_issue_list '[
  {"number": 800, "labels":[], "comments":[]}
]'

    run --separate-stderr bash "$SCRIPT" --limit 1
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"hit the --limit 1 cap"* ]]
}
