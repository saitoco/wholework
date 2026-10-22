#!/bin/bash
# push-to-base.sh - Push a local ref to origin/<base>; when the remote rejects the push by
# policy, land the commits through a phase-record PR (create + merge) instead.
#
# Usage: push-to-base.sh [--ref <local-ref>] [--base <branch>]
#   --ref   Local ref whose commits are pushed (default: same name as --base)
#   --base  Target branch on origin (default: main)
#
# Behavior:
#   1. Try the direct push first (no configuration key: whether direct push is allowed is
#      decided by how git reports the rejection).
#   2. A rejection reported as "[remote rejected]" is a server-side refusal (branch
#      protection, ruleset, pre-receive hook). Only then push a record branch
#      (wholework-record/...), open a PR against <base>, and merge it right away with the
#      repository's merge-strategy (scripts/resolve-merge-strategy.sh).
#   3. Every other failure ("[rejected]" non-fast-forward / fetch first, network, auth, or
#      an output that cannot be classified) is reported as retryable and never creates a PR.
#
# Exit codes:
#   0  Landed. stdout: "push-to-base: result=direct" or
#      "push-to-base: result=record-pr url=<PR URL>"
#   1  Retryable failure (no PR or branch was created). Caller may fetch/rebase and retry
#   2  Could not land (invalid arguments, or the record-PR path failed). Where the commits
#      are kept (local record branch, remote record branch, PR URL) is written to stderr
#
# Callers: scripts/worktree-merge-push.sh (push step), skills/merge/SKILL.md (Step 4).
# See modules/worktree-lifecycle.md "Direct push rejected by the remote: phase-record PR"
# and modules/orchestration-fallbacks.md#push-rejected-record-pr.
#
# bash 3.2+ compatible (no associative arrays, mapfile, or readarray).

set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
# Interval between merge / state-check retries (seconds); overridable so tests do not wait.
RETRY_INTERVAL="${WHOLEWORK_PUSH_RETRY_INTERVAL:-2}"

usage() {
  echo "Usage: push-to-base.sh [--ref <local-ref>] [--base <branch>]" >&2
}

REF=""
BASE="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --ref requires a ref name" >&2
        usage
        exit 2
      fi
      REF="$2"
      shift 2
      ;;
    --base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --base requires a branch name" >&2
        usage
        exit 2
      fi
      BASE="$2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -z "$REF" ]] && REF="$BASE"

if ! git check-ref-format --branch "$BASE" >/dev/null 2>&1; then
  echo "Error: invalid base branch name: $BASE" >&2
  usage
  exit 2
fi
if ! git rev-parse --verify --quiet "${REF}^{commit}" >/dev/null 2>&1; then
  echo "Error: cannot resolve ref to a commit: $REF" >&2
  usage
  exit 2
fi

# --- Step 1: direct push -------------------------------------------------------------
if [[ "$REF" == "$BASE" ]]; then
  PUSH_REFSPEC="$BASE"
else
  PUSH_REFSPEC="${REF}:refs/heads/${BASE}"
fi

push_out=$(LC_ALL=C git push origin "$PUSH_REFSPEC" 2>&1)
push_rc=$?
[[ -n "$push_out" ]] && printf '%s\n' "$push_out" >&2

if [[ $push_rc -eq 0 ]]; then
  echo "push-to-base: result=direct"
  exit 0
fi

# A server-side refusal is reported by git as "[remote rejected]"; the client-side
# non-fast-forward judgment is "[rejected]". Anything else is retryable (fail-safe: never
# open a PR on an output that cannot be classified).
if ! printf '%s\n' "$push_out" | grep -qF '[remote rejected]'; then
  exit 1
fi

# --- Step 2: phase-record PR ---------------------------------------------------------
# See modules/orchestration-fallbacks.md#push-rejected-record-pr
TMP_BODY=""
TMP_SQUASH=""
cleanup_tmp() {
  [[ -n "$TMP_BODY" ]] && rm -f "$TMP_BODY" 2>/dev/null
  [[ -n "$TMP_SQUASH" ]] && rm -f "$TMP_SQUASH" 2>/dev/null
  return 0
}
trap cleanup_tmp EXIT

RECORD_BRANCH="wholework-record/${BASE//\//-}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
if ! git check-ref-format --branch "$RECORD_BRANCH" >/dev/null 2>&1; then
  echo "Error: generated record branch name is invalid: $RECORD_BRANCH" >&2
  exit 2
fi

# Report where the commits are kept, then fail closed (exit 2).
fail_record() {
  local stage="$1" local_state="$2" remote_state="$3" recovery="$4"
  {
    echo "Error: direct push to ${BASE} was rejected by the remote and the phase-record PR path failed at: ${stage}"
    echo "  Local record branch: ${RECORD_BRANCH} (${local_state})"
    echo "  Remote record branch: ${remote_state}"
    echo "  Recovery: ${recovery}"
  } >&2
  exit 2
}

echo "Direct push to ${BASE} was rejected by the remote; landing via phase-record PR (${RECORD_BRANCH})..." >&2

if ! git branch "$RECORD_BRANCH" "$REF" >/dev/null 2>&1; then
  echo "Error: could not create local record branch ${RECORD_BRANCH} from ${REF}" >&2
  exit 2
fi
RECORD_SHA=$(git rev-parse "refs/heads/${RECORD_BRANCH}" 2>/dev/null || true)
if [[ -z "$RECORD_SHA" ]]; then
  fail_record "resolve record branch SHA" "kept" "not pushed" \
    "inspect the local branch ${RECORD_BRANCH}, push it and open a PR against ${BASE} manually"
