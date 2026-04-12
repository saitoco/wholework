#!/usr/bin/env bats
# Tests for scripts/phase-banner.sh

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

setup() {
  # Mock gh command to avoid real API calls
  gh() {
    local subcommand="$1"
    local entity_type="$2"
    local number="$3"
    if [[ "$subcommand" == "issue" && "$4" == "view" ]]; then
      number="$3"
      if [[ "$5 $6" == "--json title" || "$5" == "--json" && "$6" == "title" ]]; then
        echo "Test Issue Title"
      elif [[ "$5 $6" == "--json url" || "$5" == "--json" && "$6" == "url" ]]; then
        echo "https://github.com/example/repo/issues/${number}"
      fi
    elif [[ "$subcommand" == "pr" && "$4" == "view" ]]; then
      number="$3"
      if [[ "$5 $6" == "--json title" || "$5" == "--json" && "$6" == "title" ]]; then
        echo "Test PR Title"
      elif [[ "$5 $6" == "--json url" || "$5" == "--json" && "$6" == "url" ]]; then
        echo "https://github.com/example/repo/pull/${number}"
      fi
    fi
  }
  export -f gh

  # Source the script under test
  # shellcheck source=../scripts/phase-banner.sh
  source "$SCRIPT_DIR/phase-banner.sh"
}

@test "print_start_banner outputs unified format for issue" {
  # Mock _fetch_entity_info to set known values
  _ENTITY_TITLE="Test Issue Title"
  _ENTITY_URL="https://github.com/example/repo/issues/42"

  run print_start_banner "issue" "42" "code"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/code #42" ]
  [ "${lines[1]}" = "Test Issue Title" ]
  [ "${lines[2]}" = "https://github.com/example/repo/issues/42" ]
}

@test "print_start_banner outputs unified format for pr" {
  _ENTITY_TITLE="Test PR Title"
  _ENTITY_URL="https://github.com/example/repo/pull/88"

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
  _ENTITY_TITLE="Test Title"
  _ENTITY_URL="https://github.com/example/repo/issues/1"

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
  _ENTITY_TITLE="Test Issue Title"
  _ENTITY_URL="https://github.com/example/repo/issues/42"

  run print_start_banner "issue" "42" "spec"

  [ "$status" -eq 0 ]
  [[ "${output}" != *"Issue:"* ]]
}

@test "output does not contain URL: prefix" {
  _ENTITY_TITLE="Test Issue Title"
  _ENTITY_URL="https://github.com/example/repo/issues/42"

  run print_start_banner "issue" "42" "spec"

  [ "$status" -eq 0 ]
  [[ "${output}" != *"URL:"* ]]
}
