#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-bare-bracket-assertions.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/tests"
  cd "$BATS_TEST_TMPDIR"
}

# CI installs the Ubuntu-packaged bats (1.10.0), whose parser treats every line
# starting with `@test` as a test case -- including lines inside a heredoc. The
# fixtures below therefore inflated the suite's expected test count by 7 and left
# phantom entries in the run log that `bats --filter-status failed` could never
# re-run, which kept the serial re-run step failing regardless of real results.
# Fixtures spell the token AT_TEST; this helper restores it on the way to disk, so
# the file written for the checker is byte-identical to the previous fixtures.
write_fixture() {
  sed 's/^AT_TEST /@test /' > "$1"
}

@test "clean: single-bracket assertion produces no detection" {
  write_fixture tests/clean.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "clean example" {
  run echo "hi"
  [ "$output" = "hi" ]
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"No bare"*) ;;
    *) echo "unexpected output: $output" >&2; return 1 ;;
  esac
}

@test "clean: double-bracket assertion with || false produces no detection" {
  write_fixture tests/clean2.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "clean example with double bracket" {
  run echo "hi"
  [[ "$output" == "hi" ]] || false
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"No bare"*) ;;
    *) echo "unexpected output: $output" >&2; return 1 ;;
  esac
}

@test "detection: bare double-bracket \$output assertion is flagged" {
  write_fixture tests/bad.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "bad example" {
  run echo "hi"
  [[ "$output" == "hi" ]]
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"tests/bad.bats"*) ;;
    *) echo "expected detection of tests/bad.bats, got: $output" >&2; return 1 ;;
  esac
  case "$output" in
    *"Warning: 1 bare"*) ;;
    *) echo "expected warning count 1, got: $output" >&2; return 1 ;;
  esac
}

@test "detection: bare double-bracket \$status assertion is flagged" {
  write_fixture tests/bad_status.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "bad status example" {
  run echo "hi"
  [[ "$status" -eq 0 ]]
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"tests/bad_status.bats"*) ;;
    *) echo "expected detection of tests/bad_status.bats, got: $output" >&2; return 1 ;;
  esac
}

@test "clean: backslash-continued || false on next line produces no detection" {
  write_fixture tests/clean3.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "clean example with continuation" {
  run echo "hi"
  [[ "$output" == "hi" ]] \
    || false
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"No bare"*) ;;
    *) echo "unexpected output: $output" >&2; return 1 ;;
  esac
}

@test "detection: backslash continuation without || false on next line is still flagged" {
  write_fixture tests/bad_continuation.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "bad example with continuation" {
  run echo "hi"
  [[ "$output" == "hi" ]] \
    && echo "matched"
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"tests/bad_continuation.bats"*) ;;
    *) echo "expected detection of tests/bad_continuation.bats, got: $output" >&2; return 1 ;;
  esac
}

@test "self-exclusion: check-bare-bracket-assertions.bats fixture is excluded" {
  write_fixture tests/check-bare-bracket-assertions.bats <<'EOF'
#!/usr/bin/env bats
AT_TEST "self reference example" {
  run echo "hi"
  [[ "$output" == "hi" ]]
}
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"No bare"*) ;;
    *) echo "expected self-exclusion (no detection), got: $output" >&2; return 1 ;;
  esac
}
