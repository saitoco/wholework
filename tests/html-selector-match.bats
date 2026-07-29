#!/usr/bin/env bats

# Tests for scripts/html-selector-match.py
# Feeds HTML fixtures via stdin and runs the script as a subprocess.

REAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/html-selector-match.py"

@test "simple tag selector matches all matching elements" {
    run bash -c "printf '<div></div><p></p><div></div>' | python3 '$REAL_SCRIPT' 'div'"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "class selector matches elements containing the class" {
    run bash -c "printf '<div class=\"a b\"></div><div class=\"b\"></div>' | python3 '$REAL_SCRIPT' '.a'"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "attribute value selector matches exact attribute value" {
    run bash -c "printf '<input data-testid=\"signup\"><input data-testid=\"login\">' | python3 '$REAL_SCRIPT' \"[data-testid='signup']\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "compound tag.class[attr=value] selector matches downstream-like fixture" {
    run bash -c "printf '<form class=\"kf-form\" data-testid=\"signup\"></form><form class=\"other\"></form>' | python3 '$REAL_SCRIPT' \"form.kf-form[data-testid='signup']\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "selector with no matching elements returns 0 with exit code 0" {
    run bash -c "printf '<div></div>' | python3 '$REAL_SCRIPT' 'span'"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "invalid selector syntax exits non-zero with empty stdout" {
    run bash -c "printf '<div></div>' | python3 '$REAL_SCRIPT' 'div>>bad' 2>/dev/null"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "empty stdin returns 0 with exit code 0 (not treated as an error)" {
    run bash -c "printf '' | python3 '$REAL_SCRIPT' 'div'"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}
