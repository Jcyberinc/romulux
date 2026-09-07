#!/bin/bash
# Re-render the boot / login logo from the ASCII art. Only needed when
# config/branding/screensaver.txt changes -- the splash shows a baked PNG, not
# live text, so the art and the image are two separate things to keep in step.
#
#   tools/render-boot-logo.sh              render into the repo
#   tools/render-boot-logo.sh --install    render, then install it system-wide
#
# The art is the Enterprise-D. -interline-spacing -4 at pointsize 40 is what
# gives the ~2:1 character cell it was drawn for; without it every glyph row gets
# its full font leading and the ship comes out vertically stretched.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/lib/common.sh"

do_install=0
[[ ${1:-} == --install ]] && do_install=1

need magick "imagemagick"
ART="$REPO/config/branding/screensaver.txt"
OUT="$REPO/system/plymouth/omarchy-ascii/logo.png"
FONT=${ROMULUX_FONT:-/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf}
[[ -f $ART ]]  || die "no ASCII art at $ART"
[[ -f $FONT ]] || die "font not found: $FONT (override with ROMULUX_FONT=/path/to/font.ttf)"

step "Rendering $ART"
tmp="$(mktemp --suffix=.png)"
magick -background none -fill '#ED5B5A' \
  -font "$FONT" \
  -pointsize 40 -interline-spacing -4 \
  label:@"$ART" \
  -trim +repage -resize 776x -bordercolor none -border 12 -depth 8 "$tmp"
ok "rendered $(identify -format '%wx%h' "$tmp")"

# Compare pixels, not bytes. ImageMagick stamps a creation time into the PNG, so
# two renders of identical art are never byte-identical -- comparing with cmp
# would report a change on every single run and dirty the repo for nothing.
same_pixels() {
  local ae
  [[ -f $1 && -f $2 ]] || return 1
  ae="$(magick compare -metric AE "$1" "$2" null: 2>&1 | tail -1 | awk '{print $1}')"
  [[ $ae == 0 ]]
}

if same_pixels "$tmp" "$OUT"; then
  skip "system/plymouth/omarchy-ascii/logo.png (pixel-identical, left alone)"
else
  cp "$tmp" "$OUT"
  ok "system/plymouth/omarchy-ascii/logo.png updated"
fi
rm -f "$tmp"

if (( do_install )); then
  step "Installing system-wide"
  # Keep spare copies in /var/backups, never in the theme directory: the
  # mkinitcpio plymouth hook bundles that whole directory into the initramfs.
  pkexec /bin/bash -c '
    set -e
    install -d /var/backups/plymouth-omarchy-ascii
    [[ -f /usr/share/plymouth/themes/omarchy-ascii/logo.png ]] &&
      cp -a /usr/share/plymouth/themes/omarchy-ascii/logo.png \
            "/var/backups/plymouth-omarchy-ascii/logo.png.$(date +%Y%m%d-%H%M%S)"
    install -Dm644 "$1" /usr/share/plymouth/themes/omarchy-ascii/logo.png
  ' _ "$OUT"
  ok "boot logo installed"
  "$HOME/.local/bin/omarchy-sddm-logo-sync" omarchy-ascii && ok "login logo synced"
  echo "  the new logo appears on the next reboot"
else
  echo
  echo "  install it with:  tools/render-boot-logo.sh --install"
fi
