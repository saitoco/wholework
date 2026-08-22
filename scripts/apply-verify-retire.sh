#!/usr/bin/env bash
# apply-verify-retire.sh
# Deterministic autonomy-tier gate + retire executor for phase/verify Level 3
# (90+ day dwell) escalation (see docs/spec/issue-1271-verify-retention-auto-retire.md).
# This is the only script in the Level 3 routing path that writes to GitHub
# (Issue body / comment / label / state).
#
# Usage:
#   scripts/apply-verify-retire.sh --issue <N> --dwell <days> [--dry-run]
#
# Level x autonomy-tier gate (exhaustive):
#   LEVEL < 3            -> action=none    (no L0 writes; Level 0/1/2 routing stays
#                            owned by skills/audit/SKILL.md, unchanged by this script)
#   LEVEL = 3, TIER = L1  -> action=propose (no L0 writes; caller posts the existing
#                            "manual confirmation or remove observation condition" comment)
#   LEVEL = 3, TIER in {L2, L3} -> action=retire (this script performs the retire)
#
# LEVEL resolution: scripts/compute-escalation-level.sh verify <dwell>. A non-zero
# exit from that script is treated as fail-**closed**: a dwell that cannot be
# classified must never lead to a retire.
#
# Tier resolution: AUTONOMY_TIER env var > `get-config-value.sh autonomy L1`. Any
# value other than L1/L2/L3 falls back to L1 (safest), matching
# modules/detect-config-markers.md's existing autonomy-tier fallback rule and
# apply-run-fact-match.sh's resolution order.
#
# Retire target scope: only unchecked (`- [ ]`) Post-merge acceptance conditions
# tagged `<!-- verify-type: observation -->` or `<!-- verify-type: opportunistic -->`
# are retired. `manual` (explicitly judged to need a human) and `auto` (recoverable
# by a single /verify dispatch) are left untouched -- Level 3 still only proposes
# for those. Fenced code block content is never treated as a real AC line (same
# in_fence convention as scripts/check-pre-merge-ac.sh / modules/l0-surfaces.md
# § AC Enumeration Convention).
#
# Body rewrite: retired lines are removed from `### Post-merge` and appended as
# strikethrough entries under `### Retired Post-merge Conditions` (created
# immediately after `### Post-merge` on first use; appended to on subsequent
# runs) -- the #1165/#706 retire-format precedent. If `### Post-merge` has no
# `- [` line left after removal, a single prose line is inserted so the section
# is never left as bare bullet-less prose in violation of
# scripts/check-ac-checkbox-format.sh's format guard.
#
# Malformed structure guard: the body rewrite assumes exactly one `### Post-merge`
# (or `## Post-merge`) heading, and (when `### Retired Post-merge Conditions`
# already exists) that it comes AFTER the Post-merge heading. Either violation
# makes the line-range-based rebuild ambiguous, so the script refuses to rewrite
# and falls back to the same fail-open shape as a body-fetch failure
# (`action=retire` / `retired=0`, warning to stderr) rather than risk silently
# corrupting the body (duplicated heading / a "retired" condition left live).
#
# Retire-target verify-type tag matching requires a closing `-->` on the same
# line; a `<!-- verify-type: ...` tag with no closing delimiter is treated as
# absent (not retired), since an unterminated HTML comment written back to the
# Issue body would swallow the remainder of the body/comment when rendered by
# GitHub.
#
# Output (stdout):
#   Line 1 is always `action=<none|propose|retire>`. When LEVEL=3 and TIER is
#   L2/L3, the script tentatively targets `retire` but the Issue body is always
#   read and parsed before this line is actually printed: if the body's
#   Post-merge section has zero unchecked observation/opportunistic conditions
#   (e.g. it contains only manual/auto conditions), the script prints
#   `action=propose` instead -- identical in shape to the L1 propose case, so
#   the caller posts the same decision-prompt comment a human should still see.
#   `action=retire` is printed only when a real retire is attempted (including
#   its fail-open short-circuits below).
#   When action=retire, three more lines follow: `retired=<N>`, `remaining=<M>`
#   (unchecked post-merge AC left after the rewrite, any verify-type),
#   `transitioned=<true|false>` (whether the issue moved to phase/done). On any
#   fail-open short-circuit inside the retire path (issue body fetch failure,
#   malformed structure guard, or a failed body write-back), only `retired=0` is
#   printed and the script exits before computing remaining/transitioned.
#
# --dry-run: performs the same read + computation as a real run but skips every
#   L0 write (body edit, comment, label transition, issue close); the printed
#   retired/remaining/transitioned values are "if this ran for real" values.
#
# Exit codes: 1 on invalid arguments (missing/non-numeric --issue or --dwell,
#   unknown option). 0 otherwise, including all fail-open/fail-closed branches
#   above -- this script must never abort the /audit run that calls it.
#
# Fail-safe direction (asymmetric by design -- see Spec Notes "fail-safe critical判定"):
#   compute-escalation-level.sh failure -> fail-closed (action=none)
#   issue body fetch failure            -> fail-open (action=retire, retired=0, exit 0)
#   malformed structure (multiple Post-merge headings, or Retired-before-Post-merge)
#                                        -> fail-open (action=retire, retired=0, exit 0)
#   zero retire targets (manual/auto-only Post-merge)
#                                        -> action=propose (caller posts the decision-prompt comment)
#   body write-back failure             -> fail-open, no comment/label transition
#   comment / label transition failure  -> fail-open (warning only, continue)
#
# bash 3.2+ compatible (macOS system bash): no mapfile, no ${VAR,,}.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

