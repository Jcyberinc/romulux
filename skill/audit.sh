#!/bin/bash
# Romulux audit -- read-only. Verifies every surface of the Romulux rebrand and
# reports what has drifted back to stock Omarchy. Makes no changes; the repair
# commands are printed at the end for you to run deliberately.
#
# Run it any time:  ~/.claude/skills/romulux/audit.sh
# Exit 0 = clean, 1 = at least one FAIL.
#
# Scope note: the five package-owned checks (terminal title, session name,
# os-release, plymouth default, packaged symlink) intentionally mirror
# ~/.local/bin/romulux-reapply. This script does not re-implement their repair
# -- it defers to `pkexec ~/.local/bin/romulux-reapply-root`, so the fix logic
# lives in exactly one place. Keep the *checks* in lockstep if either changes.

set -uo pipefail

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
BRANDING="$HOME/.config/omarchy/branding"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
STATE="$HOME/.local/state/omarchy/current"
PLY_THEME=omarchy-ascii
PLY_DIR="/usr/share/plymouth/themes/$PLY_THEME"
SDDM_DIR="/usr/share/sddm/themes/$PLY_THEME"
TERMINAL_BIN=/usr/bin/omarchy-launch-floating-terminal-with-presentation
TERMINAL_LINK="$OMARCHY_PATH/bin/omarchy-launch-floating-terminal-with-presentation"
SESSION=/usr/local/share/wayland-sessions/omarchy.desktop
LOGO_W=52
LOGO_H=19

if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
  ART=$'\033[38;2;237;91;90m'   # Ethereal red #ED5B5A, the theme's accent
else
  R=; G=; Y=; B=; N=; ART=
fi

fails=(); fixes=()

# Per-area tallies for the summary table beside the emblem. `areas` keeps the
# section order; the short name doubles as the table row label and the key.
areas=(); declare -A ok_n=() fail_n=(); area=summary
ok_n[summary]=0; fail_n[summary]=0

sec()  { # sec <heading> [short-name-for-the-summary-table]
  area="${2:-$1}"
  areas+=("$area"); ok_n[$area]=0; fail_n[$area]=0
  printf '\n%s%s%s\n' "$B" "$1" "$N"
}
# pass/note must end on a successful command -- several callers chain them with
# `&& pass ... || fail ...`, so a bare (( n++ )) returning 1 would fire the fail.
pass() { printf '  %s[ OK ]%s %s\n' "$G" "$N" "$1"; (( ok_n[$area]++ )); return 0; }
note() { printf '  %s[NOTE]%s %s\n' "$Y" "$N" "$1"; return 0; }
fail() { # fail <message> [repair-command]
  printf '  %s[FAIL]%s %s\n' "$R" "$N" "$1"
  fails+=("$1")
  (( fail_n[$area]++ ))
  [[ -n ${2:-} ]] && fixes+=("$2")
  return 0
}

# Active (non-comment) lines of the JSONC menu, so commented-out examples in the
# stock header never satisfy a check.
menu_row() { grep -v '^[[:space:]]*//' "$MENU" 2>/dev/null | grep -F "\"$1\":"; }

# Widest line in characters (not bytes) and the line count of an ASCII-art file.
art_dims() { awk '{n=length($0); if(n>m)m=n} END{printf "%dx%d", m, NR}' "$1"; }

