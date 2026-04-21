#!/usr/bin/env bats

# Tests for scripts/collect-recovery-candidates.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/collect-recovery-candidates.sh"
FIXTURE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures/orchestration-recoveries-sample.md"
ISSUES_JSON_NO_MATCH="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures/open-issues-sample.json"
ISSUES_JSON_WITH_GH_PR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures/open-issues-with-gh-pr.json"

@test "parse: extract entries and count symptom frequencies correctly" {
  # With threshold=1, all non-excluded symptoms appear.
  # gh-pr-list-head-glob: 3 occurrences (all 未起票) -> count 3
  # code-pr-extraction-fail: 3 occurrences (all 未起票) -> count 3
  # merge-conflict-rebase-fail: 1 occurrence (N/A) -> count 1
  # verify-timeout-exceeded: 3 occurrences but one is 起票済み -> excluded
  run bash "$SCRIPT" "$FIXTURE" --threshold 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "gh-pr-list-head-glob"
  echo "$output" | grep -qF "code-pr-extraction-fail"
  echo "$output" | grep -qF "merge-conflict-rebase-fail"
  # verify count values via tab-separated format
  echo "$output" | grep -E $'^gh-pr-list-head-glob\t3$'
  echo "$output" | grep -E $'^code-pr-extraction-fail\t3$'
  echo "$output" | grep -E $'^merge-conflict-rebase-fail\t1$'
}

@test "threshold: K=3 filters to exactly 2 candidates" {
  # With default threshold=3, only symptoms with count >= 3 pass.
  # gh-pr-list-head-glob (3) and code-pr-extraction-fail (3) pass.
  # merge-conflict-rebase-fail (1) is filtered out.
  # verify-timeout-exceeded is excluded by 起票済み.
  run bash "$SCRIPT" "$FIXTURE" --threshold 3
  [ "$status" -eq 0 ]
  line_count=$(echo "$output" | grep -c $'.\t[0-9]' || true)
  [ "$line_count" -eq 2 ]
  echo "$output" | grep -qF "gh-pr-list-head-glob"
  echo "$output" | grep -qF "code-pr-extraction-fail"
  ! echo "$output" | grep -qF "merge-conflict-rebase-fail"
}

@test "exclusion: entries with filed improvement candidate are excluded" {
  # verify-timeout-exceeded has one entry with 起票済み #311 -> must not appear in output.
  run bash "$SCRIPT" "$FIXTURE" --threshold 1
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "verify-timeout-exceeded"
}

@test "issues-json: symptom-short matching an open issue title is excluded" {
  # open-issues-with-gh-pr.json contains a title with gh-pr-list-head-glob.
  # So gh-pr-list-head-glob must be excluded despite having count >= 3.
  # code-pr-extraction-fail is not in the issues JSON so it still appears.
  run bash "$SCRIPT" "$FIXTURE" --threshold 3 --issues-json "$ISSUES_JSON_WITH_GH_PR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "gh-pr-list-head-glob"
  echo "$output" | grep -qF "code-pr-extraction-fail"
}
