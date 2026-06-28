#!/usr/bin/env bats

# Template for new bats test files.
# Copy this file to tests/<target-name>.bats and replace placeholder content.
#
#   cp tests/_template.bats tests/my-script.bats
#
# KEY RULE: define PROJECT_ROOT once at the top level using BATS_TEST_FILENAME.
# All file paths in this test file must derive from PROJECT_ROOT to ensure
# portability regardless of the working directory when bats is invoked.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# --- Content-assertion tests (modules, skills, docs) ---
# Derive target file paths from PROJECT_ROOT:
#
#   TARGET="$PROJECT_ROOT/modules/some-module.md"
#
#   @test "some-module: ## Purpose section exists" {
#       grep -q "## Purpose" "$TARGET"
#   }

# --- Script execution tests (scripts/*.sh) ---
# Derive script path from PROJECT_ROOT:
#
#   SCRIPT="$PROJECT_ROOT/scripts/my-script.sh"
#
#   setup() {
#       MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
#       mkdir -p "$MOCK_DIR"
#       # Use WHOLEWORK_SCRIPT_DIR to redirect sibling helper calls:
#       export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
#       # Or prepend to PATH to override CLI tools (gh, git, etc.):
#       export PATH="$MOCK_DIR:$PATH"
#   }
#
#   teardown() {
#       rm -rf "$BATS_TEST_TMPDIR/mocks"
#   }
#
#   @test "my-script: exits 0 on success" {
#       run "$SCRIPT"
#       [ "$status" -eq 0 ]
#   }

# The @test below is a live sanity check that PROJECT_ROOT resolved correctly.
# Keep it in your copy — it guards against path anchoring regressions.

@test "template: PROJECT_ROOT resolves to the repository root" {
    [[ -d "$PROJECT_ROOT/scripts" ]]
    [[ -d "$PROJECT_ROOT/tests" ]]
    [[ -d "$PROJECT_ROOT/modules" ]]
}
