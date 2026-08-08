#!/usr/bin/env bash
# collect-verify-retention-stats.sh
# Measure phase/verify retention by verify-type: how much post-merge AC is still
# waiting, how much has already been resolved, and how old the waiting is.
#
# Usage:
#   scripts/collect-verify-retention-stats.sh [--window <YYYY-MM-DD>] [--cache <path>]
#                                             [--from-cache] [--format text|tsv]
#                                             [--limit <N>]
#
# --window <YYYY-MM-DD>: comparison-window start date, applied to each Issue's
#   createdAt. Metrics are reported twice -- once over all Issues, once over the
#   window. Defaults to 90 days before today, matching the population definition
#   docs/stats/*.md uses. Pass the exact date a past report used (e.g. 2026-05-07
#   for docs/stats/2026-08-05.md) to get numbers comparable with that report.
#   Comparing against a differently-scoped population is the failure mode this
#   option exists to prevent: the same repository measured all-time vs. 90-day
#   window differed by 123 vs. 18 for Manual waiting (see Issue #1251).
# --cache <path>: TSV cache path for the fetched per-Issue counts
#   (default: .tmp/verify-retention-cache.tsv). Fetching dominates runtime -- one
#   `gh issue view` per Issue over ~800 Issues -- so the cache exists to let the
#   aggregation be re-run without re-fetching.
# --from-cache: skip fetching and aggregate the existing cache file. Fails if the
#   cache does not exist.
# --format text|tsv: `text` (default) prints the human-readable report; `tsv`
#   prints one metric per line as `<section>\t<metric>\t<value>` for downstream
#   consumption.
# --limit <N>: `gh issue list` page size (default 500). A warning is printed to
#   stderr when the returned count equals the limit, since Issues beyond it were
#   not scanned.
#
# verify-type extraction: the tag is read only from inside an HTML comment
#   (`<!-- verify-type: <t>`), never from bare `verify-type: <t>` text elsewhere on
#   the line. Condition prose legitimately quotes the tag name -- Issue #1167's
#   post-merge AC contains the phrase "未チェックの `verify-type: manual` 行" while
#   the line's actual tag is `<!-- verify-type: observation event=auto-run -->` --
#   so a first-match-wins scan misclassifies it. scripts/scan-pending-ac.sh's
#   `match(line, /verify-type: [a-zA-Z_]+/)` has exactly that behaviour; this
#   script deliberately does not copy it.
#
# Post-merge section range: from the line after a heading matching
#   `^### Post-merge` or `^## Post-merge` up to (but excluding) the next line
#   matching `^## ` or `^### ` (same convention as scripts/scan-pending-ac.sh).
#
# Populations:
#   waiting  -- Issues labelled phase/verify, counting UNCHECKED post-merge AC
#   resolved -- Issues labelled phase/done, counting CHECKED post-merge AC
# An Issue carrying both labels is counted in whichever list `gh issue list`
# returns it under; the two labels are mutually exclusive by convention
# (scripts/gh-label-transition.sh removes the previous phase/* label).
#
# Output (text format) has three sections:
#   1. Waiting  -- per verify-type AC-line and Issue counts, all-time and windowed
#   2. Resolved -- per verify-type AC-line and Issue counts, all-time and windowed
#   3. Age      -- waiting Issues inside vs. outside the window, per verify-type
#
# Exit codes: 0 on success; 1 on usage error or unreadable cache.

set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WINDOW=""
CACHE=""
FROM_CACHE=false
FORMAT="text"
LIMIT=500

while [ $# -gt 0 ]; do
    case "$1" in
        --window)
            if [ $# -lt 2 ]; then
                echo "Error: --window requires an argument" >&2
                exit 1
            fi
            WINDOW="$2"
            shift 2
            ;;
        --cache)
            if [ $# -lt 2 ]; then
                echo "Error: --cache requires an argument" >&2
                exit 1
            fi
            CACHE="$2"
            shift 2
            ;;
        --from-cache)
            FROM_CACHE=true
            shift
            ;;
        --format)
            if [ $# -lt 2 ]; then
                echo "Error: --format requires an argument" >&2
                exit 1
            fi
            FORMAT="$2"
            shift 2
            ;;
        --limit)
            if [ $# -lt 2 ]; then
                echo "Error: --limit requires an argument" >&2
                exit 1
            fi
            LIMIT="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Usage: $0 [--window <YYYY-MM-DD>] [--cache <path>] [--from-cache] [--format text|tsv] [--limit <N>]" >&2
            exit 1
            ;;
    esac
done

case "$FORMAT" in
    text|tsv) ;;
    *)
        echo "Error: --format must be 'text' or 'tsv'" >&2
        exit 1
        ;;
