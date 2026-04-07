#!/bin/sh
# install.sh — wholework installer
# Creates symlinks from this repository into ~/.claude/

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DEST="$HOME/.claude/skills/wholework"
AGENTS_DEST="$HOME/.claude/agents/wholework"
MODULES_DEST="$HOME/.claude/skills/wholework/modules"
SCRIPTS_DEST="$HOME/.claude/skills/wholework/scripts"

usage() {
  echo "Usage: $0 [--uninstall]"
  echo ""
  echo "  (no flags)    Install wholework by creating symlinks in ~/.claude/"
  echo "  --uninstall   Remove installed symlinks"
}

install() {
  echo "Installing wholework..."

  # Create destination directories
  # SKILLS_DEST is a real directory (not a symlink) so that modules/ and scripts/
  # can be symlinked inside it without traversal issues.
  mkdir -p "$SKILLS_DEST"
  mkdir -p "$HOME/.claude/agents"

  # skills/<name>/ -> ~/.claude/skills/wholework/<name>/  (one symlink per skill)
  if [ -d "$REPO_DIR/skills" ]; then
    for skill_dir in "$REPO_DIR/skills"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name=$(basename "$skill_dir")
      ln -sfn "$skill_dir" "$SKILLS_DEST/$skill_name"
      echo "  Linked skills/$skill_name/ -> $SKILLS_DEST/$skill_name"
    done
  fi

  # modules/ -> ~/.claude/skills/wholework/modules/
  ln -sfn "$REPO_DIR/modules" "$MODULES_DEST"
  echo "  Linked modules/ -> $MODULES_DEST"

  # agents/ -> ~/.claude/agents/wholework/
  ln -sfn "$REPO_DIR/agents" "$AGENTS_DEST"
  echo "  Linked agents/ -> $AGENTS_DEST"

  # scripts/ -> ~/.claude/skills/wholework/scripts/
  ln -sfn "$REPO_DIR/scripts" "$SCRIPTS_DEST"
  echo "  Linked scripts/ -> $SCRIPTS_DEST"

  echo "Done. wholework is installed."
}

uninstall() {
  echo "Uninstalling wholework..."

  if [ -L "$SKILLS_DEST" ]; then
    rm "$SKILLS_DEST"
    echo "  Removed $SKILLS_DEST"
  elif [ -d "$SKILLS_DEST" ]; then
    rm -rf "$SKILLS_DEST"
    echo "  Removed $SKILLS_DEST"
  fi

  if [ -L "$MODULES_DEST" ]; then
    rm "$MODULES_DEST"
    echo "  Removed $MODULES_DEST"
  fi

  if [ -L "$AGENTS_DEST" ]; then
    rm "$AGENTS_DEST"
    echo "  Removed $AGENTS_DEST"
  fi

  if [ -L "$SCRIPTS_DEST" ]; then
    rm "$SCRIPTS_DEST"
    echo "  Removed $SCRIPTS_DEST"
  fi

  echo "Done. wholework is uninstalled."
}

case "$1" in
  --uninstall)
    uninstall
    ;;
  --help|-h)
    usage
    ;;
  "")
    install
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
esac
