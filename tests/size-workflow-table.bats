#!/usr/bin/env bats

# Shallow tests for size-workflow-table module documentation.
# LLM responses are not mocked; tests confirm that Size judgment criteria
# and workflow route terms are present in modules/size-workflow-table.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SIZE_WORKFLOW_TABLE="$PROJECT_ROOT/modules/size-workflow-table.md"

@test "size-workflow-table: 2 axes term is documented" {
    grep -q "2 axes" "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: XS table row exists" {
    grep -qE "^\| XS" "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: S table row exists (distinct from XS)" {
    grep -qE "^\| S " "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: M table row exists" {
    grep -qE "^\| M " "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: L table row exists (distinct from XL)" {
    grep -qE "^\| L " "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: XL table row exists" {
    grep -qE "^\| XL" "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: patch workflow route is documented" {
    grep -q "patch" "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: pr workflow route is documented" {
    grep -q "pr" "$SIZE_WORKFLOW_TABLE"
}
