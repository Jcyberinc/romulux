#!/bin/bash
# Romulux installer -- turns a stock Omarchy machine into Romulux.
#
#   ./install.sh              install / re-apply everything
#   ./install.sh --dry-run    print what would change, touch nothing
#   ./install.sh --no-root    user-owned half only (no password prompt)
#   ./install.sh --no-audit   skip the closing audit
#
# Idempotent: safe to run repeatedly, and re-running is the supported way to
# repair drift after an `omarchy update`. Anything it replaces is copied to
# ~/.local/state/romulux/backups/<timestamp>/ first.
#
# Split in two halves on purpose. The user-owned half (branding, theme, menu,
# plugin, helper scripts, skill) never needs root and never reverts. The
# package-owned half (os-release, session name, floating-terminal title, boot
# splash, SDDM theme, the fastfetch wrapper) lives in root-owned paths that
# package updates reset, and is applied by lib/install-root.sh through pkexec.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO/lib/common.sh"

do_root=1 do_audit=1
while (( $# )); do
  case "$1" in
  --dry-run) ROMULUX_DRY_RUN=1 ;;
  --no-root) do_root=0 ;;
  --no-audit) do_audit=0 ;;
  -h | --help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
  *) die "unknown option: $1" ;;
  esac
  shift
done

# ------------------------------------------------------------------ preflight
step "Preflight"

(( EUID != 0 )) || die "run this as your normal user, not root -- the user-owned
half writes into \$HOME, and the privileged half is escalated with pkexec on its own."

[[ -d /usr/share/omarchy ]] || die "this is not an Omarchy system (/usr/share/omarchy is missing)"
need jq "used to patch ~/.config/omarchy/shell.json without discarding your other settings"
ok "Omarchy $(omarchy-version 2>/dev/null || echo '(version unknown)')"
dry && warn "dry run -- nothing will be written"

command -v fastfetch >/dev/null || warn "fastfetch is not installed; the About screen will not render"
command -v ttfx      >/dev/null || warn "ttfx is not installed; the About logo will not animate (omarchy pkg add ttfx)"
command -v magick    >/dev/null || warn "imagemagick is not installed; tools/render-boot-logo.sh will not run (the prebuilt logo.png still installs)"

ME="${USER:-$(id -un)}"        # $USER is not always exported; id -un always works
OMA="$HOME/.config/omarchy"
SHELL_JSON="$OMA/shell.json"
BIN="$HOME/.local/bin"

# ------------------------------------------------------------------- artwork
step "Branding artwork"
# The hand-made warbird: about.txt, the six about-variants/ and screensaver.txt.
# Every variant is 52x19 to match about.txt -- omarchy-launch-about measures that
# file to size the window but shows whichever variant the fastfetch wrapper
# picked, so an odd-sized one gets framed by a window cut for different art.
sync_tree "$REPO/config/branding" "$OMA/branding"

# --------------------------------------------------------------------- theme
step "Romulan theme"
sync_tree "$REPO/config/themes/romulan" "$OMA/themes/romulan"
current_theme="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
if [[ $current_theme == romulan ]]; then
  skip "romulan already active"
elif dry; then
  plan "run: omarchy theme set romulan"
else
  omarchy theme set romulan >/dev/null 2>&1 && ok "activated the romulan theme" \
    || warn "could not activate the theme; run 'omarchy theme set romulan' by hand"
fi

# ----------------------------------------------------------- helper scripts
step "Helper scripts"
# ~/.local/bin is *after* /usr/bin in PATH on Omarchy, so nothing here can
# shadow a packaged binary. These four are all invoked by absolute path (by the
# hooks, the menu override, and each other), so that is fine. The fastfetch
# wrapper is the one that has to win a name collision, and it is installed to
# /usr/local/bin by the privileged half.
for s in romulux-reapply romulux-reapply-root omarchy-sddm-logo-sync omarchy-about-cycle; do
  sync_file "$REPO/bin/$s" "$BIN/$s" 755 "~/.local/bin/$s"
done

step "Update hooks"
# One shim, installed twice: post-update reports drift right after an update,
# post-boot catches a reverted state that predates this install. Both exec the
# real reporter in ~/.local/bin so there is only ever one copy to edit.
for h in post-update post-boot; do
  sync_file "$REPO/config/hooks/romulux-reapply" "$OMA/hooks/$h.d/romulux-reapply" 755 \
            "~/.config/omarchy/hooks/$h.d/romulux-reapply"
done

