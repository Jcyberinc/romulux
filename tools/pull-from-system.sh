#!/bin/bash
# Copy this machine's live Romulux files back into the repo, ready to commit.
# The other direction from install.sh -- use it after you have changed something
# on the running system and want the repo to carry it.
#
#   tools/pull-from-system.sh              copy, then show what changed
#   tools/pull-from-system.sh --dry-run    just show what differs
#
# Machine-specific values are turned back into placeholders on the way in:
# $HOME becomes __ROMULUX_HOME__ in the menu overrides and the menu clone's id
# becomes __ROMULUX_MENU_ID__ in BarWidget.qml, so the repo stays installable by
# anyone. Menu.qml and MenuModel.js are deliberately *not* pulled: they are
# upstream Omarchy code that `omarchy plugin clone` regenerates per release, and
# vendoring them would pin every future installer run to this machine's version.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/lib/common.sh"

[[ ${1:-} == --dry-run ]] && ROMULUX_DRY_RUN=1
OMA="$HOME/.config/omarchy"

grab() { # grab <live> <repo-relative> [sed-expr]
  local src="$1" dst="$REPO/$2" expr="${3:-}" tmp
  if [[ ! -e $src ]]; then warn "missing on this system: $src"; return 0; fi
  tmp="$(mktemp)"
  if [[ -n $expr ]]; then sed "$expr" "$src" > "$tmp"; else cp "$src" "$tmp"; fi
  if cmp -s "$tmp" "$dst" 2>/dev/null; then
    skip "$2"
  elif dry; then
    plan "update $2"
  else
    install -Dm"$(stat -c %a "$src")" "$tmp" "$dst"
    ok "$2"
  fi
  rm -f "$tmp"
}

step "Artwork and theme"
for f in "$OMA"/branding/*.txt "$OMA"/branding/about-variants/*.txt; do
  grab "$f" "config/branding/${f#"$OMA"/branding/}"
done
for f in "$OMA"/themes/romulan/colors.toml "$OMA"/themes/romulan/icons.theme \
         "$OMA"/themes/romulan/neovim.lua "$OMA"/themes/romulan/vscode.json \
         "$OMA"/themes/romulan/backgrounds/*; do
  grab "$f" "config/themes/romulan/${f#"$OMA"/themes/romulan/}"
done

step "Config"
grab "$OMA/extensions/omarchy-menu.jsonc" config/extensions/omarchy-menu.jsonc "s|$HOME|__ROMULUX_HOME__|g"
grab "$HOME/.config/fastfetch/config.jsonc" config/fastfetch/config.jsonc
grab "$OMA/hooks/post-update.d/romulux-reapply" config/hooks/romulux-reapply

step "Scripts and skill"
for s in romulux-reapply romulux-reapply-root omarchy-sddm-logo-sync omarchy-about-cycle; do
  grab "$HOME/.local/bin/$s" "bin/$s"
done
grab "$HOME/.claude/skills/romulux/SKILL.md" skill/SKILL.md
grab "$HOME/.claude/skills/romulux/audit.sh" skill/audit.sh

step "Menu plugin overlay"
menu_id="$(menu_plugin_id || true)"
if [[ -z $menu_id ]]; then
  warn "no menu clone on this system; skipping the overlay"
else
  # Both occurrences: moduleName and the `omarchy-shell shell toggle <id>` call.
  # The dot is escaped so it cannot match another character.
  grab "$OMA/plugins/$menu_id/BarWidget.qml" plugin/BarWidget.qml \
       "s|${menu_id//./\\.}|__ROMULUX_MENU_ID__|g"
  grab "$OMA/plugins/$menu_id/logo.png" plugin/logo.png
fi

step "Root-owned files"
grab /usr/share/plymouth/themes/omarchy-ascii/omarchy-ascii.plymouth system/plymouth/omarchy-ascii/omarchy-ascii.plymouth
grab /usr/share/plymouth/themes/omarchy-ascii/omarchy-ascii.script   system/plymouth/omarchy-ascii/omarchy-ascii.script
grab /usr/share/plymouth/themes/omarchy-ascii/logo.png               system/plymouth/omarchy-ascii/logo.png
grab /etc/sddm.conf.d/zz-omarchy-ascii-theme.conf                    system/sddm/zz-omarchy-ascii-theme.conf
grab /usr/local/bin/fastfetch                                        system/bin/fastfetch

step "Repo status"
if command -v git >/dev/null && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" status --short
else
  warn "$REPO is not a git repository yet"
fi
