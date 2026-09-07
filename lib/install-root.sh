#!/bin/bash
# Privileged half of the Romulux install. Not meant to be run directly --
# install.sh escalates it:
#
#     pkexec /bin/bash lib/install-root.sh <repo> <user> <user-home>
#
# pkexec and not sudo: sudo cannot prompt for a password without a TTY, so it
# fails from an agent session, a menu entry, or any other non-terminal caller.
#
# Everything here lives in a root-owned path that a package update can reset,
# which is why it is separated from the user-owned half at all:
#   - /usr/share/plymouth/themes/omarchy-ascii   the boot / shutdown splash
#   - /etc/plymouth/plymouthd.conf               which theme boots (plymouth pkg)
#   - /usr/share/sddm/themes/omarchy-ascii       the login / logout screen
#   - /etc/sddm.conf.d/zz-omarchy-ascii-theme.conf
#   - /usr/local/bin/fastfetch                   the logo-variant wrapper
#   - /etc/os-release, the wayland session entry, the floating-terminal title
#
# The last three are handled by the installed romulux-reapply-root, which is
# also what repairs them after every omarchy update -- so that logic lives in
# exactly one place and is not duplicated here.
set -euo pipefail

dryrun=0
[[ ${1:-} == --dry-run ]] && { dryrun=1; shift; }
REPO="${1:?repo path required}"
TARGET_USER="${2:?target user required}"
USER_HOME="${3:?target user home required}"

ROMULUX_DRY_RUN=$dryrun
# Root-owned backups go to the conventional system location, never inside the
# theme directories: the Plymouth mkinitcpio hook bundles its whole theme dir,
# so a .bak left in there would be baked into the initramfs.
ROMULUX_BACKUP_ROOT=/var/backups/romulux
source "$REPO/lib/common.sh"

(( dryrun )) || (( EUID == 0 )) || die "must run as root (use install.sh, which escalates with pkexec)"

PLY_THEME=omarchy-ascii
PLY_DIR="/usr/share/plymouth/themes/$PLY_THEME"
STOCK_PLY=/usr/share/plymouth/themes/omarchy

