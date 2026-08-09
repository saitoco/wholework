#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-known-events-firing.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/scripts"
  mkdir -p "$BATS_TEST_TMPDIR/skills"
  mkdir -p "$BATS_TEST_TMPDIR/modules"
  cd "$BATS_TEST_TMPDIR"
}

@test "all events have real invocation sites: exits 0" {
  echo 'KNOWN_EVENTS="test-event-alpha test-event-beta"' > scripts/opportunistic-search.sh
  echo '"${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh" --event test-event-alpha' > scripts/caller-a.sh
  echo 'Run `observation-trigger.sh --event test-event-beta`' > skills/caller-b.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "event only present in a comment line: detected as missing (false-positive regression guard)" {
  echo 'KNOWN_EVENTS="test-event-gamma"' > scripts/opportunistic-search.sh
  echo '# example: scripts/observation-trigger.sh --event test-event-gamma' > scripts/note.sh
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-event-gamma"* ]]
}

@test "event only present in an echo usage string: detected as missing (false-positive regression guard)" {
  echo 'KNOWN_EVENTS="test-event-delta"' > scripts/opportunistic-search.sh
  echo 'echo "usage: $0 --event test-event-delta" >&2' > scripts/note.sh
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-event-delta"* ]]
}

@test "event only present in a printf usage string: detected as missing (false-positive regression guard)" {
  echo 'KNOWN_EVENTS="test-event-zeta"' > scripts/opportunistic-search.sh
  echo 'printf "usage: %s --event test-event-zeta\n" "$0" >&2' > scripts/note.sh
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-event-zeta"* ]]
}

@test "event with a real invocation alongside comment/usage noise: correctly detected (not missing)" {
  echo 'KNOWN_EVENTS="test-event-epsilon"' > scripts/opportunistic-search.sh
  echo '# doc example: --event test-event-epsilon' > scripts/note-comment.sh
  echo 'echo "usage: --event test-event-epsilon" >&2' > scripts/note-usage.sh
  echo 'observation-trigger.sh --event test-event-epsilon' > modules/caller.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "multiple events, one missing: exits 1 and names only the missing event" {
  echo 'KNOWN_EVENTS="test-event-found test-event-lost"' > scripts/opportunistic-search.sh
  echo 'observation-trigger.sh --event test-event-found' > scripts/caller.sh
  echo '# --event test-event-lost' > scripts/note.sh
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-event-lost"* ]]
  [[ "$output" != *"test-event-found"* ]]
}

@test "missing source file: exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "source file without KNOWN_EVENTS assignment: exits 2" {
  echo 'echo "no known events here"' > scripts/opportunistic-search.sh
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
