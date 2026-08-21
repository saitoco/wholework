#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-bare-bracket-assertions.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/tests"
  cd "$BATS_TEST_TMPDIR"
}

@test "clean: single-bracket assertion produces no detection" {
  cat > tests/clean.bats <<'EOF'
#!/usr/bin/env bats
@test "clean example" {
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
  cat > tests/clean2.bats <<'EOF'
#!/usr/bin/env bats
@test "clean example with double bracket" {
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
  cat > tests/bad.bats <<'EOF'
#!/usr/bin/env bats
@test "bad example" {
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
  cat > tests/bad_status.bats <<'EOF'
#!/usr/bin/env bats
@test "bad status example" {
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

@test "self-exclusion: check-bare-bracket-assertions.bats fixture is excluded" {
  cat > tests/check-bare-bracket-assertions.bats <<'EOF'
#!/usr/bin/env bats
@test "self reference example" {
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
