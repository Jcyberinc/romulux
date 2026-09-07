#!/bin/bash
# Shared helpers for the Romulux installer, uninstaller and sync tools.
# Sourced, never executed.

ROMULUX_DRY_RUN=${ROMULUX_DRY_RUN:-0}

if [[ -t 1 ]]; then
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[1m'; C_N=$'\033[0m'
  C_ART=$'\033[38;2;237;91;90m'
else
  C_R=; C_G=; C_Y=; C_B=; C_N=; C_ART=
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_ART" "$C_N" "$C_B" "$1" "$C_N"; }
ok()   { printf '  %s+%s %s\n' "$C_G" "$C_N" "$1"; }
skip() { printf '  %s=%s %s\n' "$C_N" "$C_N" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_N" "$1" >&2; }
die()  { printf '\n%serror:%s %s\n' "$C_R" "$C_N" "$1" >&2; exit 1; }
plan() { printf '  %s~%s would %s\n' "$C_Y" "$C_N" "$1"; }

dry() { (( ROMULUX_DRY_RUN )); }

# Backups go outside every directory the installer manages, so nothing we write
# can pick them up: the Plymouth mkinitcpio hook bundles its whole theme dir,
# and omarchy re-reads anything dropped in hooks.d / extensions.
ROMULUX_BACKUP_ROOT=${ROMULUX_BACKUP_ROOT:-$HOME/.local/state/romulux/backups}
ROMULUX_BACKUP_DIR=""

backup_of() { # backup_of <path> -- copy a file aside, once per run
  local src="$1" rel dst
  [[ -e $src ]] || return 0
  if [[ -z $ROMULUX_BACKUP_DIR ]]; then
    ROMULUX_BACKUP_DIR="$ROMULUX_BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
  fi
  rel="${src#/}"
  dst="$ROMULUX_BACKUP_DIR/$rel"
  dry && { plan "back up $src"; return 0; }
  install -d "$(dirname "$dst")"
  cp -a "$src" "$dst"
  return 0
}

# sync_file <src> <dst> [mode] -- idempotent copy that never silently discards a
# file the user already had. Unchanged files are left alone so mtimes stay put
# (the About window watches branding/about.txt's mtime to decide when to
# repaint, and a needless touch drives that render loop).
sync_file() {
  local src="$1" dst="$2" mode="${3:-644}" label="${4:-$2}"
  [[ -f $src ]] || die "missing repo file: $src"
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
    [[ "$(stat -c %a "$dst")" == "$mode" ]] || { dry || chmod "$mode" "$dst"; }
    skip "$label (unchanged)"
    return 0
  fi
  if dry; then
    [[ -e $dst ]] && plan "replace $label (backing up the current one)" \
                  || plan "install $label"
    return 0
  fi
  [[ -e $dst ]] && backup_of "$dst"
  install -Dm"$mode" "$src" "$dst"
  ok "$label"
}

sync_tree() { # sync_tree <src-dir> <dst-dir> [mode]
  local src="$1" dst="$2" mode="${3:-644}" f rel
  [[ -d $src ]] || die "missing repo directory: $src"
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    sync_file "$f" "$dst/$rel" "$mode" "$dst/$rel"
  done < <(find "$src" -type f -print0 | sort -z)
}

need() { command -v "$1" >/dev/null || die "$1 is required but not installed${2:+ ($2)}"; }

# The menu clone's id is "<username>.menu" -- `omarchy plugin clone` prefixes it
# so a shared clone stays yours -- so it differs on every machine. Never hardcode
# it; find it by provenance (manifest .omarchy.clonedFrom).
menu_plugin_id() {
  local m id
  for m in "$HOME"/.config/omarchy/plugins/*/manifest.json; do
    [[ -f $m ]] || continue
    if command -v jq >/dev/null 2>&1; then
      [[ "$(jq -r '.omarchy.clonedFrom // empty' "$m" 2>/dev/null)" == omarchy.menu ]] || continue
    else
      grep -q '"clonedFrom"[[:space:]]*:[[:space:]]*"omarchy\.menu"' "$m" || continue
    fi
    id="$(basename "$(dirname "$m")")"
    printf '%s\n' "$id"
    return 0
  done
  return 1
}
