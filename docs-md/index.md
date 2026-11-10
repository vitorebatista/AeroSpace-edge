---
title: Home
description: AeroSpace, with upstream's fixes already in — an i3-like tiling window manager for macOS
hide:
  - toc
  - navigation
---

<div class="edge-hero" markdown>
![AeroSpace-edge](assets/edge-logo.svg){ .off-glb }
<div markdown>
# AeroSpace-edge

**AeroSpace, with upstream's fixes already in.** An i3-like tiling window manager for
macOS — no SIP disabling, no private APIs, no window animations to wait on.
</div>
</div>

<div class="edge-cta" markdown>
[Install](#install){ .md-button .md-button--primary }
[Read the Guide](guide.md){ .md-button }
[Browse commands](#commands){ .md-button }
</div>

---

## Why it exists

The fix you need is usually written before you hit the bug. It sits in a merged commit or an
open pull request while the release it belongs to takes months to land.

AeroSpace-edge closes that gap. Upstream's work gets picked up, adapted, tested and shipped in
weeks rather than release cycles. Same tree model, same config file, same commands — if you've
used AeroSpace you already know how to use this. What differs is the release cadence and what's
already fixed.

<div class="edge-badges" markdown>

[![latest release](https://img.shields.io/github/v/release/vitorebatista/AeroSpace-edge?include_prereleases&label=release&color=6366F1&style=for-the-badge)](https://github.com/vitorebatista/AeroSpace-edge/releases/latest)
[![backported pull requests](https://img.shields.io/github/issues-search?query=repo%3Avitorebatista%2FAeroSpace-edge%20is%3Apr%20is%3Amerged&label=merged%20PRs&color=22D3EE&style=for-the-badge)](https://github.com/vitorebatista/AeroSpace-edge/pulls?q=is%3Apr+is%3Amerged)
[![last commit](https://img.shields.io/github/last-commit/vitorebatista/AeroSpace-edge?label=last%20commit&color=A855F7&style=for-the-badge)](https://github.com/vitorebatista/AeroSpace-edge/commits/main)
[![license](https://img.shields.io/badge/license-MIT-64748B?style=for-the-badge)](https://github.com/vitorebatista/AeroSpace-edge/blob/main/LICENSE.txt)

</div>

Versions are `1.MINOR[.PATCH]`, numbered independently of upstream — minor for new behavior,
patch for fixes and packaging. Every backport is traceable to its upstream PR in the
[fork changelog](https://github.com/vitorebatista/AeroSpace-edge/blob/main/CHANGELOG-FORK.md).

## What you get

<div class="edge-features" markdown>

<div markdown>
### Tree-based tiling
Windows live in a tree of horizontal and vertical containers, plus accordion layouts for
narrow screens. Split, join, swap and resize any node — not just leaves.
[Read about the tree →](guide.md#tree)
</div>

<div markdown>
### Real keyboard control
Every action is bindable. Binding modes give you i3-style layers, so one chord opens a whole
sub-language of resize or move keys instead of eating a modifier.
[Binding modes →](guide.md#binding-modes)
</div>

<div markdown>
### Workspaces that aren't Spaces
AeroSpace emulates its own workspaces instead of driving macOS Spaces, so switching is instant
and scriptable — no animation, no Mission Control, no AppleScript hacks.
[Emulation of virtual workspaces →](guide.md#emulation-of-virtual-workspaces)
</div>

<div markdown>
### A CLI you can script
`aerospace-edge` talks to the running app over a UNIX socket. Query state as JSON, pipe
commands together, subscribe to events, and drive it all from your status bar.
[Command reference →](#commands)
</div>

<div markdown>
### Plain-text config
One TOML file, comments and all. No hidden state — diff it, version it, share it. The
Settings window edits that same file in place and keeps your comments.
[Settings →](settings/index.md) · [Default config →](guide.md#default-config)
</div>

<div markdown>
### Shortcuts, Spotlight and Focus
Commands are exposed as native App Intents. Drive workspaces from Shortcuts, run a command from
Spotlight, or attach a workspace to a macOS Focus mode.
[App Intents →](guide.md#shortcuts-spotlight-and-focus-filters)
</div>

<div markdown>
### Installs next to anything
Own bundle id, app name, socket, CLI and Accessibility grant. It never overwrites an existing
AeroSpace, and it reads your existing `~/.aerospace.toml` so a side-by-side comparison is fair.
</div>

</div>

Wondering how this stacks up against yabai, Amethyst or the tiling built into macOS?
[Read the comparison →](comparison.md)

## What's already fixed here

Grab a release if any of these have bitten you.

| | |
|---|---|
| **Crashes** | `is already unbound` when two `focus` commands race · `EXC_BAD_ACCESS` during display reconfiguration · `ThreadGuardedValue` crash · `die`/`dieT` deadlock |
| **Windows in the wrong place** | native tabs (Finder, Ghostty, Fork) leaving phantom tiles · windows flashing tiled before a floating rule applies · floating windows misplaced after screen wake · Emacs / Outlook / Codex / iTerm2 Settings popups mis-detected |
| **Layout math** | [`balance-sizes`](commands/balance-sizes.md) throwing away container weights, so a later [`resize`](commands/resize.md) made windows jump |
| **CLI** | [`layout sticky`](commands/layout.md) · [`list-windows --sort`](commands/list-windows.md) · [per-workspace `enable-normalization`](commands/enable-normalization.md) · [`summon-workspace --when-visible`](commands/summon-workspace.md) · [`debug-windows --app-bundle-id`](commands/debug-windows.md) · resizable floating windows |
| **Integrations** | the socket protocol handshake modern clients expect (AeroKit, aerospace-swipe, the upstream cask CLI) |

And one option with no upstream equivalent, written here:

`focus-follows-app-activation = 'always' | 'smart'`

:   `smart` stops apps that raise themselves from dragging you across workspaces, unless a
    click preceded the activation.

    !!! warning

        `smart` currently has a known regression — see the
        [fork changelog](https://github.com/vitorebatista/AeroSpace-edge/blob/main/CHANGELOG-FORK.md).
        The default `'always'` is the upstream behavior and is safe.

## How it stays trustworthy while moving fast

- **Every change is its own reviewed pull request** — never a bulk merge.
- **Nothing lands untested.** `script/build-debug.sh -Xswiftc -warnings-as-errors` and `script/swift-test.sh`
  both pass before a branch merges.
- **Refactors and breaking config changes stay out.** Moving fast on fixes and slow on churn is
  what keeps a fork from rotting.
- **Every backport is traceable** to the upstream PR it came from, where the credit belongs.

## Install

```shell
brew install --cask vitorebatista/tap/aerospace-edge
```

Or download the latest zip from
[**Releases**](https://github.com/vitorebatista/AeroSpace-edge/releases/latest), then:

```shell
unzip AeroSpace-edge-v*.zip
mv AeroSpace-edge-v*/AeroSpace-edge.app /Applications/
cp  AeroSpace-edge-v*/bin/aerospace-edge /usr/local/bin/   # or anywhere on your PATH
open -a /Applications/AeroSpace-edge.app
```

Both binaries are universal (arm64 + x86_64). You only do this once — after that,
**Check for Updates…** in the Settings window footer finds, downloads and installs new
releases in place.

!!! warning "Grant Accessibility after installing"

    Until you do, the app notices its permission is missing, clears its TCC entry, and exits
    at launch. **It looks like a crash. It isn't.**

    After installing: **System Settings → Privacy & Security → Accessibility**, switch
    AeroSpace-edge on (add `/Applications/AeroSpace-edge.app` with **+** if the row isn't
    there), then launch it again. This is a separate entry from any other window manager's —
    granting it affects nothing else.

    Releases are signed with a stable identity, so upgrades keep the grant. (Releases up to
    v1.15 were ad-hoc signed and did force a re-grant every time; the first update past that
    asks once more, then stops.)

Confirm you're talking to the right server:

```shell
aerospace-edge --version   # client and server should report the same 1.x version
```

## Commands

<div class="edge-cards" markdown>

[<code>aerospace-edge balance-sizes</code><span>Balance sizes of all windows in the current workspace</span>](commands/balance-sizes.md)

[<code>aerospace-edge close-all-windows-but-current</code><span>On the focused workspace, close all windows but current</span>](commands/close-all-windows-but-current.md)

[<code>aerospace-edge close</code><span>Close the focused window</span>](commands/close.md)

[<code>aerospace-edge config</code><span>Query AeroSpace config options</span>](commands/config.md)

[<code>aerospace-edge debug-windows</code><span>Interactive command to record Accessibility API debug information to create bug reports</span>](commands/debug-windows.md)

[<code>aerospace-edge echo</code><span>Print arguments and interpolation variables to stdout</span>](commands/echo.md)

[<code>aerospace-edge enable-normalization</code><span>Set or clear a per-workspace override for a refresh-time normalization</span>](commands/enable-normalization.md)

[<code>aerospace-edge enable</code><span>Temporarily disable window management</span>](commands/enable.md)

[<code>aerospace-edge eval</code><span>Send multiple commands to AeroSpace at once</span>](commands/eval.md)

[<code>aerospace-edge exec-and-forget</code><span>Run /bin/bash -c '&lt;bash-script&gt;'</span>](commands/exec-and-forget.md)

[<code>aerospace-edge false</code><span>Return false value</span>](commands/false.md)

[<code>aerospace-edge flatten-workspace-tree</code><span>Flatten the tree of the focused workspace</span>](commands/flatten-workspace-tree.md)

[<code>aerospace-edge focus-back-and-forth</code><span>Switch between the current and previously focused elements back and forth</span>](commands/focus-back-and-forth.md)

[<code>aerospace-edge focus-monitor</code><span>Focus monitor by relative direction, by order, or by pattern</span>](commands/focus-monitor.md)

[<code>aerospace-edge focus</code><span>Set focus to a window</span>](commands/focus.md)

[<code>aerospace-edge fullscreen</code><span>Toggle the fullscreen mode for the focused window</span>](commands/fullscreen.md)

[<code>aerospace-edge join-with</code><span>Put the focused window and the nearest node in the specified direction under a common parent container</span>](commands/join-with.md)

[<code>aerospace-edge layout</code><span>Change layout of the focused node to the given layout</span>](commands/layout.md)

[<code>aerospace-edge list-apps</code><span>Print the list of running applications that appears in the Dock and may have a user interface</span>](commands/list-apps.md)

[<code>aerospace-edge list-exec-env-vars</code><span>List environment variables that exec-* commands and callbacks are run with</span>](commands/list-exec-env-vars.md)

[<code>aerospace-edge list-modes</code><span>Print a list of modes currently specified in the configuration</span>](commands/list-modes.md)

[<code>aerospace-edge list-monitors</code><span>Print monitors that satisfy conditions</span>](commands/list-monitors.md)

[<code>aerospace-edge list-windows</code><span>Print windows that satisfy conditions</span>](commands/list-windows.md)

[<code>aerospace-edge list-workspaces</code><span>Print workspaces that satisfy conditions</span>](commands/list-workspaces.md)

[<code>aerospace-edge macos-native-fullscreen</code><span>Toggle macOS fullscreen for the focused window</span>](commands/macos-native-fullscreen.md)

[<code>aerospace-edge macos-native-minimize</code><span>Minimize focused window</span>](commands/macos-native-minimize.md)

[<code>aerospace-edge mode</code><span>Activate the specified binding mode</span>](commands/mode.md)

[<code>aerospace-edge move-mouse</code><span>Move mouse to the requested position</span>](commands/move-mouse.md)

[<code>aerospace-edge move-node-to-monitor</code><span>Move window to monitor targeted by relative direction, by order, or by pattern</span>](commands/move-node-to-monitor.md)

[<code>aerospace-edge move-node-to-workspace</code><span>Move the focused window to the specified workspace</span>](commands/move-node-to-workspace.md)

[<code>aerospace-edge move-workspace-to-monitor</code><span>Move workspace to monitor targeted by relative direction, by order, or by pattern</span>](commands/move-workspace-to-monitor.md)

[<code>aerospace-edge move</code><span>Move the focused window in the given direction</span>](commands/move.md)

[<code>aerospace-edge reload-config</code><span>Reload currently active config</span>](commands/reload-config.md)

[<code>aerospace-edge resize</code><span>Resize the focused window</span>](commands/resize.md)

[<code>aerospace-edge run-callback</code><span>Run AeroSpace config callbacks on demand</span>](commands/run-callback.md)

[<code>aerospace-edge split</code><span>Split focused window</span>](commands/split.md)

[<code>aerospace-edge subscribe</code><span>Subscribe to AeroSpace events and receive notifications via socket</span>](commands/subscribe.md)

[<code>aerospace-edge summon-workspace</code><span>Move the requested workspace to the focused monitor</span>](commands/summon-workspace.md)

[<code>aerospace-edge swap</code><span>Swaps the focused window with another window</span>](commands/swap.md)

[<code>aerospace-edge test-not</code><span>Negative condition evaluation utility</span>](commands/test-not.md)

[<code>aerospace-edge test</code><span>Condition evaluation utility</span>](commands/test.md)

[<code>aerospace-edge trigger-binding</code><span>Trigger AeroSpace binding as if it was pressed by user</span>](commands/trigger-binding.md)

[<code>aerospace-edge true</code><span>Return true value</span>](commands/true.md)

[<code>aerospace-edge volume</code><span>Manipulate volume</span>](commands/volume.md)

[<code>aerospace-edge workspace-back-and-forth</code><span>Switch between the focused workspace and previously focused workspace back and forth</span>](commands/workspace-back-and-forth.md)

[<code>aerospace-edge workspace</code><span>Focus the specified workspace</span>](commands/workspace.md)

</div>

---

Built on [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) at commit
[`63e0976b`](https://github.com/nikitabobko/AeroSpace/commit/63e0976b), MIT licensed,
Copyright (c) 2023 Nikita Bobko. This fork is not affiliated with or endorsed by the upstream
maintainer — all credit for the backported work belongs upstream.
