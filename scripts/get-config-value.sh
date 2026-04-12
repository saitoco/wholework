#!/bin/bash
# get-config-value.sh
# Helper script to extract a configuration value from .wholework.yml
#
# Usage:
#   scripts/get-config-value.sh <key> [default]
#   scripts/get-config-value.sh --help
#
# Arguments:
#   key      Flat kebab-case key to look up (e.g., spec-path, steering-docs-path, production-url)
#   default  (Optional) Default value to return if key is not set or .wholework.yml does not exist
#
# Output:
#   Prints the resolved value to stdout on one line
#   Exits with code 0 on success (including when returning default value)
#   Exits with code 1 on usage error
#
# Notes:
#   - Supports only flat kebab-case keys (nested keys like capabilities.browser are not supported)
#   - Strips surrounding quotes from values
#   - Ignores comment lines (starting with #)
#   - Returns default value if key is absent or .wholework.yml does not exist

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <key> [default]" >&2
    exit 1
fi

if [ "$1" = "--help" ]; then
    cat <<'EOF'
get-config-value.sh - Extract a configuration value from .wholework.yml

Usage:
  get-config-value.sh <key> [default]

Arguments:
  key      Flat kebab-case key to look up (e.g., spec-path, steering-docs-path, production-url)
  default  (Optional) Default value returned when key is absent or .wholework.yml does not exist

Examples:
  get-config-value.sh spec-path docs/spec
  get-config-value.sh steering-docs-path docs
  get-config-value.sh production-url ""

Notes:
  - Only flat kebab-case keys are supported (nested keys like capabilities.browser are not supported)
  - Values are returned with surrounding quotes stripped
  - Comment lines (starting with #) are ignored
EOF
    exit 0
fi

KEY="$1"
DEFAULT="${2:-}"

# Locate .wholework.yml relative to the current working directory
CONFIG_FILE=".wholework.yml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "$DEFAULT"
    exit 0
fi

# Extract value for the given key
# - Match lines of the form: key: value (with optional surrounding whitespace)
# - Strip leading/trailing whitespace and surrounding single or double quotes
VALUE=""
while IFS= read -r line; do
    # Skip comment lines
    case "$line" in
        \#*) continue ;;
    esac

    # Match: key: value (key must match exactly)
    if echo "$line" | grep -qE "^[[:space:]]*${KEY}[[:space:]]*:"; then
        VALUE=$(echo "$line" | sed -E "s/^[[:space:]]*${KEY}[[:space:]]*:[[:space:]]*//" | sed -E "s/[[:space:]]*$//" | sed -E "s/^['\"]|['\"]$//" | sed -E "s/^['\"]|['\"]$//")
        break
    fi
done < "$CONFIG_FILE"

if [ -z "$VALUE" ]; then
    echo "$DEFAULT"
else
    echo "$VALUE"
fi

exit 0
