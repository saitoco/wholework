#!/bin/bash
# setup-labels.sh
# Creates Wholework-managed labels in the repository (SSoT for all label definitions)
#
# Usage:
#   scripts/setup-labels.sh [--force] [--no-fallback]
#
# Options:
#   --force         Overwrite existing labels (default: skip labels that already exist)
#   --no-fallback   Skip environment detection; only create always-group labels
#
# Label groups:
#   Always-group (11 labels): phase/*, triaged, retro/verify, audit/drift, audit/fragility
#   Fallback-group (17 labels): type/*, priority/*, size/*, value/*
#     Created when corresponding GitHub feature (Issue Types / Projects field) is unavailable.
#     Use --no-fallback to skip environment detection and omit this group entirely.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse flags
FORCE=false
NO_FALLBACK=false
for arg in "$@"; do
    case "$arg" in
        --force)       FORCE=true ;;
        --no-fallback) NO_FALLBACK=true ;;
        --help|-h)
            sed -n '/^# Usage/,/^$/p' "$0"
            exit 0
            ;;
        *)
            echo "Error: unknown option: $arg" >&2
            echo "Usage: $0 [--force] [--no-fallback]" >&2
            exit 1
            ;;
    esac
done

# Always-group labels: created unconditionally on every run
# Format: "name|color(without #)|description"
ALWAYS_LABELS=(
    "phase/issue|1B4F8A|Issue phase"
    "phase/spec|1B4F8A|Spec phase"
    "phase/ready|1B4F8A|Spec complete, ready to implement"
    "phase/code|1B4F8A|Implementation phase"
    "phase/review|1B4F8A|Review phase"
    "phase/verify|1B4F8A|Acceptance test phase"
    "phase/done|1B4F8A|Complete"
    "triaged|0E8A16|Triaged"
    "retro/verify|5319E7|Verify retrospective attached"
    "audit/drift|D93F0B|Audit: documentation drift detected"
    "audit/fragility|E4E669|Audit: structural fragility detected"
)

# Fallback-group labels: created when GitHub feature is unavailable
# Each entry has an inline comment explaining the detection condition.
# Format: "name|color(without #)|description"
FALLBACK_LABELS=(
    # Condition: GitHub Issue Types unavailable (detect_issue_types returns false)
    "type/bug|D73A4A|Type: bug"
    "type/feature|0075CA|Type: feature"
    "type/task|E4E669|Type: task"
    # Condition: Projects V2 Priority field not found (detect_projects_field Priority returns false)
    "priority/urgent|B60205|Priority: urgent"
    "priority/high|E4E669|Priority: high"
    "priority/medium|FBCA04|Priority: medium"
    "priority/low|CFD3D7|Priority: low"
    # Condition: Projects V2 Size field not found (detect_projects_field Size returns false)
    "size/XS|BFD4F2|Size: extra small"
    "size/S|BFD4F2|Size: small"
    "size/M|BFD4F2|Size: medium"
    "size/L|BFD4F2|Size: large"
    "size/XL|BFD4F2|Size: extra large"
    # Condition: Projects V2 Value field not found (detect_projects_field Value returns false)
    "value/1|BFD4F2|Value: 1"
    "value/2|BFD4F2|Value: 2"
    "value/3|BFD4F2|Value: 3"
    "value/4|BFD4F2|Value: 4"
    "value/5|BFD4F2|Value: 5"
)

# Detect whether GitHub Issue Types feature is available
# Returns 0 (true) if Issue Types are configured, 1 (false) otherwise
detect_issue_types() {
    local count
    count=$("$SCRIPT_DIR/gh-graphql.sh" --query get-issue-types \
        --jq '.data.repository.issueTypes.nodes | length' 2>/dev/null) || return 1
    [ "${count:-0}" -ge 1 ]
}

# Detect whether a named Projects V2 field is configured
# Usage: detect_projects_field "Size"
# Returns 0 (true) if field found, 1 (false) otherwise
detect_projects_field() {
    local field_name="$1"
    local count
    count=$("$SCRIPT_DIR/gh-graphql.sh" --query get-projects-with-fields \
        --jq "[.data.repository.projectsV2.nodes[].fields.nodes[] | select(.name==\"${field_name}\")] | length" \
        2>/dev/null) || return 1
    [ "${count:-0}" -ge 1 ]
}

# Fetch existing label names (one per line) for idempotent check-then-create
EXISTING_LABELS=""
EXISTING_LABELS=$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null) || true

# Check if a label already exists in the repo
label_exists() {
    local name="$1"
    echo "$EXISTING_LABELS" | grep -qx "$name"
}

# Create a single label (check-then-create, --force flag controls overwrite behavior)
create_label() {
    local name="$1"
    local color="$2"
    local description="$3"

    if [ "$FORCE" = true ]; then
        gh label create "$name" --color "$color" --description "$description" --force
    elif label_exists "$name"; then
        : # skip — label already exists and --force not specified
    else
        gh label create "$name" --color "$color" --description "$description"
    fi
}

CREATED_COUNT=0

# Always-group: create unconditionally
for entry in "${ALWAYS_LABELS[@]}"; do
    IFS='|' read -r name color description <<< "$entry"
    create_label "$name" "$color" "$description"
    CREATED_COUNT=$(( CREATED_COUNT + 1 ))
done

# Fallback-group: create based on environment detection (skip with --no-fallback)
if [ "$NO_FALLBACK" = false ]; then
    # Detect GitHub features once; treat detection failure as "unavailable"
    HAS_ISSUE_TYPES=false
    detect_issue_types && HAS_ISSUE_TYPES=true || true

    HAS_PRIORITY_FIELD=false
    detect_projects_field "Priority" && HAS_PRIORITY_FIELD=true || true

    HAS_SIZE_FIELD=false
    detect_projects_field "Size" && HAS_SIZE_FIELD=true || true

    HAS_VALUE_FIELD=false
    detect_projects_field "Value" && HAS_VALUE_FIELD=true || true

    for entry in "${FALLBACK_LABELS[@]}"; do
        IFS='|' read -r name color description <<< "$entry"
        case "$name" in
            type/*)
                [ "$HAS_ISSUE_TYPES" = true ] && continue || true ;;
            priority/*)
                [ "$HAS_PRIORITY_FIELD" = true ] && continue || true ;;
            size/*)
                [ "$HAS_SIZE_FIELD" = true ] && continue || true ;;
            value/*)
                [ "$HAS_VALUE_FIELD" = true ] && continue || true ;;
        esac
        create_label "$name" "$color" "$description"
        CREATED_COUNT=$(( CREATED_COUNT + 1 ))
    done
fi

echo "Label setup complete (${CREATED_COUNT} labels processed)"
