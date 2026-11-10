---
title: focus
description: Set focus to a window.
section: 1
---

# aerospace-edge focus

Set focus to a window.

## Synopsis

```synopsis
aerospace-edge focus [-h|--help] [--ignore-floating] [--wrap-around]
                [--boundaries <boundary>] [--boundaries-action <action>]
                [--fail-if-fullscreen] [--fail-if-macos-native-fullscreen]
                (left|down|up|right)
aerospace-edge focus [-h|--help] [--ignore-floating] [--wrap-around]
                [--boundaries <boundary>] [--boundaries-action <action>]
                (dfs-next|dfs-prev)
aerospace-edge focus [-h|--help] --window-id <window-id>
aerospace-edge focus [-h|--help] --dfs-index <dfs-index>
```

## Description

Contrary to i3, `focus` command doesn’t have a separate argument to focus floating windows. From `focus` command perspective, floating windows are part of [the tree](../guide.md#tree). The floating window parent container is determined as the smallest tiling container that contains the center of the floating window. The technique eliminates the need for an additional binding for floating windows. This behavior can be disabled with `--ignore-floating` flag.

`focus child|parent` isn’t supported because the necessity of this operation is under the question. <https://github.com/nikitabobko/AeroSpace/issues/5>

## Options

`-h`, `--help`

: Print help

`--boundaries <boundary>`

: Defines focus boundaries.  
  `<boundary>` possible values: `(workspace|all-monitors-outer-frame)`.  
  The default is: `workspace`

`--boundaries-action <action>`

: Defines the behavior when requested to cross the `<boundary>`.  
  `<action>` possible values: `(stop|fail|wrap-around-the-workspace|wrap-around-all-monitors)`.  
  The default is: `stop`

`--wrap-around`

: An alias for `--boundaries-action wrap-around-the-workspace`. The flag is incompatible with either `--boundaries-action` or `--boundaries`.

`--window-id <window-id>`

: Focus the window with specified `<window-id>`

`--dfs-index <dfs-index>`

: Focus window by its index, based on a depth-first search (DFS) of the window within the workspace tree. Index is 0-based.

`--ignore-floating`

: Don’t perceive floating windows as part of the tree. It may be useful for more reliable scripting.

`--fail-if-fullscreen`

: Exit with non-zero code if the current target window is fullscreen by the `fullscreen` command. Only compatible with `(left|down|up|right)`.

`--fail-if-macos-native-fullscreen`

: Exit with non-zero code if the current target window is in macOS native fullscreen. Only compatible with `(left|down|up|right)`.

## Arguments

`(left|down|up|right)`

: Set focus to the nearest window in the given direction.

`(dfs-next|dfs-prev)`

: Set focus to the window before or after the current window in the depth-first order (top-to-bottom and left-to-right) of windows in the current workspace tree. In this mode, `--boundaries` must be `workspace` (the default) and `--boundaries-action` can be set to one of `(stop|fail|wrap-around-the-workspace)`.
