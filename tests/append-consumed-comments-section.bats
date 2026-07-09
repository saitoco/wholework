#!/usr/bin/env bats

# Tests for scripts/append-consumed-comments-section.sh
# Mocks: get-config-value.sh (via WHOLEWORK_SCRIPT_DIR), gh and git (via PATH prepend)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/append-consumed-comments-section.sh"

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

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    echo ""
    exit 0
fi
echo "[]"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ " \$* " == *" diff "* ]] && [[ " \$* " == *" --quiet "* ]]; then
    exit 1
fi
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$REPO_ROOT"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"
}

@test "no spec file: skips stub creation and exits 0" {
    run "$SCRIPT" 42 code
    [ "$status" -eq 0 ]
    stub_count=$(find "$BATS_TEST_TMPDIR/repo/docs/spec" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    [ "$stub_count" -eq 0 ]
}

@test "spec file exists: appends Consumed Comments section" {
    SPEC_FILE="$BATS_TEST_TMPDIR/repo/docs/spec/issue-42-some-title.md"
    printf '# Issue #42: some title\n\n## Overview\nSome content.\n' > "$SPEC_FILE"

    run "$SCRIPT" 42 code
    [ "$status" -eq 0 ]
    grep -q "^## Consumed Comments" "$SPEC_FILE"
}

@test "section already exists: dedup guard exits 0 without duplicate" {
    SPEC_FILE="$BATS_TEST_TMPDIR/repo/docs/spec/issue-42-some-title.md"
    printf '# Issue #42\n\n## Consumed Comments\nNo new comments since last phase.\n' > "$SPEC_FILE"

    run "$SCRIPT" 42 code
    [ "$status" -eq 0 ]
    section_count=$(grep -c "^## Consumed Comments" "$SPEC_FILE")
    [ "$section_count" -eq 1 ]
}
