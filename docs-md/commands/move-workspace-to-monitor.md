---
title: move-workspace-to-monitor
description: Move workspace to monitor targeted by relative direction, by order, or by pattern.
section: 1
---

# aerospace-edge move-workspace-to-monitor

Move workspace to monitor targeted by relative direction, by order, or by pattern.

## Synopsis

```synopsis
aerospace-edge move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (left|down|up|right)
aerospace-edge move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (next|prev)
aerospace-edge move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--] <monitor-pattern>...
```

## Description

Move workspace to monitor targeted by relative direction, by order, or by pattern. Focus follows the focused workspace, so the workspace stays focused.

The command fails for workspaces [that have monitor force assignment](../guide.md#assign-workspaces-to-monitors).

## Options

`-h`, `--help`

: Print help

`--wrap-around`

: Allows to move workspace between first and last monitors

`--workspace <workspace>`

: Act on the specified workspace instead of the focused workspace. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

## Arguments

`(left|down|up|right)`

: Move workspace to monitor in direction relative to the focused monitor

`(next|prev)`

: Move the workspace to next or prev monitor. 'next' or 'prev' monitor is calculated relative to the monitor `<workspace>` currently belongs to.

`<monitor-pattern>`

: Find the first matching monitor and move the workspace there. Multiple monitor patterns is useful for different monitor configurations. Monitor patterns follow the same format as in `workspace-to-monitor-force-assignment` config option
