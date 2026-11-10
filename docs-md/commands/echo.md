---
title: echo
description: Print arguments and interpolation variables to stdout
section: 1
---

# aerospace-edge echo

Print arguments and interpolation variables to stdout

## Synopsis

```synopsis
aerospace-edge echo [-h|--help] [--stderr] [--window-id <window-id>] -- <string>...
```

## Description

Print `<string>...` arguments and **interpolation variables** to stdout.

You can use this command in combination with other commands to do various things:

- You can test shell operators

- You can pipe an explicit input to some other command (e.g. [workspace](workspace.md)) inside an [eval](eval.md)

- You can print interpolation variables for the focused window (see [list-windows](list-windows.md) for the list of interpolation variables)

## Options

`-h`, `--help`

: Print help

`--stderr`

: Print to stderr instead of stdout

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

## Arguments

`<string>`

: The argument to print. Each `<string>` argument can contain **interpolation variables** similar to those in [list-windows command](list-windows.md). You can specify multiple `<string>` arguments - each of them is printed on a separate line.

## Examples

- Print the focused window title: `aerospace-edge echo -- %{window-title}`
