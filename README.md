```
         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
         ╲                                 ╱
          ╲━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╱
           ╲                             ╱
 ━━           ━━━━━━             ━━━━━━           ━━
 ╲ `━━━━.━━━━━.━`   `━━━━━━━━━━━'   '━.━━━━━.━━━━' ╱
  `.━╱  ╱        ╲━       ╲       ━╱        ╲  ╲━.'
      ╲━  ┃  ┃  ╲  `.━ ╲     ╱ ━.'  ╱  ┃  ┃  ━╱
        ╲╱━  ┃  ┃ ╱   `.╲   ╱.'   ╲ ┃  ┃  ━╲╱
           ╲╱━━╱━╱ ╱ww╲ (` ') ╱ww╲ ╲━╲━━╲╱
              .━━' ╲━━╱  ╲ ╱  ╲━━╱ `━━.
               ╲╱  ╱`┃    ┃)   ┃'╲  ╲╱
                 ╲╱━╱  ┃  ╱  ┃  ╲━╲╱
                     ╲╱━╱ ┃ ╲━╲╱
                        `━┃━'
                       ╲     ╱
                        ╲   ╱
                         ╲ ╱
                          "
```

# Romulux

A Romulan-themed rebrand of [Omarchy](https://omarchy.org): one theme, the
Romulan Star Empire insignia in place of Omarchy's mark, and custom boot,
login, shutdown and About screens.

Romulux is not a fork. It installs *beside* Omarchy — everything here is a
config file, a helper script, or a theme directory of its own, so `omarchy
update` keeps working and any part of it can be reverted. It also ships an
audit that tells you when an update has reverted something, and a Claude Code
skill so an agent can do the checking and repairing for you.

Built against **Omarchy 4.0.2**.

## Install

```bash
git clone https://github.com/Jcyberinc/romulux.git ~/Projects/romulux
cd ~/Projects/romulux
./install.sh --dry-run     # see exactly what would change
./install.sh
```

`pkexec` prompts once, for the handful of files that live in root-owned paths.
Then:

```bash
omarchy restart shell      # picks up the bar button
```

The boot and login screens change on the next reboot.

Re-running `./install.sh` is safe, and is the supported way to repair drift.
Anything it replaces is copied to `~/.local/state/romulux/backups/<timestamp>/`
first (root-owned files to `/var/backups/romulux/`).

Requirements: Omarchy, `jq`, and a running `omarchy-shell` for the bar-button
step. `fastfetch` and `ttfx` for the About screen, `imagemagick` only if you
re-render the logo.

## What it changes

| Surface | How |
|---|---|
| Theme | a single user theme, `romulan`; the **Style** submenu is hidden so nothing can switch away |
| Boot / shutdown splash | its own Plymouth theme `omarchy-ascii`, with the Enterprise-D as a baked PNG |
| Login / logout screen | its own SDDM theme carrying the same logo |
| Wordmark | `/etc/os-release`, the wayland session name, the floating-terminal title, two menu rows |
| Bar menu button | a clone of the menu plugin drawing `logo.png` instead of the Omarchy clamp glyph |
| About screen | animated logo cycling six 52x19 ASCII variants through `ttfx` effects |
| Drift reporting | `post-update` and `post-boot` hooks that notice reverted branding and say so |

Deliberately left alone: the `omarchy` CLI's own command names and help text,
`ID=omarchy` and `LOGO=omarchy` in os-release, the upstream URLs, plugin
`author`/`clonedFrom` provenance, and the green ASCII `OMARCHY` wordmark at the
top of the update terminal (it is `cat`ed from `$OMARCHY_PATH/logo.txt`, and
`$OMARCHY_PATH/bin` is first on `PATH`, so it can be neither shadowed nor
edited durably). Romulux is a reskin, not a disguise.

## The two halves

Everything Romulux touches is either **user-owned** or **package-owned**, and
the difference is the whole reason the installer is split in two.

**User-owned** — the branding artwork, the `romulan` theme, the menu
overrides, the plugin clone, `~/.config/fastfetch/config.jsonc`, the helper
scripts, the hooks. Nothing reverts these. An update cannot touch them.

**Package-owned** — the floating-terminal title, the wayland session name,
`/etc/os-release`, the Plymouth default theme. These live in files that belong
to `omarchy`, `omarchy-settings` and `plymouth`, so an update resets them. The
`post-update` hook notices and prints:

```bash
pkexec ~/.local/bin/romulux-reapply-root
```

Use `pkexec`, not `sudo` — `sudo` has no TTY to prompt on when the caller is a
hook, a menu entry or an agent session.

## Audit

```bash
~/.claude/skills/romulux/audit.sh
```

Read-only, ~45 checks, exit 0 clean / 1 on drift. It prints `[ OK ]`, `[FAIL]`
and `[NOTE]` lines by area, then the insignia beside a per-area status table,
then the exact repair command for anything that failed.

`[NOTE]` lines are not problems. They record things that are deliberately
unbranded or deliberately left in place — the 22 stock themes on disk, for
instance, which are unreachable via the hidden Style submenu. Deleting them is
a fight `pacman` always wins.

## Working on it

```bash
tools/pull-from-system.sh          # live system -> repo, ready to commit
tools/render-boot-logo.sh          # re-render the logo from screensaver.txt
./uninstall.sh                     # back to stock Omarchy
```

`pull-from-system.sh` puts the machine-specific bits back behind placeholders
(`$HOME`, the menu clone id) so the repo stays installable by anyone.

Two files are deliberately **not** vendored here: `Menu.qml` and `MenuModel.js`
from the menu plugin. They are 70K of upstream Omarchy code that changes between
releases, so the installer runs `omarchy plugin clone omarchy.menu` to get them
fresh and applies only the two-file Romulux delta on top.

## Making it your own

The art is hand-made, and it is three different subjects — worth knowing before
you swap any of it out:

- `config/branding/screensaver.txt` — the **USS Enterprise-D**, in ASCII. This
  is the source art for the boot, login, logout, shutdown and screensaver
  graphic; `tools/render-boot-logo.sh` bakes the PNG from it.
- `config/branding/about.txt` + `about-variants/*.txt` — the **Romulan Star
  Empire insignia**, in ASCII, for the About screen and the fastfetch logo.
  **Every variant must be exactly 52x19**: `omarchy-about-cycle` measures
  `about.txt` to size the window but displays whichever variant the `fastfetch`
  wrapper picked, so an odd-sized one gets framed by a window cut for different
  art. The audit measures all of them.
- `plugin/logo.png` — the same **Romulan Star Empire insignia** as a raster, for
  the bar menu button.
- `config/themes/romulan/backgrounds/1-warbird.jpg` — the wallpaper: a depiction
  of a **Romulan warbird** as it appeared in the original series.

One trap worth knowing if you edit the menu: **a partial override in
`omarchy-menu.jsonc` blanks the fields you omit.** Missing keys normalize to
empty rather than inheriting, so leaving out `icon`/`label` wipes the stock icon
and lowercases the row. Always restate them. The comment in the stock file
claiming existing fields are kept is wrong.

## Credits

Romulux is an independent reskin of [Omarchy](https://omarchy.org) and is not
affiliated with, endorsed by, or supported by that project.

<!-- ROMULUX-MAINTAINER-STATEMENT
     The paragraph below is the repo owner's own words. It is not to be
     edited, reworded, summarised, softened or "fixed" by any tool, agent or
     contributor. Replace the placeholder line with your text and leave it
     exactly as written thereafter.
-->

DHH is a racist pile of garbage, and generally unintelligent in matters that aren't related 
to technology. It's absolutely stupid that his mediocre "distro" is receiving millions of 
real american dollars in funding.
Here are several articles published by him in the past year or so, from his *own* blog, 
where he demonstrates his tendencies towards racist fearmongering and generally being an idiot:
https://world.hey.com/dhh/wolves-sheep-and-gypsies-ba44af6a
https://world.hey.com/dhh/three-sacred-cows-that-must-die-so-europe-can-live-1afb203d 
https://world.hey.com/dhh/the-rape-of-britain-610412f8
https://world.hey.com/dhh/give-me-ai-slop-over-human-sludge-any-day-8c4b747d
https://world.hey.com/dhh/calling-someone-a-nazi-is-a-permission-slip-for-violence-4bfbbb82
https://world.hey.com/dhh/it-s-beginning-to-feel-like-the-80s-in-america-again-68c2708e
https://world.hey.com/dhh/american-hype-6f7afd1b

That being said, I've used Ruby On Rails heavily in the past and I still think it's a great
tool. Omarchy really just isn't that good tho lol. If you insist on using it to test it or
whatever like I am. I encourage you to file off the branding like I did!

Probably don't run this on your computer idk what claude did.
<!-- END ROMULUX-MAINTAINER-STATEMENT -->

Star Trek and the Romulan iconography it alludes to are trademarks of
Paramount; this is unaffiliated fan work.

MIT licensed. See [LICENSE](LICENSE).
