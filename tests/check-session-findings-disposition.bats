#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for check-session-findings-disposition.sh
# Verifies ## Findings disposition tag detection for L3 session.md retrospectives:
#   exit 0 — no ## Findings section, or all top-level bullets have a canonical disposition tag
#   exit 1 — usage error (missing argument or unreadable file)
#   exit 2 — one or more ## Findings bullets lack a canonical disposition tag

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REAL_SCRIPT="$PROJECT_ROOT/scripts/check-session-findings-disposition.sh"

setup() {
    FIXTURE_DIR="$BATS_TEST_TMPDIR"
}

write_fixture() {
    local path="$1"
    cat > "$path"
}

@test "missing tag: exit 2 and untagged bullet printed to output" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
# L3 Session Retrospective: test

## Findings

- Tagged finding [Filed: #123]
- Untagged finding with no disposition tag

## Auto Retrospective
### Improvement Proposals
- x
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Untagged finding with no disposition tag"* ]]
}

@test "all tagged: exit 0 when every bullet has a canonical disposition tag" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
# L3 Session Retrospective: test

## Findings

- Filed one [Filed: #123]
- Accepted as-is [No action: already covered by #100]
- Fixed inline [Resolved directly: adjusted config]

## Auto Retrospective
### Improvement Proposals
- x
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "pending backfill: [Filed: pending] is non-canonical and detected" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
# L3 Session Retrospective: test

## Findings

- Not yet backfilled [Filed: pending]

## Auto Retrospective
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"[Filed: pending]"* ]]
}

@test "single tag type: [Filed: #N] alone passes" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
## Findings

- Filed finding [Filed: #456]
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 0 ]
}

@test "single tag type: [No action: ...] alone passes" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
## Findings

- Not actionable [No action: duplicate of #789]
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 0 ]
}

@test "single tag type: [Resolved directly: ...] alone passes" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
## Findings

- Handled in-session [Resolved directly: posted follow-up comment]
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 0 ]
}

@test "no Findings section: exit 0" {
    write_fixture "$FIXTURE_DIR/session.md" <<'EOF'
# L3 Session Retrospective: test

## What worked
- everything
EOF
    run bash "$REAL_SCRIPT" "$FIXTURE_DIR/session.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "no argument: exit 1 with usage message" {
    run bash "$REAL_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
