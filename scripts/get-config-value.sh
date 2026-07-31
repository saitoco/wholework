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
#   - Supports flat kebab-case keys and single-level nested keys in block format
#     (e.g., capabilities.workflow). Keys with two or more dots, or inline hash
#     format (capabilities: { workflow: true }), are not supported.
#   - A nested key matches only a direct child of the section: a deeper-indented
#     key (capabilities.mcp.workflow) does not answer capabilities.workflow
#   - Keys may contain only [A-Za-z0-9._-]; any other key returns the default
#     (keys can originate from free text, so they are never treated as regex)
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
  - Flat kebab-case keys and single-level nested keys in block format are
    supported (e.g., capabilities.workflow). Keys with two or more dots, or
    inline hash format (capabilities: { workflow: true }), are not supported.
  - A nested key matches only a direct child of the section; a deeper-indented
    key (capabilities.mcp.workflow) does not answer capabilities.workflow
  - Keys may contain only [A-Za-z0-9._-]; any other key returns the default
  - Values are returned with surrounding quotes stripped
  - Comment lines (starting with #) are ignored
EOF
    exit 0
fi

KEY="$1"
DEFAULT="${2:-}"

# Reject keys containing characters outside the supported charset before KEY (or the
# SECTION/SUBKEY derived from it below) is interpolated into a grep/sed pattern.
# `config=<key>` values reach this script as free text written in Issue bodies (see the
# config check gate in scripts/opportunistic-search.sh), so an unvalidated key such as
# `capabilities.(workflow` would leak regex metacharacters into the match patterns —
# emitting grep errors on stderr, or returning an unrelated substring as the "value".
case "$KEY" in
    ""|*[!A-Za-z0-9._-]*)
        echo "$DEFAULT"
        exit 0
        ;;
esac

# Locate .wholework.yml relative to the current working directory.
# WHOLEWORK_CONFIG_PATH env override allows tests to redirect to a custom path.
CONFIG_FILE="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "$DEFAULT"
    exit 0
fi

# Extract value for the given key
# - Match lines of the form: key: value (with optional surrounding whitespace)
# - Strip leading/trailing whitespace and surrounding single or double quotes
VALUE=""
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comment lines
    case "$line" in
        \#*) continue ;;
    esac

    # Match: key: value (key must match exactly)
    if echo "$line" | grep -qE "^[[:space:]]*${KEY}[[:space:]]*:"; then
        VALUE=$(echo "$line" | sed -E "s/^[[:space:]]*${KEY}[[:space:]]*:[[:space:]]*//" | sed -E "s/[[:space:]]+#.*$//" | sed -E "s/[[:space:]]*$//" | sed -E "s/^['\"]|['\"]$//" | sed -E "s/^['\"]|['\"]$//")
        break
    fi
done < "$CONFIG_FILE"

# Fallback: single-level nested key in block format (e.g., capabilities.workflow).
# Only triggered when the flat-key loop above found nothing and KEY contains
# exactly one dot (KEY.SUBKEY). Two-or-more-dot keys and inline hash format are
# not supported.
if [ -z "$VALUE" ]; then
    DOT_COUNT=$(echo "$KEY" | tr -cd '.' | wc -c | tr -d '[:space:]')
    if [ "$DOT_COUNT" = "1" ]; then
        SECTION="${KEY%%.*}"
        SUBKEY="${KEY#*.}"
        IN_SECTION=false
        # Indentation of the section's direct children, learned from the first child
        # line. Deeper-indented lines belong to a grandchild block and are skipped.
        SECTION_INDENT=""
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comment lines
            case "$line" in
                \#*) continue ;;
            esac

            if [ "$IN_SECTION" = "true" ]; then
                if echo "$line" | grep -qE "^[[:space:]]*$"; then
                    # Blank (or whitespace-only) line: section continues
                    continue
                fi
                case "$line" in
                    [[:space:]]*)
                        LINE_INDENT=$(echo "$line" | sed -E "s/^([[:space:]]*).*$/\1/")
                        if [ -z "$SECTION_INDENT" ]; then
                            SECTION_INDENT="$LINE_INDENT"
                        fi
                        # Only direct children count: a deeper indent is a grandchild
                        # (e.g., capabilities.mcp.workflow must not answer
                        # capabilities.workflow).
                        if [ "$LINE_INDENT" = "$SECTION_INDENT" ] && echo "$line" | grep -qE "^[[:space:]]+${SUBKEY}[[:space:]]*:"; then
                            VALUE=$(echo "$line" | sed -E "s/^[[:space:]]+${SUBKEY}[[:space:]]*:[[:space:]]*//" | sed -E "s/[[:space:]]+#.*$//" | sed -E "s/[[:space:]]*$//" | sed -E "s/^['\"]|['\"]$//" | sed -E "s/^['\"]|['\"]$//")
                            break
                        fi
                        ;;
                    *)
                        # Non-indented line: section ends here
                        IN_SECTION=false
                        ;;
                esac
            fi

            if [ "$IN_SECTION" = "false" ]; then
                # A trailing inline comment on the section header is valid YAML and must
                # not prevent the section from being recognized (value lines already
                # strip inline comments).
                if echo "$line" | grep -qE "^${SECTION}[[:space:]]*:[[:space:]]*(#.*)?$"; then
                    IN_SECTION=true
                    SECTION_INDENT=""
                fi
            fi
        done < "$CONFIG_FILE"
    fi
fi

if [ -z "$VALUE" ]; then
    echo "$DEFAULT"
else
    echo "$VALUE"
fi

exit 0
