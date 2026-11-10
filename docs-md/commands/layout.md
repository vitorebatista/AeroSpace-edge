---
title: layout
description: Change layout of the focused node to the given layout
section: 1
---

# aerospace-edge layout

Change layout of the focused node to the given layout

## Synopsis

```synopsis
aerospace-edge layout [-h|--help] [--window-id <window-id>|--workspace <workspace>]
                 [--root] [--fail-if-noop]
                 (<target-layout>)...
aerospace-edge layout [-h|--help] --for-next-detected-window (tiling|floating)
```

## Description

By default, the command acts on the focused window’s parent container. With `--root`, the command acts on the workspace’s root tiling container instead, which lets you toggle the workspace-level layout without flattening nested sub-containers.

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

`--workspace <workspace>`

: Act on the specified workspace instead of the focused workspace. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables). Requires `--root`.

`--root`

: Act on the focused workspace’s root tiling container instead of the focused window’s parent container. Succeeds even when no window is focused (the command operates on the root container directly), so it works on empty or floating-only workspaces. The `tiling` and `floating` descriptors are not valid with `--root` because they describe window placement modes, not container layouts. `--root` is mutually exclusive with `--window-id`.

  !!! note

      When `enable-normalization-flatten-containers` is enabled and the root has a single nested tiling container as its only child, the next normalization pass will replace the root with the nested container. In that specific tree shape, a `--root` toggle is effectively discarded by the next normalize.

`--fail-if-noop`

: Exit with non-zero exit code if already in the requested layout. When you use this flag, the command permits only one `<target-layout>` argument.

`--for-next-detected-window`

: Don't change the layout of any currently existing window. Instead, schedule the layout change, and apply it to the next window that AeroSpace-edge detects.

  The scheduled layout change is applied both before and after the [on-window-detected callbacks](../guide.md#on-window-detected-callback) are run, so that the callbacks observe the scheduled layout, and so that the scheduled layout wins over the callbacks. It is applied only once. Running `layout --for-next-detected-window` again replaces the previously scheduled layout change.

  When you use this flag, the command permits exactly one `<target-layout>` argument, and `tiling` and `floating` are its only valid values. The flag is incompatible with all the other flags.

## Arguments

`<target-layout>`

: Possible values:

  - `h_tiles|v_tiles|h_accordion|v_accordion` - Change both tiling layout and orientation in one go
  - `tiles|accordion` - Change tiling layout but preserve orientation
  - `horizontal|vertical` - Change orientation but preserve layout
  - `tiling|floating` - Toggle between floating/tiling mode (not valid with `--root`)
  - `sticky` - Toggle "sticky" mode of a floating window (a sticky floating window is shown on all workspaces of its monitor)

  If several `<target-layout>` are supplied, then the first one that doesn’t describe the currently active layout is applied.

## Examples

- Toggle between `floating` and `tiling` layouts (order of args doesn’t matter):  
  `aerospace-edge layout floating tiling`

- Toggle orientation (order of args doesn’t matter):  
  `aerospace-edge layout horizontal vertical`

- Toggle between `tiles` and `accordion` layouts (order of args doesn’t matter):  
  `aerospace-edge layout tiles accordion`

- Switch to `tiles` layout. Toggle the layout orientation if already in `tiles` layout:  
  `aerospace-edge layout tiles horizontal vertical`

- Toggle the workspace’s root layout between `tiles` and `accordion` without disturbing nested sub-containers:  
  `aerospace-edge layout --root tiles accordion`

- Toggle "sticky" mode of the focused floating window (show it on all workspaces of its monitor):  
  `aerospace-edge layout sticky`

- Make the next window that opens floating:  
  `aerospace-edge layout floating --for-next-detected-window`
