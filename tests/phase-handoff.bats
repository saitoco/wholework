#!/usr/bin/env bats

# Shallow tests for phase-handoff module documentation.
# LLM responses are not mocked; tests confirm that required sections and
# contract terms are present in modules/phase-handoff.md.

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
