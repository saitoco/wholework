#!/bin/bash
# phase-work-dir.sh - Resolve, create, sweep, and clean the phase work directory:
# the on-disk place where a phase puts large verification work files (repository
# copies, node_modules, build output, browser-automation profiles).
#
# Usage: phase-work-dir.sh <subcommand> <issue-number> <phase>
#        phase-work-dir.sh -h | --help
#
# Subcommands:
#   path    Print the work directory path. Touches nothing.
#   create  Create the work directory (mode 700) and print its path. Idempotent.
#           Refuses (exit 1) when the base directory is on tmpfs/ramfs.
#   sweep   Phase-start sweep. Removes the leftover of the same repository, Issue,
#           and phase. Warns (path and size) about every other directory under the
#           base and never removes it.
#   clean   Phase-end cleanup. Removes this phase's work directory (idempotent).
#
# Location: <base>/<repo-key>/issue-<N>-<phase>
#   <base>      ${XDG_CACHE_HOME}/wholework/work when XDG_CACHE_HOME is an absolute
#               path, otherwise $HOME/.cache/wholework/work. Never falls back to /tmp.
#   <repo-key>  <name>-<cksum> built from the git common directory, so a worktree and
#               the main checkout resolve to the same key while repositories whose
#               git directories share a parent (separate-git-dir, bare, submodule)
#               stay distinct.
#
# Environment:
#   XDG_CACHE_HOME  Changes the base location (must be absolute; otherwise ignored)
#   HOME            Used for the default base location
#
# Exit codes:
#   0  success
#   1  usage error, invalid input, or an unsafe environment (nothing was touched)
#   2  a removal failed (the directory may remain; the next run's sweep reclaims it)
#
# Bash 3.2+ compatible (no mapfile, no associative arrays, no ${var,,}).
# See modules/phase-work-dir.md for the rules this script implements.

set -euo pipefail
export LC_ALL=C

MAX_WARNINGS=20

usage() {
    cat <<'EOF'
Usage: phase-work-dir.sh <subcommand> <issue-number> <phase>
       phase-work-dir.sh -h | --help

Subcommands:
  path    print the work directory path (touches nothing)
  create  create the work directory (mode 700) and print its path
  sweep   remove the same repository/Issue/phase leftover; warn about other directories
  clean   remove this phase's work directory

Location: ${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work/<repo-key>/issue-<N>-<phase>
EOF
}

# Make untrusted text safe to echo: keep a conservative character set, cap the length.
sanitize() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '?' | cut -c1-40
}

die() {
    echo "phase-work-dir: $*" >&2
    exit 1
}

# --- Argument handling ---------------------------------------------------------

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

if [ $# -ne 3 ]; then
    usage >&2
    exit 1
fi

SUBCOMMAND="$1"
ISSUE="$2"
PHASE="$3"

case "$SUBCOMMAND" in
    path|create|sweep|clean) ;;
    *) usage >&2; exit 1 ;;
esac

# Input validation: these values build the deletion target, so reject anything unexpected.
case "$ISSUE" in
    ''|*[!0123456789]*|0*) die "invalid issue number: $(sanitize "$ISSUE")" ;;
esac
if [ "${#ISSUE}" -gt 9 ]; then
    die "invalid issue number: $(sanitize "$ISSUE")"
fi

case "$PHASE" in
    ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*|[!abcdefghijklmnopqrstuvwxyz]*)
        die "invalid phase: $(sanitize "$PHASE")" ;;
esac
if [ "${#PHASE}" -gt 32 ]; then
    die "invalid phase: $(sanitize "$PHASE")"
fi

# --- Location resolution -------------------------------------------------------

