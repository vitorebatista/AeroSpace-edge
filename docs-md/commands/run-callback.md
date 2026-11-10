---
title: run-callback
description: Run AeroSpace config callbacks on demand
section: 1
---

# aerospace-edge run-callback

Run AeroSpace config callbacks on demand

## Synopsis

```synopsis
aerospace-edge run-callback [-h|--help] [--for-every-window|--window-id <window-id>] on-window-detected
aerospace-edge run-callback [-h|--help] (on-focus-changed|on-focused-monitor-changed)
```

## Description

Run AeroSpace config callbacks on demand

The command lets you manually re-run callbacks that AeroSpace-edge normally invokes in response to events:

- `on-window-detected` - callbacks defined by [`on-window-detected`](../guide.md#on-window-detected-callback) config option. By default the callbacks are run for the focused window only. Pass `--for-every-window` to apply the callbacks to every currently known window (useful right after [`reload-config`](reload-config.md) to retroactively apply new rules to already open windows), or pass `--window-id` to target a specific window.

- `on-focus-changed` - runs commands listed under the `on-focus-changed` config key.

- `on-focused-monitor-changed` - runs commands listed under the `on-focused-monitor-changed` config key.

The command forwards stdout and stderr of all commands run in the callback. That opens up one more usecase - you can use this command to see the output of your callbacks.

## Options

`-h`, `--help`

: Print help

`--for-every-window`

: Run `on-window-detected` callbacks for every window. Only valid with `on-window-detected`. Mutually exclusive with `--window-id`.

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

  Only valid with `on-window-detected`. Mutually exclusive with `--for-every-window`.

## Arguments

`<callback>`

: One of: `on-window-detected`, `on-focus-changed`, `on-focused-monitor-changed`

## Exit Codes

The command forwards the exit code of the callback.
