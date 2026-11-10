---
title: swap
description: Swaps the focused window with another window.
section: 1
---

# aerospace-edge swap

Swaps the focused window with another window.

## Synopsis

```synopsis
aerospace-edge swap [-h|--help] [--window-id <window-id>] [--swap-focus]
               [--wrap-around] (left|down|up|right|dfs-next|dfs-prev)
```

## Description

The operation is equivalent to dragging a window with the mouse.

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

`--swap-focus`

: Swap focus away from the currently focused window. By default, this command does not change the focused window.

`--wrap-around`

: Wrap around if the window is at the edge of the workspace (for `(left|down|up|right)`) or the start/end of the depth first order (for `(dfs-next|dfs-prev)`).

## Arguments

`(left|down|up|right)`

: Swaps the focused window with the nearest window in the given direction.

`(dfs-next|dfs-prev)`

: Swaps the focused window with the next or previous window in the depth-first order (top-to-bottom and left-to-right) of windows in the current workspace tree.
