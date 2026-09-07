#!/bin/bash
# Privileged half of the Romulux uninstall. Escalated by uninstall.sh:
#
#     pkexec /bin/bash lib/uninstall-root.sh <repo>
#
# Reverts the root-owned surfaces to the stock Omarchy values. The Romulux
# Plymouth and SDDM theme *directories* are removed; the packaged `omarchy`
# themes they were built beside were never modified, so nothing has to be
# reinstalled to get the stock screens back.
set -euo pipefail

dryrun=0
[[ ${1:-} == --dry-run ]] && { dryrun=1; shift; }
REPO="${1:?repo path required}"

ROMULUX_DRY_RUN=$dryrun
ROMULUX_BACKUP_ROOT=/var/backups/romulux
source "$REPO/lib/common.sh"

(( dryrun )) || (( EUID == 0 )) || die "must run as root (use uninstall.sh, which escalates with pkexec)"

PLY_THEME=omarchy-ascii

step "Boot splash"
if [[ "$(plymouth-set-default-theme 2>/dev/null || true)" == "$PLY_THEME" ]]; then
  if dry; then
    plan "point the boot splash back at the stock omarchy theme"
  elif [[ -d /usr/share/plymouth/themes/omarchy ]]; then
    if grep -qE '^HOOKS=.*plymouth' /etc/mkinitcpio.conf 2>/dev/null; then
      plymouth-set-default-theme --rebuild-initrd omarchy
    else
      plymouth-set-default-theme omarchy
    fi
    ok "boot splash set back to omarchy"
  else
    warn "no stock omarchy plymouth theme to fall back to; leaving the splash alone"
  fi
else
  skip "boot splash is not set to $PLY_THEME"
fi

step "Theme directories and wrapper"
for p in "/usr/share/plymouth/themes/$PLY_THEME" \
         "/usr/share/sddm/themes/$PLY_THEME" \
         /etc/sddm.conf.d/zz-omarchy-ascii-theme.conf \
         /usr/local/bin/fastfetch; do
  if [[ ! -e $p ]]; then
    skip "$p (absent)"
  elif dry; then
    plan "remove $p"
  else
    backup_of "$p"
    rm -rf "$p"
    ok "removed $p"
  fi
done

step "Wordmark"
# os-release, the session entry and the floating-terminal title are edits to
# package-owned files, reverted here with the inverse substitutions.
revert() { # revert <file> <grep-pattern> <sed-expr> <label>
  local f="$1" pattern="$2" expr="$3" label="$4"
  [[ -f $f ]] || { skip "$label (no $f)"; return 0; }
  grep -qE -- "$pattern" "$f" || { skip "$label (already stock)"; return 0; }
  dry && { plan "revert $label"; return 0; }
  backup_of "$f"
  sed -i "$expr" "$f"
  ok "$label reverted"
}
revert /etc/os-release '^NAME="Romulux"$' \
       's/^NAME="Romulux"$/NAME="Omarchy"/' "os-release NAME"
revert /etc/os-release '^PRETTY_NAME="Romulux"$' \
       's/^PRETTY_NAME="Romulux"$/PRETTY_NAME="Omarchy"/' "os-release PRETTY_NAME"
revert /usr/local/share/wayland-sessions/omarchy.desktop '^Name=Romulux' \
       's/^Name=Romulux (Hyprland uwsm)$/Name=Omarchy (Hyprland uwsm)/' "session name"
revert /usr/local/share/wayland-sessions/omarchy.desktop '^Comment=Romulux' \
       's/^Comment=Romulux Hyprland session managed by uwsm$/Comment=Omarchy Hyprland session managed by uwsm/' "session comment"
revert /usr/bin/omarchy-launch-floating-terminal-with-presentation '--title=Romulux' \
       's/--title=Romulux/--title=Omarchy/' "floating terminal title"

[[ -d ${ROMULUX_BACKUP_DIR:-} ]] && echo "  root-owned backups: $ROMULUX_BACKUP_DIR"
exit 0
