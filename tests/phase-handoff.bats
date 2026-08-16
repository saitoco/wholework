#!/usr/bin/env bats

# Shallow tests (below) confirm that required sections and contract terms are
# present in modules/phase-handoff.md; the LLM-driven Write/Read Procedure
# prose itself is not mocked or executed. The tests further down exercise
# scripts/dedupe-phase-handoff-section.sh directly — that script IS a real,
# invokable deterministic fallback (Issue #1374), so those tests run it
# against fixture Spec files and assert on actual file content, not prose.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PHASE_HANDOFF="$PROJECT_ROOT/modules/phase-handoff.md"

@test "phase-handoff: ## Purpose section exists" {
    grep -q "## Purpose" "$PHASE_HANDOFF"
}

@test "phase-handoff: write procedure section documents handoff write contract" {
    grep -q "## Write Procedure" "$PHASE_HANDOFF"
}

@test "phase-handoff: read procedure section documents handoff read contract" {
    grep -q "## Read Procedure" "$PHASE_HANDOFF"
}

@test "phase-handoff: rotation boundary detection is documented" {
    grep -q "rotation" "$PHASE_HANDOFF"
}

@test "phase-handoff: Phase Handoff section format uses phase marker comment" {
    grep -q "<!-- phase:" "$PHASE_HANDOFF"
}

@test "phase-handoff: Phase Position Asymmetry table is documented" {
    grep -q "Phase Position Asymmetry" "$PHASE_HANDOFF"
}

@test "phase-handoff: AC cross-reference staleness check is documented" {
    grep -q "resolved after handoff" "$PHASE_HANDOFF"
}

@test "phase-handoff: deterministic dedupe fallback is documented" {
    grep -q "dedupe-phase-handoff-section.sh" "$PHASE_HANDOFF"
}

# --- scripts/dedupe-phase-handoff-section.sh behavioral tests ---
# Mocking convention follows tests/append-consumed-comments-section.bats'
# setup(): a WHOLEWORK_SCRIPT_DIR mock directory providing get-config-value.sh
# (spec-path -> docs/spec) and a git stub resolving rev-parse --show-toplevel
# to the fixture repo root, with the fixture Spec at
# $BATS_TEST_TMPDIR/repo/docs/spec/issue-N-*.md.

DEDUPE_SCRIPT="$PROJECT_ROOT/scripts/dedupe-phase-handoff-section.sh"

setup() {
    REPO_ROOT="$BATS_TEST_TMPDIR/repo"
    MOCK_DIR="$REPO_ROOT/mocks"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$REPO_ROOT/docs/spec"

    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    spec-path) echo "docs/spec" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$REPO_ROOT"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"
}

@test "dedupe-phase-handoff-section: no spec file exits 0 as no-op" {
    run "$DEDUPE_SCRIPT" 999999
    [ "$status" -eq 0 ]
    stub_count=$(find "$REPO_ROOT/docs/spec" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    [ "$stub_count" -eq 0 ]
}

@test "dedupe-phase-handoff-section: single Phase Handoff block is a no-op" {
    SPEC_FILE="$REPO_ROOT/docs/spec/issue-42-some-title.md"
    printf '# Issue #42: some title\n\n## Overview\nSome content.\n\n## Phase Handoff\n<!-- phase: code -->\n\n### Key Decisions\n- decision A\n\n### Deferred Items\n- None\n\n### Notes for Next Phase\n- note A\n' > "$SPEC_FILE"
    ORIGINAL=$(cat "$SPEC_FILE")

    run "$DEDUPE_SCRIPT" 42

    [ "$status" -eq 0 ]
    UPDATED=$(cat "$SPEC_FILE")
    [ "$ORIGINAL" = "$UPDATED" ]
}

@test "dedupe-phase-handoff-section: regression - block followed by another section then a new block collapses to the latest only" {
    SPEC_FILE="$REPO_ROOT/docs/spec/issue-42-some-title.md"
    cat > "$SPEC_FILE" <<'EOF'
# Issue #42: some title

## Overview
Some content.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- old decision from code phase

### Deferred Items
- None

### Notes for Next Phase
- old note

## review retrospective
Some retrospective content.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- new decision from merge phase

### Deferred Items
- None

### Notes for Next Phase
- new note
EOF

    run "$DEDUPE_SCRIPT" 42

    [ "$status" -eq 0 ]

    PH_COUNT=$(grep -c "^## Phase Handoff" "$SPEC_FILE")
    [ "$PH_COUNT" -eq 1 ]

    grep -q "<!-- phase: merge -->" "$SPEC_FILE"
    grep -q "new decision from merge phase" "$SPEC_FILE"
    grep -q "## review retrospective" "$SPEC_FILE"
    grep -q "Some retrospective content." "$SPEC_FILE"

    ! grep -q "<!-- phase: code -->" "$SPEC_FILE"
    ! grep -q "old decision from code phase" "$SPEC_FILE"
}