# ------------------------------------------------------------ menu overrides
step "Menu overrides"
# The About row points at an absolute path because the shell spawns it and its
# PATH need not carry ~/.local/bin -- so the repo keeps a __ROMULUX_HOME__
# placeholder and it is rendered per machine here.
rendered="$(mktemp)"; trap 'rm -f "$rendered"' EXIT
sed "s|__ROMULUX_HOME__|$HOME|g" "$REPO/config/extensions/omarchy-menu.jsonc" > "$rendered"
if [[ -f $OMA/extensions/omarchy-menu.jsonc ]] \
   && ! grep -q 'Romulux' "$OMA/extensions/omarchy-menu.jsonc" \
   && ! cmp -s "$rendered" "$OMA/extensions/omarchy-menu.jsonc"; then
  warn "you already have menu overrides; the current file is backed up, but any"
  warn "  custom rows in it must be merged back by hand afterwards"
fi
sync_file "$rendered" "$OMA/extensions/omarchy-menu.jsonc" 644 "~/.config/omarchy/extensions/omarchy-menu.jsonc"

step "About screen"
# Lives in ~/.config/fastfetch, which wins over /etc/fastfetch in fastfetch's
# search order and is user-owned, so no package update can revert the OS line.
sync_file "$REPO/config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc" 644 \
          "~/.config/fastfetch/config.jsonc"

# ----------------------------------------------------------- the menu plugin
step "Bar menu button"
# The bar button cannot be themed from config: BarWidget.qml hardcodes the
# Omarchy clamp glyph ( in the packaged "omarchy" font). The fix is a
# clone of the whole menu plugin with an Image in place of that glyph.
#
# The clone is made by `omarchy plugin clone`, not shipped in this repo, on
# purpose: Menu.qml and MenuModel.js are 70K of upstream code that changes
# between releases, so a vendored copy would pin them to whatever version this
# repo was cut from. Only the two-file Romulux delta is versioned here.
menu_id="$(menu_plugin_id || true)"
if [[ -n $menu_id ]]; then
  skip "existing menu clone: $menu_id"
elif dry; then
  plan "run: omarchy plugin clone omarchy.menu (creates $ME.menu)"
  menu_id="$ME.menu"
else
  if omarchy plugin clone omarchy.menu >/dev/null 2>&1; then
    menu_id="$(menu_plugin_id || true)"
    ok "cloned omarchy.menu to ${menu_id:-?}"
  else
    menu_id=""
    warn "omarchy plugin clone failed. It needs a running omarchy-shell (it calls"
    warn "  'omarchy-shell shell rescanPlugins' and waits for discovery), so this"
    warn "  step cannot run over SSH with no desktop session. Everything else is"
    warn "  installed -- re-run ./install.sh from inside the session to finish."
  fi
fi

if [[ -n $menu_id ]]; then
  plug="$OMA/plugins/$menu_id"
  rendered_qml="$(mktemp)"
  sed "s|__ROMULUX_MENU_ID__|$menu_id|g" "$REPO/plugin/BarWidget.qml" > "$rendered_qml"
  sync_file "$rendered_qml" "$plug/BarWidget.qml" 644 "$menu_id/BarWidget.qml"
  rm -f "$rendered_qml"
  sync_file "$REPO/plugin/logo.png" "$plug/logo.png" 644 "$menu_id/logo.png"
  # Compute the patch first and compare, so --dry-run reports a change only when
  # there is one. jq is read-only here; nothing is written until the else branch.
  if [[ -f $plug/manifest.json ]]; then
    tmp="$(mktemp)"
    if jq '.name = "My Romulux menu" | .description = "Quickshell-powered Romulux command menu"
           | .barWidget.displayName = "My Romulux menu"
           | .barWidget.description = "Launches the Romulux menu"' \
          "$plug/manifest.json" > "$tmp" && jq -e . "$tmp" >/dev/null; then
      if cmp -s "$tmp" "$plug/manifest.json"; then
        skip "$menu_id/manifest.json (unchanged)"
      elif dry; then
        plan "rebrand $menu_id/manifest.json (name/description)"
      else
        backup_of "$plug/manifest.json"
        cat "$tmp" > "$plug/manifest.json"
        ok "$menu_id/manifest.json rebranded"
      fi
    else
      warn "could not rebrand $plug/manifest.json"
    fi
    rm -f "$tmp"
  fi
fi

