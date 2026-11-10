---
title: move-node-to-workspace
description: Move the focused window to the specified workspace
section: 1
---

# aerospace-edge move-node-to-workspace

Move the focused window to the specified workspace

## Synopsis

```synopsis
aerospace-edge move-node-to-workspace [-h|--help] [--focus-follows-window] [--wrap-around]
                                 [--stdin|--no-stdin]
                                 (next|prev)
aerospace-edge move-node-to-workspace [-h|--help] [--focus-follows-window] [--fail-if-noop]
                                 [--window-id <window-id>] [--] <workspace-name>
```

## Description

`(next|prev)` is identical to `workspace (next|prev)`

## Options

`-h`, `--help`

: Print help

`--wrap-around`

: Make it possible to jump between first and last workspaces using (next|prev)

`--fail-if-noop`

: Exit with non-zero code if move window to workspace it already belongs to

`--focus-follows-window`

: Make sure that the window in question receives focus after moving. This flag is a shortcut for manually running `aerospace-workspace`/`aerospace-focus` after `move-node-to-workspace` successful execution.

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

`--stdin`

: Read the list of workspaces from stdin. Incompatible with `--no-stdin`

`--no-stdin`

: Ignore the list of workspaces from stdin, even if provided. Incompatible with `--stdin`

## Arguments

`(next|prev)`

: Move window to next or prev workspace in **the list** -

  - If stdin is not TTY and stdin contains non whitespace characters then **the list** is taken from stdin

  - Otherwise, **the list** is defined as all workspaces on focused monitor in alphabetical order

`<workspace-name>`

: Specifies workspace name where to move window to
