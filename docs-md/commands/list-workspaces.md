---
title: list-workspaces
description: Print workspaces that satisfy conditions
section: 1
---

# aerospace-edge list-workspaces

Print workspaces that satisfy conditions

## Synopsis

```synopsis
aerospace-edge list-workspaces [-h|--help] --monitor <monitor>... [--visible [no]] [--empty [no]] [--format <output-format>] [--count] [--json]
aerospace-edge list-workspaces [-h|--help] --all [--format <output-format>] [--count] [--json]
aerospace-edge list-workspaces [-h|--help] --focused [--format <output-format>] [--count] [--json]
```

## Description

## Options

`-h`, `--help`

: Print help

`--format <output-format>`

: Specify output format. See "Output Format" section for more details

`--all`

: Alias for `--monitor all`. Please use this option **with caution**. Use it when you really need to get workspaces/windows from **all monitors**.

  For multi-monitor setup `--monitor focused` is almost always a preferred option. If you’re automating something then you don’t want to mess up with workspaces/windows on a different monitor.

  With great power comes great responsibility.

`--focused`

: An alias for `--monitor focused --visible`. Always prints a single workspace

`--monitor <monitors>`

: Filter results to only print workspaces/windows that are attached to specified monitors. `<monitors>` is a space separated list of monitor IDs.  

  Possible monitors IDs:  

  1.  1-based index of a monitor as if monitors were ordered horizontally from left to right

  2.  `all` is a special monitor ID that represents all monitors

  3.  `mouse` is a special monitor ID that represents monitor with the mouse

  4.  `focused` is a special monitor ID that represents the focused monitor

--visible [no]

: Filter results to only print currently visible workspaces. `[no]` inverts the condition. Several workspaces can be visible in multi-monitor setup

--empty [no]

: Filter results to only print empty workspaces. `[no]` inverts the condition.

`--format <output-format>`

: Specify output format. See "Output Format" section for more details. Incompatible with `--count`

`--count`

: Output only the number of workspaces. Incompatible with `--format`

`--json`

: Output in JSON format. Can be used in combination with `--format` to specify which data to include into the json. Incompatible with `--count`

## Output Format

Output format can be configured with optional `[--format <output-format>]` option. `<output-format>` supports [string interpolation](https://en.wikipedia.org/wiki/String_interpolation).

If not specified, the default `<output-format>` is:  
`%{workspace}`

The following variables can be used inside `<output-format>`:

%{workspace}

: String. Name of the belonging workspace

%{workspace-is-focused}

: Boolean. `true` if the workspace has focus

%{workspace-is-visible}

: Boolean. `true` if the workspace is visible. A workspace can be visible but not focused in a multi-monitor setup

%{workspace-root-container-layout}

: String. The layout (`v_tiles`, `h_tiles`, `v_accordion`, `h_accordion`) of the workspace’s root container

%{workspace-root-container-orientation}

: String. The orientation (`horizontal`, `vertical`) of the workspace’s root container

%{monitor-id}

: 1-based Number. Sequential number of the belonging monitor

%{monitor-appkit-nsscreen-screens-id}

: 1-based index of the belonging monitor in `NSScreen.screens` array. Useful for integration with other tools that might be using `NSScreen.screens` ordering (like sketchybar).

%{monitor-name}

: String. Name of the belonging monitor

%{monitor-is-main}

: Boolean. `true` if the monitor is main.

%{right-padding}

: A special variable which expands with a minimum number of spaces required to form a right padding in the appropriate column

%{newline}

: Unicode U+000A newline symbol `\n`

%{tab}

: Unicode U+0009 tab symbol `\t`

%{all}

: Includes all available variables. Can only be used with `--json` flag
