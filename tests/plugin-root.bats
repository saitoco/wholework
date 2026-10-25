#!/usr/bin/env bats

# Tests for scripts/plugin-root.sh (sourceable helper, Issue #1546)

HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/plugin-root.sh"
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Call expand_plugin_root_placeholder in an isolated shell
_expand() {
    bash -c 'source "$1"; expand_plugin_root_placeholder "$2" "$3"' _ "$HELPER" "$1" "$2"
}

@test "expand: replaces multiple, adjacent, leading and trailing placeholders" {
    run _expand 'A ${CLAUDE_PLUGIN_ROOT}/x B ${CLAUDE_PLUGIN_ROOT}/y' /root
    [ "$status" -eq 0 ]
    [ "$output" = "A /root/x B /root/y" ]

    run _expand '${CLAUDE_PLUGIN_ROOT}${CLAUDE_PLUGIN_ROOT}' /r
    [ "$output" = "/r/r" ]

    run _expand '${CLAUDE_PLUGIN_ROOT}/start
end ${CLAUDE_PLUGIN_ROOT}' /r
    [ "$output" = "/r/start
end /r" ]
}

@test "expand: leaves non-matching forms unchanged" {
    run _expand 'a $CLAUDE_PLUGIN_ROOT b ${CLAUDE_PLUGIN_ROOT:-} c ${OTHER}' /root
    [ "$status" -eq 0 ]
    [ "$output" = 'a $CLAUDE_PLUGIN_ROOT b ${CLAUDE_PLUGIN_ROOT:-} c ${OTHER}' ]
}

@test "expand: inserts a root with special characters verbatim" {
    local special='/tmp/a&b\c|d$e"f'"'"'g h'
    run _expand 'x ${CLAUDE_PLUGIN_ROOT}/m y' "$special"
    [ "$status" -eq 0 ]
    [ "$output" = "x ${special}/m y" ]
}

@test "expand: preserves multibyte characters and CRLF" {
    run _expand $'日本語 ${CLAUDE_PLUGIN_ROOT}/m 終\r\nnext' /r
    [ "$status" -eq 0 ]
    [ "$output" = $'日本語 /r/m 終\r\nnext' ]
}

@test "expand: empty input and input without placeholder" {
    run _expand '' /root
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run _expand 'no placeholder here' /root
    [ "$status" -eq 0 ]
    [ "$output" = "no placeholder here" ]
}

@test "expand: real SKILL.md bodies keep no placeholder and keep the line count" {
    local name skill end body before after count_before count_after root
    root='/opt/we ird&root\x|y'
    for name in spec code review merge issue; do
        skill="$REPO_ROOT/skills/$name/SKILL.md"
        end="$(awk 'NR>1 && /^---$/{print NR; exit}' "$skill")"
        body="$(tail -n +"$((end + 1))" "$skill")"
        count_before="$(printf '%s\n' "$body" | grep -o '${CLAUDE_PLUGIN_ROOT}' | wc -l | tr -d ' ')"
        [ "$count_before" -gt 0 ]
        after="$(_expand "$body" "$root")"
        [[ "$after" != *'${CLAUDE_PLUGIN_ROOT}'* ]] || false
        count_after="$(printf '%s\n' "$after" | grep -oF "$root" | wc -l | tr -d ' ')"
        [ "$count_after" -eq "$count_before" ]
        [ "$(printf '%s\n' "$after" | wc -l | tr -d ' ')" -eq "$(printf '%s\n' "$body" | wc -l | tr -d ' ')" ]
    done
}

@test "expand: fail-open when awk fails (warning on stderr, original text on stdout, exit 0)" {
    mkdir -p "$BATS_TEST_TMPDIR/fakebin"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/fakebin/awk"
    chmod +x "$BATS_TEST_TMPDIR/fakebin/awk"
    run bash -c 'PATH="$1:$PATH"; source "$2"; expand_plugin_root_placeholder "$3" /root 2>"$4"' _ \
        "$BATS_TEST_TMPDIR/fakebin" "$HELPER" 'keep ${CLAUDE_PLUGIN_ROOT}/m' "$BATS_TEST_TMPDIR/stderr.txt"
    [ "$status" -eq 0 ]
    [ "$output" = 'keep ${CLAUDE_PLUGIN_ROOT}/m' ]
    grep -q "Warning: could not expand the plugin root placeholder" "$BATS_TEST_TMPDIR/stderr.txt"
}

@test "note: includes the root and no unresolved placeholder" {
    run bash -c 'source "$1"; plugin_root_note "$2"' _ "$HELPER" /some/root
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugin root: /some/root"* ]] || false
    [[ "$output" != *'${CLAUDE_PLUGIN_ROOT}'* ]] || false
    [[ "$output" == *"CLAUDE_PLUGIN_ROOT"* ]] || false
}
