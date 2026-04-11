#!/bin/bash
# phase-banner.sh — sourceable helper for run-*.sh phase banner display
# Usage: source this file, then call print_start_banner / print_end_banner

# Fetch and cache title/URL for the given entity
# Args: entity_type ("issue"|"pr"), entity_number
_fetch_entity_info() {
  local entity_type="$1" entity_number="$2"
  if [[ "$entity_type" == "pr" ]]; then
    _ENTITY_TITLE=$(gh pr view "$entity_number" --json title -q '.title' 2>/dev/null || echo "")
    _ENTITY_URL=$(gh pr view "$entity_number" --json url -q '.url' 2>/dev/null || echo "")
  else
    _ENTITY_TITLE=$(gh issue view "$entity_number" --json title -q '.title' 2>/dev/null || echo "")
    _ENTITY_URL=$(gh issue view "$entity_number" --json url -q '.url' 2>/dev/null || echo "")
  fi
}

# Print start banner with title/URL
# Args: entity_type ("issue"|"pr"), entity_number
print_start_banner() {
  local entity_type="$1" entity_number="$2"
  _fetch_entity_info "$entity_type" "$entity_number"
  local label; [[ "$entity_type" == "pr" ]] && label="PR" || label="Issue"
  echo "${label}: #${entity_number} ${_ENTITY_TITLE}"
  echo "URL: ${_ENTITY_URL}"
}

# Print end banner with cached title/URL
# Args: entity_type ("issue"|"pr"), entity_number
print_end_banner() {
  local entity_type="$1" entity_number="$2"
  local label; [[ "$entity_type" == "pr" ]] && label="PR" || label="Issue"
  echo "${label}: #${entity_number} ${_ENTITY_TITLE}"
  echo "URL: ${_ENTITY_URL}"
}
