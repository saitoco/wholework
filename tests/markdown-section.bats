#!/usr/bin/env bats

# Tests for the shared md_section helper (tests/helpers/markdown-section.bash).
# The fenced-heading cases reproduce the CI failure of Issue #1512 / PR #1513:
# an inline awk treated a '## ...' line inside a code fence as a heading and cut
# the section short.

load 'helpers/markdown-section'

setup() {
    FIXTURE="$BATS_TEST_TMPDIR/doc.md"
}

# Fail when $output matches the grep pattern. A bare '! cmd' is not used because
# bats does not fail a test on a negated pipeline.
refute_output_has() {
    if printf '%s\n' "$output" | grep -q -- "$1"; then
        echo "unexpected match for: $1" >&2
        return 1
    fi
}

@test "md_section: fenced ## and ### lines do not end the section" {
    cat > "$FIXTURE" <<'EOF'
# Doc

## Target

intro line

```markdown
## Fenced heading
### Fenced sub heading
```

tail line after fence

## Next
after
EOF
    run md_section "$FIXTURE" "## Target"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^## Target$'
    echo "$output" | grep -q '^## Fenced heading$'
    echo "$output" | grep -q '^### Fenced sub heading$'
    echo "$output" | grep -q '^tail line after fence$'
    refute_output_has '^## Next$'
    refute_output_has '^after$'
}

@test "md_section: fenced copy of the heading before the real one does not start the section" {
    cat > "$FIXTURE" <<'EOF'
# Doc

```markdown
## Target
fenced copy of the heading
```

## Target

real body

## Next
after
EOF
    run md_section "$FIXTURE" "## Target"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^real body$'
    refute_output_has 'fenced copy'
    [ "$(echo "$output" | head -n 1)" = "## Target" ]
}

@test "md_section: indented fence does not end the section" {
    cat > "$FIXTURE" <<'EOF'
## Target

intro

   ```bash
## heading-like line inside indented fence
   ```

after indented fence

## Next
EOF
    run md_section "$FIXTURE" "## Target"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'heading-like line inside indented fence'
    echo "$output" | grep -q '^after indented fence$'
    refute_output_has '^## Next$'
}

@test "md_section: END_LEVEL overrides the default end level" {
    cat > "$FIXTURE" <<'EOF'
## Target
body

### Child
child body

### Sibling
sibling body

## Next
after
EOF
    run md_section "$FIXTURE" "## Target"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^child body$'
    echo "$output" | grep -q '^sibling body$'
    refute_output_has '^## Next$'

    run md_section "$FIXTURE" "## Target" 3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^body$'
    refute_output_has '^### Child$'
    refute_output_has '^child body$'

    run md_section "$FIXTURE" "### Child"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^child body$'
    refute_output_has '^### Sibling$'
    refute_output_has '^sibling body$'

    run md_section "$FIXTURE" "### Child" 2
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^child body$'
    echo "$output" | grep -q '^### Sibling$'
    echo "$output" | grep -q '^sibling body$'
    refute_output_has '^## Next$'
}

@test "md_section: default end level is the level of the start heading" {
    cat > "$FIXTURE" <<'EOF'
### Parent
#### X
x body
##### Deeper
deeper body
#### Sibling
sibling body
### Next
after
EOF
    run md_section "$FIXTURE" "#### X"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^deeper body$'
    refute_output_has '^#### Sibling$'
    refute_output_has 'sibling body'

    run md_section "$FIXTURE" "#### Sibling"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^sibling body$'
    refute_output_has '^### Next$'
}

@test "md_section: section without a following heading runs to end of file" {
    cat > "$FIXTURE" <<'EOF'
## Target
line one
line two
EOF
    run md_section "$FIXTURE" "## Target"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^line one$'
    echo "$output" | grep -q '^line two$'
}

@test "md_section: missing heading returns status 1 with empty output" {
    cat > "$FIXTURE" <<'EOF'
## Other
body
EOF
    run md_section "$FIXTURE" "## Target"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "md_section: prefix without leading # and no END_LEVEL returns status 2" {
    cat > "$FIXTURE" <<'EOF'
## Target
body
EOF
    run md_section "$FIXTURE" "Target"
    [ "$status" -eq 2 ]
}

@test "md_section: explicit END_LEVEL allows a prefix without leading #" {
    cat > "$FIXTURE" <<'EOF'
Target line
body
## Next
after
EOF
    run md_section "$FIXTURE" "Target line" 2
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^body$'
    refute_output_has '^after$'
}

@test "md_section: HEADING_PREFIX matches literally, not as a regex or a number prefix" {
    cat > "$FIXTURE" <<'EOF'
### 1243 Other
other body

### 12.3 Real
real body
EOF
    run md_section "$FIXTURE" "### 12.3"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^### 12.3 Real$'
    echo "$output" | grep -q '^real body$'
    refute_output_has 'other body'
}
