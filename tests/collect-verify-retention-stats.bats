#!/usr/bin/env bats

# Direct unit tests for scripts/collect-verify-retention-stats.sh
# Covers the aggregation path only (--from-cache), so no `gh` access is needed.
# The fetch path is exercised in real runs; the parts worth protecting here are
# the verify-type tag extraction and the window/age arithmetic.
# All tests use inline fixtures via BATS_TEST_TMPDIR.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/collect-verify-retention-stats.sh"

setup() {
  CACHE="$BATS_TEST_TMPDIR/cache.tsv"
}

# Cache columns:
#   1 number  2 createdAt  3 kind  4 obs_u  5 opp_u  6 man_u  7 auto_u
#   8 obs_c   9 opp_c     10 man_c 11 auto_c
write_cache() {
  printf '%s\n' "$@" > "$CACHE"
}

@test "usage error: unknown argument exits 1" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "usage error: invalid --format exits 1" {
  run bash "$SCRIPT" --format json --from-cache --cache "$CACHE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--format must be"* ]]
}

@test "usage error: invalid --window shape exits 1" {
  run bash "$SCRIPT" --window 2026/05/07 --from-cache --cache "$CACHE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--window must be YYYY-MM-DD"* ]]
}

@test "--from-cache with missing cache exits 1" {
  run bash "$SCRIPT" --from-cache --cache "$BATS_TEST_TMPDIR/absent.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cache not found"* ]]
}

@test "empty cache: all counters are zero and exit 0" {
  : > "$CACHE"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07 --format tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting	total_issues_all	0"* ]]
  [[ "$output" == *"resolved	total_issues_all	0"* ]]
}

@test "waiting counts split by verify-type" {
  write_cache \
    "$(printf '101\t2026-06-01T00:00:00Z\twaiting\t2\t0\t0\t0\t0\t0\t0\t0')" \
    "$(printf '102\t2026-06-02T00:00:00Z\twaiting\t0\t1\t0\t0\t0\t0\t0\t0')" \
    "$(printf '103\t2026-06-03T00:00:00Z\twaiting\t0\t0\t3\t0\t0\t0\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07 --format tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting	observation_lines_all	2"* ]]
  [[ "$output" == *"waiting	observation_issues_all	1"* ]]
  [[ "$output" == *"waiting	opportunistic_lines_all	1"* ]]
  [[ "$output" == *"waiting	manual_lines_all	3"* ]]
  [[ "$output" == *"waiting	total_issues_all	3"* ]]
}

@test "window filter: Issues created before the window are excluded from windowed counts" {
  write_cache \
    "$(printf '201\t2026-01-15T00:00:00Z\twaiting\t1\t0\t0\t0\t0\t0\t0\t0')" \
    "$(printf '202\t2026-06-15T00:00:00Z\twaiting\t1\t0\t0\t0\t0\t0\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07 --format tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting	observation_issues_all	2"* ]]
  [[ "$output" == *"waiting	observation_issues_window	1"* ]]
  [[ "$output" == *"waiting	observation_issues_older_than_window	1"* ]]
}

@test "resolved counts come from the checked columns, not the unchecked ones" {
  write_cache \
    "$(printf '301\t2026-06-01T00:00:00Z\tresolved\t0\t0\t0\t0\t2\t1\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07 --format tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *"resolved	observation_lines_all	2"* ]]
  [[ "$output" == *"resolved	opportunistic_lines_all	1"* ]]
  [[ "$output" == *"resolved	manual_lines_all	0"* ]]
  [[ "$output" == *"waiting	observation_lines_all	0"* ]]
}

@test "no-unchecked-AC waiting Issues are counted separately" {
  write_cache \
    "$(printf '401\t2026-06-01T00:00:00Z\twaiting\t0\t0\t0\t0\t0\t0\t0\t0')" \
    "$(printf '402\t2026-06-02T00:00:00Z\twaiting\t1\t0\t0\t0\t0\t0\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07 --format tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting	no_unchecked_ac_all	1"* ]]
}

@test "text format renders the three sections and the window start" {
  write_cache \
    "$(printf '501\t2026-06-01T00:00:00Z\twaiting\t1\t0\t0\t0\t0\t0\t0\t0')" \
    "$(printf '502\t2026-06-02T00:00:00Z\tresolved\t0\t0\t0\t0\t1\t0\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07
  [ "$status" -eq 0 ]
  [[ "$output" == *"window start: 2026-05-07"* ]]
  [[ "$output" == *"## 1. Waiting"* ]]
  [[ "$output" == *"## 2. Resolved"* ]]
  [[ "$output" == *"## 3. Resolution rate and age of waiting"* ]]
}

@test "resolution rate is resolved/(resolved+waiting) within the window" {
  # 3 resolved + 1 waiting -> 75%
  write_cache \
    "$(printf '601\t2026-06-01T00:00:00Z\tresolved\t0\t0\t0\t0\t1\t0\t0\t0')" \
    "$(printf '602\t2026-06-01T00:00:00Z\tresolved\t0\t0\t0\t0\t1\t0\t0\t0')" \
    "$(printf '603\t2026-06-01T00:00:00Z\tresolved\t0\t0\t0\t0\t1\t0\t0\t0')" \
    "$(printf '604\t2026-06-01T00:00:00Z\twaiting\t1\t0\t0\t0\t0\t0\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07
  [ "$status" -eq 0 ]
  [[ "$output" == *"| observation | 3 | 1 | 75% |"* ]]
}

@test "resolution rate is n/a when a verify-type has no data" {
  write_cache \
    "$(printf '701\t2026-06-01T00:00:00Z\twaiting\t1\t0\t0\t0\t0\t0\t0\t0')"

  run bash "$SCRIPT" --from-cache --cache "$CACHE" --window 2026-05-07
  [ "$status" -eq 0 ]
  [[ "$output" == *"| opportunistic | 0 | 0 | n/a |"* ]]
}
