#!/usr/bin/env bats

# Tests for scripts/check-translation-sync.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-translation-sync.sh"

setup() {
    mkdir -p "$BATS_TEST_TMPDIR/docs/ja"
    mkdir -p "$BATS_TEST_TMPDIR/docs/guide"
    cd "$BATS_TEST_TMPDIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
}

@test "in_sync: ja file committed after en file reports IN_SYNC" {
    echo "en content" > docs/en.md
    git add docs/en.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add en"

    echo "ja content" > docs/ja/en.md
    git add docs/ja/en.md
    GIT_COMMITTER_DATE="2024-01-02T10:00:00" GIT_AUTHOR_DATE="2024-01-02T10:00:00" \
        git commit -q -m "add ja"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/en.md"*"IN_SYNC"* ]]
}

@test "outdated: en file committed after ja file reports OUTDATED" {
    echo "ja content" > docs/ja/en.md
    git add docs/ja/en.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add ja"

    echo "en content" > docs/en.md
    git add docs/en.md
    GIT_COMMITTER_DATE="2024-01-02T10:00:00" GIT_AUTHOR_DATE="2024-01-02T10:00:00" \
        git commit -q -m "add en"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/en.md"*"OUTDATED"* ]]
}

@test "missing_ja: en file without ja counterpart reports MISSING_JA" {
    echo "en content" > docs/en.md
    git add docs/en.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add en"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/en.md"*"MISSING_JA"* ]]
}

@test "git_log_untracked: files not in git history default to timestamp 0 and report IN_SYNC" {
    # Require at least one commit so git log does not fail with exit 128
    git commit -q --allow-empty -m "initial"

    echo "en content" > docs/en.md
    echo "ja content" > docs/ja/en.md

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/en.md"*"IN_SYNC"* ]]
}

@test "fail_if_outdated: exits 1 when OUTDATED file exists" {
    echo "ja content" > docs/ja/en.md
    git add docs/ja/en.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add ja"

    echo "en content" > docs/en.md
    git add docs/en.md
    GIT_COMMITTER_DATE="2024-01-02T10:00:00" GIT_AUTHOR_DATE="2024-01-02T10:00:00" \
        git commit -q -m "add en"

    run bash "$SCRIPT" --fail-if-outdated
    [ "$status" -eq 1 ]
}

@test "fail_if_outdated: exits 1 when MISSING_JA file exists" {
    echo "en content" > docs/en.md
    git add docs/en.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add en"

    run bash "$SCRIPT" --fail-if-outdated
    [ "$status" -eq 1 ]
}

@test "fail_if_outdated: exits 0 when all files are in sync" {
    echo "en content" > docs/en.md
    git add docs/en.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add en"

    echo "ja content" > docs/ja/en.md
    git add docs/ja/en.md
    GIT_COMMITTER_DATE="2024-01-02T10:00:00" GIT_AUTHOR_DATE="2024-01-02T10:00:00" \
        git commit -q -m "add ja"

    run bash "$SCRIPT" --fail-if-outdated
    [ "$status" -eq 0 ]
}

@test "excludes: docs/spec directory is not included in source files" {
    mkdir -p docs/spec
    echo "spec content" > docs/spec/spec.md
    git add docs/spec/spec.md
    GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
        git commit -q -m "add spec"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"docs/spec/spec.md"* ]]
}