# --------------------------------------------------------------- shell.json
step "Shell configuration"
# `omarchy plugin clone` already enables the clone, but not deterministically
# in the left slot and not always with the stock menu disabled -- and this has
# to be idempotent on a machine where someone rearranged the bar. Patch, never
# overwrite: every other key in shell.json is the user's.
SEED=/usr/share/omarchy/config/omarchy/shell.json
if [[ -z ${menu_id:-} ]]; then
  skip "no menu clone yet -- nothing to wire into the bar"
else
  if [[ ! -f $SHELL_JSON ]]; then
    [[ -f $SEED ]] || die "no $SHELL_JSON and no packaged default at $SEED to seed from"
    if dry; then
      plan "seed shell.json from the packaged default, then wire in $menu_id"
    else
      install -Dm644 "$SEED" "$SHELL_JSON"
      ok "seeded shell.json from the packaged default"
    fi
  fi
fi
# Same as the manifest above: build the patched file, diff it, and only then
# decide. A dry run that reports changes it would not make is worthless.
if [[ -n ${menu_id:-} && -f $SHELL_JSON ]]; then
  tmp="$(mktemp)"
  jq --arg id "$menu_id" '
      # the clone replaces the stock button, so drop omarchy.menu from every slot
      .bar.layout = ((.bar.layout // {}) | with_entries(.value = ((.value // []) | map(select(.id != "omarchy.menu")))))
    | .bar.layout.left = ((.bar.layout.left // []) | if (map(.id) | index($id)) then . else [{"id": $id}] + . end)
    | .disabledPlugins = (((.disabledPlugins // []) + ["omarchy.menu"]) | unique)
    | .cloneSourceRestores = (((.cloneSourceRestores // []) + [$id]) | unique)
  ' "$SHELL_JSON" > "$tmp" && jq -e . "$tmp" >/dev/null || die "failed to patch $SHELL_JSON (left untouched)"
  if cmp -s "$tmp" "$SHELL_JSON"; then
    skip "shell.json (already wired up)"
  elif dry; then
    plan "wire $menu_id into bar.layout.left, disable omarchy.menu and list the"
    plan "  clone in cloneSourceRestores in shell.json"
  else
    backup_of "$SHELL_JSON"
    cat "$tmp" > "$SHELL_JSON"
    ok "shell.json: $menu_id in the bar, omarchy.menu disabled"
  fi
  rm -f "$tmp"
fi

# -------------------------------------------------------------------- skill
step "Audit skill"
# The /romulux skill for Claude Code: an agent can then check and repair this
# install on its own. Harmless if you do not use Claude Code.
sync_file "$REPO/skill/SKILL.md" "$HOME/.claude/skills/romulux/SKILL.md" 644 "~/.claude/skills/romulux/SKILL.md"
sync_file "$REPO/skill/audit.sh" "$HOME/.claude/skills/romulux/audit.sh" 755 "~/.claude/skills/romulux/audit.sh"

# ----------------------------------------------------------- privileged half
if (( do_root )); then
  step "Package-owned surfaces (needs root)"
  echo "  boot splash, SDDM login theme, os-release, session name, floating-terminal"
  echo "  title and the /usr/local/bin/fastfetch wrapper. pkexec will prompt."
  args=("$REPO" "$ME" "$HOME")
  dry && args=(--dry-run "${args[@]}")
  if dry; then
    plan "run: pkexec /bin/bash $REPO/lib/install-root.sh ${args[*]}"
    /bin/bash "$REPO/lib/install-root.sh" "${args[@]}" || true
  else
    pkexec /bin/bash "$REPO/lib/install-root.sh" "${args[@]}" \
      || warn "the privileged half did not complete -- re-run: pkexec /bin/bash $REPO/lib/install-root.sh $REPO $ME $HOME"
  fi
else
  step "Package-owned surfaces"
  skip "skipped (--no-root); run: pkexec /bin/bash $REPO/lib/install-root.sh $REPO $ME $HOME"
fi

# ------------------------------------------------------------------- wrap up
step "Done"
[[ -n $ROMULUX_BACKUP_DIR ]] && echo "  replaced files were backed up to $ROMULUX_BACKUP_DIR"
if grep -rqE 'omarchy[- ]theme[- ]?(set|next)' "$HOME/.config/hypr/"*.lua 2>/dev/null; then
  warn "a Hyprland keybinding can still switch themes, which breaks the single-style"
  warn "  lock. Remove it from ~/.config/hypr/bindings.lua (not edited automatically)."
fi
echo "  restart the shell to pick up the bar button:  omarchy restart shell"
echo "  the boot and login screens change on the next reboot."

if (( do_audit )) && ! dry; then
  step "Audit"
  "$HOME/.claude/skills/romulux/audit.sh" || true
fi
