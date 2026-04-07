#!/bin/bash
# Skills test runner
#
# Usage:
#   ./scripts/test-skills.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Skills syntax validation ==="
echo ""

python3 "$SCRIPT_DIR/validate-skill-syntax.py" "$PROJECT_ROOT/skills/"

echo ""
echo "=== All tests complete ==="
