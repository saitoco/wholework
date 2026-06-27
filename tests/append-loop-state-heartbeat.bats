#!/usr/bin/env bats

# Tests for scripts/append-loop-state-heartbeat.sh
# Mocks gh/jq via PATH so the script runs hermetically.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/append-loop-state-heartbeat.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Mock gh: emit minimal JSON shape the script expects.
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
# Mock: gh issue list --state open --json labels --limit 1000
echo '[
  {"labels":[{"name":"phase/issue"}]},
  {"labels":[{"name":"phase/issue"}]},
  {"labels":[{"name":"phase/spec"}]},
  {"labels":[{"name":"phase/code"}]},
  {"labels":[{"name":"phase/review"}]},
  {"labels":[{"name":"phase/review"}]},
  {"labels":[{"name":"phase/verify"}]}
]'
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

# The script must place loop-state files in <script_dir>/../docs/reports.
# Stage a wrapper script that points at our temp repo root.
_make_wrapper() {
    local fake_root="$1"
    mkdir -p "$fake_root/scripts"
    cp "$SCRIPT" "$fake_root/scripts/append-loop-state-heartbeat.sh"
    chmod +x "$fake_root/scripts/append-loop-state-heartbeat.sh"
    echo "$fake_root/scripts/append-loop-state-heartbeat.sh"
}

@test "missing --issue: warns and exits 0 (best-effort)" {
    run "$SCRIPT" --from spec --to code
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing --issue/--from/--to"* ]]
}

@test "missing --from: warns and exits 0" {
    run "$SCRIPT" --issue 701 --to code
    [ "$status" -eq 0 ]
}

@test "missing --to: warns and exits 0" {
    run "$SCRIPT" --issue 701 --from spec
    [ "$status" -eq 0 ]
}

@test "unknown option: exits non-zero" {
    run "$SCRIPT" --bogus xyz
    [ "$status" -ne 0 ]
}

@test "creates loop-state file with shared schema when absent" {
    fake_root="$BATS_TEST_TMPDIR/repo"
    wrapper=$(_make_wrapper "$fake_root")
    run "$wrapper" --issue 701 --from spec --to code
    [ "$status" -eq 0 ]
    today=$(date -u +%Y-%m-%d)
    file="$fake_root/docs/reports/loop-state-$today.md"
    [ -f "$file" ]
    # Header must match #703 schema for coexistence.
    grep -q '| Time (UTC) | Phase | Event | Detail |' "$file"
    grep -q 'type: report' "$file"
}

@test "appends a phase-transition row with from→to and aggregated snapshot" {
    fake_root="$BATS_TEST_TMPDIR/repo"
    wrapper=$(_make_wrapper "$fake_root")
    run "$wrapper" --issue 701 --from spec --to code
    [ "$status" -eq 0 ]
    today=$(date -u +%Y-%m-%d)
    file="$fake_root/docs/reports/loop-state-$today.md"
    grep -q '| code | phase-transition |' "$file"
    grep -q '#701 spec→code' "$file"
    # Snapshot aggregation from the mocked gh.
    grep -q 'issue:2 spec:1 code:1 review:2 verify:1' "$file"
}

@test "second call appends without rewriting header" {
    fake_root="$BATS_TEST_TMPDIR/repo"
    wrapper=$(_make_wrapper "$fake_root")
    "$wrapper" --issue 701 --from spec --to code
    "$wrapper" --issue 702 --from code --to review
    today=$(date -u +%Y-%m-%d)
    file="$fake_root/docs/reports/loop-state-$today.md"
    # Header must appear exactly once.
    header_count=$(grep -c '| Time (UTC) | Phase | Event | Detail |' "$file")
    [ "$header_count" -eq 1 ]
    grep -q '#701 spec→code' "$file"
    grep -q '#702 code→review' "$file"
}

@test "gh failure does not break the script (graceful snapshot fallback)" {
    fake_root="$BATS_TEST_TMPDIR/repo"
    # Override gh to fail.
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"
    wrapper=$(_make_wrapper "$fake_root")
    run "$wrapper" --issue 701 --from spec --to code
    [ "$status" -eq 0 ]
    today=$(date -u +%Y-%m-%d)
    file="$fake_root/docs/reports/loop-state-$today.md"
    [ -f "$file" ]
    grep -q 'snapshot:\[snapshot-unavailable\]' "$file"
}

@test "phase-label override applies to the Phase column" {
    fake_root="$BATS_TEST_TMPDIR/repo"
    wrapper=$(_make_wrapper "$fake_root")
    run "$wrapper" --issue 701 --from spec --to code --phase-label code-patch
    [ "$status" -eq 0 ]
    today=$(date -u +%Y-%m-%d)
    file="$fake_root/docs/reports/loop-state-$today.md"
    grep -q '| code-patch | phase-transition |' "$file"
}
