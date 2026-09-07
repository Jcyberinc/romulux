# Romulux — instructions for an agent

This repo installs **Romulux**, a Romulan-themed rebrand of Omarchy, onto the
machine you are running on. Read this before running anything. `README.md` is
the human-facing version; this file is the operating procedure.

## Installing

```bash
./install.sh --dry-run     # always first; prints every change, writes nothing
./install.sh               # pkexec prompts once for the root-owned half
```

Then verify, and report the audit's own summary rather than your impression of
it:

```bash
~/.claude/skills/romulux/audit.sh
```

Exit 0 = clean, 1 = drift. It ends with the Romulan insignia beside a per-area
status table — paste that block into your report verbatim, in a fenced code
block. Do not rebuild it as a markdown table (a markdown table cannot sit
beside ASCII art) and do not retype the art.

The installer is idempotent, so re-running it is the normal way to fix a
partial install. It backs up anything it replaces to
`~/.local/state/romulux/backups/<timestamp>/`.

## Rules that will bite you

- **`pkexec`, never `sudo`.** `sudo` cannot prompt for a password without a
  TTY, so it hangs or fails from an agent session. Every privileged step here
  is already wrapped in `pkexec`; do not "simplify" one to `sudo`.
- **Never edit the branding artwork.** It is hand-made, and it is three
  different subjects — do not describe them interchangeably:
  - `config/branding/screensaver.txt` and the Plymouth/SDDM `logo.png` baked
    from it are the **USS Enterprise-D**. That is the boot, login, logout,
    shutdown and screensaver graphic.
  - `config/branding/about.txt`, the six files in `about-variants/`, and
    `plugin/logo.png` are the **Romulan Star Empire insignia**. That is the
    About screen, the fastfetch logo, and the bar menu button.
  - `config/themes/romulan/backgrounds/1-warbird.jpg` is a depiction of a
    **Romulan warbird** as it appeared in the original series.

  None of it is the Omarchy "clamp" logo — an agent once misread the art as one
  and tried to replace it. Regenerate the PNG only from `screensaver.txt`, only
  with `tools/render-boot-logo.sh`, and only when asked.
- **Never edit `/usr/share/omarchy/`.** It is package-owned and reverts on
  update. That is why the Plymouth and SDDM themes live in their own
  `omarchy-ascii` directories.
- **Never delete the stock themes.** Every `omarchy update` reinstalls all 22
  and deleting them leaves the package failing `pacman -Qkk`. The hidden
  **Style** submenu already makes them unreachable. Lock the style there, not
  on disk.
- **`~/.local/bin` is *after* `/usr/bin` in `PATH`.** It cannot shadow a
  packaged binary. Wrappers that must win go in `/usr/local/bin` — that is why
  the `fastfetch` wrapper is installed there. Commands symlinked from
  `$OMARCHY_PATH/bin` cannot be shadowed at all; attach at a different seam,
  the way the About screen is reached through a menu override instead of by
  replacing `omarchy-launch-about`.
- **Menu overrides blank omitted fields.** A partial override in
  `omarchy-menu.jsonc` normalizes missing keys to empty, so omitting
  `icon`/`label` wipes the stock icon and lowercases the row. Always restate
  them. The stock comment claiming "existing fields are kept" is wrong.
- **Menu rows can only render a font glyph.** `Menu.qml`'s `Image` branch is
  gated on `kind === "app"`, so a custom mark in a menu row has to exist in a
  font. The bar *button* is different — the plugin clone draws a real
  `logo.png`.
- **Do not vendor `Menu.qml` / `MenuModel.js`.** The installer calls `omarchy
  plugin clone omarchy.menu` so those come from the installed Omarchy release.
  Committing a copy pins them to one version.
- **Do not hardcode the menu plugin id.** `omarchy plugin clone` names it
  `<username>.menu`. Use `menu_plugin_id` from `lib/common.sh` (or the copy in
  `skill/audit.sh`), which finds it by `.omarchy.clonedFrom` in the manifest.

## Repairing, not reinstalling

After an `omarchy update`, only the **package-owned** half reverts: the
floating-terminal title, the wayland session name, `/etc/os-release`, the
Plymouth default theme, and the packaged symlink in `$OMARCHY_PATH/bin`. All
five are repaired by one command, which needs a password:

```bash
pkexec ~/.local/bin/romulux-reapply-root
```

Run the audit first to confirm that is what drifted. Do not re-implement those
five fixes anywhere — the audit and the installer both defer to that script so
the logic lives in one place. The **user-owned** half (menu overrides, plugin
clone, artwork, fastfetch config, helper scripts) never reverts; if one of those
is broken it was edited, and the audit prints the specific fix.

Apply without asking: `omarchy theme set romulan`,
`~/.local/bin/omarchy-sddm-logo-sync`, `chmod +x` on the helper scripts,
re-installing a missing hook shim, and re-running `./install.sh`.

Ask first: `pkexec ~/.local/bin/romulux-reapply-root`, anything that rewrites
`omarchy-menu.jsonc` or `shell.json` by hand, any re-render of the boot logo,
and `./uninstall.sh`.

## `[NOTE]` lines are not findings

The audit's `[NOTE]` lines record deliberate decisions and things that cannot be
branded: the 22 stock themes on disk, the green ASCII `OMARCHY` wordmark in the
update terminal, `ID=omarchy`, `LOGO=omarchy`, the upstream URLs, the `omarchy`
CLI command names, plugin provenance, and the wordmark-free hyprlock screen. Do
not "fix" them and do not report them as problems.

## Layout

| Path | Role |
|---|---|
| `install.sh` | orchestrates both halves; `--dry-run`, `--no-root`, `--no-audit` |
| `lib/common.sh` | logging, backup-then-copy, `menu_plugin_id` |
| `lib/install-root.sh` | privileged half — Plymouth, SDDM, `/usr/local/bin`, `/etc` |
| `uninstall.sh`, `lib/uninstall-root.sh` | revert to stock Omarchy (`--purge` also drops the artwork) |
| `skill/` | the `/romulux` Claude Code skill: `SKILL.md` + `audit.sh` |
| `bin/` | helper scripts installed to `~/.local/bin` |
| `config/` | user-owned files: branding, theme, menu, fastfetch, hooks |
| `plugin/` | the two-file delta applied over the menu clone |
| `system/` | root-owned files: Plymouth theme, SDDM conf, fastfetch wrapper |
| `tools/pull-from-system.sh` | live system → repo, re-inserting placeholders |
| `tools/render-boot-logo.sh` | re-bake the boot logo from `screensaver.txt` |

Placeholders rendered at install time: `__ROMULUX_HOME__` (the About row needs
an absolute path — the shell spawns it and its `PATH` need not carry
`~/.local/bin`) and `__ROMULUX_MENU_ID__` in `plugin/BarWidget.qml`.