usage() {
  echo "Usage: $0 --issue <N> --dwell <days> [--dry-run]" >&2
}

ISSUE_NUMBER=""
DWELL=""
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      if [ $# -lt 2 ]; then
        echo "Error: --issue requires an argument" >&2
        usage
        exit 1
      fi
      ISSUE_NUMBER="$2"
      shift 2
      ;;
    --dwell)
      if [ $# -lt 2 ]; then
        echo "Error: --dwell requires an argument" >&2
        usage
        exit 1
      fi
      DWELL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$ISSUE_NUMBER" ] || ! echo "$ISSUE_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "Error: --issue is required and must be a positive integer" >&2
  usage
  exit 1
fi
if [ -z "$DWELL" ] || ! echo "$DWELL" | grep -qE '^[0-9]+$'; then
  echo "Error: --dwell is required and must be a non-negative integer" >&2
  usage
  exit 1
fi

# --- LEVEL resolution (fail-closed) -----------------------------------------

if ! LEVEL=$("$SCRIPT_DIR/compute-escalation-level.sh" verify "$DWELL" 2>/dev/null); then
  echo "Warning: compute-escalation-level.sh failed for dwell=${DWELL}; fail-closed (action=none)" >&2
  echo "action=none"
  exit 0
fi

# --- TIER resolution ---------------------------------------------------------

TIER="${AUTONOMY_TIER:-}"
if [ -z "$TIER" ]; then
  TIER=$("$SCRIPT_DIR/get-config-value.sh" autonomy L1 2>/dev/null || echo L1)
fi
case "$TIER" in
  L1 | L2 | L3) ;;
  *)
    TIER="L1"
    ;;
esac

# --- Level x tier routing -----------------------------------------------------

ACTION="none"
if [ "$LEVEL" = "3" ]; then
  case "$TIER" in
    L1) ACTION="propose" ;;
    L2 | L3) ACTION="retire" ;;
  esac
fi

if [ "$ACTION" != "retire" ]; then
  echo "action=${ACTION}"
  exit 0
fi

# --- Retire path (tentative -- the body is parsed before "action=retire" is
# actually printed; a zero-target body resolves to action=propose instead) ---

BODY_FILE=$(mktemp)
RETIRE_META_FILE=$(mktemp)
META_FILE=$(mktemp)
NEW_BODY_FILE=$(mktemp)
COMMENT_FILE=$(mktemp)
cleanup() {
  rm -f "$BODY_FILE" "$RETIRE_META_FILE" "$META_FILE" "$NEW_BODY_FILE" "$COMMENT_FILE"
}
trap cleanup EXIT

