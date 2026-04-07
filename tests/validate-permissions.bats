#!/usr/bin/env bats

# Tests for validate-permissions.sh
# Recreates a project structure in a temp directory and validates
# the bidirectional consistency check between skills/<name>/SKILL.md and the name: field.

REAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/validate-permissions.sh"

setup() {
    PROJECT_ROOT="$(mktemp -d)"
    mkdir -p "$PROJECT_ROOT/scripts"
    mkdir -p "$PROJECT_ROOT/skills"

    # Copy the real script into the temp project so SCRIPT_DIR/PROJECT_ROOT resolve correctly
    cp "$REAL_SCRIPT" "$PROJECT_ROOT/scripts/validate-permissions.sh"

    SCRIPT="$PROJECT_ROOT/scripts/validate-permissions.sh"
}

teardown() {
    rm -rf "$PROJECT_ROOT"
}

# Helper: create a skill with matching name: field
create_skill() {
    local name="$1"
    mkdir -p "$PROJECT_ROOT/skills/$name"
    cat > "$PROJECT_ROOT/skills/$name/SKILL.md" <<EOF
---
name: $name
description: Test skill
---

# $name
EOF
}

@test "success: single skill with matching name field" {
    create_skill "myskill"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "success: multiple skills all with matching name fields" {
    create_skill "skill-a"
    create_skill "skill-b"
    create_skill "skill-c"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "success: no skills directory entries (empty skills/)" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "error: SKILL.md missing name: field" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
description: Test skill
---

# myskill
EOF
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing the 'name:' frontmatter field"* ]]
}

@test "error: name: field does not match directory name" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: wrongname
description: Test skill
---

# myskill
EOF
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"wrongname"* ]]
    [[ "$output" == *"myskill"* ]]
}

@test "error: multiple skills, one has wrong name field" {
    create_skill "skill-a"
    mkdir -p "$PROJECT_ROOT/skills/skill-b"
    cat > "$PROJECT_ROOT/skills/skill-b/SKILL.md" <<'EOF'
---
name: skill-wrong
description: Test skill
---

# skill-b
EOF
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skill-wrong"* ]]
}

@test "error: multiple issues are all reported" {
    mkdir -p "$PROJECT_ROOT/skills/skill-a"
    cat > "$PROJECT_ROOT/skills/skill-a/SKILL.md" <<'EOF'
---
name: wrong-a
description: Test skill
---

# skill-a
EOF
    mkdir -p "$PROJECT_ROOT/skills/skill-b"
    cat > "$PROJECT_ROOT/skills/skill-b/SKILL.md" <<'EOF'
---
name: wrong-b
description: Test skill
---

# skill-b
EOF
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"wrong-a"* ]]
    [[ "$output" == *"wrong-b"* ]]
}

@test "error: SKILL.md has name field pointing to nonexistent directory" {
    # Manually create a SKILL.md with a name: that has no matching directory
    # This simulates check 2: name: field -> directory exists
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: ghost
description: Test skill
---

# ghost
EOF
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ghost"* ]]
}
