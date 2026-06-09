#!/bin/bash
# UserPromptSubmit hook: auto-rename session title on /auto invocation
# Outputs {"hookSpecificOutput":{"sessionTitle":"..."}} when prompt matches /auto pattern.
# Silent exit (empty output) on no match or gh failure to preserve existing session name.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

# Early exit: not starting with /auto
case "$PROMPT" in
  /auto*) ;;
  *) exit 0 ;;
esac

# Early exit: help mode
case "$PROMPT" in
  *--help*) exit 0 ;;
esac

# Strip leading "/auto" and optional whitespace
REST=$(echo "$PROMPT" | sed 's|^/auto[[:space:]]*||')

TITLE=""

case "$REST" in
  *"--batch"*)
    BATCH_PART=$(echo "$REST" | sed -E 's/.*--batch[[:space:]]*//')
    NUMS=$(echo "$BATCH_PART" | grep -oE '^([0-9]+[[:space:]]+)*[0-9]+' | xargs)
    if [ -z "$NUMS" ]; then
      exit 0
    fi
    NUM_COUNT=$(echo "$NUMS" | wc -w | tr -d ' ')
    if [ "$NUM_COUNT" -eq 1 ]; then
      TITLE="auto batch ($NUMS issues)"
    else
      COMMA_NUMS=$(echo "$NUMS" | tr ' ' ',')
      TITLE="auto batch #$COMMA_NUMS"
    fi
    ;;

  *"--resume"*)
    N=$(echo "$REST" | sed -E 's/.*--resume[[:space:]]*//' | grep -oE '^[0-9]+')
    if [ -z "$N" ]; then
      exit 0
    fi
    RAW=$(gh issue view "$N" --json title -q .title 2>/dev/null) || exit 0
    [ -z "$RAW" ] && exit 0
    STRIPPED=$(echo "$RAW" | sed -E 's/^[A-Za-z0-9_/-]+:[[:space:]]*//')
    TITLE="auto #$N (resume): $STRIPPED"
    ;;

  *)
    N=$(echo "$REST" | grep -oE '[0-9]+' | head -1)
    if [ -z "$N" ]; then
      exit 0
    fi
    RAW=$(gh issue view "$N" --json title -q .title 2>/dev/null) || exit 0
    [ -z "$RAW" ] && exit 0
    STRIPPED=$(echo "$RAW" | sed -E 's/^[A-Za-z0-9_/-]+:[[:space:]]*//')
    TITLE="auto #$N: $STRIPPED"
    ;;
esac

# Truncate to 50 chars (bash ${#} counts bytes on macOS bash 3.2, accepted as compromise)
if [ ${#TITLE} -gt 50 ]; then
  TITLE="${TITLE:0:49}…"
fi

jq -n --arg title "$TITLE" '{"hookSpecificOutput":{"sessionTitle":$title}}'
