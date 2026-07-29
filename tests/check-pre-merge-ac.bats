#!/usr/bin/env bats

# Tests for check-pre-merge-ac.sh
# Mock gh command via PATH

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/check-pre-merge-ac.sh"

setup() {
    cd "$PROJECT_ROOT"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

# make_gh_mock_body: gh mock that prints the given body text regardless of arguments
# Usage: make_gh_mock_body <<'BODY' ... BODY
make_gh_mock_body() {
    local body_file="$BATS_TEST_TMPDIR/body.txt"
    cat > "$body_file"
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
cat "$body_file"
MOCK
    chmod +x "$MOCK_DIR/gh"
}

@test "error: no arguments exits with code 1" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "error: non-numeric issue number exits with code 1" {
    run bash "$SCRIPT" "abc"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "error: too many arguments exits with code 1" {
    run bash "$SCRIPT" "1" "2"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "(a) all pre-merge checkboxes checked returns unchecked_count 0" {
    make_gh_mock_body <<'BODY'
## Acceptance Criteria

### Pre-merge (auto-verified)

- [x] item one
- [x] item two

### Post-merge

- [ ] post item
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.resolved')" = "true" ]
    [ "$(echo "$result" | jq -r '.pre_merge_total')" = "2" ]
    [ "$(echo "$result" | jq -r '.unchecked_count')" = "0" ]
    [ "$(echo "$result" | jq -r '.unchecked_indices')" = "" ]
    [ "$(echo "$result" | jq -c '.unchecked_items')" = "[]" ]
}

@test "(b) pre-merge unchecked 2 + post-merge unchecked 1 excludes post-merge index" {
    make_gh_mock_body <<'BODY'
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] pre item one
- [x] pre item two
- [ ] pre item three

### Post-merge

- [ ] post item
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.pre_merge_total')" = "3" ]
    [ "$(echo "$result" | jq -r '.unchecked_count')" = "2" ]
    [ "$(echo "$result" | jq -r '.unchecked_indices')" = "1,3" ]
    # index 4 (post item) must not appear in unchecked_indices
    [[ "$(echo "$result" | jq -r '.unchecked_indices')" != *"4"* ]]
}

@test "(c) no Pre-merge heading returns pre_merge_total 0" {
    make_gh_mock_body <<'BODY'
## Acceptance Criteria

- [ ] item one
- [x] item two
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.resolved')" = "true" ]
    [ "$(echo "$result" | jq -r '.pre_merge_total')" = "0" ]
    [ "$(echo "$result" | jq -r '.unchecked_count')" = "0" ]
}

@test "(d) gh failure returns resolved false with exit 0" {
    printf '#!/bin/bash\nexit 1\n' > "$MOCK_DIR/gh"
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.resolved')" = "false" ]
    [ "$(echo "$output" | jq -r '.pre_merge_total')" = "0" ]
    [ "$(echo "$output" | jq -r '.unchecked_count')" = "0" ]
}

@test "(d) empty body returns resolved false with exit 0" {
    printf '#!/bin/bash\necho -n ""\n' > "$MOCK_DIR/gh"
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.resolved')" = "false" ]
}

@test "(e) invalid argument exits with code 1" {
    run bash "$SCRIPT" "-1"
    [ "$status" -eq 1 ]
}

@test "(f) global index counts checkboxes outside Acceptance Criteria too" {
    make_gh_mock_body <<'BODY'
## Some Other Section

- [ ] outside item zero

## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] pre item one
- [x] pre item two

### Post-merge

- [ ] post item

## Notes

- [ ] outside item after
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    # global index: 1=outside item zero, 2=pre item one, 3=pre item two, 4=post item, 5=outside item after
    [ "$(echo "$result" | jq -r '.pre_merge_total')" = "2" ]
    [ "$(echo "$result" | jq -r '.unchecked_count')" = "1" ]
    [ "$(echo "$result" | jq -r '.unchecked_indices')" = "2" ]
    [ "$(echo "$result" | jq -r '.unchecked_items[0].index')" = "2" ]
    [ "$(echo "$result" | jq -r '.unchecked_items[0].text')" = "pre item one" ]
}

@test "text strips HTML comments and marker" {
    make_gh_mock_body <<'BODY'
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: rubric "x" --> <!-- ac-tier: preview --> visible text here
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.unchecked_items[0].text')" = "visible text here" ]
}

@test "text strips HTML comment containing a > character" {
    make_gh_mock_body <<'BODY'
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: command "python3 bin/daily_routine.py 2>&1 | grep foo" --> new column appears
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.unchecked_items[0].text')" = "new column appears" ]
}

@test "large Pre-merge body (>64KB following heading) still resolves the section" {
    {
        echo "## Acceptance Criteria"
        echo
        echo "### Pre-merge (auto-verified)"
        echo
        echo "- [ ] pre item one"
        head -c 70000 < /dev/zero | tr '\0' 'x'
        echo
    } > "$BATS_TEST_TMPDIR/body.txt"
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
cat "$BATS_TEST_TMPDIR/body.txt"
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.pre_merge_total')" = "1" ]
    [ "$(echo "$result" | jq -r '.unchecked_count')" = "1" ]
}

@test "checkbox with no trailing space after bracket still strips prefix" {
    make_gh_mock_body <<'BODY'
## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ]
BODY
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    [ "$(echo "$result" | jq -r '.unchecked_items[0].text')" = "" ]
}

@test "CRLF body does not leave trailing carriage return in text" {
    printf '## Acceptance Criteria\r\n\r\n### Pre-merge (auto-verified)\r\n\r\n- [ ] item one\r\n' > "$BATS_TEST_TMPDIR/body.txt"
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
cat "$BATS_TEST_TMPDIR/body.txt"
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    result="$output"
    text="$(echo "$result" | jq -r '.unchecked_items[0].text')"
    [ "$text" = "item one" ]
}
