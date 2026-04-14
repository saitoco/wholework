#!/bin/bash
# setup-labels.sh
# Creates status/* labels and triage-related labels in the repository
#
# Usage:
#   scripts/setup-labels.sh
#
# Uses gh label create --force, so existing labels will be overwritten.

set -euo pipefail

# Label definitions: "name|color|description"
LABELS=(
    "phase/issue|#1B4F8A|Issue phase"
    "phase/spec|#1B4F8A|Spec phase"
    "phase/ready|#1B4F8A|Spec complete, ready to implement"
    "phase/code|#1B4F8A|Implementation phase"
    "phase/review|#1B4F8A|Review phase"
    "phase/verify|#1B4F8A|Acceptance test phase"
    "triaged|#0E8A16|Triaged"
    "type/bug|#D73A4A|Type: bug"
    "type/feature|#0075CA|Type: feature"
    "type/task|#E4E669|Type: task"
)

for entry in "${LABELS[@]}"; do
    IFS='|' read -r name color description <<< "$entry"
    gh label create "$name" --color "${color#\#}" --description "$description" --force
done

echo "Label setup complete (${#LABELS[@]} labels)"
