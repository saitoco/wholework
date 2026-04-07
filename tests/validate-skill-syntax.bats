#!/usr/bin/env bats

# Tests for validate-skill-syntax.py
# Creates skill files in a temp directory and validates the validation logic.

REAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/validate-skill-syntax.py"

setup() {
    PROJECT_ROOT="$(mktemp -d)"
    mkdir -p "$PROJECT_ROOT/scripts"
    mkdir -p "$PROJECT_ROOT/skills"
    mkdir -p "$PROJECT_ROOT/modules"
}

teardown() {
    rm -rf "$PROJECT_ROOT"
}

# Helper: create a valid skill file
create_valid_skill() {
    local name="${1:-myskill}"
    mkdir -p "$PROJECT_ROOT/skills/$name"
    cat > "$PROJECT_ROOT/skills/$name/SKILL.md" <<EOF
---
name: $name
description: A valid test skill
allowed-tools: Bash(gh issue view:*), Read, Glob
---

# Test Skill

This is a valid skill.
EOF
}

# Helper: create a script file
create_script() {
    local name="$1"
    touch "$PROJECT_ROOT/scripts/$name"
}

# Helper: create an include file
create_include() {
    local name="$1"
    local content="$2"
    printf '%s\n' "$content" > "$PROJECT_ROOT/modules/$name"
}

# --- Basic tests ---

@test "success: valid skill passes all checks" {
    create_valid_skill
    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

@test "success: valid skill with context and agent" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A valid test skill
allowed-tools: Bash(gh:*), Read
context: fork
agent: general-purpose
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- allowed-tools tool name validation ---

@test "error: unknown tool name in allowed-tools" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bsh(gh:*), Read
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown tool name"* ]]
    [[ "$output" == *"Bsh"* ]]
}

@test "error: multiple unknown tool names" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bassh, Rread, Glob
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bassh"* ]]
    [[ "$output" == *"Rread"* ]]
}

@test "success: all known tools pass validation" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash, Glob, Grep, Read, Write, Edit, TaskCreate, TaskUpdate, TaskList, TaskGet, WebFetch, WebSearch, NotebookEdit, EnterPlanMode, Task, Skill
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

@test "error: AskUserQuestion in allowed-tools is forbidden" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(gh:*), Read, AskUserQuestion
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden tool"* ]]
    [[ "$output" == *"AskUserQuestion"* ]]
}

@test "success: MCP tool names with mcp__ prefix pass validation" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(gh:*), Read, mcp__plugin_figma_figma__get_design_context, mcp__plugin_figma_figma__get_variable_defs
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- context field validation ---

@test "error: invalid context value" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
context: frok
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'context' の値が無効です"* ]]
    [[ "$output" == *"frok"* ]]
}

@test "success: valid context value fork" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
context: fork
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- agent field validation ---

@test "error: invalid agent value" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
agent: genral-purpose
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'agent' の値が無効です"* ]]
    [[ "$output" == *"genral-purpose"* ]]
}

@test "success: valid agent value general-purpose" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
agent: general-purpose
---

# Test Skill

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- body script path validation ---

@test "error: body references non-existent script" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

Run this:

```bash
~/.claude/scripts/nonexistent-script.sh arg1
```
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"本文中に参照されたスクリプトが存在しません"* ]]
    [[ "$output" == *"nonexistent-script.sh"* ]]
}

@test "success: body references existing script" {
    create_script "my-helper.sh"
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(~/.claude/scripts/my-helper.sh:*)
---

# Test Skill

Run this:

```bash
~/.claude/scripts/my-helper.sh arg1
```
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

@test "error: body references script not in allowed-tools" {
    create_script "my-script.sh"
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(gh issue view:*), Read
---

# Test Skill

Run this:

```bash
~/.claude/scripts/my-script.sh arg1
```
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"本文中に参照されたスクリプト 'my-script.sh' が allowed-tools の Bash(...) パターンに含まれていません"* ]]
}

@test "success: body references script in allowed-tools" {
    create_script "my-script.sh"
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(gh issue view:*, ~/.claude/scripts/my-script.sh:*), Read
---

# Test Skill

Run this:

```bash
~/.claude/scripts/my-script.sh arg1
```
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- shell-sensitive character validation ---

@test "error: exclamation mark outside code fence" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

Bash tool escapes the ! character which causes issues.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"shell-sensitive character"* ]]
}