esac

if [ -z "$WINDOW" ]; then
    WINDOW=$(date -u -v-90d '+%Y-%m-%d' 2>/dev/null) \
        || WINDOW=$(date -u -d '90 days ago' '+%Y-%m-%d' 2>/dev/null) \
        || WINDOW="1970-01-01"
fi

case "$WINDOW" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *)
        echo "Error: --window must be YYYY-MM-DD, got '${WINDOW}'" >&2
        exit 1
        ;;
esac

if [ -z "$CACHE" ]; then
    CACHE="${REPO_ROOT}/.tmp/verify-retention-cache.tsv"
fi

# Counts UNCHECKED and CHECKED post-merge AC lines per verify-type for one Issue
# body on stdin. Emits a single tab-separated row:
#   obs_u opp_u man_u auto_u obs_c opp_c man_c auto_c
count_body() {
    awk '
      BEGIN { in_section = 0 }
      /^### Post-merge/ || /^## Post-merge/ { in_section = 1; next }
      /^## / || /^### / { in_section = 0 }
      in_section && /^- \[[ xX]\]/ {
        checked = (substr($0, 4, 1) == " ") ? 0 : 1
        vtype = ""
        # Read the tag only from inside an HTML comment, so condition prose that
        # quotes a tag name (Issue #1167) cannot be mistaken for the real tag.
        if (match($0, /<!--[ \t]*verify-type:[ \t]*[a-zA-Z_]+/)) {
          tag = substr($0, RSTART, RLENGTH)
          sub(/^<!--[ \t]*verify-type:[ \t]*/, "", tag)
          vtype = tag
        } else if ($0 ~ /<!--[ \t]*verify:/) {
          vtype = "auto"
        } else {
          # No verify-type tag and no verify command: treated as manual, matching
          # skills/verify/SKILL.md Step 8b.
          vtype = "manual"
        }
        if (checked) { c[vtype]++ } else { u[vtype]++ }
      }
      END {
        printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d",
          u["observation"]+0, u["opportunistic"]+0, u["manual"]+0, u["auto"]+0,
          c["observation"]+0, c["opportunistic"]+0, c["manual"]+0, c["auto"]+0
      }'
}

fetch_population() {
    label="$1"
    kind="$2"
    list_json=$(gh issue list --label "$label" --state all \
        --json number,createdAt --limit "$LIMIT" 2>/dev/null) || {
        echo "Error: gh issue list failed for label ${label}" >&2
        return 1
    }
    count=$(printf '%s' "$list_json" | jq 'length' 2>/dev/null || echo 0)
    if [ "$count" -eq "$LIMIT" ]; then
        echo "Warning: ${label} hit the --limit ${LIMIT} cap; some Issues were not scanned." >&2
    fi
    printf '%s' "$list_json" | jq -r '.[] | "\(.number)\t\(.createdAt)"' | while IFS=$'\t' read -r n created; do
        [ -z "$n" ] && continue
        body=$(gh issue view "$n" --json body --jq '.body' 2>/dev/null || true)
        counts=$(printf '%s\n' "$body" | count_body)
        printf '%s\t%s\t%s\t%s\n' "$n" "$created" "$kind" "$counts"
    done
}

if [ "$FROM_CACHE" = true ]; then
    if [ ! -f "$CACHE" ]; then
        echo "Error: --from-cache given but cache not found: ${CACHE}" >&2
        exit 1
    fi
else
    mkdir -p "$(dirname "$CACHE")"
    : > "$CACHE"
    fetch_population "phase/verify" waiting >> "$CACHE" || exit 1
    fetch_population "phase/done" resolved >> "$CACHE" || exit 1
fi

