#!/bin/bash
# Put a Romulux machine back to stock Omarchy.
#
#   ./uninstall.sh              revert branding, keep the artwork on disk
#   ./uninstall.sh --purge      also delete ~/.config/omarchy/branding and the theme
#   ./uninstall.sh --dry-run    print what would change, touch nothing
#   ./uninstall.sh --no-root    user-owned half only
#
# What it cannot undo: files this repo replaced are not restored from the
# install backups automatically -- they are still in
# ~/.local/state/romulux/backups/<timestamp>/ and /var/backups/romulux/, and
# the path of each is printed so you can put back a menu file you had before.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO/lib/common.sh"

purge=0 do_root=1
while (( $# )); do
  case "$1" in
  --dry-run) ROMULUX_DRY_RUN=1 ;;
  --purge) purge=1 ;;
  --no-root) do_root=0 ;;
  -h | --help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
  *) die "unknown option: $1" ;;
  esac
  shift
done

(( EUID != 0 )) || die "run this as your normal user, not root"
OMA="$HOME/.config/omarchy"
BIN="$HOME/.local/bin"
FALLBACK_THEME=${ROMULUX_FALLBACK_THEME:-tokyo-night}

rm_path() { # rm_path <path> [label]
  local p="$1" label="${2:-$1}"
  [[ -e $p ]] || { skip "$label (absent)"; return 0; }
  dry && { plan "remove $label"; return 0; }
  backup_of "$p"
  rm -rf "$p"
  ok "removed $label"
}

step "Menu, About screen and hooks"
rm_path "$OMA/extensions/omarchy-menu.jsonc" "~/.config/omarchy/extensions/omarchy-menu.jsonc"
rm_path "$HOME/.config/fastfetch/config.jsonc" "~/.config/fastfetch/config.jsonc"
for h in post-update post-boot; do
  rm_path "$OMA/hooks/$h.d/romulux-reapply" "~/.config/omarchy/hooks/$h.d/romulux-reapply"
done

step "Bar menu button"
# Hand the bar back to the packaged plugin before deleting the clone, or the
# left slot ends up empty and there is no menu button at all.
menu_id="$(menu_plugin_id || true)"
if [[ -z $menu_id ]]; then
  skip "no menu clone found"
elif dry; then
  plan "re-enable omarchy.menu, drop $menu_id from shell.json, remove the clone"
else
  if [[ -f $OMA/shell.json ]]; then
    tmp="$(mktemp)"
    jq --arg id "$menu_id" '
        .bar.layout = ((.bar.layout // {}) | with_entries(.value = ((.value // []) | map(select(.id != $id)))))
      | .bar.layout.left = ((.bar.layout.left // []) | if (map(.id) | index("omarchy.menu")) then . else [{"id": "omarchy.menu"}] + . end)
      | .disabledPlugins = ((.disabledPlugins // []) | map(select(. != "omarchy.menu")))
      | .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != $id)))
    ' "$OMA/shell.json" > "$tmp" && jq -e . "$tmp" >/dev/null || die "failed to patch shell.json (left untouched)"
    backup_of "$OMA/shell.json"
    cat "$tmp" > "$OMA/shell.json"
    rm -f "$tmp"
    ok "shell.json: omarchy.menu restored to the bar"
  fi
  rm_path "$OMA/plugins/$menu_id" "~/.config/omarchy/plugins/$menu_id"
fi

step "Theme"
if [[ "$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)" != romulan ]]; then
  skip "romulan is not the active theme"
elif dry; then
  plan "run: omarchy theme set $FALLBACK_THEME"
else
  omarchy theme set "$FALLBACK_THEME" >/dev/null 2>&1 && ok "switched to $FALLBACK_THEME" \
    || warn "could not switch themes; run 'omarchy theme set <name>' by hand"
fi
(( purge )) && rm_path "$OMA/themes/romulan" "~/.config/omarchy/themes/romulan"

step "Helper scripts and skill"
for s in romulux-reapply romulux-reapply-root omarchy-sddm-logo-sync omarchy-about-cycle; do
  rm_path "$BIN/$s" "~/.local/bin/$s"
done
rm_path "$HOME/.claude/skills/romulux" "~/.claude/skills/romulux"

if (( purge )); then
  step "Artwork"
  warn "--purge deletes the warbird artwork; it is only recoverable from this repo"
  rm_path "$OMA/branding" "~/.config/omarchy/branding"
fi

if (( do_root )); then
  step "Package-owned surfaces (needs root)"
  args=("$REPO")
  dry && args=(--dry-run "${args[@]}")
  if dry; then
    plan "run: pkexec /bin/bash $REPO/lib/uninstall-root.sh ${args[*]}"
    /bin/bash "$REPO/lib/uninstall-root.sh" "${args[@]}" || true
  else
    pkexec /bin/bash "$REPO/lib/uninstall-root.sh" "${args[@]}" \
      || warn "the privileged half did not complete -- re-run: pkexec /bin/bash $REPO/lib/uninstall-root.sh $REPO"
  fi
fi

step "Done"
[[ -n $ROMULUX_BACKUP_DIR ]] && echo "  what was removed is in $ROMULUX_BACKUP_DIR"
echo "  run 'omarchy restart shell' to reload the bar."
