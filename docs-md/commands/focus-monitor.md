---
title: focus-monitor
description: Focus monitor by relative direction, by order, or by pattern
section: 1
---

# aerospace-edge focus-monitor

Focus monitor by relative direction, by order, or by pattern

## Synopsis

```synopsis
aerospace-edge focus-monitor [-h|--help] [--wrap-around] (left|down|up|right)
aerospace-edge focus-monitor [-h|--help] [--wrap-around] (next|prev)
aerospace-edge focus-monitor [-h|--help] [--] <monitor-pattern>...
```

## Description

## Options

`-h`, `--help`

: Print help

`--wrap-around`

: Make it possible to wrap around focus

## Arguments

`(left|down|up|right)`

: Focus monitor in direction relative to the focused monitor

`(next|prev)`

: Focus next|prev monitor in order they appear in tray icon

<monitor-pattern>...

: Find the first matching monitor and focus it. Multiple monitor patterns is useful for different monitor configurations. Monitor patterns follow the same format as in `workspace-to-monitor-force-assignment` config option
