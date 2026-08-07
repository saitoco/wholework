#!/bin/bash
# opportunistic-search.sh
# Issue search helper script for opportunistic verification
#
# Usage:
#   scripts/opportunistic-search.sh <skill-name> [--dry-run] [--facts <path>]
#   scripts/opportunistic-search.sh --event <event-name> [--dry-run] [--context-file <path>] [--facts-file <path>]
#
# Examples:
#   scripts/opportunistic-search.sh /issue
#   scripts/opportunistic-search.sh /spec --dry-run
#   scripts/opportunistic-search.sh /verify --facts .tmp/facts-session1.json
#   scripts/opportunistic-search.sh --event pr-review-full
#   scripts/opportunistic-search.sh --event auto-run --dry-run
#   scripts/opportunistic-search.sh --event pr-review-full --context-file /tmp/spec.md
#   scripts/opportunistic-search.sh --event auto-run --facts-file .tmp/run-facts-session1.json
#
# --context-file gates event-mode matches: when a matched AC line carries a
# `keyword=<text>` attribute and --context-file is given, the Issue is only
# included if the context file contains that keyword (case-insensitive) after
# path-like tokens (e.g. docs/workflow.md) are stripped from the context file's
# content. ACs without `keyword=`, or runs without --context-file, match
# unconditionally (backward compatible). See modules/observation-trigger.md §
# Condition Check Gate (keyword=).
#
# `config=<key>` gates event-mode matches on .wholework.yml validity: when a
# matched AC line carries a `config=<key>` attribute, the Issue is only
# included if that flat kebab-case key resolves to "true" (case-insensitive)
# in the current repository's .wholework.yml (via get-config-value.sh). ACs
# without `config=` match unconditionally (backward compatible). No new CLI
# argument is needed — .wholework.yml is read directly from CWD. See
# modules/observation-trigger.md § Condition Check Gate (config=).
#
# `when=<axis>:<value>` gates event-mode matches on /auto run context (route /
# mode / recovery-tier): when a matched AC line carries a `when=` attribute,
# the Issue is only included if the run facts JSON (scripts/collect-run-facts.sh
# output) satisfies every comma-separated clause (AND). --facts-file <path>
# supplies the facts JSON explicitly; when omitted, the facts are collected
# lazily (once per process) by calling collect-run-facts.sh with no arguments.
# Facts that are unavailable, invalid, or contextless resolve the gate to
# unconditional match (fail-open). ACs without `when=` match unconditionally
# (backward compatible). See modules/observation-trigger.md § Condition Check
# Gate (when=).
#
# --facts <path>: opportunistic mode (--event omitted) only. Pre-filters matches by
# run-fact token substring: a matched AC line is only included if its condition text
# (lowercased, HTML comments and checkbox markup stripped) contains at least one token
# from --facts <path>'s collect-run-facts.sh JSON (unioned fact_tokens across all
# issues, same matching logic as scripts/scan-pending-ac.sh's --facts). No AC-side
# attribute is required. Ignored in event mode (--event) -- event mode uses
# --facts-file/when= instead. When --facts <path> is omitted, missing, or unparseable,
# a warning is printed and the gate is disabled (fail-open), the same convention as
# --context-file/--facts-file above. Distinct from --facts-file <path>, which gates
# event-mode when=<axis>:<value> clauses against structured run-facts fields.
#
# Output: JSON array [{"number": N, "condition": "condition text"}]
#         Empty array [] when no matches found

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# Parse arguments
SKILL_NAME=""
EVENT_NAME=""
DRY_RUN=false
CONTEXT_FILE=""
FACTS_FILE=""
FACTS_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --event)
            if [ $# -lt 2 ]; then
                echo "Error: --event requires an argument" >&2
                exit 1
            fi
            EVENT_NAME="$2"
            shift 2
            ;;
        --context-file)
            if [ $# -lt 2 ]; then
                echo "Error: --context-file requires an argument" >&2
                exit 1
            fi
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --facts-file)
            if [ $# -lt 2 ]; then
                echo "Error: --facts-file requires an argument" >&2
                exit 1
            fi
            FACTS_FILE="$2"
            shift 2
            ;;
        --facts)
            if [ $# -lt 2 ]; then
                echo "Error: --facts requires an argument" >&2
                exit 1
            fi
            FACTS_PATH="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [ -n "$SKILL_NAME" ]; then
                echo "Error: Only one skill name may be specified" >&2
                exit 1
            fi
            SKILL_NAME="$1"
            shift
            ;;
    esac
done

# Validate: skill name required when --event is not specified
if [ -z "$EVENT_NAME" ] && [ -z "$SKILL_NAME" ]; then
    echo "Usage: $0 <skill-name> [--dry-run]" >&2
    echo "       $0 --event <event-name> [--dry-run]" >&2
    echo "Example: $0 /issue" >&2
    echo "         $0 --event pr-review-full" >&2
    exit 1
fi

# Validate known event names; warn and fall back to opportunistic treatment on unknown
KNOWN_EVENTS="pr-review-full pr-review-light auto-run watchdog-kill fix-cycle"
if [ -n "$EVENT_NAME" ]; then
    IS_KNOWN=false
    for e in $KNOWN_EVENTS; do
        if [ "$EVENT_NAME" = "$e" ]; then
            IS_KNOWN=true
            break
        fi
    done
    if [ "$IS_KNOWN" = false ]; then
        echo "Warning: unknown event '${EVENT_NAME}', falling back to opportunistic treatment" >&2
        # Fall back: treat as opportunistic (clear event, require skill name)
        EVENT_NAME=""
        if [ -z "$SKILL_NAME" ]; then
            echo "Error: unknown event fallback requires a skill name" >&2
            exit 1
        fi
    fi
fi

# --context-file gate: if the path does not exist, disable the gate (fall back to unconditional match)
if [ -n "$CONTEXT_FILE" ] && [ ! -f "$CONTEXT_FILE" ]; then
    echo "Warning: --context-file '${CONTEXT_FILE}' not found, disabling condition check gate" >&2
    CONTEXT_FILE=""
fi

# --facts-file: if the path does not exist, clear it so resolve_run_facts() falls back to
# lazy collection instead of reading a missing file.
if [ -n "$FACTS_FILE" ] && [ ! -f "$FACTS_FILE" ]; then
    echo "Warning: --facts-file '${FACTS_FILE}' not found, falling back to lazy run-facts collection" >&2
    FACTS_FILE=""
fi

# --facts <path>: resolve the union of fact_tokens (lowercased) from the given
# collect-run-facts.sh JSON, same logic as scripts/scan-pending-ac.sh's --facts. Missing
# path or parse failure disables the gate with a warning (fail-open), matching the
# --context-file/--facts-file convention above rather than scan-pending-ac.sh's hard error.
FACT_TOKENS_LOWER=""
if [ -n "$FACTS_PATH" ]; then
    if [ ! -f "$FACTS_PATH" ]; then
        echo "Warning: --facts '${FACTS_PATH}' not found, disabling fact-token filter gate" >&2
    else
        FACT_TOKENS_LOWER=$(jq -r '[.issues[].fact_tokens[]?] | unique | .[]' "$FACTS_PATH" 2>/dev/null | tr '[:upper:]' '[:lower:]') || {
            echo "Warning: failed to parse --facts file '${FACTS_PATH}', disabling fact-token filter gate" >&2
            FACT_TOKENS_LOWER=""
        }
    fi
fi

# resolve_run_facts: lazily resolve run facts JSON, once per process. Called on demand by
# the first `when=`-tagged AC line encountered in the match loop below. Result is cached in
# RUN_FACTS_JSON (empty string means the gate is disabled — fail-open).
RUN_FACTS_RESOLVED=false
RUN_FACTS_JSON=""

# resolve_filtered_context: lazily strip path-like tokens (e.g. docs/workflow.md) from
# CONTEXT_FILE, once per process. Called on demand by the first keyword=-tagged AC line
# encountered in the match loop below. Result is cached in FILTERED_CONTEXT (empty when
# CONTEXT_FILE is unset). This prevents a keyword= value from matching only because it
# appears as a fragment of an unrelated file path (Issue #1220).
FILTERED_CONTEXT_RESOLVED=false
FILTERED_CONTEXT=""

resolve_filtered_context() {
    if [ "$FILTERED_CONTEXT_RESOLVED" = true ]; then
        return
    fi
    FILTERED_CONTEXT_RESOLVED=true

    if [ -n "$CONTEXT_FILE" ]; then
        FILTERED_CONTEXT=$(sed -E 's#[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+##g' "$CONTEXT_FILE" 2>/dev/null || true)
    fi
}

resolve_run_facts() {
    if [ "$RUN_FACTS_RESOLVED" = true ]; then
        return
    fi
    RUN_FACTS_RESOLVED=true

    local facts
    if [ -n "$FACTS_FILE" ]; then
        facts=$(cat "$FACTS_FILE" 2>/dev/null || true)
    else
        facts=$("${SCRIPT_DIR}/collect-run-facts.sh" 2>/dev/null || true)
    fi

    if [ -z "$facts" ]; then
        echo "Warning: run facts unavailable, disabling when= condition check gate" >&2
        return
    fi
    if ! echo "$facts" | jq -e 'type == "object"' >/dev/null 2>&1; then
        echo "Warning: run facts are not a valid JSON object, disabling when= condition check gate" >&2
        return
    fi
    if echo "$facts" | jq -e '(.issues | length) == 0 and .mode == "unknown"' >/dev/null 2>&1; then
        echo "Warning: run facts carry no run context (empty issues, mode=unknown), disabling when= condition check gate" >&2
        return
    fi

    RUN_FACTS_JSON="$facts"
}

# 1. Fetch closed Issues with phase/verify label
#
# Previously fetched via a fixed --limit 50 with no pre-filter, silently
# truncating the population once phase/verify+closed Issues exceeded 50
# (Issue #1169). Adopted approach: pre-filter the population by mode via
# --search (observation vs. opportunistic AC text) + raise POPULATION_LIMIT
# to 300 + warn on stderr if the limit is still reached.
#
# Alternatives considered and rejected:
# - Full fetch (drop --limit entirely): rejected — the unfiltered population
#   is 316 Issues (measured 2026-08-05), which would make the per-Issue
#   `gh issue view` calls below scale linearly with total closed Issues, the
#   exact scaling problem the mode pre-filter avoids (54-132 Issues per mode
#   instead of 316).
# - Connect to /audit stats --retention retire escalation: rejected —
#   deciding which observation AC to retire is a separate concern from
#   stopping the silent truncation, and is out of scope for this Issue.
POPULATION_LIMIT=300
if [ -n "$EVENT_NAME" ]; then
    SEARCH_TEXT="verify-type: observation in:body"
else
    SEARCH_TEXT="verify-type: opportunistic in:body"
fi
ISSUES_JSON=$(gh issue list --label "phase/verify" --state closed --search "$SEARCH_TEXT" --json number --limit "$POPULATION_LIMIT")
ISSUE_COUNT=$(echo "$ISSUES_JSON" | jq 'length')
if [ "$ISSUE_COUNT" -ge "$POPULATION_LIMIT" ]; then
    echo "Warning: population fetch reached --limit ${POPULATION_LIMIT}; results may be truncated. Consider raising POPULATION_LIMIT in scripts/opportunistic-search.sh or narrowing the --search filter." >&2
fi
ISSUE_NUMBERS=$(echo "$ISSUES_JSON" | jq -r '.[].number')

if [ -z "$ISSUE_NUMBERS" ]; then
    echo "[]"
    exit 0
fi

# 2. Fetch each Issue body and filter
RESULTS="[]"

for N in $ISSUE_NUMBERS; do
    BODY=$(gh issue view "$N" --json body -q .body)

    if [ -n "$EVENT_NAME" ]; then
        # Event mode: match verify-type: observation with the specified event name
        MATCHED=$(echo "$BODY" | grep -E '^- \[ \]' | grep "verify-type: observation" | grep "event=${EVENT_NAME}" || true)
    else
        # Opportunistic mode: match verify-type: opportunistic with skill name
        MATCHED=$(echo "$BODY" | grep -E '^- \[ \]' | grep "verify-type: opportunistic" | grep -F "$SKILL_NAME" || true)
    fi

    if [ -z "$MATCHED" ]; then
        continue
    fi

    # Convert each matched line to a JSON entry
    while IFS= read -r line; do
        # Extract text with HTML comments and checkbox markup removed
        CONDITION=$(echo "$line" \
            | sed 's/^- \[ \] //' \
            | sed 's/ *<!--.*-->//g')

        # Fact-token filter gate (opportunistic mode only, --event unset): skip lines
        # whose lowercased CONDITION does not contain any --facts token as a substring.
        # No --facts / empty FACT_TOKENS_LOWER means unconditional match (backward
        # compatible). Not applied in event mode -- event mode uses --facts-file/when=
        # instead. See scripts/scan-pending-ac.sh for the same matching approach.
        if [ -z "$EVENT_NAME" ] && [ -n "$FACT_TOKENS_LOWER" ]; then
            CONDITION_LOWER=$(echo "$CONDITION" | tr '[:upper:]' '[:lower:]')
            FACT_MATCHED=false
            while IFS= read -r tok; do
                [ -z "$tok" ] && continue
                case "$CONDITION_LOWER" in
                    *"$tok"*)
                        FACT_MATCHED=true
                        break
                        ;;
                esac
            done <<< "$FACT_TOKENS_LOWER"
            if [ "$FACT_MATCHED" = false ]; then
                continue
            fi
        fi

        # Condition check gate: skip lines whose keyword= attribute does not
        # appear in CONTEXT_FILE once path-like tokens (e.g. docs/workflow.md) are
        # stripped out. No keyword= attribute or no --context-file means unconditional
        # match (backward compatible). See modules/observation-trigger.md § Condition
        # Check Gate (keyword=) — Path-like token exclusion (Issue #1220).
        KEYWORD=$(echo "$line" | grep -oE 'keyword=[^ >]+' | sed -e 's/^keyword=//' -e 's/-*$//' || true)
        if [ -n "$KEYWORD" ] && [ -n "$CONTEXT_FILE" ]; then
            resolve_filtered_context
            if ! echo "$FILTERED_CONTEXT" | grep -qi -- "$KEYWORD"; then
                continue
            fi
        fi

        # Config check gate: skip lines whose config= attribute names a
        # .wholework.yml key that is not "true" in this repository. No
        # config= attribute means unconditional match (backward compatible).
        CONFIG_KEY=$(echo "$line" | grep -oE 'config=[^ >]+' | sed -e 's/^config=//' -e 's/-*$//' || true)
        if [ -n "$CONFIG_KEY" ]; then
            CONFIG_VALUE=$("${SCRIPT_DIR}/get-config-value.sh" "$CONFIG_KEY" "false" | tr '[:upper:]' '[:lower:]')
            if [ "$CONFIG_VALUE" != "true" ]; then
                continue
            fi
        fi

        # when= condition check gate: skip lines whose when=<axis>:<value>[,<axis>:<value>...]
        # clauses (AND) do not all match the current /auto run facts (route / mode /
        # recovery-tier). No when= attribute means unconditional match (backward compatible).
        # Facts unavailable/invalid/contextless (resolve_run_facts fail-open), and unknown axes
        # or malformed clauses, are ignored rather than excluding the line.
        # Extraction is scoped to the HTML comment tag (not the whole line) and takes only the
        # last match: the AC's human-readable prose may itself quote "when=..." syntax (e.g. to
        # describe the attribute), and matching against the whole line would corrupt WHEN_ATTR
        # with an embedded newline from grep -o's one-match-per-line output.
        AC_TAG=$(echo "$line" | grep -oE '<!--.*-->' || true)
        WHEN_ATTR=$(echo "$AC_TAG" | grep -oE 'when=[^ >]+' | tail -n 1 | sed -e 's/^when=//' -e 's/-*$//' || true)
        if [ -n "$WHEN_ATTR" ]; then
            resolve_run_facts
            if [ -n "$RUN_FACTS_JSON" ]; then
                WHEN_MATCH=true
                # IFS=',' read -a splits on commas without word-splitting/globbing the result,
                # unlike `for CLAUSE in $WHEN_ATTR` which would pathname-expand values
                # containing *, ?, or [...] against files in the current working directory.
                IFS=',' read -r -a WHEN_CLAUSES <<< "$WHEN_ATTR"
                for CLAUSE in "${WHEN_CLAUSES[@]}"; do
                    case "$CLAUSE" in
                        *:*) ;;
                        *)
                            echo "Warning: malformed when= clause '${CLAUSE}' (missing ':'), ignoring" >&2
                            continue
                            ;;
                    esac
                    WHEN_AXIS="${CLAUSE%%:*}"
                    WHEN_VALUE="${CLAUSE#*:}"
                    if [ -z "$WHEN_VALUE" ]; then
                        echo "Warning: malformed when= clause '${CLAUSE}' (empty value), ignoring" >&2
                        continue
                    fi
                    case "$WHEN_AXIS" in
                        route)
                            if echo "$RUN_FACTS_JSON" | jq -e '(.issues | length) == 0' >/dev/null 2>&1; then
                                echo "Warning: run facts carry no per-issue context, ignoring when=route clause" >&2
                            elif ! echo "$RUN_FACTS_JSON" | jq -e --arg v "$WHEN_VALUE" 'any(.issues[]?; .route == $v)' >/dev/null 2>&1; then
                                WHEN_MATCH=false
                            fi
                            ;;
                        mode)
                            if echo "$RUN_FACTS_JSON" | jq -e '.mode == "unknown"' >/dev/null 2>&1; then
                                echo "Warning: run facts carry no mode context, ignoring when=mode clause" >&2
                            elif ! echo "$RUN_FACTS_JSON" | jq -e --arg v "$WHEN_VALUE" '.mode == $v' >/dev/null 2>&1; then
                                WHEN_MATCH=false
                            fi
                            ;;
                        recovery-tier)
                            if echo "$RUN_FACTS_JSON" | jq -e '(.issues | length) == 0' >/dev/null 2>&1; then
                                echo "Warning: run facts carry no per-issue context, ignoring when=recovery-tier clause" >&2
                            elif ! echo "$RUN_FACTS_JSON" | jq -e --arg v "$WHEN_VALUE" 'any(.issues[]?; ((.recovery_tiers // []) | map(tostring)) | index($v) != null)' >/dev/null 2>&1; then
                                WHEN_MATCH=false
                            fi
                            ;;
                        *)
                            echo "Warning: unknown when= axis '${WHEN_AXIS}', ignoring clause" >&2
                            ;;
                    esac
                done
                if [ "$WHEN_MATCH" = false ]; then
                    continue
                fi
            fi
        fi

        RESULTS=$(echo "$RESULTS" | jq --argjson n "$N" --arg c "$CONDITION" '. += [{"number": $n, "condition": $c}]')
    done <<< "$MATCHED"
done

echo "$RESULTS"
