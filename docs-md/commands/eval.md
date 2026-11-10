---
title: eval
description: Send multiple commands to AeroSpace at once
section: 1
---

# aerospace-edge eval

Send multiple commands to AeroSpace at once

## Synopsis

```synopsis
aerospace-edge eval [-h|--help] [--stdin] [--] <aerospace-shell-expr>
```

## Description

Send multiple commands to AeroSpace at once

## Options

`-h`, `--help`

: Print help

`--stdin`

: Capture CLIs stdin and forward it to `<aerospace-shell-expr>`. If not supplied, stdin is ignored.

## Arguments

`<aerospace-shell-expr>`

: This argument is AeroSpace's shell expression. See [shell](../guide.md#shell) for more info.

## Examples

- Cycle between workspaces a, b, and c:  
  `aerospace-edge eval 'echo a b c | workspace --wrap-around --stdin next'`
