#!/usr/bin/env bats

# Schema validation tests for modules/orchestration-fallbacks.md.
# Verifies file existence, minimum entry count, required section presence
# per entry, Rationale references, and #319 consumer reference.
# bash 3.2+ compatible: no mapfile or associative arrays.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CATALOG="$PROJECT_ROOT/modules/orchestration-fallbacks.md"

@test "orchestration-fallbacks: catalog file exists" {
    test -f "$CATALOG"
}

@test "orchestration-fallbacks: at least 6 pattern entries (## headings with subsections)" {
    count=$(grep -c '^## ' "$CATALOG")
    # Total ## headings include intro sections (Purpose, Input, Pointer, Output, Operational Notes)
    # We check for >= 6 pattern entries by counting ### Symptom occurrences
    symptom_count=$(grep -c '^### Symptom' "$CATALOG")
    [ "$symptom_count" -ge 6 ]
}

@test "orchestration-fallbacks: each pattern entry has ### Symptom section" {
    entry_count=$(grep -c '^### Symptom' "$CATALOG")
    [ "$entry_count" -ge 6 ]
}

@test "orchestration-fallbacks: each pattern entry has ### Applicable Phases section" {
    entry_count=$(grep -c '^### Applicable Phases' "$CATALOG")
    [ "$entry_count" -ge 6 ]
}

@test "orchestration-fallbacks: each pattern entry has ### Fallback Steps section" {
    entry_count=$(grep -c '^### Fallback Steps' "$CATALOG")
    [ "$entry_count" -ge 6 ]
}

@test "orchestration-fallbacks: each pattern entry has ### Escalation section" {
    entry_count=$(grep -c '^### Escalation' "$CATALOG")
    [ "$entry_count" -ge 6 ]
}

@test "orchestration-fallbacks: each pattern entry has ### Rationale section" {
    entry_count=$(grep -c '^### Rationale' "$CATALOG")
    [ "$entry_count" -ge 6 ]
}

@test "orchestration-fallbacks: all 5 required sections appear the same number of times" {
    symptom=$(grep -c '^### Symptom' "$CATALOG")
    phases=$(grep -c '^### Applicable Phases' "$CATALOG")
    steps=$(grep -c '^### Fallback Steps' "$CATALOG")
    escalation=$(grep -c '^### Escalation' "$CATALOG")
    rationale=$(grep -c '^### Rationale' "$CATALOG")
    [ "$symptom" -eq "$phases" ] && [ "$symptom" -eq "$steps" ] && \
        [ "$symptom" -eq "$escalation" ] && [ "$symptom" -eq "$rationale" ]
}

@test "orchestration-fallbacks: each Rationale section contains at least one Issue reference (#N)" {
    # Extract each block from ## heading to next ## or EOF and check Rationale has #NNN.
    # found_rationale persists across ### boundaries so Rationale need not be the last subsection.
    awk '
        /^## / {
            if (in_entry && found_rationale && !has_ref) {
                missing_ref++
            }
            in_entry = /^## / && !/^## (Purpose|Input|Pointer|Output|Operational)/ ? 1 : 0
            in_rationale = 0
            found_rationale = 0
            has_ref = 0
        }
        in_entry && /^### Rationale/ { in_rationale = 1; found_rationale = 1 }
        in_entry && in_rationale && /^### / && !/^### Rationale/ { in_rationale = 0 }
        in_entry && in_rationale && /#[0-9]/ { has_ref = 1 }
        END {
            if (in_entry && found_rationale && !has_ref) missing_ref++
            exit (missing_ref > 0) ? 1 : 0
        }
    ' "$CATALOG"
}

@test "orchestration-fallbacks: catalog references #319 (tier 2 consumer)" {
    grep -q '#319' "$CATALOG"
}
