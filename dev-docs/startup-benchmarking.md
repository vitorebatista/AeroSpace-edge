# Startup benchmarking

Startup cost is dominated by Accessibility round-trips, and each one is a
synchronous IPC call into another process. Wall-clock numbers are therefore
specific to the machine, the config, the connected displays, and the set of
running applications. Compare two revisions on the same machine in the same
session, or don't compare at all.

There is no committed runner. An `xctrace --launch` recording of the app is not
usable as a startup benchmark: `--time-limit` kills the target, so the trace
duration is the time limit, not the launch. The two procedures below are what
actually produce attributable numbers.

## Preparation

1. Keep the usual display arrangement connected.
2. Use the same AeroSpace config and the same running-application workload for
   both revisions.
3. Build both revisions the same way:
   `./script/build-debug.sh -Xswiftc -warnings-as-errors`.
4. Never kill or quit an AeroSpace process you did not launch; stop only the
   debug PID you started.

## Phase attribution: signposts

The startup path emits `OSSignposter` intervals on the app's subsystem, under
Points of Interest:

| Interval | Emitted by |
| --- | --- |
| `startup.config` | `initAppBundle()` around config load |
| `startup.restorePersistedLayout` | `initAppBundle()` around layout restore |
| `runHeavyCompleteRefreshSession(...)` | every heavy refresh session, keyed on `#function` |
| `runLightSession(...)` | every light session, keyed on `#function` |

Record with Instruments' `os_signpost` / Points of Interest instrument against
a launch of `./.debug/AeroSpaceApp`, then read the interval durations. This is
the only measurement that attributes time to a specific startup phase, and it
is the right tool for judging a change to the refresh path.

Do not add a signpost around a call that already emits one — the two session
functions above cover their own bodies.

## End-to-end: readiness and early resource use

For a running debug executable: launch it in the background, poll
`./.debug/aerospace-edge list-monitors` every 100 ms until it succeeds, take
`ps -p <pid> -o %cpu=,rss=` immediately, then stop only that PID. Repeat seven
times per revision and report every sample, not just the median.

This measures how quickly the server accepts commands plus a single early
CPU/RSS sample. Two caveats, both load-bearing:

- Socket readiness happens well before window layout settles, so this number is
  blind to any change in the refresh path.
- An instantaneous `%cpu` reading at a poll boundary is noisy — the samples in
  `benchmarks/2026-08-30-startup-performance.md` span 24.6%–42.2% on an
  unchanged build. Do not read a few percent of movement as a result.

Report the machine model, macOS and Swift versions, display topology, the
config used, and the exact commands. Treat everything as a local measurement,
never as a universal performance claim.
