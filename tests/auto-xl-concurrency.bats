#!/usr/bin/env bats

# Tests for XL route concurrency cap via AUTO_MAX_CONCURRENT (Issue #589)
# Structural tests: verify that skills/auto/SKILL.md and modules/detect-config-markers.md
# contain required content for semaphore-based concurrency control.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"
MARKERS_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/modules/detect-config-markers.md"

# Extract the XL route block from SKILL.md
xl_route_section() {
    awk '/^\*\*XL route:/{found=1} /^---/{if(found)exit} found{print}' "$SKILL_FILE"
}

@test "XL route: AUTO_MAX_CONCURRENT semaphore pattern present" {
    run bash -c "awk '/^\*\*XL route:/{found=1} /^---/{if(found)exit} found{print}' '$SKILL_FILE' | grep -q 'AUTO_MAX_CONCURRENT'"
    [ "$status" -eq 0 ]
}

@test "XL route: kill -0 bash 3.2 fallback present" {
    run bash -c "awk '/^\*\*XL route:/{found=1} /^---/{if(found)exit} found{print}' '$SKILL_FILE' | grep -q 'kill -0'"
    [ "$status" -eq 0 ]
}

@test "detect-config-markers: auto-max-concurrent fallback rule present" {
    run grep -q 'auto-max-concurrent.*AUTO_MAX_CONCURRENT' "$MARKERS_FILE"
    [ "$status" -eq 0 ]
}
