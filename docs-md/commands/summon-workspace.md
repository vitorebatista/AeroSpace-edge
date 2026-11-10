---
title: summon-workspace
description: Move the requested workspace to the focused monitor.
section: 1
---

# aerospace-edge summon-workspace

Move the requested workspace to the focused monitor.

## Synopsis

```synopsis
aerospace-edge summon-workspace [-h|--help] [--fail-if-noop] [--when-visible (focus|swap)] [--] <workspace>
```

## Description

Move the requested workspace to the focused monitor. The moved workspace becomes focused. The behavior is identical to Xmonad.

The command makes sense only in multi-monitor setup. In single monitor setup the command is identical to `workspace` command.

## Options

`-h`, `--help`

: Print help

`--fail-if-noop`

: Exit with non-zero exit code if the workspace is already visible on the focused monitor.

`--when-visible <action>`

: Defines the behavior if the workspace is already visible on another monitor. `<action>` possible values: `(focus|swap)`.  
  The default is: `focus`

## Arguments

`<workspace>`

: The workspace to operate on.
