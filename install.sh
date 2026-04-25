#!/usr/bin/env sh
# install.sh — copy Claude skills into ~/.claude/skills/
#
# Usage:
#   ./install.sh              install all skills
#   ./install.sh <name>...    install specific skill(s) by name
#   ./install.sh --list       list available skills
#   ./install.sh --dry-run    show what would be installed without copying

set -e

SKILLS_DIR="$(cd "$(dirname "$0")/skills" && pwd)"
TARGET_DIR="$HOME/.claude/skills"
DRY_RUN=0
LIST=0
SELECTED=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --list)    LIST=1 ;;
    *)         SELECTED="$SELECTED $arg" ;;
  esac
done

if [ "$LIST" = "1" ]; then
  echo "Available skills:"
  for d in "$SKILLS_DIR"/*/; do
    name="$(basename "$d")"
    desc="$(awk '/^description:/{found=1; sub(/^description: /,""); print; exit} found && /^---/{exit}' "$d/SKILL.md" 2>/dev/null | head -1)"
    printf "  %-20s %s\n" "$name" "$desc"
  done
  exit 0
fi

if [ -z "$SELECTED" ]; then
  SKILLS="$(ls "$SKILLS_DIR")"
else
  SKILLS="$SELECTED"
fi

mkdir -p "$TARGET_DIR"

install_skill() {
  name="$1"
  src="$SKILLS_DIR/$name"

  if [ ! -d "$src" ]; then
    echo "ERROR: skill '$name' not found in $SKILLS_DIR" >&2
    exit 1
  fi

  dest="$TARGET_DIR/$name"

  if [ "$DRY_RUN" = "1" ]; then
    if [ -d "$dest" ]; then
      echo "[dry-run] would overwrite $dest"
    else
      echo "[dry-run] would install $src → $dest"
    fi
    return
  fi

  if [ -d "$dest" ]; then
    backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    cp -r "$dest" "$backup"
    echo "backed up existing $name → $(basename "$backup")"
  fi

  cp -r "$src" "$dest"
  echo "installed $name → $dest"
}

for name in $SKILLS; do
  name="$(echo "$name" | tr -d ' ')"
  [ -z "$name" ] && continue
  install_skill "$name"
done
