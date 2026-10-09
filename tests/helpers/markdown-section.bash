# Shared bats helper: extract one Markdown section that starts at a heading.
#
# Usage (from a .bats file):
#   load 'helpers/markdown-section'
#   md_section FILE HEADING_PREFIX [END_LEVEL]
#
# Arguments:
#   FILE            Markdown file to read.
#   HEADING_PREFIX  Literal text (not a regex) that the start heading line begins with,
#                   e.g. "### Step 0:".
#   END_LEVEL       Optional. The section ends just before the first heading whose level
#                   (number of leading '#') is <= END_LEVEL. Defaults to the number of
#                   leading '#' in HEADING_PREFIX.
#
# Behavior:
#   - Prints the section to stdout, including the start heading line.
#   - Lines inside a code fence (a line starting with optional whitespace followed by
#     three backticks toggles the fence) are never treated as a start or end heading,
#     but are printed when they are inside the section. Fence tracking begins at the
#     top of the file, so a fenced copy of the heading before the real one is ignored.
#     '~~~' fences and indented code blocks are not recognized.
#   - If the section runs to the end of the file, everything up to EOF is printed.
#
# Exit status:
#   0  heading found
#   1  heading not found (output is empty)
#   2  END_LEVEL omitted and HEADING_PREFIX does not start with '#'
#
# Compatibility: bash 3.2+; awk uses only POSIX features (index, match, RLENGTH), so it
# runs on mawk, BWK awk, and gawk.

md_section() {
    local file="$1" prefix="$2" level="${3:-}"
    if [ -z "$level" ]; then
        level="${prefix%%[!#]*}"
        level="${#level}"
    fi
    if [ "$level" -lt 1 ]; then
        echo "md_section: HEADING_PREFIX must start with '#', or pass END_LEVEL" >&2
        return 2
    fi
    awk -v prefix="$prefix" -v level="$level" '
        /^[ \t]*```/ { infence = !infence; if (found) print; next }
        infence { if (found) print; next }
        !found && index($0, prefix) == 1 { found = 1; print; next }
        found {
            if (match($0, /^#+ /) && RLENGTH - 1 <= level) exit
            print
        }
        END { if (!found) exit 1 }
    ' "$file"
}
