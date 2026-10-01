# Startup Performance — Plan

Design record: [`../specs/2026-08-30-startup-performance-design.md`](../specs/2026-08-30-startup-performance-design.md).
Measurement procedures: [`dev-docs/startup-benchmarking.md`](../../../dev-docs/startup-benchmarking.md).
Baseline numbers: [`dev-docs/benchmarks/2026-08-30-startup-performance.md`](../../../dev-docs/benchmarks/2026-08-30-startup-performance.md).

## Done

- [x] Profile the launch sequence and identify the cost as Accessibility
      round-trips serialized on the main actor, not CPU or allocation.
- [x] Signpost `startup.config` and `startup.restorePersistedLayout`. Do not
      wrap the two refresh session functions — they already emit their own.
- [x] Concurrent AX prefetch (`MacWindow.prefetchAxSnapshots`) feeding the
      unchanged serial registration loop in `refresh()`.
- [x] Skip the discarded rect read when parking a tiling window in a hide corner.
- [x] Enumerate the window-level cache at most once per refresh session.
- [x] Debug build with `-Xswiftc -warnings-as-errors`, full Swift suite, and
      `lint.sh` all passing.

## Reverted

- [x] Skipping the follow-up refresh after the startup light session, and the
      `shouldScheduleFollowUpRefresh` helper and tests introduced for it. It
      dropped windows that appeared while `restorePersistedLayout()` was awaiting,
      and had no measurable benefit. Rationale in the design record.
- [x] `script/benchmark-startup.sh`. Its CSV was never the source of any reported
      number, and an `xctrace --launch --time-limit` recording cannot measure
      launch duration — the time limit kills the target, so the trace duration is
      the time limit.

- [x] Measure on the three-display machine with Points of Interest signposts,
      alternating blocks. Result: 149 ms vs 163 ms median on the initial heavy
      refresh, ~8%, p≈0.2 at n=7. Real but below the noise floor and below
      perceptibility — see the benchmark record. Do not justify this branch on speed.

## Open

- [ ] `on-window-detected` matching reads each window's title over AX, once per
      candidate callback, inside the serial registration loop. If a config with
      many callbacks shows up in the signpost trace, that read is the next thing
      to hoist into the prefetch phase.
