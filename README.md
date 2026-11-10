<div align="center">

<img src="./docs-md/assets/edge-logo.svg" width="120" alt="AeroSpace-edge">

# AeroSpace‑edge

**AeroSpace, with upstream's fixes already in.**

[![latest release](https://img.shields.io/github/v/release/vitorebatista/AeroSpace-edge?include_prereleases&label=release&color=6366F1)](https://github.com/vitorebatista/AeroSpace-edge/releases/latest)
[![license](https://img.shields.io/badge/license-MIT-22D3EE)](./LICENSE.txt)
[![upstream](https://img.shields.io/badge/upstream-nikitabobko%2FAeroSpace-A855F7)](https://github.com/nikitabobko/AeroSpace)

</div>

---

## What this is

**AeroSpace‑edge is an i3-like tiling window manager for macOS that ships fixes as soon as they exist,
not whenever the next release is tagged.**

Tree-based tiling, real keyboard control, plain-text config, a CLI you can script, no SIP disabling and
no private-API tricks. If you've used AeroSpace, you already know how to use this — same tree model, same
config file, same commands. What's different is the release cadence and what's already fixed.

The fix you need is usually written before you hit the bug. It sits in a merged commit or an open pull
request while the release it belongs to takes months to land. AeroSpace‑edge exists to close that gap:
the work gets picked up, adapted, tested and shipped, in weeks rather than release cycles.

How it stays trustworthy while moving fast:

- **Every change is its own reviewed pull request** — 59 of them so far — never a bulk merge.
- **Nothing lands untested.** `./script/build-debug.sh -Xswiftc -warnings-as-errors` and `./script/swift-test.sh` both
  pass before a branch merges; warnings are errors, and the suite runs 227 tests.
- **52 fixes and features** carried so far, each traceable to where it came from in
  [`CHANGELOG-FORK.md`](./CHANGELOG-FORK.md).
- **Refactors and breaking config changes stay out.** Moving fast on fixes and slow on churn is the
  whole trick — it's what keeps a fork from rotting.
- **It installs as its own app**, so it can sit next to another window manager and be judged on results
  rather than on a promise.

Thirteen releases so far. Current: **v1.13**. Versions are `1.MINOR[.PATCH]` — minor for new behavior,
patch for fixes and packaging.

Built on [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) at commit
[`63e0976b`](https://github.com/nikitabobko/AeroSpace/commit/63e0976b), MIT, with full credit
[below](#credit).

## Why you might want it

Grab a release if any of these have bitten you:

| | |
|---|---|
| **Crashes** | `is already unbound` when two `focus` commands race · `EXC_BAD_ACCESS` during display reconfiguration · `ThreadGuardedValue` crash · `die`/`dieT` deadlock |
| **Windows in the wrong place** | native tabs (Finder, Ghostty, Fork) leaving phantom tiles · windows flashing tiled before a floating rule applies · floating windows misplaced after screen wake · Emacs / Outlook / Codex / iTerm2 Settings popups mis-detected |
| **Layout math** | `balance-sizes` throwing away container weights, so a later `resize` made windows jump |
| **CLI** | `layout sticky` · `list-windows --sort` · `enable-normalization` per workspace · `summon-workspace --when-visible` · `debug-windows --app-bundle-id` · resizable floating windows |
| **Integrations** | the socket protocol handshake modern clients expect (AeroKit, aerospace-swipe, the upstream cask CLI) |

And two features that have no upstream equivalent, written here:

- **`focus-follows-app-activation = 'always' \| 'smart'`** — `smart` stops apps that raise themselves
  from dragging you across workspaces, unless a click preceded the activation.
  ⚠️ `smart` currently has a [known regression](./CHANGELOG-FORK.md); the default `'always'` is the
  upstream behavior and is safe.

- **Native Settings window** — edit the same AeroSpace-edge config the app resolves at startup from
  the menu bar's **Settings…** item, without moving to a separate preference store
  ([docs](https://vitorebatista.github.io/AeroSpace-edge/settings/)). Fixed-choice options use
  native controls; keybindings, window rules and callbacks remain transparent TOML editors for the
  full command DSL. Save validates the complete candidate with AeroSpace's real parser before writing
  anything, preserves untouched regions of the file, then reloads the configuration. It also opens a
  raw recovery editor for an invalid config and refuses to guess when more than one candidate config
  exists, making routine changes safer without hiding the underlying config.

  ![AeroSpace-edge Settings window, showing the Gaps editor](./docs-md/assets/settings-window.jpg)

- **Shortcuts, Spotlight and Focus filters** — AeroSpace‑edge exposes its commands as native
  [App Intents](https://vitorebatista.github.io/AeroSpace-edge/guide/#shortcuts-spotlight-and-focus-filters).
  Drive workspaces from Shortcuts without shelling out, run a command straight from Spotlight, or
  attach a workspace to a macOS Focus so turning on **Work** puts you where you work. No other
  window manager in this category offers Focus filters — they're reachable only through App Intents,
  which a hotkey daemon has no way to register.

## How it compares

The honest version. Every one of these is good at something, and the right pick depends on what you
value — this table is about structural differences, not quality.

| | AeroSpace‑edge | AeroSpace | yabai | Amethyst | Rectangle | macOS built-in |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Tiling model** | tree | tree | BSP tree | preset layouts | manual snap | manual snap |
| **Layout persists** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Needs SIP disabled** | never | never | for parts | never | never | — |
| **Private APIs** | ❌ | ❌ | ✅ | ❌ | ❌ | — |
| **Workspaces** | emulated, unlimited | emulated, unlimited | native Spaces | native Spaces | none | native Spaces |
| **Config** | TOML file | TOML file | shell script | GUI | GUI | System Settings |
| **Built-in keybindings** | ✅ | ✅ | needs `skhd` | ✅ | ✅ | fixed set |
| **Scriptable CLI** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Shortcuts / Spotlight** | ✅ | ❌ | ❌ | ❌ | ❌ | — |
| **macOS Focus filters** | ✅ | ❌ | ❌ | ❌ | ❌ | — |
| **Native Settings UI** | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Ships upstream fixes early** | ✅ | — | — | — | — | — |
| **License** | MIT | MIT | MIT | MIT | MIT | closed |

**What the rows actually mean:**

- **SIP and private APIs.** yabai's best features need System Integrity Protection partially disabled
  and a scripting addition injected into Dock. That's a real security and stability tradeoff, and it
  breaks on macOS updates. AeroSpace‑edge works entirely through the public Accessibility API — nothing
  to disable, nothing to re-patch after an OS update.
- **Emulated workspaces.** Native macOS Spaces have a slow unskippable switch animation, a 16-Space
  cap, and no public API at all. Tools built on Spaces inherit every one of those limits. AeroSpace
  reimplements workspaces instead: instant, unlimited, assignable to monitors, scriptable.
- **Focus filters** are the row that has no workaround. They're only reachable through App Intents, so
  it isn't a feature the others haven't gotten around to — it's one their architecture can't reach.
- **Against upstream AeroSpace**, the tiling is the same tiling; that's the point. What differs is
  cadence and what's already fixed — plus native integrations written here.

**Pick something else if:** you want window opacity, borders and per-Space rules and don't mind
disabling SIP (yabai); you want tiling with zero configuration (Amethyst); or you only ever wanted to
throw a window to half the screen (Rectangle, or macOS itself — both are free and already installed).

*Snapshot as of v1.13. If a row is out of date, [open an issue](https://github.com/vitorebatista/AeroSpace-edge/issues)
— an inaccurate comparison table helps nobody.*

## Installs alongside anything else

AeroSpace‑edge is its own app — its own bundle id, name, icon, socket, CLI and Accessibility grant.
It doesn't overwrite an existing AeroSpace install, so you can run one, quit it, run the other, and
decide on evidence. Nothing is replaced, nothing is lost.

| | upstream AeroSpace | AeroSpace‑edge |
|---|---|---|
| App | `/Applications/AeroSpace.app` | `/Applications/AeroSpace-edge.app` |
| Spotlight | "AeroSpace" | "AeroSpace-edge" |
| Bundle id | `bobko.aerospace` | `vitorebatista.aerospace-edge` |
| CLI | `aerospace` | `aerospace-edge` |
| Socket | `/tmp/bobko.aerospace-$USER.sock` | `/tmp/vitorebatista.aerospace-edge-$USER.sock` |
| Config | `~/.aerospace.toml` | `~/.aerospace-edge.toml`, falling back to `~/.aerospace.toml` |

**It won't let you run two at once.** On startup, AeroSpace‑edge checks whether another AeroSpace is
already running and refuses to start if one is — two tiling window managers on the same keybindings
would fight over your windows. You get a dialog offering to quit the other one and continue, or to quit
AeroSpace‑edge and keep what you had. Nothing starts managing windows until that's resolved.

### Config: shared by default

With no `~/.aerospace-edge.toml`, AeroSpace‑edge reads your existing `~/.aerospace.toml` (or
`$XDG_CONFIG_HOME/aerospace/aerospace.toml`). That's deliberate — it's what makes a comparison fair:
same config, same keybindings, only the binary changes.

Create `~/.aerospace-edge.toml` (or `$XDG_CONFIG_HOME/aerospace-edge/aerospace-edge.toml`) when you want
options that only exist here. The fork's own config wins whenever it exists, and having both files is not
an error.

## Install

```bash
brew install --cask vitorebatista/tap/aerospace-edge
```

Or download the latest zip from [**Releases**](https://github.com/vitorebatista/AeroSpace-edge/releases/latest),
then:

```bash
unzip AeroSpace-edge-v1.10.zip
mv AeroSpace-edge-v*/AeroSpace-edge.app /Applications/
cp  AeroSpace-edge-v*/bin/aerospace-edge /usr/local/bin/   # or anywhere on your PATH
open -a /Applications/AeroSpace-edge.app
```

Both binaries are universal (arm64 + x86_64).

You only have to do this once: after that, **Check for Updates…** in the Settings window footer
(menu bar → **Settings…**) finds new releases, downloads them and installs them in place.

Pick one update channel and stay on it. If you installed with Homebrew, `brew upgrade --cask
aerospace-edge` keeps you current; using **Check for Updates…** on a Homebrew install leaves Homebrew
with a stale idea of the installed version until the next `brew upgrade` overwrites it.

### Granting Accessibility

On first install: **System Settings → Privacy & Security → Accessibility**, switch AeroSpace‑edge on
(add `/Applications/AeroSpace-edge.app` with **+** if the row isn't there), then launch it again. Until
you do, the app notices its permission is missing, clears its TCC entry and exits at launch — it looks
like a crash, it isn't. This is a separate entry from any other window manager's — granting it affects
nothing else.

Releases are signed with a stable identity, so **upgrades keep the grant** and you don't have to redo
this every time. (Releases up to and including v1.15 were signed ad-hoc, which did force a re-grant on
every upgrade; the first update past that asks once more, then stops.)

Confirm you're talking to the right server:

```bash
aerospace-edge --version   # client and server should report the same 1.x version
```

### Updating

Menu bar → **Settings…**, then **Check for Updates…** in the window footer (it's on every page of the
window). It finds the newest release, shows what changed, and on confirmation downloads it, verifies
it, replaces the app and the CLI in place, and relaunches.

Accessibility survives the update: releases are signed with a stable certificate, so macOS keeps the
grant when the app is replaced. If it does ask again — it will once, coming from an ad-hoc-signed
release up to v1.15 — re-grant it in System Settings → Privacy & Security → Accessibility.

The updater only accepts downloads from this repository's GitHub releases over HTTPS, and refuses to
install a payload whose bundle id or version doesn't match the release it claims to be.

### Uninstalling

```bash
brew uninstall --cask aerospace-edge   # if you installed it with Homebrew
```

```bash
rm -rf /Applications/AeroSpace-edge.app
rm -f  /usr/local/bin/aerospace-edge
rm -f  ~/.aerospace-edge.toml            # only if you made one
```

Any other install, its config and its Accessibility grant are untouched throughout.

## Documentation

The fork ships its own manual, with every backported flag and config key already folded in:

- **[vitorebatista.github.io/AeroSpace-edge](https://vitorebatista.github.io/AeroSpace-edge/)** —
  [Guide](https://vitorebatista.github.io/AeroSpace-edge/guide/) ·
  [Commands](https://vitorebatista.github.io/AeroSpace-edge/#commands) ·
  [Goodies](https://vitorebatista.github.io/AeroSpace-edge/goodies/)

Sources live under [`docs-md/`](./docs-md); the site is built with Material for MkDocs and published
by [`.github/workflows/docs.yml`](./.github/workflows/docs.yml). Release history is in
[`CHANGELOG-FORK.md`](./CHANGELOG-FORK.md).

Agents and LLM tooling can read
[`/llms.txt`](https://vitorebatista.github.io/AeroSpace-edge/llms.txt) for a machine-readable index.

## How it's kept current

Upstream is checked periodically. Each pass looks only at what's new since the last recorded sync
point, triages it, and backports what clears the bar:

- ✅ Bug fixes, crash fixes, window-detection fixes.
- ✅ Small, additive features — a new flag, a new config key, a new subscribe event.
- ❌ Large refactors, breaking config-syntax changes, anything that would conflict with the
  backports already carried.

Each backport gets its own branch and pull request, is adapted to this tree's conventions where it
differs from upstream, and has to pass `./script/build-debug.sh -Xswiftc -warnings-as-errors` **and**
`./script/swift-test.sh` before merging. Nothing lands untested, and nothing lands as a bulk merge.

The full state — sync point, everything already ported, everything deliberately skipped and why — is
in [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md).

## Contributions are genuinely welcome

This fork exists because someone wanted a fix sooner. If that's you, say so — the bar for "worth
carrying" is low, and requests shape what gets picked up next.

- **Spotted an upstream PR or commit you want early?** Open an issue with the number. That's the single
  most useful thing you can send, and it's usually a quick turnaround.
- **Found a bug?** Open an issue here — but first check whether it reproduces on an
  [upstream release](https://github.com/nikitabobko/AeroSpace/releases). If it does, it belongs
  upstream; that's where it gets fixed for everyone.
- **Want to send code?** PRs against `main` are welcome. One change per PR, keep the upstream
  attribution intact, and make sure the build and tests pass.
- **Ideas that don't exist upstream** are fair game too. `focus-follows-app-activation` started as one.

New ideas, better implementations, corrections to something here — all of it is open. Nothing about
this fork is settled.

## Building from source

```bash
./script/build-debug.sh -Xswiftc -warnings-as-errors   # warnings are errors
./script/swift-test.sh                                  # swift-testing suite
./script/test.sh                                        # everything CI runs
```

Setup details are in [`dev-docs/development.md`](./dev-docs/development.md); the layout of the codebase
is in [`dev-docs/architecture.md`](./dev-docs/architecture.md). Release builds in this fork use the lean
path documented in [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) — the upstream
release script needs docs tooling that isn't required here.

## macOS support

| | Ventura 13 | Sonoma 14 | Sequoia 15 | Tahoe 26 |
|---|:---:|:---:|:---:|:---:|
| Release binary runs | ✅ | ✅ | ✅ | ✅ |
| Build from source (debug or release, Xcode 26+) | — | — | ✅ | ✅ |
| Verified by CI on every commit | — | — | ✅ | ✅ |

Nothing above changes what the app supports — the deployment target is macOS 13. Building from
source is only guaranteed where CI builds: GitHub Actions never offered a macOS 13 runner, and it
[retired the macOS 14 one on 2026-11-02](https://github.com/actions/runner-images/issues/13518), so
macOS 15 is the minimum build host (as upstream).

## Credit

**AeroSpace is [@nikitabobko](https://github.com/nikitabobko)'s work**, along with everyone who has
contributed to it. Every backport here links the upstream pull request or commit it came from, because
that's where the engineering happened. This fork just refuses to wait for the tag.

If AeroSpace is useful to you, [sponsor the person who wrote it](https://github.com/sponsors/nikitabobko).

## License

MIT, unchanged from upstream — `Copyright (c) 2023 Nikita Bobko`. See [`LICENSE.txt`](./LICENSE.txt).

> **Not affiliated with, endorsed by, or supported by the upstream project.** These are unofficial
> builds. Don't report problems with them to upstream — bring them
> [here](https://github.com/vitorebatista/AeroSpace-edge/issues) instead.
