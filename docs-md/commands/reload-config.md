---
title: reload-config
description: Reload currently active config
section: 1
---

# aerospace-edge reload-config

Reload currently active config

## Synopsis

```synopsis
aerospace-edge reload-config [-h|--help] [--no-gui] [--dry-run] [--warnings-as-errors]
```

## Description

If the config contains errors they will be printed to stdout, and GUI will open to show the errors.

By default, warnings are written to stderr and do not open the diagnostics window. With `--warnings-as-errors`, warnings are treated like errors: written to stdout, shown in the diagnostics window, and the exit code is non-zero.

## Options

`-h`, `--help`

: Print help.

`--no-gui`

: Don’t open GUI to show error. Only use stdout to report errors.

`--dry-run`

: Validate the config and show errors (if any) but don’t reload the config.

`--warnings-as-errors`

: Treat warnings as errors: print them to stdout, open the GUI diagnostics window, and return a non-zero exit code.

## Exit Codes

0

: Success. The config contains no errors.

non-zero exit code

: Failure. The config contains errors.
