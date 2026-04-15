#!/bin/bash
# get-sub-issue-graph.sh - Fetch sub-issue dependency graph of a parent Issue and output as JSON
#
# Usage: get-sub-issue-graph.sh <parent-issue-number>
#
# Output (JSON):
# {
#   "sub_issues": [
#     {"number": 101, "title": "...", "state": "OPEN", "blocked_by": []},
#     {"number": 102, "title": "...", "state": "OPEN", "blocked_by": [101]}
#   ],
#   "independent": [101],
#   "execution_order": [[101], [102]]
# }

set -euo pipefail

PARENT_NUMBER="${1:?Usage: get-sub-issue-graph.sh <parent-issue-number>}"

if ! [[ "$PARENT_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $PARENT_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# Fetch sub-issues + blockedBy in a single GraphQL call
RAW_JSON=$("$SCRIPT_DIR/gh-graphql.sh" --query get-sub-issues -F "num=$PARENT_NUMBER")

# Extract only OPEN sub-issues, consider only dependencies within the parent Issue, and build JSON
jq -r '
  .data.repository.issue.subIssues.nodes // [] |
  # Extract only OPEN sub-issues
  map(select(.state == "OPEN")) as $open_issues |
  ($open_issues | map(.number)) as $open_numbers |

  # Build sub_issues list (blocked_by considers only OPEN sub-issues within parent)
  ($open_issues | map({
    number: .number,
    title: .title,
    state: .state,
    blocked_by: (
      (.blockedBy.nodes // []) |
      map(.number) |
      map(select(. as $n | $open_numbers | index($n) != null))
    )
  })) as $sub_issues |

  # Independent sub-issues (empty blocked_by)
  ($sub_issues | map(select(.blocked_by | length == 0)) | map(.number)) as $independent |

  # Calculate level-based execution order via topological sort
  # Each level: sub-issues whose blocked_by are all completed in prior levels
  (
    reduce range(50) as $_ (
      {"levels": [], "done": []};
      . as $acc |
      if ($sub_issues | map(select(
        (.blocked_by | all(. as $b | $acc.done | index($b) != null)) and
        (.number as $n | $acc.done | index($n) | not)
      )) | length) > 0 then
        ($sub_issues | map(select(
          (.blocked_by | all(. as $b | $acc.done | index($b) != null)) and
          (.number as $n | $acc.done | index($n) | not)
        ))) as $next_level |
        {
          "levels": ($acc.levels + [($next_level | map(.number))]),
          "done": ($acc.done + ($next_level | map(.number)))
        }
      else
        $acc
      end
    ) | .levels
  ) as $execution_order |

  # Circular dependency check: if resolved count differs from sub_issues count
  ([$execution_order[] | .[]] | length) as $resolved_count |
  if $resolved_count != ($sub_issues | length) then
    error("Circular dependency detected. Please check your dependency relationships.")
  else
    {
      sub_issues: $sub_issues,
      independent: $independent,
      execution_order: $execution_order
    }
  end
' <<< "$RAW_JSON"