# Cache columns:
#   1 number  2 createdAt  3 kind  4 obs_u  5 opp_u  6 man_u  7 auto_u
#   8 obs_c   9 opp_c     10 man_c 11 auto_c
awk -F'\t' -v window="$WINDOW" -v fmt="$FORMAT" '
  function inwin(created) { return (substr(created, 1, 10) >= window) }
  {
    kind = $3
    if (kind == "waiting") {
      wt_issues++
      if (inwin($2)) ww_issues++
      split("observation opportunistic manual auto", names, " ")
      for (i = 1; i <= 4; i++) {
        col = 3 + i
        n = names[i]
        wt_lines[n] += $col
        if ($col > 0) { wt_iss[n]++; if (inwin($2)) { ww_iss[n]++ } }
        if (inwin($2)) ww_lines[n] += $col
      }
      if ($4 + $5 + $6 + $7 == 0) { wt_empty++; if (inwin($2)) ww_empty++ }
    } else if (kind == "resolved") {
      rt_issues++
      if (inwin($2)) rw_issues++
      split("observation opportunistic manual auto", names, " ")
      for (i = 1; i <= 4; i++) {
        col = 7 + i
        n = names[i]
        rt_lines[n] += $col
        if ($col > 0) { rt_iss[n]++; if (inwin($2)) { rw_iss[n]++ } }
        if (inwin($2)) rw_lines[n] += $col
      }
    }
  }
  END {
    split("observation opportunistic manual auto", names, " ")
    if (fmt == "tsv") {
      for (i = 1; i <= 4; i++) {
        n = names[i]
        printf "waiting\t%s_lines_all\t%d\n", n, wt_lines[n]+0
        printf "waiting\t%s_issues_all\t%d\n", n, wt_iss[n]+0
        printf "waiting\t%s_lines_window\t%d\n", n, ww_lines[n]+0
        printf "waiting\t%s_issues_window\t%d\n", n, ww_iss[n]+0
        printf "waiting\t%s_issues_older_than_window\t%d\n", n, (wt_iss[n]+0) - (ww_iss[n]+0)
        printf "resolved\t%s_lines_all\t%d\n", n, rt_lines[n]+0
        printf "resolved\t%s_issues_all\t%d\n", n, rt_iss[n]+0
        printf "resolved\t%s_lines_window\t%d\n", n, rw_lines[n]+0
        printf "resolved\t%s_issues_window\t%d\n", n, rw_iss[n]+0
      }
      printf "waiting\ttotal_issues_all\t%d\n", wt_issues+0
      printf "waiting\ttotal_issues_window\t%d\n", ww_issues+0
      printf "waiting\tno_unchecked_ac_all\t%d\n", wt_empty+0
      printf "waiting\tno_unchecked_ac_window\t%d\n", ww_empty+0
      printf "resolved\ttotal_issues_all\t%d\n", rt_issues+0
      printf "resolved\ttotal_issues_window\t%d\n", rw_issues+0
      printf "meta\twindow_start\t%s\n", window
      exit
    }

    printf "# phase/verify retention stats (window start: %s)\n\n", window
    printf "## 1. Waiting (phase/verify, unchecked post-merge AC)\n\n"
    printf "| verify-type | AC lines (all) | Issues (all) | AC lines (window) | Issues (window) |\n"
    printf "|---|---|---|---|---|\n"
    for (i = 1; i <= 4; i++) {
      n = names[i]
      printf "| %s | %d | %d | %d | %d |\n", n, wt_lines[n]+0, wt_iss[n]+0, ww_lines[n]+0, ww_iss[n]+0
    }
    printf "\nphase/verify Issues: %d (all) / %d (window)\n", wt_issues+0, ww_issues+0
    printf "Issues with no unchecked post-merge AC: %d (all) / %d (window) -- label transition may have been missed\n\n", wt_empty+0, ww_empty+0

    printf "## 2. Resolved (phase/done, checked post-merge AC)\n\n"
    printf "| verify-type | AC lines (all) | Issues (all) | AC lines (window) | Issues (window) |\n"
    printf "|---|---|---|---|---|\n"
    for (i = 1; i <= 4; i++) {
      n = names[i]
      printf "| %s | %d | %d | %d | %d |\n", n, rt_lines[n]+0, rt_iss[n]+0, rw_lines[n]+0, rw_iss[n]+0
    }
    printf "\nphase/done Issues: %d (all) / %d (window)\n\n", rt_issues+0, rw_issues+0

    printf "## 3. Resolution rate and age of waiting\n\n"
    printf "| verify-type | resolved (window) | waiting (window) | rate | waiting older than window |\n"
    printf "|---|---|---|---|---|\n"
    for (i = 1; i <= 4; i++) {
      n = names[i]
      denom = (rw_iss[n]+0) + (ww_iss[n]+0)
      if (denom > 0) {
        rate = sprintf("%d%%", int((rw_iss[n]+0) * 100 / denom))
      } else {
        rate = "n/a"
      }
      printf "| %s | %d | %d | %s | %d |\n", n, rw_iss[n]+0, ww_iss[n]+0, rate, (wt_iss[n]+0) - (ww_iss[n]+0)
    }
    printf "\nA large \"waiting older than window\" figure is the stale tail that\n"
    printf "escalation Level 3 (90+ days) is meant to clear -- see Issue #1271.\n"
  }
' "$CACHE"
