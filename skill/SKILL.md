---
name: romulux
description: Audit and repair the Romulux rebrand of this Omarchy system. Use when asked to check, verify, or re-apply Romulux branding, or after an `omarchy update` or a `pacman` upgrade of omarchy/omarchy-settings/plymouth/sddm has reverted customizations. Covers the single Romulan theme lock, the Omarchy->Romulux wordmark in titles/menus/About, the custom boot (Plymouth), login/logout (SDDM) and shutdown screens, and the animated About logo. Triggers: Romulux, rebrand, warbird, romulan theme, boot splash, plymouth, sddm login logo, about screen, branding drift.
---

# Romulux

This machine is **Romulux**, an Omarchy subdistro: one theme (`romulan`), a
warbird wordmark in place of Omarchy's, and custom boot/login/shutdown/About
screens. Package updates revert parts of it. This skill audits every surface and
repairs the drift.

## Run the audit first

```bash
~/.claude/skills/romulux/audit.sh
```

Read-only, ~45 checks, exit 0 clean / 1 on drift. It prints `[ OK ]`, `[FAIL]`
and `[NOTE]` lines by area, then the warbird emblem with a per-area status table
beside it, then a deduplicated list of repair commands.
**Always run it before changing anything** — it tells you which of the two
halves of the rebrand has drifted, and they are repaired very differently.

`[NOTE]` lines are informational. They record deliberate decisions and things
that cannot be branded. Do not "fix" them.

## Reporting the result

The audit's closing block is the emblem and the status table, side by side:

```
 ━━           ━━━━━━             ━━━━━━           ━━  Romulux        OK  FAIL
 ╲ `━━━━.━━━━━.━`   `━━━━━━━━━━━'   '━.━━━━━.━━━━' ╱  ────────────  ───  ────
  `.━╱  ╱        ╲━       ╲       ━╱        ╲  ╲━.'   Theme lock     11     0
      ╲━  ┃  ┃  ╲  `.━ ╲     ╱ ━.'  ╱  ┃  ┃  ━╱       Wordmark       13     0
```

Paste that block into the report **verbatim, inside a fenced code block** —
copied from the audit output, not retyped. Do not rebuild it as a markdown
table: a markdown table cannot sit beside ASCII art, so the emblem would end up
stacked above it, and retyping the art risks corrupting the warbird (the same
mistake as the "clamp logo" incident below). Add prose or a `[FAIL]` breakdown
after the block, not in place of it.

The layout is chosen from the terminal width: side by side at ≥ 80 columns
(and always when the output is piped, which is how an agent reads it), emblem
stacked above the table below that, table alone below 52 columns. The art is
read from `~/.config/omarchy/branding/about.txt` — the audit never writes it. If
that file is missing, the table prints alone and the `about.txt` check fails,
which is the real finding to report.

## The two halves

**Package-owned** (reverts on update): floating-terminal window title,
wayland session name, `/etc/os-release`, the Plymouth default theme, and the
packaged symlink in `$OMARCHY_PATH/bin`. All five are repaired by one command:

```bash
pkexec ~/.local/bin/romulux-reapply-root
```

`pkexec`, never `sudo` — sudo has no TTY to prompt on here and will hang or
fail from an agent session. Do not re-implement these fixes; the audit
deliberately defers to that script so the logic lives in one place.

**User-owned** (never reverts, but can be broken by editing): the menu
overrides, the menu plugin clone, `~/.config/fastfetch/config.jsonc`,
the SDDM theme directory, the branding artwork, and the helper scripts in
`~/.local/bin`. Repair these individually; the audit prints the specific fix.

## Repair policy

Apply without asking: `omarchy theme set romulan`,
`~/.local/bin/omarchy-sddm-logo-sync`, `chmod +x` on the helper scripts, and
re-installing a missing hook shim.

Ask first: `pkexec ~/.local/bin/romulux-reapply-root` (root, prompts for a
password), anything that rewrites `omarchy-menu.jsonc` or `shell.json`, and any
re-render of the boot logo.

After repairing, re-run the audit and report the delta.

## Hard rules

- **Never touch the branding artwork.** `~/.config/omarchy/branding/about.txt`,
  the six files in `about-variants/`, `screensaver.txt`, and the Plymouth/SDDM
  `logo.png` are a hand-made Romulan warbird. It is *not* the Omarchy "clamp"
  logo — a previous agent misread it as one and tried to replace it. Regenerate
  a `logo.png` only from `screensaver.txt`, and only when asked.
- **Never edit `/usr/share/omarchy/`.** It is package-owned and reverts. The
  custom Plymouth and SDDM themes live in their own directories
  (`omarchy-ascii`) precisely so updates cannot clobber them.
- **Never delete the stock themes.** An earlier version did; every `omarchy
  update` reinstalls all 22 and it left the package failing `pacman -Qkk`, so
  the drift report fired forever. The hidden **Style** submenu already makes
  them unreachable. Lock the style there, not on disk.
- **`~/.local/bin` is *after* `/usr/bin` in PATH.** It cannot shadow a packaged
  binary. Wrappers that must win go in `/usr/local/bin` (that is why the
  `fastfetch` wrapper lives there). Commands symlinked from
  `$OMARCHY_PATH/bin` cannot be shadowed at all — attach at a different seam,
  the way the About screen is reached through a menu override rather than by
  replacing `omarchy-launch-about`.
- **Menu overrides blank omitted fields.** A partial override in
  `omarchy-menu.jsonc` normalizes missing keys to empty — omitting `icon`/
  `label` wipes the stock icon and lowercases the row. Always restate them. The
  stock comment claiming "existing fields are kept" is wrong.
- **The menu clone's id is machine-specific.** `omarchy plugin clone` names it
  `<username>.menu`, so never hardcode it: the audit finds it by provenance
  (`.omarchy.clonedFrom == "omarchy.menu"` in the plugin manifest) and prints
  the id it found, so read the id off the audit rather than assuming one.
- **Menu rows can only render a font glyph.** `Menu.qml`'s `Image` branch is
  gated on `kind === "app"`, so a custom mark in a menu row has to exist in a
  font. The bar *button* is different — the menu plugin clone draws a real
  `logo.png`.

## Re-rendering the boot logo

Only when the branding ASCII changes. The boot logo is a baked PNG, not live
text. `-interline-spacing -4` at pointsize 40 gives the ~2:1 character cell the
art assumes; without it the warbird is vertically stretched.

```bash
magick -background none -fill '#ED5B5A' \
  -font /usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf \
  -pointsize 40 -interline-spacing -4 \
  label:@~/.config/omarchy/branding/screensaver.txt \
  -trim +repage -resize 776x -bordercolor none -border 12 -depth 8 logo.png
