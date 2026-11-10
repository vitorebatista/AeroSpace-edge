---
title: move-node-to-monitor
description: Move window to monitor targeted by relative direction, by order, or by pattern
section: 1
---

# aerospace-edge move-node-to-monitor

Move window to monitor targeted by relative direction, by order, or by pattern

## Synopsis

```synopsis
aerospace-edge move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                               [--wrap-around] (left|down|up|right|next|prev)
aerospace-edge move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                               [--fail-if-noop] [--] <monitor-pattern>...
```

## Description

## Options

`-h`, `--help`

: Print help

`--wrap-around`

: Make it possible to wrap around the movement

`--focus-follows-window`

: Make sure that the window in question receives focus after moving. This flag is a shortcut for manually running `aerospace-workspace`/`aerospace-focus` after `move-node-to-monitor` successful execution.

`--fail-if-noop`

: Exit with non-zero code if moving window to monitor it already belongs to

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

## Arguments

`(left|down|up|right)`

: Move window to monitor in direction relative to the focused monitor

`(next|prev)`

: Move window to next|prev monitor in order they appear in tray icon

<monitor-pattern>...

: Find the first matching monitor and move the window there. Multiple monitor patterns is useful for different monitor configurations. Monitor patterns follow the same format as in `workspace-to-monitor-force-assignment` config option