# The menu clone's id is "<username>.menu" -- `omarchy plugin clone` prefixes it
# with the username so a shared clone stays yours -- so it is machine-specific
# and must not be hardcoded. Find it by provenance instead: the clone carries
# .omarchy.clonedFrom = "omarchy.menu" in its manifest.
menu_plugin_id() {
  local m
  for m in "$HOME"/.config/omarchy/plugins/*/manifest.json; do
    [[ -f $m ]] || continue
    if command -v jq >/dev/null 2>&1; then
      [[ "$(jq -r '.omarchy.clonedFrom // empty' "$m" 2>/dev/null)" == omarchy.menu ]] || continue
    else
      grep -q '"clonedFrom"[[:space:]]*:[[:space:]]*"omarchy\.menu"' "$m" || continue
    fi
    basename "$(dirname "$m")"
    return 0
  done
  return 1
}
MENU_ID="$(menu_plugin_id || true)"
MENU_DIR="$HOME/.config/omarchy/plugins/$MENU_ID"

printf '%sRomulux audit%s  %s\n' "$B" "$N" "$(date '+%Y-%m-%d %H:%M')"

# ---------------------------------------------------------------- theme lock
sec "Theme lock (single Romulan style)" "Theme lock"

if [[ -f $STATE/theme.name ]] && [[ "$(cat "$STATE/theme.name")" == romulan ]]; then
  pass "active theme is romulan"
else
  fail "active theme is '$(cat "$STATE/theme.name" 2>/dev/null || echo unknown)', not romulan" \
       "omarchy theme set romulan"
fi

if [[ -f $HOME/.config/omarchy/themes/romulan/colors.toml ]]; then
  pass "user theme ~/.config/omarchy/themes/romulan is present"
  if cmp -s "$STATE/theme/colors.toml" "$HOME/.config/omarchy/themes/romulan/colors.toml"; then
    pass "generated theme in state matches the romulan source"
  else
    fail "applied theme colors differ from the romulan source (stale generation)" \
         "omarchy theme set romulan"
  fi
else
  fail "user theme ~/.config/omarchy/themes/romulan is missing -- restore from backup" ""
fi

for f in backgrounds icons.theme neovim.lua vscode.json; do
  [[ -e $HOME/.config/omarchy/themes/romulan/$f ]] \
    && pass "romulan/$f present" \
    || fail "romulan/$f missing" ""
done

bg="$(readlink -f "$STATE/background" 2>/dev/null)"
if [[ -f $bg && $bg == *"/theme/backgrounds/"* ]]; then
  pass "background resolves into the active theme ($(basename "$bg"))"
else
  fail "background does not resolve into the active theme" "omarchy theme set romulan"
fi

others=$(find "$HOME/.config/omarchy/themes" -mindepth 1 -maxdepth 1 -type d \
         ! -name romulan -printf '%f ' 2>/dev/null)
[[ -z $others ]] && pass "romulan is the only user theme" \
                 || note "extra user themes present: $others"

if [[ -n $(menu_row style | grep -F '"when":"false"') ]]; then
  pass "Style submenu hidden from the Super+Space menu"
else
  fail "Style submenu is reachable -- stock themes can be selected" \
       "add  \"style\": {\"icon\":\"\",\"label\":\"Style\",\"when\":\"false\"}  to $MENU"
fi

if grep -rqE 'omarchy[- ]theme[- ]?(set|next)' "$HOME/.config/hypr/"*.lua 2>/dev/null; then
  fail "a Hyprland keybinding can still switch themes" "remove the theme binding from ~/.config/hypr/bindings.lua"
else
  pass "no Hyprland keybinding switches themes"
fi

stock=$(find "$OMARCHY_PATH/themes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
if (( stock > 0 )); then
  note "$stock stock themes still on disk under $OMARCHY_PATH/themes -- expected."
  note "  Deleting them is a fight pacman always wins (every update reinstalls all"
  note "  of them and leaves the package failing 'pacman -Qkk'). They are made"
  note "  unreachable by the hidden Style submenu above instead."
else
  note "stock themes are absent -- they will return on the next omarchy update"
fi

# ------------------------------------------------------------ wordmark/titles
sec "Wordmark and titling" "Wordmark"

if grep -q '^NAME="Romulux"' /etc/os-release && grep -q '^PRETTY_NAME="Romulux"' /etc/os-release; then
  pass "os-release NAME/PRETTY_NAME are Romulux (About OS line, TTY banner)"
else
  fail "os-release reset to Omarchy" "pkexec ~/.local/bin/romulux-reapply-root"
fi

if [[ -f $SESSION ]] && grep -q '^Name=Romulux' "$SESSION"; then
  pass "wayland session entry is Romulux"
else
  fail "login session name reset to Omarchy" "pkexec ~/.local/bin/romulux-reapply-root"
fi

if [[ -f $TERMINAL_BIN ]] && grep -q -- '--title=Romulux' "$TERMINAL_BIN"; then
  pass "floating terminal title is Romulux"
else
  fail "floating terminal title reset to Omarchy" "pkexec ~/.local/bin/romulux-reapply-root"
fi

if [[ ! -e $TERMINAL_LINK || -L $TERMINAL_LINK ]]; then
  pass "packaged symlink at \$OMARCHY_PATH/bin is intact"
else
  fail "packaged symlink replaced by a detached copy (pins a stale script body)" \
       "pkexec ~/.local/bin/romulux-reapply-root"
fi

for row in learn.omarchy update.omarchy; do
  if [[ -n $(menu_row "$row" | grep -F '"label":"Romulux"') ]]; then
    pass "menu row $row is labelled Romulux"
  else
    fail "menu row $row still says Omarchy" "restore the \"$row\" override in $MENU"
  fi
done

if [[ -n $(menu_row update.omarchy | grep -F 'iconFont') ]]; then
  fail "update.omarchy still sets iconFont -- it will draw the Omarchy clamp mark" \
       "drop iconFont from the \"update.omarchy\" row in $MENU"
else
  pass "update.omarchy uses the bird glyph, not the omarchy icon font"
fi

if [[ -n $(menu_row learn | grep -F '"when":"false"') ]]; then
  pass "Learn submenu hidden"
else
  note "Learn submenu is visible (cosmetic -- its row is rebranded either way)"
fi

if [[ -n $MENU_ID ]]; then
  pass "$MENU_ID plugin clone present (rebranded bar menu button)"
  if grep -q 'logo.png' "$MENU_DIR/BarWidget.qml" 2>/dev/null && [[ -f $MENU_DIR/logo.png ]]; then
    pass "bar menu button draws the Romulan insignia logo.png"
  else
    fail "bar menu button fell back to the \\ue900 Omarchy clamp glyph" \
         "restore BarWidget.qml + logo.png in ~/.config/omarchy/plugins/$MENU_ID"
  fi
  if command -v jq >/dev/null && [[ -f $SHELL_JSON ]]; then
    jq -e --arg id "$MENU_ID" '[.bar.layout[][].id] | index($id)' "$SHELL_JSON" >/dev/null 2>&1 \
      && pass "$MENU_ID is in the bar layout" \
      || fail "$MENU_ID is not in the bar layout" "add {\"id\":\"$MENU_ID\"} to bar.layout.left in $SHELL_JSON"
    jq -e '(.disabledPlugins // []) | index("omarchy.menu")' "$SHELL_JSON" >/dev/null 2>&1 \
      && pass "stock omarchy.menu is disabled" \
      || fail "stock omarchy.menu is still enabled (duplicate menu)" "add \"omarchy.menu\" to disabledPlugins in $SHELL_JSON"
  fi
else
  fail "no menu plugin clone -- bar button reverts to the Omarchy mark" \
       "omarchy plugin clone omarchy.menu, then re-run the Romulux installer"
fi

if grep -q 'Romulux \$version' "$HOME/.config/fastfetch/config.jsonc" 2>/dev/null; then
  pass "About screen OS line reads Romulux"
else
  fail "About screen OS line no longer reads Romulux" \
       "restore the OS module text in ~/.config/fastfetch/config.jsonc"
fi

note "unbranded by necessity: the green ASCII OMARCHY wordmark printed by"
note "  omarchy-show-logo at the top of the update terminal. It cats"
note "  \$OMARCHY_PATH/logo.txt, and \$OMARCHY_PATH/bin is first on PATH, so it"
note "  can be neither shadowed nor edited durably."
note "deliberate: ID=omarchy, LOGO=omarchy, upstream URLs, the omarchy CLI"
note "  command names and help text, and plugin author/clonedFrom provenance."

# ------------------------------------------------------------------ boot
sec "Boot screen (Plymouth)" "Boot splash"

if [[ -d $PLY_DIR ]]; then
  pass "custom plymouth theme $PLY_THEME present"
else
  fail "plymouth theme $PLY_THEME is gone" "re-render logo.png and recreate $PLY_DIR (see custom-plymouth-theme memory)"
fi

if [[ "$(plymouth-set-default-theme 2>/dev/null)" == "$PLY_THEME" ]]; then
  pass "boot splash is set to $PLY_THEME"
else
  fail "boot splash reset to the stock plymouth theme" "pkexec ~/.local/bin/romulux-reapply-root"
fi

if [[ -f $PLY_DIR/logo.png ]]; then
  if cmp -s "$PLY_DIR/logo.png" /usr/share/plymouth/themes/omarchy/logo.png; then
    fail "boot logo is byte-identical to the stock Omarchy logo" \
         "re-render logo.png from $BRANDING/screensaver.txt -- the Enterprise-D art (see tools/render-boot-logo.sh)"
  else
    pass "boot logo differs from stock (custom Enterprise-D render)"
  fi
else
  fail "boot logo.png missing from $PLY_DIR" ""
fi

if grep -q '0.929, 0.357, 0.353' "$PLY_DIR/$PLY_THEME.script" 2>/dev/null; then
  pass "boot message text is Ethereal red"
else
  fail "boot message text is not the Ethereal red floats (0.929, 0.357, 0.353)" \
       "edit Image.Text in $PLY_DIR/$PLY_THEME.script"
fi

strays=$(find "$PLY_DIR" -maxdepth 1 \( -name '*.bak' -o -name '*.orig' -o -name '*~' \) 2>/dev/null)
if [[ -z $strays ]]; then
  pass "no backup files inside the theme dir"
else
  fail "backup files inside $PLY_DIR would be bundled into the UKI: $strays" \
       "move them to /var/backups/plymouth-omarchy-ascii/"
fi

if grep -qE '^HOOKS=.*plymouth' /etc/mkinitcpio.conf 2>/dev/null; then
  note "mkinitcpio HOOKS carries plymouth -- logo changes need an initramfs rebuild"
else
  pass "plymouth runs from the real root (no initramfs rebuild needed for logo changes)"
fi

grep -qw splash /proc/cmdline \
  && pass "kernel cmdline carries 'splash'" \
  || fail "kernel cmdline has no 'splash' -- the boot screen will not show" "add splash to the kernel cmdline"

# ----------------------------------------------------------------- login
sec "Login / logout screen (SDDM)" "Login screen"

if [[ -d $SDDM_DIR ]]; then
  pass "local SDDM theme $PLY_THEME present (survives omarchy update)"
else
  fail "local SDDM theme missing -- login shows the stock green OMARCHY wordmark" \
       "~/.local/bin/omarchy-sddm-logo-sync"
fi

if cmp -s "$SDDM_DIR/logo.png" "$PLY_DIR/logo.png" 2>/dev/null; then
  pass "login logo matches the boot logo"
else
  fail "login logo is out of sync with the boot logo" "~/.local/bin/omarchy-sddm-logo-sync"
fi

# Last-sorting [Theme] Current wins in SDDM's conf.d merge.
winner=$(grep -l '^\[Theme\]' /etc/sddm.conf.d/*.conf 2>/dev/null | sort | tail -1)
if [[ -n $winner ]] && grep -q "^Current=$PLY_THEME" "$winner"; then
  pass "SDDM theme selected by $(basename "$winner")"
else
  fail "the last-sorting sddm.conf.d file does not select $PLY_THEME (winner: ${winner:-none})" \
       "ensure /etc/sddm.conf.d/zz-omarchy-ascii-theme.conf sorts last and sets Current=$PLY_THEME"
fi

note "shutdown and reboot screens are the same Plymouth theme as boot"
note "  (plymouth-poweroff/reboot.service), so the boot checks above cover them."
note "the hyprlock lock screen carries no wordmark -- it renders theme colors only."

# ----------------------------------------------------------------- about
sec "About screen (animated logo)" "About screen"

if [[ -x $HOME/.local/bin/omarchy-about-cycle ]]; then
  pass "omarchy-about-cycle present and executable"
else
  fail "omarchy-about-cycle missing or not executable" "chmod +x ~/.local/bin/omarchy-about-cycle"
fi

if [[ -n $(menu_row about | grep -F 'omarchy-about-cycle') ]]; then
  pass "menu About row runs the cycling About screen"
  if [[ -n $(menu_row about | grep -F '"label":"About"') ]]; then
    pass "About row restates its label (a partial override would blank it)"
  else
    fail "About row omits label -- the override blanks the stock label" \
         "restate \"icon\" and \"label\" on the \"about\" row in $MENU"
  fi
else
  fail "menu About row falls back to the stock static About screen" \
       "point the \"about\" row at /home/\$USER/.local/bin/omarchy-about-cycle in $MENU"
fi

command -v ttfx >/dev/null \
  && pass "ttfx installed (drives the logo effects)" \
  || fail "ttfx missing -- the About logo will not animate" "omarchy pkg add ttfx"

if [[ "$(command -v fastfetch)" == /usr/local/bin/fastfetch ]]; then
  pass "fastfetch wrapper shadows /usr/bin/fastfetch (random logo variant)"
else
  fail "fastfetch wrapper is not first on PATH -- logo variants will not rotate" \
       "reinstall the wrapper at /usr/local/bin/fastfetch (~/.local/bin is appended to PATH and cannot shadow)"
fi

if [[ -f $BRANDING/about.txt ]]; then
  d=$(art_dims "$BRANDING/about.txt")
  [[ $d == "${LOGO_W}x${LOGO_H}" ]] \
    && pass "about.txt is ${LOGO_W}x${LOGO_H}" \
    || fail "about.txt is $d, expected ${LOGO_W}x${LOGO_H} -- the About window is cut from this file" ""
else
  fail "about.txt missing" ""
fi

shopt -s nullglob
variants=("$BRANDING"/about-variants/*.txt)
shopt -u nullglob
if (( ${#variants[@]} )); then
  bad=()
  for v in "${variants[@]}"; do
    d=$(art_dims "$v")
    [[ $d == "${LOGO_W}x${LOGO_H}" ]] || bad+=("$(basename "$v"):$d")
  done
  if (( ${#bad[@]} == 0 )); then
    pass "all ${#variants[@]} logo variants are ${LOGO_W}x${LOGO_H}"
  else
    fail "logo variants with the wrong size: ${bad[*]} -- they will be framed by a window cut for about.txt" ""
  fi
else
  fail "no logo variants in $BRANDING/about-variants" ""
fi

[[ -f $BRANDING/screensaver.txt ]] \
  && pass "screensaver.txt present (Enterprise-D, source art for the boot logo)" \
  || fail "screensaver.txt missing" ""

# ------------------------------------------------------- update resilience
sec "Update resilience" "Resilience"

for s in romulux-reapply romulux-reapply-root omarchy-sddm-logo-sync omarchy-about-cycle; do
  [[ -x $HOME/.local/bin/$s ]] && pass "~/.local/bin/$s executable" \
                              || fail "~/.local/bin/$s missing or not executable" ""
done

for h in post-update post-boot; do
  hook="$HOME/.config/omarchy/hooks/$h.d/romulux-reapply"
  if [[ -x $hook ]] && grep -q 'romulux-reapply' "$hook"; then
    pass "$h hook installed"
  else
    fail "$h hook missing -- drift will go unreported" \
         "install a shim at $hook that execs ~/.local/bin/romulux-reapply"
  fi
done

# ---------------------------------------------------------------- summary
# Per-area tally, printed beside the emblem. The art is *read* from
# ~/.config/omarchy/branding/about.txt and never written -- it is the same 52x19
# Romulan Star Empire insignia the About screen frames. Composition happens in awk because bash
# printf pads by bytes, and the box-drawing glyphs are multi-byte: %-52s would
# short-pad every line and shear the right-hand column.
summary_table() {
  local w=5 a tok=0 tfail=0 dash
  for a in "${areas[@]}"; do (( ${#a} > w )) && w=${#a}; done
  printf -v dash '%*s' "$w" ''; dash=${dash// /─}
  printf '%-*s  %3s  %4s\n' "$w" "Romulux" "OK" "FAIL"
  printf '%s  %3s  %4s\n' "$dash" "───" "────"
  for a in "${areas[@]}"; do
    printf '%-*s  %3d  %4d\n' "$w" "$a" "${ok_n[$a]}" "${fail_n[$a]}"
    (( tok += ok_n[$a], tfail += fail_n[$a] ))
  done
  printf '%s  %3s  %4s\n' "$dash" "───" "────"
  printf '%-*s  %3d  %4d\n' "$w" "Total" "$tok" "$tfail"
}

table="$(summary_table)"
tblw=$(printf '%s\n' "$table" | awk '{n=length($0); if(n>m)m=n} END{print m}')

# Not a tty (piped into a report): assume a wide destination and stay side by
# side. On a tty, fall back to stacking when the emblem plus table would wrap.
cols=100
if [[ -t 1 ]]; then
  c=$(tput cols 2>/dev/null)
  [[ $c =~ ^[0-9]+$ ]] && cols=$c
fi

printf '\n'
if [[ -s $BRANDING/about.txt ]] && (( cols >= LOGO_W + 2 + tblw )); then
  awk -v W="$LOGO_W" -v C="$ART" -v Z="$N" '
    FNR==NR { art[++na]=$0; next }
            { tbl[++nb]=$0 }
    END {
      rows = na > nb ? na : nb
      aoff = nb > na ? int((nb - na) / 2) : 0   # vertically centre the shorter
      toff = na > nb ? int((na - nb) / 2) : 0   # block against the taller one
      for (i = 1; i <= rows; i++) {
        ai = i - aoff; ti = i - toff
        line = ""
        if (ai >= 1 && ai in art) {
          pad = W - length(art[ai]) + 2; if (pad < 1) pad = 1
          line = C art[ai] Z sprintf("%*s", pad, "")
        } else if (ti >= 1 && ti in tbl) {
          line = sprintf("%*s", W + 2, "")
        }
        if (ti >= 1 && ti in tbl) line = line tbl[ti]
        sub(/[ \t]+$/, "", line)
        print line
      }
    }
  ' "$BRANDING/about.txt" - <<< "$table"
else
  # Stacked: emblem above the table, and dropped entirely below 52 columns
  # where every line of it would wrap.
  [[ -s $BRANDING/about.txt ]] && (( cols >= LOGO_W )) \
    && printf '%s%s%s\n\n' "$ART" "$(cat "$BRANDING/about.txt")" "$N"
  printf '%s\n' "$table"
fi

printf '\n%s%s%s\n' "$B" "────────────────────────────────────────────────────────" "$N"
if (( ${#fails[@]} == 0 )); then
  printf '%sRomulux is fully applied.%s No drift found.\n' "$G" "$N"
  exit 0
fi

printf '%s%d check(s) failed.%s Repair:\n\n' "$R" "${#fails[@]}" "$N"
printf '%s\n' "${fixes[@]}" | awk '!seen[$0]++ {print "  " $0}'
printf '\nRe-run this audit afterwards to confirm.\n'
exit 1
