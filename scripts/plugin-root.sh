#!/bin/bash
# sourceable helper — do not execute directly
# bash 3.2+ compatible: no associative arrays, no mapfile
#
# plugin-root.sh - Resolve ${CLAUDE_PLUGIN_ROOT} for headless run-*.sh sessions (Issue #1546)
#
# run-*.sh pass the SKILL.md body to `claude -p` as a raw prompt, so Claude Code's inline
# substitution of ${CLAUDE_PLUGIN_ROOT} (done only when it loads a Skill) never runs, and the
# variable is not exported to the Bash tool either. The wrappers use these helpers to resolve it
# themselves: expand the placeholder in the prompt text, export CLAUDE_PLUGIN_ROOT, and add a
# short note to the prompt for Read paths inside modules that are read at run time.
# See modules/execution-context.md § Fork Context.
#
# Functions:
#   expand_plugin_root_placeholder TEXT ROOT
#     Print TEXT with every literal ${CLAUDE_PLUGIN_ROOT} replaced by ROOT. Only the exact
#     braced form is replaced ($CLAUDE_PLUGIN_ROOT and ${CLAUDE_PLUGIN_ROOT:-} are left alone).
#     ROOT is inserted verbatim (no special treatment of &, \, |, $, quotes, or spaces).
#     Always returns 0 (fail-open): when awk fails, a warning goes to stderr and TEXT is printed
#     unchanged, so a failure of this convenience step never stops the phase.
#   plugin_root_note ROOT
#     Print a two-line note for the prompt: the plugin root path and how to use it for Read paths.

expand_plugin_root_placeholder() {
  local text="$1" root="$2" out
  # awk index/substr loop (no regex). ROOT goes through ENVIRON, not -v, because -v interprets
  # backslash escapes. ${var//pat/rep} is avoided: bash 5.2 patsub_replacement expands & in ROOT
  # and bash 3.2 keeps quotes on the replacement side.
  if out="$(printf '%s\n' "$text" | PLUGIN_ROOT_VALUE="$root" awk '
      BEGIN { pat = "${CLAUDE_PLUGIN_ROOT}"; plen = length(pat); root = ENVIRON["PLUGIN_ROOT_VALUE"] }
      {
        rest = $0; res = ""
        while ((i = index(rest, pat)) > 0) { res = res substr(rest, 1, i - 1) root; rest = substr(rest, i + plen) }
        print res rest
      }')"; then
    printf '%s' "$out"
  else
    echo "Warning: could not expand the plugin root placeholder; leaving the prompt text unchanged" >&2
    printf '%s' "$text"
  fi
  return 0
}

plugin_root_note() {
  local root="$1"
  printf '%s\n' "Plugin root: $root"
  printf '%s\n' 'The environment variable CLAUDE_PLUGIN_ROOT is set to this directory for Bash commands. When a file you read (a module or a skill document) refers to this directory by that variable name, replace it with the path above in the path you pass to the Read tool instead of searching the filesystem.'
}
