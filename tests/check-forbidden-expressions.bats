#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-forbidden-expressions.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/skills"
  mkdir -p "$BATS_TEST_TMPDIR/modules"
  mkdir -p "$BATS_TEST_TMPDIR/agents"
  mkdir -p "$BATS_TEST_TMPDIR/tests"
  mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
  cd "$BATS_TEST_TMPDIR"
}

@test "no violations: clean directory exits 0" {
  echo "clean content" > skills/clean.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "detection: deprecated term in skills dir exits 1" {
  echo "use verification hint here" > skills/bad.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verification hint"* ]]
}

@test "detection: term in docs/spec exits 1" {
  echo "use verification hint here" > docs/spec/spec.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "exclusion: line with Formerly called exits 0" {
  echo "Formerly called verification hint" > skills/note.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "exclusion: line with kyusho Japanese legacy marker exits 0" {
  echo "verification hint の旧称" > modules/note.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "false positive: Issue Specification is not flagged" {
  echo "# Issue Specification" > skills/spec.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "false positive: design files plural is not flagged" {
  echo "Figma design files are useful" > docs/guide.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "false positive: lowercase dispatch prose is not flagged" {
  echo "command dispatch mechanism" > docs/report.md
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "detection: acceptance check exits 1" {
  echo "this is an acceptance check" > modules/bad.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detection: Dispatch capital D exits 1" {
  echo "The Dispatch feature was removed" > docs/guide.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detection: Design file exact match exits 1" {
  echo "use Design file format" > docs/guide.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detection: Issue Spec exact match exits 1" {
  echo "Do not use Issue Spec format" > docs/guide.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detection: verify hint exits 1" {
  echo "use verify hint here" > skills/bad.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detection: verify katakana hint exits 1" {
  echo "use verify ヒント here" > skills/bad.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detection: kensho hint exits 1" {
  echo "use 検証ヒント here" > skills/bad.md
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}
