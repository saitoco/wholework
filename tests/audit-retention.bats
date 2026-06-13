#!/usr/bin/env bats

# Tests for scripts/compute-escalation-level.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/compute-escalation-level.sh"

# --- verify type ---

@test "verify: 29 days returns level 0" {
  run bash "$SCRIPT" verify 29
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "verify: 30 days returns level 1" {
  run bash "$SCRIPT" verify 30
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "verify: 59 days returns level 1" {
  run bash "$SCRIPT" verify 59
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "verify: 60 days returns level 2" {
  run bash "$SCRIPT" verify 60
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "verify: 89 days returns level 2" {
  run bash "$SCRIPT" verify 89
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "verify: 90 days returns level 3" {
  run bash "$SCRIPT" verify 90
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "verify: 0 days returns level 0" {
  run bash "$SCRIPT" verify 0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# --- icebox type ---

@test "icebox: 89 days returns level 0" {
  run bash "$SCRIPT" icebox 89
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "icebox: 90 days returns level 1" {
  run bash "$SCRIPT" icebox 90
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "icebox: 179 days returns level 1" {
  run bash "$SCRIPT" icebox 179
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "icebox: 180 days returns level 2" {
  run bash "$SCRIPT" icebox 180
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "icebox: 0 days returns level 0" {
  run bash "$SCRIPT" icebox 0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# --- error handling ---

@test "invalid type exits with status 1" {
  run bash "$SCRIPT" unknown 10
  [ "$status" -eq 1 ]
}

@test "missing arguments exits with status 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "non-numeric days exits with status 1" {
  run bash "$SCRIPT" verify abc
  [ "$status" -eq 1 ]
}
