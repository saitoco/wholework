#!/usr/bin/env bats

# Tests for detect-pr-ci-workflows.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/detect-pr-ci-workflows.sh"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
}

@test "detect-pr-ci-workflows: no .github/workflows directory -> absent" {
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "absent" ]
}

@test "detect-pr-ci-workflows: empty workflows directory -> absent" {
    mkdir -p "$REPO/.github/workflows"
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "absent" ]
}

@test "detect-pr-ci-workflows: schedule + workflow_dispatch only (saito/ops shape) -> absent" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/mail-check.yml" <<'EOF'
on:
  schedule:
    - cron: '0 * * * *'
  workflow_dispatch: {}
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "absent" ]
}

@test "detect-pr-ci-workflows: on: pull_request (string form) -> present" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
on: pull_request
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "detect-pr-ci-workflows: on: [push, pull_request] (array form) -> present" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "detect-pr-ci-workflows: indented pull_request: mapping form -> present" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "detect-pr-ci-workflows: pull_request_target only -> present" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
on:
  pull_request_target:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "detect-pr-ci-workflows: .yaml extension -> present" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yaml" <<'EOF'
on: pull_request
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "detect-pr-ci-workflows: commented-out trigger only (# on: pull_request) -> absent" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
# on: pull_request
on:
  workflow_dispatch: {}
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "absent" ]
}

@test "detect-pr-ci-workflows: pull_request only in a non-.yml file (e.g. README.md) -> absent" {
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/mail-check.yml" <<'EOF'
on:
  workflow_dispatch: {}
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
    cat > "$REPO/.github/workflows/README.md" <<'EOF'
This workflow does not run on pull_request.
EOF
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "absent" ]
}

@test "detect-pr-ci-workflows: CRLF line endings, mapping form -> present" {
    mkdir -p "$REPO/.github/workflows"
    printf 'on:\r\n  pull_request:\r\n    branches: [main]\r\njobs:\r\n  test:\r\n    runs-on: ubuntu-latest\r\n    steps:\r\n      - run: echo hi\r\n' > "$REPO/.github/workflows/ci.yml"
    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "detect-pr-ci-workflows: unreadable workflow file -> unknown" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root; chmod 000 has no effect on readability"
    fi
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
on:
  workflow_dispatch: {}
EOF
    chmod 000 "$REPO/.github/workflows/ci.yml"
    run "$SCRIPT" "$REPO"
    chmod 644 "$REPO/.github/workflows/ci.yml"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect-pr-ci-workflows: nonexistent repo-root -> unknown" {
    run "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect-pr-ci-workflows: unreadable repo-root -> unknown (not absent)" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root; chmod 000 has no effect on readability"
    fi
    mkdir -p "$REPO/.github/workflows"
    cat > "$REPO/.github/workflows/ci.yml" <<'EOF'
on:
  pull_request:
    branches: [main]
EOF
    chmod 000 "$REPO"
    run "$SCRIPT" "$REPO"
    chmod 755 "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect-pr-ci-workflows: two arguments -> exit 1 with usage" {
    run "$SCRIPT" "$REPO" "extra-arg"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Usage"
}
