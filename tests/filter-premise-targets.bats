#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for filter-premise-targets.sh
# The filter drops Issues whose implementation has already landed (phase/verify,
# phase/done) before /audit premise evaluates their premise markers. Input JSON is
# written to fixture files (heredoc with a quoted delimiter) and fed on stdin.

load 'helpers/markdown-section'

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/filter-premise-targets.sh"
EVALUATOR="$PROJECT_ROOT/scripts/check-premise-expiry.sh"
AUDIT_SKILL="$PROJECT_ROOT/skills/audit/SKILL.md"

setup() {
    FIXTURE="$BATS_TEST_TMPDIR/issues.json"
}

# --- exclusion (positive cases) ---

@test "excludes phase/verify and phase/done Issues and keeps the rest in order" {
    cat > "$FIXTURE" <<'EOF'
[
  {"number": 101, "title": "pending", "body": "text", "labels": [{"name": "phase/ready"}, {"name": "triaged"}]},
  {"number": 102, "title": "landed", "body": "text", "labels": [{"name": "phase/verify"}, {"name": "retro/verify"}]},
  {"number": 103, "title": "no labels key", "body": "text"},
  {"number": 104, "title": "done", "body": "text", "labels": [{"name": "phase/done"}]},
  {"number": 105, "title": "coding", "body": "text", "labels": [{"name": "phase/code"}]},
  {"number": 106, "title": "empty labels", "body": "text", "labels": []}
]
EOF
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -c '[.[].number]')" = "[101,103,105,106]" ]
    [[ "$stderr" == *"EXCLUDED: #102 (phase/verify)"* ]] || false
    [[ "$stderr" == *"EXCLUDED: #104 (phase/done)"* ]] || false
    if [[ "$stderr" == *"EXCLUDED: #101"* ]]; then false; fi
    if [[ "$stderr" == *"EXCLUDED: #103"* ]]; then false; fi
}

@test "an Issue carrying both phase labels is excluded once with both names" {
    cat > "$FIXTURE" <<'EOF'
[{"number": 108, "labels": [{"name": "phase/done"}, {"name": "phase/verify"}]}]
EOF
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    [ "$stderr" = "EXCLUDED: #108 (phase/done,phase/verify)" ]
}

# --- exact label match (negative cases) ---

@test "similar label names are not excluded" {
    cat > "$FIXTURE" <<'EOF'
[
  {"number": 201, "labels": [{"name": "retro/verify"}]},
  {"number": 202, "labels": [{"name": "phase/verify-extra"}]},
  {"number": 203, "labels": [{"name": "Phase/Verify"}]},
  {"number": 204, "labels": [{"name": "not-phase/verify"}]},
  {"number": 205, "labels": [{"name": "phase/done-ish"}]}
]
EOF
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -c '[.[].number]')" = "[201,202,203,204,205]" ]
    [ -z "$stderr" ]
}

@test "malformed labels shapes are kept" {
    cat > "$FIXTURE" <<'EOF'
[
  {"number": 301},
  {"number": 302, "labels": null},
  {"number": 303, "labels": []},
  {"number": 304, "labels": ["phase/verify"]},
  {"number": 305, "labels": {"name": "phase/done"}},
  {"number": 306, "labels": [42, null, {"id": "x"}]},
  42,
  "text"
]
EOF
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -c 'length')" = "8" ]
    [ -z "$stderr" ]
}

# --- pass-through fidelity ---

@test "kept elements are passed through unmodified" {
    cat > "$FIXTURE" <<'EOF'
[
  {"number": 401, "title": "keep", "body": "a > b \"quoted\" line\r\nsecond line\n日本語のテキスト", "labels": [{"name": "phase/code"}]},
  {"number": 402, "title": "drop", "body": "x", "labels": [{"name": "phase/verify"}]}
]
EOF
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    expected="$(jq -c '.[0]' "$FIXTURE")"
    actual="$(printf '%s' "$output" | jq -c '.[0]')"
    [ "$actual" = "$expected" ]
    body="$(printf '%s' "$output" | jq -r '.[0].body')"
    [[ "$body" == *'a > b "quoted" line'* ]] || false
    [[ "$body" == *"日本語のテキスト"* ]] || false
}

@test "empty array passes through as an empty array" {
    printf '[]\n' > "$FIXTURE"
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    [ -z "$stderr" ]
}

@test "large input: 300 Issues, every third one excluded" {
    jq -n '[range(0; 300) | {number: ., title: "t\(.)", body: ("x" * 1024), labels: [{name: (if . % 3 == 0 then "phase/verify" else "phase/ready" end)}]}]' > "$FIXTURE"
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq 'length')" = "200" ]
    [ "$(printf '%s\n' "$stderr" | grep -c '^EXCLUDED:')" = "100" ]
}