# ------------------------------------------------------------------ plymouth
step "Boot splash (Plymouth theme $PLY_THEME)"
# Kept in its own theme directory, not as an edit to the packaged `omarchy`
# theme, precisely so a plymouth or omarchy-settings update cannot clobber it.
# The chrome (bullet, entry, lock, progress bars) is seeded from the stock theme
# rather than vendored here -- only the logo and the script are Romulux.
if [[ -d $STOCK_PLY ]]; then
  missing=()
  while IFS= read -r -d '' f; do
    rel="${f#"$STOCK_PLY"/}"
    case "$rel" in
    logo.png | omarchy.plymouth | omarchy.script) continue ;;   # replaced by ours
    esac
    [[ -e $PLY_DIR/$rel ]] || missing+=("$rel")
  done < <(find "$STOCK_PLY" -type f -print0)
  if (( ${#missing[@]} == 0 )); then
    skip "chrome images already present"
  elif dry; then
    plan "seed $PLY_DIR with ${#missing[@]} chrome image(s): ${missing[*]}"
  else
    install -d -m755 "$PLY_DIR"
    for rel in "${missing[@]}"; do
      install -Dm644 "$STOCK_PLY/$rel" "$PLY_DIR/$rel"
    done
    ok "seeded ${#missing[@]} chrome image(s)"
  fi
else
  warn "no stock plymouth theme at $STOCK_PLY to seed the chrome images from"
fi

sync_file "$REPO/system/plymouth/$PLY_THEME/$PLY_THEME.plymouth" "$PLY_DIR/$PLY_THEME.plymouth" 644 "$PLY_DIR/$PLY_THEME.plymouth"
sync_file "$REPO/system/plymouth/$PLY_THEME/$PLY_THEME.script"   "$PLY_DIR/$PLY_THEME.script"   644 "$PLY_DIR/$PLY_THEME.script"
# The boot logo is a baked PNG render of branding/screensaver.txt, not live
# text. Re-render it with tools/render-boot-logo.sh if the art ever changes.
sync_file "$REPO/system/plymouth/$PLY_THEME/logo.png"            "$PLY_DIR/logo.png"            644 "$PLY_DIR/logo.png"

# Backups must not be left inside the theme dir -- the mkinitcpio plymouth hook
# copies the directory wholesale.
strays="$(find "$PLY_DIR" -maxdepth 1 \( -name '*.bak' -o -name '*.orig' -o -name '*~' \) 2>/dev/null || true)"
[[ -z $strays ]] || warn "stray backup files in $PLY_DIR: $strays"

current_ply="$(plymouth-set-default-theme 2>/dev/null || true)"
if [[ $current_ply == "$PLY_THEME" ]]; then
  skip "boot splash already set to $PLY_THEME"
elif dry; then
  plan "point the boot splash at $PLY_THEME (currently: ${current_ply:-unknown})"
else
  # --rebuild-initrd only matters when plymouth is inside the initramfs. With no
  # plymouth hook in HOOKS the splash runs from the real root and a mkinitcpio
  # run would be several wasted minutes -- but on a machine that does carry the
  # hook, skipping the rebuild would silently leave the old splash.
  if grep -qE '^HOOKS=.*plymouth' /etc/mkinitcpio.conf 2>/dev/null; then
    warn "plymouth is in mkinitcpio HOOKS -- rebuilding the initramfs, this takes a while"
    plymouth-set-default-theme --rebuild-initrd "$PLY_THEME"
  else
    plymouth-set-default-theme "$PLY_THEME"
  fi
  ok "boot splash set to $PLY_THEME"
fi

# ---------------------------------------------------------------------- sddm
step "Login screen (SDDM)"
# Omarchy does not sync the SDDM logo from the Plymouth theme, and the packaged
# theme is replaced on update, so Romulux keeps its own theme dir built by the
# helper. Calling the helper (rather than repeating it) keeps one implementation.
sync_helper="$USER_HOME/.local/bin/omarchy-sddm-logo-sync"
if [[ ! -x $sync_helper ]]; then
  warn "$sync_helper is missing -- run install.sh (its user-owned half installs it) first"
elif [[ ! -d /usr/share/sddm/themes/omarchy ]]; then
  warn "no packaged SDDM theme at /usr/share/sddm/themes/omarchy to build from; skipping"
elif cmp -s "$PLY_DIR/logo.png" "/usr/share/sddm/themes/$PLY_THEME/logo.png" 2>/dev/null; then
  skip "SDDM theme already carries the current logo"
elif dry; then
  plan "run $sync_helper to build /usr/share/sddm/themes/$PLY_THEME with the branded logo"
else
  "$sync_helper" "$PLY_THEME" && ok "SDDM theme built with the branded logo"
fi
# Sorts last in /etc/sddm.conf.d, so this [Theme] Current wins the merge.
sync_file "$REPO/system/sddm/zz-omarchy-ascii-theme.conf" /etc/sddm.conf.d/zz-omarchy-ascii-theme.conf 644 \
          /etc/sddm.conf.d/zz-omarchy-ascii-theme.conf

# ---------------------------------------------------------- fastfetch wrapper
step "About-screen logo wrapper"
# /usr/local/bin, not ~/.local/bin: this wrapper has to *shadow*
# /usr/bin/fastfetch, and on Omarchy ~/.local/bin sorts after /usr/bin in PATH.
sync_file "$REPO/system/bin/fastfetch" /usr/local/bin/fastfetch 755 /usr/local/bin/fastfetch

# ------------------------------------------------------- wordmark in /etc etc
step "Wordmark in package-owned files"
reapply="$USER_HOME/.local/bin/romulux-reapply-root"
reporter="$USER_HOME/.local/bin/romulux-reapply"
if [[ ! -x $reapply ]]; then
  warn "$reapply is missing -- run install.sh first"
elif [[ -x $reporter ]] && [[ -z "$("$reporter" 2>/dev/null)" ]]; then
  # The reporter prints nothing when all five package-owned items are branded.
  skip "os-release, session entry and terminal title already branded"
elif dry; then
  plan "run $reapply (os-release, session name, floating-terminal title)"
else
  "$reapply"
  ok "os-release, session entry and terminal title checked"
fi

[[ -d ${ROMULUX_BACKUP_DIR:-} ]] && echo "  root-owned backups: $ROMULUX_BACKUP_DIR"
exit 0