```

Then, as root, copy it into `/usr/share/plymouth/themes/omarchy-ascii/` and run
`~/.local/bin/omarchy-sddm-logo-sync` so the login screen matches. Keep backups
in `/var/backups/plymouth-omarchy-ascii/`, **not** in the theme directory — the
Plymouth mkinitcpio hook bundles the whole directory. (This machine's `HOOKS`
carries no plymouth hook, so no initramfs rebuild is needed; the audit checks
that assumption still holds. If it ever changes, see the UKI/limine memory —
`mkinitcpio -P` does not work here.)

## About-screen invariants

Every logo variant must be **exactly 52x19**, matching `about.txt`.
`omarchy-about-cycle` measures `about.txt` to size the window but displays
whichever variant the `fastfetch` wrapper picked, so an odd-sized variant gets
framed by a window cut for different art. The audit measures all of them.

## Known-unbranded, on purpose

The green ASCII `OMARCHY` wordmark at the top of the update terminal
(`omarchy-show-logo` cats `$OMARCHY_PATH/logo.txt`, and `$OMARCHY_PATH/bin` is
first on PATH). Also deliberate: `ID=omarchy` and `LOGO=omarchy` in os-release,
the upstream URLs, the `omarchy` CLI command names and help text, and plugin
`author`/`clonedFrom` provenance. Leave all of it alone.

## Files

Romulux is packaged at <https://github.com/Jcyberinc/romulux> (cloned to
`~/Projects/romulux` here). That repo is the source of truth: `./install.sh` is
idempotent and re-applies everything below, `tools/pull-from-system.sh` copies
live changes back into it, and `./uninstall.sh` reverts to stock Omarchy. After
changing any file in the table below, run `pull-from-system.sh` and commit, or
the change lives on this machine only.

| Path | Role |
|---|---|
| `~/Projects/romulux/` | the packaged repo: installer, uninstaller, sync tools |
| `~/.claude/skills/romulux/audit.sh` | this skill's read-only audit |
| `~/.local/bin/romulux-reapply` | unprivileged drift reporter; also the post-update/post-boot hook |
| `~/.local/bin/romulux-reapply-root` | privileged repair for the five package-owned items |
| `~/.local/bin/omarchy-sddm-logo-sync` | rebuilds the local SDDM theme with the branded logo |
| `~/.local/bin/omarchy-about-cycle` | animated About screen (ttfx effects) |
| `/usr/local/bin/fastfetch` | wrapper injecting a random logo variant |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | menu overrides (About, Style/Learn hidden, wordmark rows) |
| `~/.config/omarchy/plugins/$USER.menu/` | cloned menu plugin; rebranded bar button |
| `~/.config/omarchy/branding/` | the warbird artwork — never edit |
