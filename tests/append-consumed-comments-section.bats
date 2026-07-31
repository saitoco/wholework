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
if [[ "\$*" == *"rev-parse --git-dir"* ]]; then
    echo "$REPO_ROOT/.git/worktrees/mock"
    exit 0
fi
if [[ "\$*" == *"rev-parse --git-common-dir"* ]]; then
    echo "$REPO_ROOT/.git"
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

@test "existing section with new comment: appends new entry without removing existing one" {
    SPEC_FILE="$BATS_TEST_TMPDIR/repo/docs/spec/issue-42-some-title.md"
    printf '# Issue #42\n\n## Consumed Comments\n- alice / MEMBER / first-class / old comment / https://github.com/org/repo/issues/42#issuecomment-1\n\n## Phase Handoff\n- placeholder\n' > "$SPEC_FILE"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    echo ""
    exit 0
fi
cat <<'JSON'
[{"author":{"login":"bob"},"authorAssociation":"MEMBER","url":"https://github.com/org/repo/issues/42#issuecomment-2","body":"new comment body","createdAt":"2026-07-31T00:00:00Z"}]
JSON
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42 verify
    [ "$status" -eq 0 ]
    grep -q "issuecomment-1" "$SPEC_FILE"
    grep -q "issuecomment-2" "$SPEC_FILE"
    section_count=$(grep -c "^## Consumed Comments" "$SPEC_FILE")
    [ "$section_count" -eq 1 ]
    # The new entry must land inside the Consumed Comments section, before the next "## " heading.
    [[ "$(sed -n '/^## Phase Handoff/,$p' "$SPEC_FILE")" != *"issuecomment-2"* ]]
}

@test "existing section re-run with same comment: no duplicate entry added" {
    SPEC_FILE="$BATS_TEST_TMPDIR/repo/docs/spec/issue-42-some-title.md"
    printf '# Issue #42\n\n## Consumed Comments\n- bob / MEMBER / first-class / new comment body / https://github.com/org/repo/issues/42#issuecomment-2\n' > "$SPEC_FILE"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    echo ""
    exit 0
fi
cat <<'JSON'
[{"author":{"login":"bob"},"authorAssociation":"MEMBER","url":"https://github.com/org/repo/issues/42#issuecomment-2","body":"new comment body","createdAt":"2026-07-31T00:00:00Z"}]
JSON
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42 verify
    [ "$status" -eq 0 ]
    occurrence_count=$(grep -c "issuecomment-2" "$SPEC_FILE")
    [ "$occurrence_count" -eq 1 ]
}

@test "jq failure on RAW_COMMENTS: warns on stderr, falls back to empty array, exits 0" {
    SPEC_FILE="$BATS_TEST_TMPDIR/repo/docs/spec/issue-42-some-title.md"
    printf '# Issue #42: some title\n\n## Overview\nSome content.\n' > "$SPEC_FILE"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    echo ""
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    echo "not valid json"
    exit 1
fi
echo "[]"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42 code
    [ "$status" -eq 0 ]
    [[ "$output" == *"jq failed"* ]]
    [[ "$output" == *"RAW_COMMENTS"* ]]
    grep -q "^## Consumed Comments" "$SPEC_FILE"
}

@test "not in worktree: emits defense-in-depth warning" {
    SPEC_FILE="$BATS_TEST_TMPDIR/repo/docs/spec/issue-42-some-title.md"
    printf '# Issue #42: some title\n\n## Overview\nSome content.\n' > "$SPEC_FILE"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ " \$* " == *" diff "* ]] && [[ " \$* " == *" --quiet "* ]]; then
    exit 1
fi
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$REPO_ROOT"
    exit 0
fi
if [[ "\$*" == *"rev-parse --git-dir"* ]]; then
    echo "$REPO_ROOT/.git"
    exit 0
fi
if [[ "\$*" == *"rev-parse --git-common-dir"* ]]; then
    echo "$REPO_ROOT/.git"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run "$SCRIPT" 42 code
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"worktree"* ]]
}