resolve_base() {
    local cache=""
    case "${XDG_CACHE_HOME:-}" in
        /*) cache="$XDG_CACHE_HOME" ;;
    esac
    if [ -z "$cache" ]; then
        case "${HOME:-}" in
            /*) cache="$HOME/.cache" ;;
            *) die "cannot resolve a cache directory (set XDG_CACHE_HOME or HOME to an absolute path)" ;;
        esac
    fi
    while [ "${cache%/}" != "$cache" ]; do
        cache="${cache%/}"
    done
    [ -n "$cache" ] || die "cache directory resolves to /"
    case "$cache" in
        *$'\n'*|*$'\r'*) die "cache directory contains a line break" ;;
    esac
    case "/$cache/" in
        */../*) die "cache directory contains a .. component" ;;
    esac
    BASE="$cache/wholework/work"
}

resolve_repo_key() {
    local common root name sum
    # The key is derived from the git common dir itself (shared by a worktree and its
    # main checkout, unique per repository), not from its parent: a --separate-git-dir
    # repository, a bare repository, or a submodule keeps its git dir next to others.
    if common="$(git rev-parse --git-common-dir 2>/dev/null)" && [ -n "$common" ] \
        && root="$(CDPATH= cd -- "$common" 2>/dev/null && pwd -P)"; then
        name="$(basename "$root")"
        if [ "$name" = ".git" ]; then
            name="$(basename "$(dirname "$root")")"
        else
            name="${name%.git}"
        fi
    else
        root="$(pwd -P)"
        name="$(basename "$root")"
    fi
    name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
    sum="$(printf '%s' "$root" | cksum | cut -d' ' -f1)" || sum=""
    [ -n "$sum" ] || die "cannot compute a repository key"
    REPO_KEY="${name}-${sum}"
}

resolve_base
resolve_repo_key
TARGET="$BASE/$REPO_KEY/issue-$ISSUE-$PHASE"

# --- Helpers -------------------------------------------------------------------

# Human-readable size of a directory ("123 KiB" / "12 MiB" / "1.5 GiB" / "size unknown").
dir_size() {
    local kb
    kb="$(du -sk -- "$1" 2>/dev/null | cut -f1 || true)"
    case "$kb" in
        ''|*[!0-9]*) echo "size unknown"; return 0 ;;
    esac
    awk -v k="$kb" 'BEGIN {
        if (k >= 1048576) printf "%.1f GiB\n", k / 1048576
        else if (k >= 1024) printf "%d MiB\n", k / 1024
        else printf "%d KiB\n", k
    }'
}

# Remove TARGET only. A symlink is removed as a link and never followed.
remove_target() {
    case "$TARGET" in
        "$BASE"/*/issue-*) ;;
        *) die "refusing to remove an unexpected path" ;;
    esac
    if [ -L "$TARGET" ]; then
        rm -f -- "$TARGET"
        return
    fi
    chmod -R u+rwX -- "$TARGET" 2>/dev/null || true
    rm -rf -- "$TARGET"
}

target_exists() {
    [ -e "$TARGET" ] || [ -L "$TARGET" ]
}

# --- Subcommands ---------------------------------------------------------------

case "$SUBCOMMAND" in
    path)
        echo "$TARGET"
        ;;

    create)
        ancestor="$BASE"
        while [ ! -e "$ancestor" ] && [ "$ancestor" != "/" ]; do
            ancestor="$(dirname "$ancestor")"
        done
        fs_type="$(stat -f -c %T "$ancestor" 2>/dev/null)" || fs_type=""
        case "$fs_type" in
            tmpfs|ramfs)
                die "refusing to create a work directory on $fs_type (it uses memory): $ancestor" ;;
        esac
        if [ -L "$TARGET" ]; then
            die "work directory path is a symbolic link: $TARGET"
        fi
        (umask 077; mkdir -p -- "$TARGET") || die "cannot create $TARGET"
        echo "$TARGET"
        ;;

    sweep)
        [ -d "$BASE" ] || exit 0
        rc=0
        if target_exists; then
            size="$(dir_size "$TARGET")"
            if remove_target; then
                echo "phase-work-dir: removed leftover of a previous run: $TARGET ($size)" >&2
            else
                echo "phase-work-dir: WARNING: could not remove leftover: $TARGET ($size)" >&2
                rc=2
            fi
        fi
        shown=0
        extra=0
        for dir in "$BASE"/*/issue-*; do
            [ -d "$dir" ] || continue
            [ "$dir" = "$TARGET" ] && continue
            if [ "$shown" -lt "$MAX_WARNINGS" ]; then
                size="$(dir_size "$dir")"
                echo "phase-work-dir: WARNING: not removed: $dir ($size) - left by another Issue, phase, or repository; it may belong to a session running in parallel" >&2
                shown=$((shown + 1))
            else
                extra=$((extra + 1))
            fi
        done
        if [ "$extra" -gt 0 ]; then
            echo "phase-work-dir: WARNING: $extra more directories not shown" >&2
        fi
        exit "$rc"
        ;;

    clean)
        target_exists || exit 0
        if ! remove_target; then
            echo "phase-work-dir: WARNING: could not remove work directory: $TARGET (the next run's sweep will retry)" >&2
            exit 2
        fi
        ;;
esac
