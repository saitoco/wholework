#!/bin/bash
# detect-pr-ci-workflows.sh - Detect whether any GitHub Actions workflow file
# under <repo-root>/.github/workflows/ (directly, non-recursive) is triggered
# by pull_request or pull_request_target.
#
# Usage: detect-pr-ci-workflows.sh [<repo-root>]
#   <repo-root> defaults to the current directory.
#
# Output (single line to stdout):
#   present - at least one *.yml/*.yaml file directly under
#             .github/workflows/ has a pull_request / pull_request_target
#             trigger outside a comment
#   absent  - no such file has that trigger, and no read/detection error
#             occurred (also covers a missing .github/workflows directory,
#             or zero *.yml/*.yaml files under it)
#   unknown - <repo-root> is not a directory, is not a readable+searchable
#             directory itself, .github/workflows exists but is not a
#             readable+searchable directory, or a workflow file could not
#             be read (grep exit code >= 2, e.g. permission denied)
#
# Fail-safe policy: fail-closed. Only "absent" changes caller behavior
# (scripts/run-review.sh's CI wait gate; modules/ci-failure-classifier.md's
# Structural CI Absence Check). Callers treat "unknown" and any script
# failure the same as "present" — i.e., they keep existing PENDING / retry
# behavior unchanged.
#
# Bash 3.2+ compatible: no mapfile, no reliance on `shopt -s nullglob`.

set -uo pipefail

if [[ $# -ge 2 ]]; then
  echo "Usage: detect-pr-ci-workflows.sh [<repo-root>]" >&2
  exit 1
fi

REPO_ROOT="${1:-.}"

if [[ ! -d "$REPO_ROOT" ]] || [[ ! -r "$REPO_ROOT" ]] || [[ ! -x "$REPO_ROOT" ]]; then
  echo "unknown"
  exit 0
fi

WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"

if [[ ! -e "$WORKFLOWS_DIR" ]]; then
  echo "absent"
  exit 0
fi

if [[ ! -d "$WORKFLOWS_DIR" ]] || [[ ! -r "$WORKFLOWS_DIR" ]] || [[ ! -x "$WORKFLOWS_DIR" ]]; then
  echo "unknown"
  exit 0
fi

_had_error=false
for f in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
  [[ -e "$f" ]] || continue
  LC_ALL=C grep -qE '^[^#]*pull_request' "$f" 2>/dev/null
  _rc=$?
  if [[ "$_rc" -eq 0 ]]; then
    echo "present"
    exit 0
  elif [[ "$_rc" -ge 2 ]]; then
    _had_error=true
  fi
done

if [[ "$_had_error" == "true" ]]; then
  echo "unknown"
  exit 0
fi

echo "absent"
exit 0
