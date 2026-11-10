# Fork Changelog

This fork backports upstream pull requests that are already implemented in
[nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) but not yet merged into an
upstream release. The base for all of these backports is upstream `main` at commit `63e0976b`.

Each entry links the original upstream PR (where all credit belongs) and the corresponding fork
PR that backports it. This fork is not an official release and is not affiliated with or endorsed
by the upstream maintainer.

## Versioning

AeroSpace-edge versions itself independently of upstream, as `1.MINOR[.PATCH]`:

- **minor** — new behavior: upstream backports (the usual case) or a fork-original feature.
- **patch** — a fix, docs, or packaging change that adds no new behavior.
- **major** — reserved for a breaking change to config syntax or the CLI.

The upstream commit this fork is based on (`63e0976b`) is recorded here and in
[`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) rather than in the version string.

> **Renumbered 2026-08-27.** Releases 1 through 10 were originally published as
> `v0.20.3-Beta-fork.1` … `v0.20.3-Beta-fork.10` and have been retagged to `v1.1` … `v1.10`.
> The old tags are gone, so links to them no longer resolve. The build attached to each release
> older than 1.10 still reports its original `0.20.3-Beta-fork.N` version string internally —
> only 1.10 was rebuilt under the new scheme.

## Unreleased: upstream sync 2026-11-09

Backports opened as fork PRs #77–#94 from the upstream sync on 2026-11-09. They ship in the next
`1.MINOR` release once merged. The fork PRs describe each fork adaptation in detail.

Bug fixes:
- FL Studio windows were treated as popups ([#2338](https://github.com/nikitabobko/AeroSpace/pull/2338), fork #77).
- 1Password windows at the pop-up-menu level are no longer managed ([#2385](https://github.com/nikitabobko/AeroSpace/pull/2385), fork #78).
- Menu-bar style previews in Settings are kept visible on the macOS 27 SDK (upstream `0921fb81`, fork #79).
- A callback process that fails to start is now reported instead of crashing or being ignored silently ([#2343](https://github.com/nikitabobko/AeroSpace/pull/2343), fork #80).
- Workspace focus skips empty MRU children ([#2348](https://github.com/nikitabobko/AeroSpace/pull/2348), fork #81).
- `balance-sizes` resets the closed-windows cache ([#2310](https://github.com/nikitabobko/AeroSpace/pull/2310), fork #82).
- Apps that NSWorkspace reports with pid -1 are managed correctly ([#2316](https://github.com/nikitabobko/AeroSpace/pull/2316), fork #83).
- `focus dfs-next/prev` over floating windows: no tree changes in the middle of the command, and windows at equal positions no longer swap focus back and forth ([#2335](https://github.com/nikitabobko/AeroSpace/pull/2335), fork #84).
- A cancelled native focus job no longer raises its window ([#2299](https://github.com/nikitabobko/AeroSpace/pull/2299), fork #85).
- An unresponsive app is no longer treated as having no windows, and a timed-out window list never removes a live native tab ([#2326](https://github.com/nikitabobko/AeroSpace/pull/2326), fork #87).
- The hide corner is chosen from where the parked window body lands ([#2355](https://github.com/nikitabobko/AeroSpace/pull/2355), fork #88).
- The focused workspace stays visible after monitor changes ([#2358](https://github.com/nikitabobko/AeroSpace/pull/2358), fork #89).

Performance:
- `focus --window-id` no longer runs `makeFloatingWindowsSeenAsTiling` ([#2289](https://github.com/nikitabobko/AeroSpace/pull/2289), fork #86).
- AX frame writes are skipped when the window already has the target frame ([#2369](https://github.com/nikitabobko/AeroSpace/pull/2369), fork #90).
- Tray model updates are skipped when nothing changed ([#2359](https://github.com/nikitabobko/AeroSpace/pull/2359), fork #91).
- Native window state and floating window rects are queried concurrently (upstream `846f1a22`, fork #92).

Features:
- `exec` adds the Intel Homebrew prefix to its default PATH on Intel Macs ([#2284](https://github.com/nikitabobko/AeroSpace/pull/2284), fork #93).
- New flag: `layout --for-next-detected-window` (upstream `d080afe4`, fork #94).

## v1.16.2 (2026-08-31)

One user-facing fix, no new behavior. Fork-original, no backports.

- **`focus-follows-app-activation = 'smart'` no longer leaves the app's window drawn on the
  workspace you are on.** `smart` refuses the workspace switch when an app activates itself, but by
  the time AeroSpace's callback runs macOS has already ordered that app's window front — and
  `orderFront` constrains an offscreen frame back onto the screen, so the window parked in the hide
  corner became visible over the workspace you were actually using. Refusing the switch was only
  half the job: the suppression path re-focused the intended window and returned without a layout
  pass, so the stray window sat there until an unrelated refresh happened along. It now schedules a
  refresh session, which re-parks it. This is the **KNOWN ISSUE with `smart`** recorded under 1.7
  from the 2026-07-24 field report, and its recorded fix direction ("force-layout the offender's
  workspace after suppressing") is exactly what landed. (fork PR #74)
  - The `'always'` default is unchanged and stays deliberate. `smart` suppresses every
    cross-workspace activation without a recent click, including ones you asked for (`open -a` from
    a script, a clicked notification banner), so it remains opt-in.

## v1.16.1 (2026-08-31)

First patch release under the `1.MINOR[.PATCH]` scheme. One user-facing fix, one CI change, no
new behavior.

- **The workspace you left off on now survives an immediate quit.** 1.16 recorded the focused
  workspace inside the layout snapshot, which is written on a two-second debounce — so quitting
  right after switching workspaces, or crashing inside that window, lost the switch and brought
  you back on the previous workspace. It is now written the moment focus crosses a workspace
  boundary, and read back at launch before startup can overwrite it. Two narrower gaps close with
  it: a workspace reachable only through its binding can be restored on `config-version = 2`,
  where it is not a live object until first visited; and focus restore still runs when the layout
  file is missing or written by an older version, instead of being skipped along with the window
  replay.
- **CI no longer builds on the macos-14 runner.** GitHub began deprecating that image on
  2026-07-06, fails jobs on it during brownout windows through October, and retires it on
  2026-11-02. `build-debug` now runs on `macos-15` and `macos-26`, matching `build-release`.
  This drops a runner, not an OS: the deployment target is still macOS 13.

## v1.16 (2026-08-30)

**Updates no longer cost you the Accessibility grant.** Releases are signed with a stable
self-signed certificate instead of ad-hoc. An ad-hoc signature has no certificate, so its
designated requirement is the literal binary hash — it changes with every build, and macOS
treats each update as a different app and revokes the permission. The requirement is now
`identifier "vitorebatista.aerospace-edge" and certificate leaf = H"…"`, which is stable
across versions, so the grant survives an update.

> **This release still asks once.** Going from an ad-hoc-signed build to a signed one is
> itself an identity change. Grant Accessibility one more time after installing 1.16 — and
> not again after that. `tccutil reset Accessibility vitorebatista.aerospace-edge` clears
> the stale entry if the old one lingers.

**The menu-bar menu and the Settings window.** Fork-original; no upstream equivalent.

- **"New" now lists workspaces you have a binding for but have never visited.** `Workspace.all`
  only holds live workspaces, and on `config-version = 2` the persistent list is explicit rather
  than derived from bindings — so a workspace like `D`, reachable by `alt-d`, was missing from the
  menu until the first time you went there. With every live workspace in use the submenu vanished
  altogether.
- **The version line at the top of the menu is gone.** It is in Settings → Application → Version,
  where it can be copied.
- **A workspace restart lands you where you left off.** The persisted layout already restored every
  window and each monitor's visible workspace, but not focus, so a restart dropped you on whichever
  workspace sorted first. The focused workspace is now recorded with the layout and restored with it.
- **Raw TOML editors are syntax-highlighted** — comments, strings, numbers, booleans, table headers
  and keys, in VS Code's Light+/Dark+ palettes. The colouring is derived from the text, not from a
  parse, so a half-typed or invalid document still reads as TOML; Save remains the only validator.
- **"Check for Updates…" moved to the window footer**, reachable from every destination instead of
  buried in one.
- **Menu-bar appearance is its own destination**, and can now pin the item's position. macOS stores
  a status item's position per app and restores it at launch, so an item that once landed behind the
  notch — where a freshly installed app goes when the menu bar is full — stayed there, invisible and
  undraggable. Settings → Menu Bar → Position re-pins it at startup, warns when a value is wider than
  the display, and has a Relaunch to Apply button, since nothing can move a status item once it exists.
- **Application → Show Crash Reports** selects `~/Library/Logs/DiagnosticReports/AeroSpace-edge-*.ips`
  in Finder, so a crash file can be attached to a bug report.
- **Every destination links to its documentation page**, and controls that need a structure typed
  into them — key notation overrides, env vars, persistent workspaces, workspace-to-monitor
  assignment, per-monitor gaps, border colour — show concrete examples in the tooltip and the help
  popover. The three raw TOML panes show worked examples instead of a one-line description.

**Docs and tooling.** `script/create-codesign-certificate.sh` creates the signing certificate without
the Keychain Access clicks. `CLAUDE.md` gained a Settings window checklist and the menu-bar item
behavior that is easy to rediscover the hard way.

## v1.15 (2026-08-30)

**Settings is now the single application and configuration surface.** The menu-bar menu
has direct Enable/Disable, **Settings…**, and Quit actions instead of a nested Settings
submenu. A new Application destination contains config-file actions, menu-bar appearance,
update checking, and version information; these actions do not dirty the config draft.

- Changing a loaded effective-version-1 config to version 2 is now an explicit,
  transactional migration. AeroSpace-edge materializes the persistent workspace order
  that v1 derived from binding source order and monitor assignments, validates the complete
  candidate, and asks for confirmation before writing.
- A successful migration first creates a byte-identical
  `<filename>.backup-v1-YYYYMMDD-HHmmss` beside the resolved target. Backup collisions never
  overwrite an existing file, symlinks remain intact, permissions are preserved, failures
  leave or restore the original bytes, and Settings displays/reveals the exact backup path.
- The docs gained a **Settings section** with one page per destination in the window, in the
  same order as its sidebar, so "where do I change this?" has a one-line answer. Each option
  carries its TOML key, allowed values, parser fallback and when it takes effect, and the
  spatial ones (layout, orientation, gaps, accordion padding, border, normalization, focus
  follows app activation, new-window flicker, workspace-to-monitor priority) are explained
  with animated diagrams of the before/after. The section also covers the save pipeline,
  source-preservation boundaries, raw fragment validation,
  first-save/ambiguous/symlink/external-edit behavior, and migration recovery.

**Native macOS integration.** Four fork-original changes that use public macOS APIs the codebase
wasn't reaching for. No upstream equivalent for any of them.

- **App Intents: Shortcuts, Spotlight and Focus filters.** Commands are published as native App
  Intents — `Run Command` (any CLI command verbatim), `Focus Workspace`, and a `Switch Workspace`
  Focus filter that ties a workspace to a macOS Focus mode. Intents route through the same
  parse → execute path as the CLI and the socket server, so every existing and future command is
  exposed for free. `exec-and-forget` is rejected, as it already is over the socket. Documented in
  [the guide](./docs-md/guide.md#shortcuts-spotlight-and-focus-filters).
- **The layout now reacts to display changes.** Nothing was observing
  `NSApplication.didChangeScreenParametersNotification`, so plugging in a monitor, unplugging one,
  changing resolution or rearranging displays left the tree on the stale monitor arrangement until
  some unrelated event happened to trigger a refresh. The burst of notifications a reconfiguration
  emits is coalesced, so the layout runs once against the final arrangement.
- **A hung app can no longer stall the whole refresh.** Per-app Accessibility elements now set
  `AXUIElementSetMessagingTimeout`. Every AX read is a synchronous IPC round-trip into the target
  app; without a timeout, one wedged app (Electron mid-freeze, an IDE indexing) blocked the refresh
  and the window manager appeared hung. A slow app now loses one refresh cycle instead.
- **More reliable focus on macOS 14+.** `nativeFocus` used
  `activate(options: .activateIgnoringOtherApps)`, which macOS 14 both deprecated and increasingly
  ignores — a root cause of "the focus command did nothing". On macOS 14+ it now uses
  `activate(from:)`, which models activation as a transfer from the app currently holding focus and
  is honoured by the window server. Falls back to the old call, so macOS 13 is unchanged.

**Docs.** New [comparison page](./docs-md/comparison.md) and README matrix covering AeroSpace-edge
against upstream AeroSpace, yabai, Amethyst, Rectangle and the tiling built into macOS.

**The fork now calls itself `aerospace-edge` consistently.** The binary and app were already
named that, but the docs, the completion grammar and a few runtime strings still said
`aerospace` / `AeroSpace.app`. Command pages, examples and doc-site links now spell the CLI
`aerospace-edge`; `grammar/commands-bnf-grammar.txt` declared the wrong command name, so the
generated bash/fish/zsh completions were registered for `aerospace` rather than
`aerospace-edge`. Runtime strings updated too: the crash-report URL/title/filename, the
`enable on` and `enable-normalization` hints, the version-mismatch hint and the env-vars
message. The `~/.aerospace.toml` fallback tier is deliberately unchanged, so an existing
upstream config keeps working.

**Two crash fixes and window-placement memory.** Fork-original; no upstream equivalent.

- **Fixed: segfault during display reconfiguration.** `Monitor.activeWorkspace` retried
  `rearrangeWorkspacesOnMonitors()` by recursing into itself, but that only ever caches the
  monitors `NSScreen.screens` reports right now. A `Monitor` that list no longer contains — the
  ordinary case when you close the lid with external displays attached, or while every display is
  momentarily off and `screens` is empty — could never be found, so the retry ran until the stack
  guard was hit (`EXC_BAD_ACCESS` / `SIGSEGV`). It now falls back to a stub workspace and lets the
  next refresh settle the placement.
- **Fixed: Settings window crashed on open.** TOMLDecoder unpacks scalars through
  `source.utf8.withContiguousStorageIfAvailable { ... }!`, which returns nil — and therefore traps
  with `SIGTRAP` — for a String that isn't natively stored. Config read from disk is native, but
  text handed back by AppKit/SwiftUI is NSString-backed, so the Settings panes' own parse check
  could take the app down. `parseConfig` now normalizes its input with `makeContiguousUTF8()`.
- **Window placement survives a restart.** AeroSpace already froze the whole window tree in memory
  to recover from the lock screen; that snapshot is now also written to
  `~/Library/Application Support/AeroSpace-edge/window-layout.json`, debounced two seconds after
  any layout change, and replayed once at startup. Windows are matched back by WindowServer id,
  falling back to app bundle id + window title so placement still restores after a reboot or an
  app relaunch, when ids have changed. Unmatched windows are left where they land today.

## v1.14 (2026-08-28)

**Settings window.** AeroSpace-edge can now edit its own config from a GUI, reachable from
Settings → **Settings…** in the menu bar menu. It edits the same config file the fork
already resolves at startup (`~/.aerospace-edge.toml`, or the `XDG_CONFIG_HOME` equivalent)
in place, rather than being a separate config store. Fork-only; no upstream equivalent.

- **Save validates before it writes.** The rendered document is checked with the same
  parser AeroSpace uses at startup; if the result wouldn't load, nothing is written and the
  error is shown in the window instead.
- **Form controls for options with a fixed set of values,** covering general, layout, gaps,
  focus, window border, workspaces/monitors, key mapping, and exec settings.
- **Keybindings, window rules, and callbacks are edited as TOML text** in their own
  sections, since the AeroSpace command DSL isn't a fixed set of values — each pane gives
  advisory parse feedback as you type, with the caveat that it's checked as a fragment and
  Save validates the whole file.
- **Comments, key order, and unknown keys survive a save,** with one exception: the
  `gaps`, `key-mapping`, `exec`, and `workspace-to-monitor-force-assignment` tables —
  including their sub-tables (`[gaps.inner]`, `[key-mapping.key-notation-to-key-code]`,
  `[exec.env-vars]`, and similar) — are regenerated in full whenever a value in them
  changes, so comments written there don't survive.
- **Only what changed is written.** A key, a table, or a raw pane you didn't touch is left
  byte for byte as it was — a save is never a reformat of the whole file.
- **A first save with no custom config** creates `~/.aerospace-edge.toml`, seeded from the
  bundled default config the window opened on.
- **Degrades safely when it can't edit normally:** an unparseable config opens as a single
  raw editor over the whole file with the parse error shown (a save re-reads the file, so
  the form returns once it parses), and if several config files exist at once the window
  refuses to write anything rather than guess which one you meant.

## v1.13 (2026-08-28)

Menu-bar menu reorganised. With 35 configured workspaces and ~10 in use, the old menu listed all 35 at
the top level, so "Quit" and everything else sat below a 25-item wall of empty workspaces.

- **Only workspaces in use are listed.** Empty ones move into a **New** submenu. "In use" means has
  windows, is visible on a monitor, or is focused — a workspace you're looking at stays put even when
  empty, instead of vanishing into a submenu as its last window closes.
- **New "Settings" submenu** holds Enable/Disable, Open config, Reload config, Experimental UI Settings,
  and Check for Updates.
- **"Sponsor AeroSpace on GitHub" removed** from the menu. The sponsor link is still in the README —
  support for upstream belongs there, not in a menu the user opens dozens of times a day.
- **"Copy to clipboard" moved** out of the top level into Check for Updates → **Copy Version Info**,
  next to the version it copies.

Top level is now: version, workspaces in use, New, Settings, Quit.

## v1.12 (2026-08-27)

- **"Check for Updates…" in the menu bar.** Finds the newest release, shows what changed, and on
  confirmation downloads it, verifies it, replaces the app (and the CLI, where it's writable) in place,
  and relaunches. Fork-only; no upstream equivalent.
  - Versions compare component-wise and numerically, so 1.10 correctly sorts after 1.9 — a string
    comparison would have told every 1.10+ user to "update" back to 1.9 forever.
  - It reads the full release list rather than GitHub's `/releases/latest`, which skips prereleases:
    every AeroSpace-edge release is a prerelease, so that endpoint would report "no updates" forever.
  - Downloads are restricted to HTTPS on GitHub's own hosts, re-checked after redirects, and the
    unpacked payload is rejected unless its bundle id and version match the release it claims to be —
    the app is replacing its own bundle with this, so it's a trust boundary.
  - Because builds are ad-hoc signed, macOS revokes Accessibility whenever the app is replaced. The
    updater says so up front instead of leaving the user with an app that appears to quit on launch.
    A paid Apple Developer ID would remove that step.

## v1.11 (2026-08-27)

- **Refuses to start while another AeroSpace is running.** Two tiling window managers on the same
  keybindings fight over the same windows, so on startup AeroSpace-edge looks for a running upstream
  AeroSpace (`bobko.aerospace`, or its debug build) and blocks with a dialog: quit the other one and
  continue, or quit AeroSpace-edge and keep what's already running. It re-checks after quitting the
  other app, so a refused or slow quit re-prompts instead of starting anyway. The check runs before the
  Accessibility prompt — a window-manager conflict is the more useful thing to be told about — and is
  skipped under `--read-only`, which doesn't manage windows. Fork-only; no upstream equivalent.

## v1.10 (2026-08-27)

No upstream backports in this one. The fork becomes **its own app**, so it can be installed and tried
side by side with an upstream AeroSpace install instead of replacing it.

- App is now `AeroSpace-edge.app` (debug: `AeroSpace-edge-Debug.app`), bundle id
  `vitorebatista.aerospace-edge`, CLI `aerospace-edge`. Separate Spotlight entry, separate icon,
  separate Accessibility grant, separate `start-at-login` registration.
- Socket moves with the bundle id — `/tmp/vitorebatista.aerospace-edge-${USER}.sock`. Third-party
  socket clients pointed at the fork need this path; upstream's socket is untouched, so both servers
  can be installed at once (run one at a time — two window managers on the same keybindings fight).
- **Config falls back to upstream's.** With no `~/.aerospace-edge.toml` (or
  `${XDG_CONFIG_HOME}/aerospace-edge/aerospace-edge.toml`), the fork reads `~/.aerospace.toml` /
  `${XDG_CONFIG_HOME}/aerospace/aerospace.toml`, so a comparison runs on the very same config. Create
  the edge-specific file only for fork-only options that upstream would refuse to parse. The fork's own
  config wins when present; having both is not an "ambiguous config" error. Covered by `ConfigFileTest`.
- The legacy LaunchAgent cleanup is now scoped to the fork's own id — it will not delete a co-installed
  upstream AeroSpace's `bobko.aerospace.plist`.
- New logo and app icon; repo renamed to `vitorebatista/AeroSpace-edge`; README rewritten.
- Release zips are now `AeroSpace-edge-v<ver>.zip` and ship `legal/` (LICENSE + third-party licenses),
  which the 1.9 zip was missing.

Upgrading from 1.9 or earlier: the old `AeroSpace.app` and `aerospace` CLI are a *different app* to
macOS now. Delete them if you don't want both, and grant Accessibility to `AeroSpace-edge.app`.

## v1.9 (2026-08-27)

New backports since 1.8 (delta past upstream review point `d56e1637`; 2 new upstream-`main`
commits — both skipped, see below — and 17 new open upstream PRs triaged). Bug fixes only, plus one
tree-model fix; no new features.

- Fix iTerm2 Settings window detection — the Settings window has no fullscreen button, so the
  iTerm2 heuristic classified it as not-a-window; windows whose `AXIdentifier` is
  `mainPreferencesWindow` are now exempt from that check. Covered by a new `axDumps` fixture.
  (Upstream [nikitabobko/AeroSpace#2244](https://github.com/nikitabobko/AeroSpace/pull/2244); fork PR #55)
- Fix crash: cache `isUnitTest` instead of calling `NSClassFromString` on a hot path — the ObjC
  class lookup ran on every `mainMonitor` / `monitors` access and could crash with `EXC_BAD_ACCESS`
  inside dyld during display reconfiguration.
  (Upstream [nikitabobko/AeroSpace#2232](https://github.com/nikitabobko/AeroSpace/pull/2232); fork PR #56)
  - Fork adaptation: comment references the fork's `mainMonitor` / `monitors` (upstream has since
    renamed them to `mainMonitorInfo` / `monitorInfos`).
- `balance-sizes`: preserve the container's total weight instead of resetting every child to the
  constant `1`. A `resize` later in the same binding's command list no longer works against a total
  that doesn't match the monitor, so windows stop jumping.
  (Upstream [nikitabobko/AeroSpace#2211](https://github.com/nikitabobko/AeroSpace/pull/2211),
  upstream issue [#1837](https://github.com/nikitabobko/AeroSpace/issues/1837); fork PR #57)
  - Fork adaptation: tests rewritten against the fork's test API (direct command construction
    instead of upstream's `parseCommand` helper).
- `FocusCommand`: fix the `is already unbound` crash when two `focus` commands race —
  `makeFloatingWindowsSeenAsTiling` awaits `getCenter()` twice, and a concurrent `focus` could
  unbind the window in between. Both suspension points now re-validate the window.
  (Upstream [nikitabobko/AeroSpace#2228](https://github.com/nikitabobko/AeroSpace/pull/2228),
  upstream issue [#1311](https://github.com/nikitabobko/AeroSpace/issues/1311); fork PR #58)
  - Fork adaptations: floating windows are direct children of `Workspace` here (upstream's
    `floatingWindowsContainer` refactor isn't ported), so the guard is `window.parent === workspace`;
    tests use `Task { @MainActor in }` instead of upstream's `Task.startUnstructured`.
- Insert replaced native-tab windows into their old tree slot — apps that fold native tabs into one
  titlebar (Finder, Ghostty, Fork) keep the old tab's AX object alive but drop it from `AXWindows`,
  so switching tabs left a phantom tile and re-placed the visible tab via `on-window-detected`/MRU.
  The stale window is now retired and the replacement spliced into the exact slot (parent, index,
  weight, floating size, fullscreen state, cached geometry).
  (Upstream [nikitabobko/AeroSpace#2225](https://github.com/nikitabobko/AeroSpace/pull/2225); fork PR #59)
  - Fork adaptations: the fork's `getFocusedWindow()` / `runInLoop` take no `CancellationMode` and
    guard on `threadGuardedOrNil` (AX-destroy-race hardening, fork PR #43), so the new logic sits
    inside those guards and uses the unwrapped `axApp`.

Notable skips this cycle: upstream PRs #2238 / #2245 patch `mouse/focusFollowsMouse.swift`, which
this fork never ported; #2220 is a duplicate of #2024, already in the fork; #2213 removes
`lastNativeFocusedWindowId`, which the #2225 backport above depends on. Six feature PRs
(#2207, #2217, #2229, #2240, #2241, #2242) were deferred — this fork's bar is bug fixes plus small
safe features, and none were requested.

## v1.8 (2026-07-24)

- Socket protocol versions handshake — the server now answers the 4-byte protocol-version
  handshake modern upstream clients perform on connect, instead of deadlocking on it. Fixes
  third-party socket clients (AeroKit, aerospace-swipe, the upstream Homebrew-cask CLI)
  hanging or degrading to CLI shelling against the fork server. Also ports the guide's new
  "Socket protocol" documentation section.
  (Backports upstream commit [`8413641c`](https://github.com/nikitabobko/AeroSpace/commit/8413641c),
  upstream issue [#1513](https://github.com/nikitabobko/AeroSpace/issues/1513); fork PR #54)
  - Fork adaptations: upstream's `getIgnoringErrorsOrNil()` → the fork's `Result.getOrNil()`;
    upstream's `EvalCommandTest` tweak dropped (eval command family not ported).

## v1.7 (2026-07-24)

- New fork feature: `focus-follows-app-activation = 'always'|'smart'` config option — `smart`
  suppresses cross-workspace workspace switches caused by apps activating themselves (focus
  stealing) unless the activation was preceded by a mouse click. No upstream equivalent;
  i3 precedent: `focus_on_window_activation`. (fork PR #53)
- **KNOWN ISSUE with `smart` (field report 2026-07-24) — FIXED 2026-08-31:** windows belonging
  to another workspace could reappear on the current one. Cause: macOS orders the activating
  app's window front before AeroSpace's callback runs, and `orderFront` constrains an offscreen
  frame back onto the screen — so the window parked in the hide corner became visible. `smart`
  refused the workspace switch but never relayouted, so the stray window sat there until an
  unrelated refresh. The suppression path now schedules a refresh session, which re-parks it.
  The `'always'` default is unchanged and stays deliberate: `smart` suppresses every
  cross-workspace activation without a recent click, including ones you asked for (`open -a`
  from a script, a clicked notification banner), so it remains opt-in.

## v1.6 (2026-07-18)

New backports since 1.5 (delta past upstream review point `d56e1637`; no new upstream-`main` commits, three new open PRs triaged):

- Add `debug-windows --app-bundle-id <id>` to dump unregistered AX windows — upstream [nikitabobko/AeroSpace#2184](https://github.com/nikitabobko/AeroSpace/pull/2184) (fork PR #51)
- Add `enable-normalization` command for per-workspace normalization overrides — upstream [nikitabobko/AeroSpace#2190](https://github.com/nikitabobko/AeroSpace/pull/2190) (fork PR #52)
- Add AeroKit to the trackpad-gestures goodies list (docs) — upstream [nikitabobko/AeroSpace#2188](https://github.com/nikitabobko/AeroSpace/pull/2188) (fork PR #50)

## v1.5 (2026-07-14)

New backports since 1.4 (delta past upstream review point `649301b2`):

- Fix wisprFlow popup detection — upstream commits [`4a3aab24`](https://github.com/nikitabobko/AeroSpace/commit/4a3aab24) + [`d56e1637`](https://github.com/nikitabobko/AeroSpace/commit/d56e1637) (fork PR #46)
- Ignore windows with `kCGNullWindowID` window-id — upstream commit [`0f6b2e78`](https://github.com/nikitabobko/AeroSpace/commit/0f6b2e78) (fork PR #47)
- Add `window-closed` subscribe event — upstream [nikitabobko/AeroSpace#2181](https://github.com/nikitabobko/AeroSpace/pull/2181) (fork PR #48)
- Fix Device Hub (Xcode 27) compact-view flicker when tiled — upstream [nikitabobko/AeroSpace#2167](https://github.com/nikitabobko/AeroSpace/pull/2167) (fork PR #49)

## v1.4 (2026-07-10)

New backports since 1.3 (delta past upstream review point `fb8b1df6`):

- Fix menu-bar clicks stealing focus when "Displays have separate spaces" is off — upstream commit [`cfd4eab2`](https://github.com/nikitabobko/AeroSpace/commit/cfd4eab2) (fork PR #39)
- Add `window-moved-to-workspace` subscribe event — upstream [nikitabobko/AeroSpace#2162](https://github.com/nikitabobko/AeroSpace/pull/2162) (fork PR #40)
- FocusCommand: don't insert floating windows between accordion children — upstream commit [`8c3efca2`](https://github.com/nikitabobko/AeroSpace/commit/8c3efca2) (fork PR #41)
- Fix floating windows nudged off right/bottom edges on workspace unhide — upstream commit [`649301b2`](https://github.com/nikitabobko/AeroSpace/commit/649301b2) (fork PR #42)
- MacApp: fix AX-object destroy race + wipPids spin in `getOrRegister` — upstream commits [`dd6b927a`](https://github.com/nikitabobko/AeroSpace/commit/dd6b927a) + [`1e6ce27e`](https://github.com/nikitabobko/AeroSpace/commit/1e6ce27e) (fork PR #43)
- Fix cross-workspace focus races — upstream [nikitabobko/AeroSpace#2165](https://github.com/nikitabobko/AeroSpace/pull/2165) (fork PR #44)

## v1.3 (2026-06-29)

New backports since 1.2 (delta past upstream review point `a60f9630`):

- Fix Codex window classification (pet window → popup) — upstream commits [`82c4a405`](https://github.com/nikitabobko/AeroSpace/commit/82c4a405) + [`cb347265`](https://github.com/nikitabobko/AeroSpace/commit/cb347265) (fork PR #33)
- Fix `workspace next/prev` when current workspace isn't in the `--stdin` list — upstream commit [`6a2a126d`](https://github.com/nikitabobko/AeroSpace/commit/6a2a126d) (fork PR #34)
- Fix self-conflicting focus env vars in `exec-on-workspace-change` callback — upstream commit [`dd61a340`](https://github.com/nikitabobko/AeroSpace/commit/dd61a340) (fork PR #35)
- Document `AEROSPACE_WINDOW_ID` / `AEROSPACE_WORKSPACE` env variables — upstream commit [`3e381925`](https://github.com/nikitabobko/AeroSpace/commit/3e381925) (fork PR #36)
- Add binary-tree (BSP) normalization (`enable-normalization-binary-tree`) — upstream [nikitabobko/AeroSpace#2135](https://github.com/nikitabobko/AeroSpace/pull/2135) (fork PR #37)

## v1.2 (2026-06-12)

Backported since 1.1 — 3 newly-merged upstream `main` bug-fix commits + 3 feature PRs:

- Fix MRU bug after `swap` command — upstream commit [`19b5999d`](https://github.com/nikitabobko/AeroSpace/commit/19b5999d) (fork PR #25)
- Fix deadlock in `dieT`/`die` functions — upstream commit [`8b236f1b`](https://github.com/nikitabobko/AeroSpace/commit/8b236f1b) (fork PR #26)
- parseConfig: don't silently swallow `String.init` exceptions — upstream commit [`a0f17f88`](https://github.com/nikitabobko/AeroSpace/commit/a0f17f88) (fork PR #27)
- `new-window-prevent-flicker` config option — upstream [nikitabobko/AeroSpace#2109](https://github.com/nikitabobko/AeroSpace/pull/2109) (fork PR #28)
- `workspace-layout-changed` subscribe event — upstream [nikitabobko/AeroSpace#2116](https://github.com/nikitabobko/AeroSpace/pull/2116) (fork PR #29)
- Native focused-window border — upstream [nikitabobko/AeroSpace#2107](https://github.com/nikitabobko/AeroSpace/pull/2107) (fork PR #30)

## v1.1 (initial — 22 backports)

## Crash & stability

- Fix `ThreadGuardedValue` crash — upstream [nikitabobko/AeroSpace#2012](https://github.com/nikitabobko/AeroSpace/pull/2012) (fork PR #3)
- Normalize the tree after `flatten-workspace-tree` — upstream [nikitabobko/AeroSpace#1953](https://github.com/nikitabobko/AeroSpace/pull/1953) (fork PR #9)

## Window detection / popups

- Detect Outlook popups correctly — upstream [nikitabobko/AeroSpace#2103](https://github.com/nikitabobko/AeroSpace/pull/2103) (fork PR #1)
- Treat Emacs popups as floating — upstream [nikitabobko/AeroSpace#2081](https://github.com/nikitabobko/AeroSpace/pull/2081) (fork PR #2)
- Re-float windows correctly after screen wake — upstream [nikitabobko/AeroSpace#2098](https://github.com/nikitabobko/AeroSpace/pull/2098) (fork PR #5)

## Rendering / display

- Fix tiling flash on window creation — upstream [nikitabobko/AeroSpace#2024](https://github.com/nikitabobko/AeroSpace/pull/2024) (fork PR #4)
- Fix GTK3 black window redraw — upstream [nikitabobko/AeroSpace#2052](https://github.com/nikitabobko/AeroSpace/pull/2052) (fork PR #6)

## UI / menu bar

- Sort workspaces consistently in the menu bar UI — upstream [nikitabobko/AeroSpace#1926](https://github.com/nikitabobko/AeroSpace/pull/1926) (fork PR #8)

## CLI commands & flags

- `move-workspace-to-monitor` improvements — upstream [nikitabobko/AeroSpace#1944](https://github.com/nikitabobko/AeroSpace/pull/1944) (fork PR #7)
- Better stdin error message — upstream [nikitabobko/AeroSpace#1529](https://github.com/nikitabobko/AeroSpace/pull/1529) (fork PR #10)
- Add `create-implicit-container-or-fail` — upstream [nikitabobko/AeroSpace#2097](https://github.com/nikitabobko/AeroSpace/pull/2097) (fork PR #11)
- Support `layout --root` — upstream [nikitabobko/AeroSpace#2080](https://github.com/nikitabobko/AeroSpace/pull/2080) (fork PR #12)
- Allow resizing floating windows — upstream [nikitabobko/AeroSpace#1156](https://github.com/nikitabobko/AeroSpace/pull/1156) (fork PR #13)
- Add `list-windows --sort` — upstream [nikitabobko/AeroSpace#1932](https://github.com/nikitabobko/AeroSpace/pull/1932) (fork PR #18)
- Support `layout sticky` — upstream [nikitabobko/AeroSpace#2083](https://github.com/nikitabobko/AeroSpace/pull/2083) (fork PR #21)
- Add `summon-workspace --when-visible` — upstream [nikitabobko/AeroSpace#1349](https://github.com/nikitabobko/AeroSpace/pull/1349) (fork PR #22)

## on-window-detected matchers

- Substring matching for `app-id-regex` — upstream [nikitabobko/AeroSpace#2082](https://github.com/nikitabobko/AeroSpace/pull/2082) (fork PR #14)
- Allow an array of `app-id` matchers — upstream [nikitabobko/AeroSpace#1665](https://github.com/nikitabobko/AeroSpace/pull/1665) (fork PR #15)

## Format variables

- Add `%{all}` format variable — upstream [nikitabobko/AeroSpace#1708](https://github.com/nikitabobko/AeroSpace/pull/1708) (fork PR #16)
- Add orientation format variables — upstream [nikitabobko/AeroSpace#1778](https://github.com/nikitabobko/AeroSpace/pull/1778) (fork PR #17)

## Performance

- Throttle app registration — upstream [nikitabobko/AeroSpace#2085](https://github.com/nikitabobko/AeroSpace/pull/2085) (fork PR #19)

## Documentation

- Add KeePassXC docs note — upstream [nikitabobko/AeroSpace#1344](https://github.com/nikitabobko/AeroSpace/pull/1344) (fork PR #20)

## Versioning

This fork does not publish official releases. To build your own fork release with a clearly marked
version string, see [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md).
