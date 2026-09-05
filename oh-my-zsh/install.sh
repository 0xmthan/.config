#!/usr/bin/env bash
# Install the `normin` theme into $ZSH_CUSTOM/themes/ and point ~/.zshrc at it.
#
#   ./install.sh              install the theme and set ZSH_THEME
#   ./install.sh --no-zshrc   install the theme only, leave ~/.zshrc alone
set -euo pipefail

THEME="normin"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/themes" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
DEST="${ZSH_CUSTOM:-$ZSH_DIR/custom}/themes"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

EDIT_ZSHRC=1
[[ "${1:-}" == "--no-zshrc" ]] && EDIT_ZSHRC=0

# normin reads oh-my-zsh's async prompt API, so oh-my-zsh has to be there first.
if [[ ! -d "$ZSH_DIR" ]]; then
  echo "oh-my-zsh not found at $ZSH_DIR" >&2
  echo "Install it first: https://ohmyz.sh" >&2
  exit 1
fi

mkdir -p "$DEST"
cp -v "$SRC/$THEME.zsh-theme" "$DEST/"

if (( ! EDIT_ZSHRC )); then
  echo
  echo "Theme installed. Set it yourself with:  ZSH_THEME=\"$THEME\""
  exit 0
fi

if [[ ! -f "$ZSHRC" ]]; then
  echo
  echo "No $ZSHRC found. Add this to yours:"
  echo "    ZSH_THEME=\"$THEME\""
  exit 0
fi

# Match the first uncommented ZSH_THEME assignment — that is the one oh-my-zsh
# actually uses, and the file usually carries commented examples around it.
if ! grep -qE '^[[:space:]]*ZSH_THEME=' "$ZSHRC"; then
  echo
  echo "No ZSH_THEME line in $ZSHRC. Add this:"
  echo "    ZSH_THEME=\"$THEME\""
  exit 0
fi

current="$(sed -n 's/^[[:space:]]*ZSH_THEME=["'\'']\{0,1\}\([^"'\'']*\).*/\1/p' "$ZSHRC" | head -1)"

if [[ "$current" == "$THEME" ]]; then
  echo
  echo "ZSH_THEME is already \"$THEME\" — nothing to change."
else
  backup="$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"
  cp "$ZSHRC" "$backup"
  # Rewrite via a temp file rather than `sed -i`, whose in-place flag takes an
  # argument on BSD/macOS but not on GNU.
  tmp="$(mktemp)"
  awk -v theme="$THEME" '
    !done && /^[[:space:]]*ZSH_THEME=/ { print "ZSH_THEME=\"" theme "\""; done=1; next }
    { print }
  ' "$ZSHRC" > "$tmp"
  cat "$tmp" > "$ZSHRC"   # preserve the original file's inode and permissions
  rm -f "$tmp"
  echo
  echo "ZSH_THEME: \"$current\" -> \"$THEME\"   (backup: $backup)"
fi

cat <<EOF

Installed to $DEST/$THEME.zsh-theme
Reload with:  exec zsh

Tune it from ~/.zshrc (set before 'source \$ZSH/oh-my-zsh.sh'):
    NORMIN_DURATION_THRESHOLD=2   # seconds before timing shows; 0 = always
    NORMIN_PATH_DEPTH=3           # trailing path segments; 0 = full path
    NORMIN_SHOW_HOST=1            # 0 hides the hostname
    NORMIN_GIT_COUNTS=1           # 0 shows bare flags instead of counts
    NORMIN_HOST_COLOR=yellow
    NORMIN_DIM_COLOR=242
EOF