@test "success: exclamation mark inside code fence is allowed" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

GraphQL example:

```bash
query($owner:String!,$repo:String!) { repository(owner:$owner,name:$repo) { name } }
```
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- decimal step validation ---

@test "error: decimal step in body is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

### Step 1: First step

Content here.

### Step 1.5: Intermediate step

This is a decimal step.

### Step 2: Second step

More content.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"小数ステップ"* ]]
}

@test "success: integer steps pass decimal step check" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

### Step 1: First step

Content here.

### Step 2: Second step

More content.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- Phase-only heading validation ---

@test "error: phase-only heading is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

### Phase 1: Preparation

Content here.

### Phase 2: Execution

More content.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Phase-only"* ]]
}

# --- verify hint syntax validation ---

@test "success: valid verify hints pass validation" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

- [ ] <!-- verify: file_exists "some/file.txt" --> file exists
- [ ] <!-- verify: grep "pattern" "some/file.txt" --> grep matches
- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> command runs
- [ ] <!-- verify: browser_check "http://localhost:3000" "title" --> browser ok
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

@test "error: unknown verify command name is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

- [ ] <!-- verify: unknown_cmd "arg" --> unknown command
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"未知の verify コマンド"* ]]
    [[ "$output" == *"unknown_cmd"* ]]
}

@test "error: verify hint with too few args is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

- [ ] <!-- verify: file_contains "path/only" --> only one arg given, needs two
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"引数が不足"* ]]
    [[ "$output" == *"file_contains"* ]]
}

@test "error: verify hint with too many args is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

- [ ] <!-- verify: file_exists "a" "b" --> too many args
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"引数が多すぎます"* ]]
    [[ "$output" == *"file_exists"* ]]
}

@test "error: verify hint with unterminated quote is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill-bad-quote"
    cat > "$PROJECT_ROOT/skills/myskill-bad-quote/SKILL.md" <<'EOF'
---
name: myskill-bad-quote
description: A test skill with bad verify syntax
---

# Test Skill

- [ ] <!-- verify: file_exists "some/file.txt --> unterminated quote
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"構文エラー"* ]]
}

@test "success: verify hint with --when modifier passes validation" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

- [ ] <!-- verify: command "bats tests/validate-skill-syntax.bats" --when="which bats" --> bats test passes
- [ ] <!-- verify: file_exists "scripts/validate-skill-syntax.py" --when="test -n \"$CI\"" --> file exists in CI
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- multiple path specifications ---

@test "success: two skill file paths are both validated" {
    create_valid_skill "skill-a"
    create_valid_skill "skill-b"
    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills/skill-a/SKILL.md" "$PROJECT_ROOT/skills/skill-b/SKILL.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 スキル"* ]]
    [[ "$output" == *"0 error"* ]]
}

@test "error: nonexistent path exits with error" {
    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills/nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "success: individual skill directory path is accepted" {
    create_valid_skill "myskill"
    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills/myskill"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- body tool usage vs allowed-tools validation ---

@test "error: body uses Glob but Glob not in allowed-tools" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(gh issue view:*), Read
---

# Test Skill

Use Glob to search for files.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"本文中でツール 'Glob' が使用されていますが allowed-tools に含まれていません"* ]]
}

@test "success: body uses Glob and Glob is in allowed-tools" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
allowed-tools: Bash(gh issue view:*), Read, Glob
---

# Test Skill

Use Glob to search for files.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}

# --- tilde-claude-scripts in command hints ---

@test "error: tilde-claude-scripts path in command hint is rejected" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

Check this:

- [ ] <!-- verify: command "~/.claude/scripts/my-script.sh arg" --> script runs

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"~/.claude/scripts"* ]]
}

@test "success: repo-relative path in command hint is allowed" {
    mkdir -p "$PROJECT_ROOT/skills/myskill"
    cat > "$PROJECT_ROOT/skills/myskill/SKILL.md" <<'EOF'
---
name: myskill
description: A test skill
---

# Test Skill

Check this:

- [ ] <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validator runs

Content here.
EOF

    run python3 "$REAL_SCRIPT" "$PROJECT_ROOT/skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 error"* ]]
}