if ! gh issue view "$ISSUE_NUMBER" --json body --jq '.body' > "$BODY_FILE" 2>/dev/null; then
  echo "Warning: failed to fetch issue body for #${ISSUE_NUMBER}; fail-open (retired=0)" >&2
  echo "action=retire"
  echo "retired=0"
  exit 0
fi

# Single-pass metadata + retire-target extraction. Writes:
#   RETIRE_META_FILE: <line_no>\t<global_ac_index>\t<verify-type>\t<had_cr:0|1>\t<clean text>
#     for every unchecked Post-merge AC line whose verify-type is
#     observation/opportunistic (retire candidates). had_cr records whether the
#     source line ended with a CRLF \r so the retired display line can restore it.
#   META_FILE: pm_start=/pm_end=/rt_start=/rt_end=/total_lines=/prose_needed=/
#     multi_pm=/reordered= (shell-sourceable; values are integers computed
#     entirely by this awk script -- never derived from Issue body content --
#     so sourcing is safe).
awk -v RETIRE_META="$RETIRE_META_FILE" -v META="$META_FILE" '
  BEGIN { in_fence = 0; idx = 0; section = "none"; pm_start = 0; pm_end = 0; rt_start = 0; rt_end = 0; pm_heading_count = 0 }
  {
    line = $0
    if (line ~ /^[ \t]*```/) {
      in_fence = !in_fence
    } else if (!in_fence) {
      if (line ~ /^### Post-merge/ || line ~ /^## Post-merge/) {
        if (section == "postmerge" && pm_end == 0) pm_end = NR - 1
        if (section == "retired" && rt_end == 0) rt_end = NR - 1
        section = "postmerge"; pm_start = NR
        pm_heading_count++
      } else if (line ~ /^### Retired Post-merge Conditions/) {
        if (section == "postmerge" && pm_end == 0) pm_end = NR - 1
        section = "retired"; rt_start = NR
      } else if (line ~ /^## / || line ~ /^### /) {
        if (section == "postmerge" && pm_end == 0) pm_end = NR - 1
        if (section == "retired" && rt_end == 0) rt_end = NR - 1
        section = "other"
      }
    }
    fence_state[NR] = in_fence
    if (!in_fence && line ~ /^- \[[ xX]\]/) {
      idx++
      if (section == "postmerge" && substr(line, 4, 1) == " ") {
        vtype = ""
        # Full-span match through the tags own closing --> (modules/verify-classifier.md
        # section Tag Extraction Rule canonical form) -- a tag with no closing delimiter on the
        # same line does not match and is treated as absent, since an unterminated <!-- written
        # back to the Issue body would swallow the remainder of the rendered body/comment on GitHub.
        if (match(line, /<!--[ \t]*verify-type:[ \t]*[a-zA-Z_]+([^-]|-[^-]|--[^>])*-->/)) {
          tag = substr(line, RSTART, RLENGTH)
          sub(/^<!--[ \t]*verify-type:[ \t]*/, "", tag)
          match(tag, /^[a-zA-Z_]+/)
          vtype = substr(tag, RSTART, RLENGTH)
        }
        if (vtype == "observation" || vtype == "opportunistic") {
          text = line
          sub(/^- \[ \][ \t]*/, "", text)
          gsub(/<!--([^-]|-[^-]|--[^>])*-->/, "", text)
          gsub(/^[ \t]+/, "", text)
          had_cr = (text ~ /\r$/) ? 1 : 0
          gsub(/[ \t\r]+$/, "", text)
          print NR "\t" idx "\t" vtype "\t" had_cr "\t" text > RETIRE_META
          retired_line[NR] = 1
        }
      }
    }
    raw[NR] = line
    total_lines = NR
  }
  END {
    close(RETIRE_META)
    if (section == "postmerge" && pm_end == 0) pm_end = total_lines
    if (section == "retired" && rt_end == 0) rt_end = total_lines
    remaining_pm_checkbox = 0
    for (i = pm_start + 1; i <= pm_end; i++) {
      if (retired_line[i]) continue
      if (fence_state[i]) continue
      if (raw[i] ~ /^- \[/) remaining_pm_checkbox = 1
    }
    printf "pm_start=%d\n", pm_start > META
    printf "pm_end=%d\n", pm_end > META
    printf "rt_start=%d\n", rt_start > META
    printf "rt_end=%d\n", rt_end > META
    printf "total_lines=%d\n", total_lines > META
    printf "prose_needed=%d\n", (pm_start > 0 && !remaining_pm_checkbox) ? 1 : 0 > META
    printf "multi_pm=%d\n", (pm_heading_count > 1) ? 1 : 0 > META
    printf "reordered=%d\n", (rt_start > 0 && pm_start > 0 && rt_start < pm_start) ? 1 : 0 > META
    close(META)
  }
' "$BODY_FILE"

# shellcheck source=/dev/null
. "$META_FILE"

if [ "${multi_pm:-0}" = "1" ]; then
  echo "Warning: multiple ### Post-merge headings found in issue #${ISSUE_NUMBER}; refusing to rewrite (ambiguous section boundaries)" >&2
  echo "action=retire"
  echo "retired=0"
  exit 0
fi

if [ "${reordered:-0}" = "1" ]; then
  echo "Warning: ### Retired Post-merge Conditions precedes ### Post-merge in issue #${ISSUE_NUMBER}; refusing to rewrite (unexpected section order)" >&2
  echo "action=retire"
  echo "retired=0"
  exit 0
fi

RETIRED_COUNT=$(wc -l < "$RETIRE_META_FILE" | tr -d ' ')
if [ -z "$RETIRED_COUNT" ] || [ "$RETIRED_COUNT" -eq 0 ]; then
  echo "action=propose"
  exit 0
fi

echo "action=retire"

# --- Build the rewritten body -------------------------------------------------

RETIRE_LINES_FILE=$(mktemp)
trap 'cleanup; rm -f "$RETIRE_LINES_FILE"' EXIT
cut -f1 "$RETIRE_META_FILE" > "$RETIRE_LINES_FILE"

# Segment 1: lines 1..pm_end, dropping retired lines; insert prose if the
# Post-merge section has no `- [` line left.
awk -v endline="$pm_end" -v exclf="$RETIRE_LINES_FILE" '
  BEGIN { while ((getline l < exclf) > 0) ex[l] = 1 }
  NR <= endline { if (!(NR in ex)) print; next }
  { exit }
' "$BODY_FILE" > "$NEW_BODY_FILE"

if [ "$prose_needed" = "1" ]; then
  printf "%s\n" "すべての post-merge 条件は phase/verify Level 3 の自動 retire で退避済み (下記 \`### Retired Post-merge Conditions\` を参照)。" >> "$NEW_BODY_FILE"
fi

# Determine the most recent dispatch marker's createdAt for this Issue (used
# in every retired line's audit text below). Read-only, so this is safe to
# run even for --dry-run.
DISPATCH_TS=$(gh issue view "$ISSUE_NUMBER" --json comments \
  --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=observation-trigger") or contains("<!-- wholework-event: type=batch-verify-dispatch")) | .createdAt] | sort | last // empty' \
  2>/dev/null || true)
if [ -z "$DISPATCH_TS" ]; then
  DISPATCH_TS="none"
fi

# Segment 2: the (existing or new) Retired Post-merge Conditions section,
# followed by whatever originally followed it.
{
  if [ "$rt_start" -gt 0 ]; then
    awk -v s="$((pm_end + 1))" -v e="$rt_end" 'NR >= s && NR <= e { print }' "$BODY_FILE"
  else
    printf '\n### Retired Post-merge Conditions\n\n'
  fi
  while IFS=$'\t' read -r _lno _gidx vtype had_cr text; do
    cr=""
    if [ "$had_cr" = "1" ]; then
      cr=$'\r'
    fi
    printf -- "- ~~%s~~ — **retired (auto, dwell %sd)**: 90 日間 event が発火せず、または発火しても判定に至らなかった (verify-type: %s, 最終 dispatch: %s)%s\n" \
      "$text" "$DWELL" "$vtype" "$DISPATCH_TS" "$cr"
  done < "$RETIRE_META_FILE"
  if [ "$rt_start" -gt 0 ]; then
    awk -v s="$((rt_end + 1))" -v e="$total_lines" 'NR >= s && NR <= e { print }' "$BODY_FILE"
  else
    awk -v s="$((pm_end + 1))" -v e="$total_lines" 'NR >= s && NR <= e { print }' "$BODY_FILE"
  fi
} >> "$NEW_BODY_FILE"

REMAINING=$(awk '
  BEGIN { in_section = 0; in_fence = 0; n = 0 }
  /^[ \t]*```/ { in_fence = !in_fence; next }
  in_fence { next }
  /^### Post-merge/ || /^## Post-merge/ { in_section = 1; next }
  /^## / || /^### / { in_section = 0; next }
  in_section && /^- \[ \]/ { n++ }
  END { print n + 0 }
' "$NEW_BODY_FILE")

if [ "$REMAINING" -eq 0 ]; then
  WOULD_TRANSITION=true
else
  WOULD_TRANSITION=false
fi

if [ "$DRY_RUN" = true ]; then
  echo "retired=${RETIRED_COUNT}"
  echo "remaining=${REMAINING}"
  echo "transitioned=${WOULD_TRANSITION}"
  exit 0
fi

# --- Real run: write body back, then comment + label transition --------------

if ! "$SCRIPT_DIR/gh-issue-edit.sh" "$ISSUE_NUMBER" "$NEW_BODY_FILE" >/dev/null 2>&1; then
  echo "Warning: failed to write retired body for issue #${ISSUE_NUMBER}; skipping comment and label transition (fail-open, retired=0)" >&2
  echo "retired=0"
  exit 0
fi

AC_LIST=$(cut -f2 "$RETIRE_META_FILE" | paste -s -d, -)
{
  printf '%s\n' "<!-- wholework-event: type=verify-ac-retired phase=audit issue=${ISSUE_NUMBER} dwell=${DWELL} ac=${AC_LIST} verify-types=observation,opportunistic -->"
  printf '%s\n\n' "## phase/verify Level 3 Auto-Retire"
  printf "dwell: %sd, 最終 dispatch: %s\n\n" "$DWELL" "$DISPATCH_TS"
  printf "Retired post-merge acceptance conditions (90 日間 event が発火せず、または発火しても判定に至らなかった):\n\n"
  while IFS=$'\t' read -r _lno gidx vtype _had_cr text; do
    printf -- "- #%s (verify-type: %s): %s\n" "$gidx" "$vtype" "$text"
  done < "$RETIRE_META_FILE"
} > "$COMMENT_FILE"

if ! "$SCRIPT_DIR/gh-issue-comment.sh" "$ISSUE_NUMBER" "$COMMENT_FILE" >/dev/null 2>&1; then
  echo "Warning: failed to post retire audit-trail comment on issue #${ISSUE_NUMBER}" >&2
fi

TRANSITIONED=false
if [ "$REMAINING" -eq 0 ]; then
  if "$SCRIPT_DIR/gh-label-transition.sh" "$ISSUE_NUMBER" done >/dev/null 2>&1; then
    STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state' 2>/dev/null || echo "")
    if [ "$STATE" = "OPEN" ]; then
      if ! gh issue close "$ISSUE_NUMBER" >/dev/null 2>&1; then
        echo "Warning: failed to close issue #${ISSUE_NUMBER}" >&2
      fi
    fi
    TRANSITIONED=true
  else
    echo "Warning: failed to transition issue #${ISSUE_NUMBER} to phase/done; not closing" >&2
  fi
fi

echo "retired=${RETIRED_COUNT}"
echo "remaining=${REMAINING}"
echo "transitioned=${TRANSITIONED}"
exit 0
