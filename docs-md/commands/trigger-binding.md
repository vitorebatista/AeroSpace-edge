---
title: trigger-binding
description: Trigger AeroSpace binding as if it was pressed by user
section: 1
---

# aerospace-edge trigger-binding

Trigger AeroSpace binding as if it was pressed by user

## Synopsis

```synopsis
aerospace-edge trigger-binding [-h|--help] --mode <mode-id> [--] <binding>
```

## Description

You can use aerospace-config command to inspect available bindings:  
`aerospace-edge config --get mode.main.binding --keys`

## Options

`-h`, `--help`

: Print help

`--mode <mode-id>`

: Mode to search `<binding>` in

## Arguments

`<binding>`

: Binding to trigger

## Examples

- Run alphabetically first binding from config (useless and synthetic example):  
  `aerospace-edge trigger-binding --mode main "$(aerospace-edge config --get mode.main.binding --keys | head -1)"`

- Trigger `alt-tab` binding:  
  `aerospace-edge trigger-binding --mode main alt-tab`