fi

RANGE="refs/remotes/origin/${BASE}..refs/heads/${RECORD_BRANCH}"

# The PR body and the squash message are built from RANGE; without the remote-tracking ref
# the log would come back empty and the squash commit would lose the original messages
# (closes #N, Signed-off-by). Try to fetch it once, otherwise fail closed.
if ! git rev-parse --verify --quiet "refs/remotes/origin/${BASE}^{commit}" >/dev/null 2>&1; then
  git fetch origin "$BASE" >&2 2>&1 || true
  if ! git rev-parse --verify --quiet "refs/remotes/origin/${BASE}^{commit}" >/dev/null 2>&1; then
    fail_record "resolve refs/remotes/origin/${BASE}" "kept" "not pushed" \
      "run: git fetch origin ${BASE}, then push ${RECORD_BRANCH} and open a PR against ${BASE} manually"
  fi
fi

if ! LC_ALL=C git push origin "refs/heads/${RECORD_BRANCH}:refs/heads/${RECORD_BRANCH}" >&2; then
  fail_record "push record branch" "kept" "not pushed" \
    "fix the push failure, then run: git push origin ${RECORD_BRANCH} and open a PR against ${BASE}"
fi

if ! command -v gh >/dev/null 2>&1; then
  fail_record "create PR (gh not found)" "kept" "pushed" \
    "open a PR from ${RECORD_BRANCH} to ${BASE} and merge it manually"
fi

PR_TITLE="Phase record: $(git log -1 --format=%s "refs/heads/${RECORD_BRANCH}" 2>/dev/null | tr -d '\r')"

TMP_BODY=$(mktemp 2>/dev/null || true)
if [[ -z "$TMP_BODY" ]]; then
  fail_record "create PR (mktemp failed)" "kept" "pushed" \
    "open a PR from ${RECORD_BRANCH} to ${BASE} and merge it manually"
fi
{
  echo "A direct push to ${BASE} was rejected by the remote (branch protection, ruleset, or hook)."
  echo "Wholework records the phase artifacts through this PR and merges it right away."
  echo
  echo "Commits:"
  git log --format='- %h %s' "$RANGE" 2>/dev/null | tr -d '\r'
} > "$TMP_BODY"

PR_URL=$(gh pr create --base "$BASE" --head "$RECORD_BRANCH" --title "$PR_TITLE" --body-file "$TMP_BODY" | tail -n 1 | tr -d '\r')
if [[ -z "$PR_URL" ]] || [[ "$PR_URL" != http* ]]; then
  fail_record "create PR" "kept" "pushed" \
    "open a PR from ${RECORD_BRANCH} to ${BASE} and merge it manually"
fi

# Merge method: same fail-safe as resolve-merge-strategy.sh itself (anything unexpected -> squash).
# The resolver reads .wholework.yml relative to the CWD, so run it from the repository root.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
MERGE_FLAG=$( (cd "${REPO_ROOT:-.}" && "$SCRIPT_DIR/resolve-merge-strategy.sh" --flag) 2>/dev/null || true)
case "$MERGE_FLAG" in
  --squash|--merge|--rebase) ;;
  *) MERGE_FLAG="--squash" ;;
esac

MERGE_ARGS=("$PR_URL" "$MERGE_FLAG" --delete-branch --match-head-commit "$RECORD_SHA")
if [[ "$MERGE_FLAG" == "--squash" ]]; then
  TMP_SQUASH=$(mktemp 2>/dev/null || true)
  if [[ -z "$TMP_SQUASH" ]]; then
    fail_record "merge PR (mktemp failed)" "kept" "pushed; PR ${PR_URL} stays open" \
      "merge ${PR_URL} manually"
  fi
  git log --format=%B "$RANGE" 2>/dev/null | tr -d '\r' > "$TMP_SQUASH"
  MERGE_ARGS+=(--subject "$PR_TITLE" --body-file "$TMP_SQUASH")
fi

# Success is judged by the PR state, not the exit code of `gh pr merge` (a failing
# --delete-branch cleanup must not turn a completed merge into a failure).
pr_state=""
merge_try=0
while [[ $merge_try -lt 3 ]]; do
  merge_try=$((merge_try + 1))
  gh pr merge "${MERGE_ARGS[@]}" >&2 2>&1 || true
  verify_try=0
  while [[ $verify_try -lt 3 ]]; do
    verify_try=$((verify_try + 1))
    pr_state=$(gh pr view "$PR_URL" --json state -q .state 2>/dev/null | tr -d '\r' || true)
    [[ "$pr_state" == "MERGED" ]] && break
    [[ $verify_try -lt 3 ]] && sleep "$RETRY_INTERVAL"
  done
  [[ "$pr_state" == "MERGED" ]] && break
  [[ $merge_try -lt 3 ]] && sleep "$RETRY_INTERVAL"
done

if [[ "$pr_state" != "MERGED" ]]; then
  fail_record "merge PR (state=${pr_state:-unknown})" "kept" "pushed; PR ${PR_URL} stays open" \
    "merge ${PR_URL} manually (required approvals, required checks, or a merge queue may be blocking it)"
fi

git branch -D "$RECORD_BRANCH" >/dev/null 2>&1 || true
git fetch origin "$BASE" >&2 || echo "Warning: git fetch origin ${BASE} failed after the record PR merged" >&2

echo "push-to-base: result=record-pr url=${PR_URL}"
exit 0
