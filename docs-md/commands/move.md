---
title: move
description: Move the focused window in the given direction
section: 1
---

# aerospace-edge move

Move the focused window in the given direction

## Synopsis

```synopsis
aerospace-edge move [-h|--help] [--window-id <window-id>] [--boundaries <boundary>]
               [--boundaries-action <boundary-action>] [--fail-if-fullscreen]
               [--fail-if-macos-native-fullscreen] (left|down|up|right)
```

## Description

Move the focused window in the given direction. See the "Examples" section for more details.

Deprecated name: `move-through`

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

`--boundaries <boundary>`

: Defines move boundaries.  
  `<boundary>` possible values: `(workspace|all-monitors-outer-frame)`.  
  The default is: `workspace`

`--boundaries-action <boundary-action>`

: Defines the behavior when requested to move across the `<boundary>`.  
  `<boundary-action>` possible values: `(stop|fail|create-implicit-container|create-implicit-container-or-fail)`.  
  The default is: `create-implicit-container`

`--fail-if-fullscreen`

: Exit with non-zero code if the target window is fullscreen by the `fullscreen` command.

`--fail-if-macos-native-fullscreen`

: Exit with non-zero code if the target window is in macOS native fullscreen.

## Examples

1.  Given this layout

        h_tiles
        ├── window 1 (focused)
        └── window 2

    `move right` will result in the following layout

        h_tiles
        ├── window 2
        └── window 1 (focused)

2.  Given this layout

        h_tiles
        ├── window 1
        ├── window 2 (focused)
        └── v_tiles
            ├── window 3
            └── window 4

    `move right` will result in the following layout

        h_tiles
        ├── window 1
        └── v_tiles
            ├── window 3
            ├── window 2 (focused)
            └── window 4

3.  Given this layout

        h_tiles
        ├── window 1
        └── v_tiles
            ├── window 3
            ├── window 2 (focused)
            └── window 4

    `move left` will result in the following layout

        h_tiles
        ├── window 1
        ├── window 2 (focused)
        └── v_tiles
            ├── window 3
            └── window 4

4.  **Implicit container example**

    In some cases, `move` needs to implicitly create a container to fulfill your command.

    Given this layout

        h_tiles
        ├── window 1
        ├── window 2 (focused)
        └── window 3

    `move up` will result in the following layout

        v_tiles
        ├── window 2 (focused)
        └── h_tiles
            ├── window 1
            └── window 3

    `v_tiles` is an implicitly created container.

    **Remark**: If `--boundaries` is set to `all-monitors-outer-frame` and there is a monitor in the `up` direction, the implicit container isn’t created.

    Instead, `window 2` would be moved to the monitor above the current.

    **Remark on `create-implicit-container-or-fail`**: When `--boundaries-action` is set to `create-implicit-container-or-fail` (and normalization is enabled), the command will fail if the newly created implicit container is immediately flattened away by container normalization.
