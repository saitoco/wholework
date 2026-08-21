#!/usr/bin/env bats

# Tests for check-config-schema.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-config-schema.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "no .wholework.yml: exits 0" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "known keys only: exits 0 with no Unknown key output" {
  cat > .wholework.yml << 'EOF'
spec-path: docs/spec
autonomy: L3
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown key"* ]]
}

@test "typo key: exits 1 and reports the typo" {
  cat > .wholework.yml << 'EOF'
spec-path: docs/spec
autonomy-tier: L2
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown key"* ]]
  [[ "$output" == *"autonomy-tier"* ]]
}

@test "nested child key under known section: exits 0" {
  cat > .wholework.yml << 'EOF'
spec-path: docs/spec
capabilities:
  browser: true
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown key"* ]]
}

@test "comment line: not misdetected as a key" {
  cat > .wholework.yml << 'EOF'
spec-path: docs/spec
# autonomy-tier: L2
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown key"* ]]
}
