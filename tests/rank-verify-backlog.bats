#!/usr/bin/env bats

# Tests for scripts/rank-verify-backlog.sh (see
# docs/spec/issue-1349-rank-verify-backlog-batch.md).
# Mocks: gh (via PATH prepend), following the same gh-mock convention as
# tests/scan-pending-ac.bats / tests/run-fact-matching.bats.
#
# The script writes ranked Issue numbers to stdout and per-issue score lines
# to stderr, so `run --separate-stderr` is used throughout to keep the two
# streams apart in assertions ($output = stdout only, $stderr = stderr only).

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/rank-verify-backlog.sh"

setup() {
    cd "$PROJECT_ROOT"

    export MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "rank-verify-backlog: ranks issues by auto_count descending" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[
  {"number": 100, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"a\" --> auto one\n"},
  {"number": 200, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"a\" --> auto one\n- [ ] <!-- verify: rubric \"b\" --> auto two\n"}
]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "200
100" ]
}

@test "rank-verify-backlog: code fence sample checkbox lines are excluded from both counts (#709 regression)" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number": 700, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"real\" --> real auto condition\n\n```\n- [ ] <!-- verify: rubric \"fake\" --> fenced sample checkbox\n- [ ] fenced manual sample\n```\n\n- [ ] manual after fence\n"}]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "700" ]
}

@test "rank-verify-backlog: fenced sample checkbox does not inflate auto_count or manual_count (stderr score check)" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number": 701, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"real\" --> real auto condition\n\n```\n- [ ] <!-- verify: rubric \"fake\" --> fenced sample checkbox\n- [ ] fenced manual sample\n```\n\n- [ ] manual after fence\n"}]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"#701: auto=1 manual=1"* ]]
}

@test "rank-verify-backlog: --top truncates ranked output" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[
  {"number": 10, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"a\" --> a\n- [ ] <!-- verify: rubric \"a\" --> a\n- [ ] <!-- verify: rubric \"a\" --> a\n"},
  {"number": 20, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"a\" --> a\n- [ ] <!-- verify: rubric \"a\" --> a\n"},
  {"number": 30, "body": "### Post-merge\n\n- [ ] <!-- verify: rubric \"a\" --> a\n"}
]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT" --top 2
    [ "$status" -eq 0 ]
    [ "$output" = "10
20" ]
}

@test "rank-verify-backlog: Option B co-tagged line (verify-type + verify) counts toward auto_count" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number": 900, "body": "### Post-merge\n\n- [ ] <!-- verify-type: observation event=auto-run --> <!-- verify: rubric \"w\" --> option b form\n"}]
JSON
  exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "rank-verify-backlog: gh failure fails open with empty stdout and exit 0" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "rank-verify-backlog: --top requires a positive integer" {
    run --separate-stderr bash "$SCRIPT" --top abc
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error"* ]]
}

@test "rank-verify-backlog: --limit requires a positive integer" {
    run --separate-stderr bash "$SCRIPT" --limit abc
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error"* ]]
}

@test "rank-verify-backlog: gh issue list is called with --state all and phase/verify label" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    printf '%s\n' "$@" >> "$MOCK_DIR/gh-list-args.txt"
    echo "[]"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    args_joined="$(tr '\n' ' ' < "$MOCK_DIR/gh-list-args.txt")"
    [[ "$args_joined" == *"--state all"* ]]
    [[ "$args_joined" == *"--label phase/verify"* ]]
    [[ "$args_joined" == *"--json number,body"* ]]
}
