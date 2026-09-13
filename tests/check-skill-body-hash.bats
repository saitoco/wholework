#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/check-skill-body-hash.sh"

setup() {
    TMP_TARGET="$BATS_TEST_TMPDIR/target.md"
}

@test "check-skill-body-hash: exits 0 when marker matches computed hash" {
    printf '# Title\n<!-- skill-body-lines: 3 -->\nbody line\n' > "$TMP_TARGET"
    hash=$(grep -v '<!-- skill-body-' "$TMP_TARGET" | shasum -a 256 | cut -c1-8)
    printf '<!-- skill-body-sha: %s -->\n' "$hash" >> "$TMP_TARGET"

    run "$SCRIPT" "$TMP_TARGET"
    [ "$status" -eq 0 ]
}

@test "check-skill-body-hash: exits 1 with expected value when marker is stale" {
    printf '# Title\n<!-- skill-body-lines: 3 -->\nbody line\n<!-- skill-body-sha: deadbeef -->\n' > "$TMP_TARGET"
    expected=$(grep -v '<!-- skill-body-' "$TMP_TARGET" | shasum -a 256 | cut -c1-8)

    run --separate-stderr "$SCRIPT" "$TMP_TARGET"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"$expected"* ]]
}

@test "check-skill-body-hash: exits 1 when marker is absent" {
    printf '# Title\nbody line without a sha marker\n' > "$TMP_TARGET"

    run --separate-stderr "$SCRIPT" "$TMP_TARGET"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"marker not found"* ]]
}

@test "check-skill-body-hash: exits 0 when target file is absent (fail-open)" {
    run "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist.md"
    [ "$status" -eq 0 ]
}

@test "check-skill-body-hash: exits 1 on same-line-count content change (rename-equivalent edit)" {
    printf '# Title\n<!-- skill-body-lines: 3 -->\nold_name reference\n' > "$TMP_TARGET"
    hash=$(grep -v '<!-- skill-body-' "$TMP_TARGET" | shasum -a 256 | cut -c1-8)
    printf '<!-- skill-body-sha: %s -->\n' "$hash" >> "$TMP_TARGET"

    # Rename-equivalent edit: same line count, different content, marker not updated.
    sed -i.bak 's/old_name reference/new_name reference/' "$TMP_TARGET"
    rm -f "$TMP_TARGET.bak"

    run "$SCRIPT" "$TMP_TARGET"
    [ "$status" -eq 1 ]
}
