# Startup Performance — 2026-08-30

## Method

Points of Interest signposts, read back with:

```bash
log show --start "<launch time>" --signpost --style compact \
  --predicate 'subsystem == "vitorebatista.aerospace-edge.debug"'
```

The metric is the **initial `runHeavyCompleteRefreshSession`** interval — the startup
window-discovery pass, where all three changes on this branch act. Each sample is a
cold start: kill the debug app, wait 2 s, launch, wait 8 s, kill, read the log.

Machine: MacBook Pro, macOS 26.5.1, Swift 6.3.3. Three displays (built-in 1512×982,
DELL P2725QE 1920×1080, DELL P2317H 1080×1920). Same config and same running
applications throughout. Both revisions built with `xcodebuild -configuration Debug`
to the same output path so the Accessibility grant carried over unchanged.

Blocks were run alternating — branch, main, branch, main — with a rebuild between
each. `main` here is `33d3f769`.

## Results

| Block | Samples (ms) | Median |
| --- | --- | ---: |
| branch, unsettled | 137, 144, 189, 192, 412, 609, 4332 | 192 |
| main | 98, 152, 157, 161, 177, 187, 258 | 161 |
| branch, settled | 85, 104, 116, 149, 161, 174, 182 | **149** |
| main, settled | 103, 126, 154, 163, 179, 188, 209 | **163** |

Settled vs settled: **149 ms vs 163 ms**, roughly 8% / 14 ms faster. The two `main`
blocks agree closely (161, 163), so the baseline is stable. The branch and main
distributions overlap heavily: Mann-Whitney U on the settled branch block against all
14 `main` samples gives U=66, z≈1.27, **p≈0.2 — not significant at n=7**.

Other intervals were unchanged within noise: `startup.config` 6–10 ms,
`startup.restorePersistedLayout` 1–8 ms, the startup light session 6–10 ms, and the
follow-up heavy refresh 12–23 ms (branch) vs 14–22 ms (main).

## Discard the first block

The first branch block ran immediately after the displays were reconnected, while
macOS was still settling them. It contains a 4332 ms sample and two others above
400 ms, and its median (192 ms) is *worse* than `main`. Re-running the same build on
the settled system gave 149 ms.

Taken alone, that first block would have supported the opposite conclusion. Any
measurement here has to be repeated after the system is quiet, and blocks have to be
alternated — a single before/after pair proves nothing on this metric.

## Interpretation

The change removes work, and the measurement is consistent with that, but 14 ms on a
~200 ms startup is below what anyone will notice and below what n=7 can prove. This
branch should not be justified on speed.

An earlier revision of this branch reported -0.7% CPU / -0.1% RSS against a
readiness-poll baseline. That was noise — the CPU sample spans 24.6%–42.2% across
seven runs of an unchanged build — and it measured a metric that fires before window
layout starts, so it could not have observed the refresh path either way. Those
numbers have been removed rather than corrected.

## Notes for the next measurement

- The bottom-left hide corner is the one chosen on this three-display layout, and
  that path still issues a `getAxSize` read. The tiling-window change takes it from
  two AX round-trips to one there, not to zero as it does on a bottom-right corner.
- Repeated kill/relaunch cycles of the app degrade the macOS Accessibility subsystem:
  after ~30 cycles `_AXUIElementGetWindow` began failing for every window, for
  `main`, the branch, and the installed release build alike. Recovery is toggling the
  app's Accessibility permission, or logging out. Keep benchmark blocks short, and
  check that windows are still being discovered before trusting a number.
