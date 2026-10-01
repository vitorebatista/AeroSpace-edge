# Startup Performance Design

## Goal

Reduce the work AeroSpace does during a quit-and-relaunch on a three-display
macOS desktop, without changing window placement, the order in which windows are
bound into the tree, or the behavior of `after-startup-command`.

## Scope

The launch sequence and the work it causes immediately afterwards. Not in scope:
the command protocol, the configuration format, the pinned Swift toolchain, or
unrelated window-management behavior.

## Where the time goes

Startup cost is Accessibility round-trips. Each one is a synchronous IPC call
into another process, capped at `axMessagingTimeoutSeconds` (1.5 s), and the main
actor `await`s them one at a time. CPU and resident memory are close to
irrelevant next to how many of these calls happen and how many of them overlap.

At startup every window is new, so the discovery path pays in full:

- `refresh()` registers windows one at a time. Each new window costs an
  `getAxRect` and a `getAxUiElementWindowType`, plus a title read per matching
  `on-window-detected` callback. Every app already owns a dedicated AX thread,
  so those reads *could* overlap across apps; the serial `await` loop prevented
  it.
- `layoutWorkspaces()` parks the windows of every non-visible workspace in a
  corner. `hideInCorner` first calls `saveFloatingPositionIfNeeded`, which reads
  the window's rect over AX — for a tiling window, to compute a value that
  `unhideFromCorner` then discards unread, because tiling windows are put back by
  `layoutRecursive`.
- `getWindowLevel(for:)` re-enumerates the entire window list on every cache
  miss, and `CGWindowListCopyWindowInfo` is asked for on-screen windows only, so
  minimized windows, hidden apps and windows on other Spaces miss permanently —
  one full enumeration each, all of them returning nothing.

## Chosen design

1. **Split the discovery path into a concurrent read phase and a serial mutate
   phase.** `MacWindow.prefetchAxSnapshots` issues the two per-window AX reads
   for every not-yet-registered window at once; the existing registration loop
   then binds windows into the tree in exactly the same order as before, taking
   its data from the prefetched snapshots. Tree mutation and `on-window-detected`
   callbacks stay strictly serial and strictly ordered.
2. **Skip the rect read when parking a tiling window**, storing only the sentinel
   that marks it hidden — the same thing `preventNewWindowFlickerIfNeeded`
   already does. Floating windows keep the read; they are the ones that use the
   saved position.
3. **Enumerate the window-level cache at most once per refresh session**,
   invalidated at the top of both session entry points (deliberately not inside
   `refreshModel()`, which runs *after* `getNativeFocusedWindow()` has already
   registered the focused window).
4. **Signpost only what isn't already signposted.** `startup.config` and
   `startup.restorePersistedLayout`; the two refresh session functions emit their
   own intervals keyed on `#function`.

## Alternatives rejected

**Parallelize the registration loop itself.** Running `getOrRegister` for
different apps concurrently would interleave tree mutation and, worse, interleave
one window's `on-window-detected` command sequence with another window's binding.
Placement would become nondeterministic. The read/mutate split above gets the
same overlap without that exposure.

**Skip the follow-up refresh after the startup light session.** Tried and
reverted. `runLightSession` cancels whatever refresh is pending when it starts,
and during startup that is routinely a real one: `restorePersistedLayout()` awaits
for a long time, and every app that finishes launching in that window schedules a
refresh which the session then throws away. The trailing
`scheduleCancellableCompleteRefreshSession` is what re-runs it; without it those
windows stay unregistered until some later unrelated event. It also showed no
measurable benefit.

**Defer saved-layout restoration.** Would improve perceived startup by visibly
moving windows after the app appears. Worse relaunch experience.

## Correctness and safety constraints

- Swift 6.3 strict concurrency; app state stays main-actor owned.
- Window placement and binding order must be byte-for-byte what they were. Any
  concurrency added must be over reads only.
- Never make the startup socket accept commands before the first discovery phase
  completes.
- Instrumentation must not log window titles, configuration contents, or socket
  payloads.
- Benchmark artifacts stay untracked.

## Testing and verification

The debug build with `-Xswiftc -warnings-as-errors`, the full Swift suite, and
`lint.sh` must pass. None of these changes is unit-testable: all three are pure
Accessibility-API runtime behavior, and the test harness uses `TestWindow`, not
`MacWindow`. Per the repo checklist that is stated rather than papered over with
a test that restates the implementation.

Measurement is by Points of Interest signposts on the three-display machine —
see `dev-docs/startup-benchmarking.md`. Readiness/CPU/RSS sampling cannot see
this change: socket readiness happens before layout settles, and the CPU sample's
run-to-run spread on an unchanged build is larger than any plausible effect.

## Deliverables

- Implementation changes, individually committed.
- Benchmarking guidance describing the procedures that actually attribute time.
- A committed baseline record in `dev-docs/benchmarks/`.