# --- fail-open ---

@test "empty input: warning, empty stdout, exit 0" {
    run --separate-stderr bash "$SCRIPT" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Warning:"* ]] || false
}

@test "whitespace-only input: warning, empty stdout, exit 0" {
    printf '  \n\t\n' > "$FIXTURE"
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Warning:"* ]] || false
}

@test "invalid JSON is passed through unchanged with a warning" {
    printf 'this is not json\n' > "$FIXTURE"
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$output" = "this is not json" ]
    [[ "$stderr" == *"Warning:"* ]] || false
}

@test "non-array JSON is passed through unchanged with a warning" {
    printf '{"number": 1, "labels": [{"name": "phase/verify"}]}\n' > "$FIXTURE"
    run --separate-stderr bash "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$output" = '{"number": 1, "labels": [{"name": "phase/verify"}]}' ]
    [[ "$stderr" == *"Warning:"* ]] || false
}

@test "jq unavailable: input is passed through unchanged with a warning" {
    NOJQ="$BATS_TEST_TMPDIR/nojq-bin"
    mkdir -p "$NOJQ"
    ln -s "$(command -v cat)" "$NOJQ/cat"
    printf '[{"number": 1, "labels": [{"name": "phase/verify"}]}]\n' > "$FIXTURE"
    run --separate-stderr env PATH="$NOJQ" "$BASH" "$SCRIPT" < "$FIXTURE"
    [ "$status" -eq 0 ]
    [ "$output" = '[{"number": 1, "labels": [{"name": "phase/verify"}]}]' ]
    [[ "$stderr" == *"Warning:"* ]] || false
}

@test "any argument is a usage error (exit 1)" {
    run --separate-stderr bash "$SCRIPT" extra-arg < /dev/null
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Usage:"* ]] || false
}

# --- detection power: collapsed premise vs. still-open premise ---

# Reproduces /audit premise Step 1 -> Step 2 Layer 1: feed Issues through a gate, then
# evaluate the markers of every Issue that reaches the evaluator. Issue #201 has landed
# (phase/verify); #202 has not (phase/code). Both carry the same premise, which no
# longer holds in the work tree. Prints "<N>: EXPIRED" or "<N>: HOLDS" per Issue seen.
evaluate_through() {
    local gate="$1"
    local issues="$BATS_TEST_TMPDIR/pipeline-issues.json"
    local repo="$BATS_TEST_TMPDIR/repo"
    local body='Premise before the fix: <!-- premise: grep_count "token" "sub/" -eq 0 -->'

    mkdir -p "$repo/sub"
    git init -q "$repo"
    echo "token here" > "$repo/sub/a.txt"
    git -C "$repo" add -A

    jq -n --arg body "$body" '[
      {number: 201, title: "landed", body: $body, labels: [{name: "phase/verify"}]},
      {number: 202, title: "still open", body: $body, labels: [{name: "phase/code"}]}
    ]' > "$issues"

    local gated n rc
    gated="$("$gate" < "$issues" 2>/dev/null)"
    cd "$repo"
    for n in $(printf '%s' "$gated" | jq -r '.[].number'); do
        printf '%s' "$gated" | jq -r --argjson n "$n" '.[] | select(.number == $n) | .body' > "$repo/body-$n.md"
        rc=0
        "$EVALUATOR" "$repo/body-$n.md" > /dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 2 ]; then
            echo "$n: EXPIRED"
        else
            echo "$n: HOLDS"
        fi
    done
}

passthrough_gate() {
    cat
}

@test "detection power: only the not-yet-implemented Issue is reported as EXPIRED" {
    run evaluate_through "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"202: EXPIRED"* ]] || false
    if [[ "$output" == *"201:"* ]]; then false; fi
}

@test "control: without the filter both Issues are reported as EXPIRED" {
    run evaluate_through passthrough_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *"201: EXPIRED"* ]] || false
    [[ "$output" == *"202: EXPIRED"* ]] || false
}

# --- wiring into /audit premise ---

@test "audit premise section wires the filter into Step 1" {
    section="$(md_section "$AUDIT_SKILL" "## premise Subcommand")"
    [ -n "$section" ]
    [[ "$section" == *"--json number,title,body,labels"* ]] || false
    [[ "$section" == *"filter-premise-targets.sh"* ]] || false
}

@test "audit allowed-tools permits the filter script" {
    run grep -F '${CLAUDE_PLUGIN_ROOT}/scripts/filter-premise-targets.sh:*' "$AUDIT_SKILL"
    [ "$status" -eq 0 ]
}
