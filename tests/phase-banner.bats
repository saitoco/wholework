#!/usr/bin/env bats
# Tests for scripts/phase-banner.sh

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

setup() {
  source "$SCRIPT_DIR/phase-banner.sh"
  # Override _fetch_entity_info to avoid real API calls
  _fetch_entity_info() {
    local entity_type="$1" entity_number="$2"
    if [[ "$entity_type" == "pr" ]]; then
      _ENTITY_TITLE="Test PR Title"
      _ENTITY_URL="https://github.com/example/repo/pull/${entity_number}"
    else
      _ENTITY_TITLE="Test Issue Title"
      _ENTITY_URL="https://github.com/example/repo/issues/${entity_number}"
    fi
  }
}

@test "print_start_banner outputs unified format for issue" {
  run print_start_banner "issue" "42" "code"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/code #42" ]
  [ "${lines[1]}" = "Test Issue Title" ]
  [ "${lines[2]}" = "https://github.com/example/repo/issues/42" ]
}

@test "print_start_banner outputs unified format for pr" {
  run print_start_banner "pr" "88" "review"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/review #88" ]
  [ "${lines[1]}" = "Test PR Title" ]
  [ "${lines[2]}" = "https://github.com/example/repo/pull/88" ]
}

@test "print_end_banner outputs unified format for issue" {
  _ENTITY_TITLE="Test Issue Title"
  _ENTITY_URL="https://github.com/example/repo/issues/42"

  run print_end_banner "issue" "42" "verify"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/verify #42" ]
  [ "${lines[1]}" = "Test Issue Title" ]
  [ "${lines[2]}" = "https://github.com/example/repo/issues/42" ]
}

@test "print_end_banner outputs unified format for pr" {
  _ENTITY_TITLE="Test PR Title"
  _ENTITY_URL="https://github.com/example/repo/pull/88"

  run print_end_banner "pr" "88" "merge"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/merge #88" ]
  [ "${lines[1]}" = "Test PR Title" ]
  [ "${lines[2]}" = "https://github.com/example/repo/pull/88" ]
}

@test "print_start_banner with missing third argument does not error" {
  run print_start_banner "issue" "1"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/ #1" ]
}

@test "print_end_banner with missing third argument does not error" {
  _ENTITY_TITLE="Test Title"
  _ENTITY_URL="https://github.com/example/repo/issues/1"

  run print_end_banner "issue" "1"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/ #1" ]
}

@test "output does not contain old Issue: prefix" {
  run print_start_banner "issue" "42" "spec"

  [ "$status" -eq 0 ]
  [[ "${output}" != *"Issue:"* ]]
}

@test "output does not contain URL: prefix" {
  run print_start_banner "issue" "42" "spec"

  [ "$status" -eq 0 ]
  [[ "${output}" != *"URL:"* ]]
}
