---
title: list-windows
description: Print windows that satisfy conditions
section: 1
---

# aerospace-edge list-windows

Print windows that satisfy conditions

## Synopsis

```synopsis
aerospace-edge list-windows [-h|--help] (--workspace <workspace>...|--monitor <monitor>...)
                       [--monitor <monitor>...] [--workspace <workspace>...]
                       [--pid <pid>] [--app-bundle-id <app-bundle-id>] [--format <output-format>]
                       [--count] [--json] [--sort <sort-option>...]
aerospace-edge list-windows [-h|--help] --all [--format <output-format>] [--count] [--json] [--sort <sort-option>...]
aerospace-edge list-windows [-h|--help] --focused [--format <output-format>] [--count] [--json] [--sort <sort-option>...]
```

## Description

## Options

`-h`, `--help`

: Print help

`--all`

: Alias for `--monitor all`. Please use this option **with caution**. Use it when you really need to get workspaces/windows from **all monitors**.

  For multi-monitor setup `--monitor focused` is almost always a preferred option. If you’re automating something then you don’t want to mess up with workspaces/windows on a different monitor.

  With great power comes great responsibility.

`--focused`

: Print the focused window. Please note that it is possible for no window to be in focus. In that case, error is reported.

--workspace <workspace>...

: Filter results to only print windows that belong to either of specified workspaces. `<workspace>...` is a space-separated list of workspace names.

  Possible values:  

  1.  Workspace name

  2.  `focused` is a special workspace name that represents the focused workspace

  3.  `visible` is a special workspace name that represents all currently visible workspaces (In multi-monitor setup, there are multiple visible workspaces)

`--monitor <monitors>`

: Filter results to only print workspaces/windows that are attached to specified monitors. `<monitors>` is a space separated list of monitor IDs.  

  Possible monitors IDs:  

  1.  1-based index of a monitor as if monitors were ordered horizontally from left to right

  2.  `all` is a special monitor ID that represents all monitors

  3.  `mouse` is a special monitor ID that represents monitor with the mouse

  4.  `focused` is a special monitor ID that represents the focused monitor

`--pid <pid>`

: Filter results to only print windows that belong to the Application with specified `<pid>`

`--app-bundle-id <app-bundle-id>`

: Filter results to only print windows that belong to the Application with specified [Bundle ID](https://developer.apple.com/documentation/appstoreconnectapi/bundle_ids)

  Deprecated (but still supported) flag name: `--app-id`

--sort <sort-option>...

: Sort the output by the specified criteria. `<sort-option>...` is a comma-separated list of sort options.

  Possible values:  

  1.  `recent` - Sort by most recently focused

  2.  `app-name` - Sort by application name

  3.  `window-title` - Sort by window title

      If not specified, the default sort order is: `app-name,window-title`

`--format <output-format>`

: Specify output format. See "Output Format" section for more details. Incompatible with `--count`

`--count`

: Output only the number of windows. Incompatible with `--format`

`--json`

: Output in JSON format. Can be used in combination with `--format` to specify which data to include into the json. Incompatible with `--count`

## Output Format

Output format can be configured with optional `[--format <output-format>]` option. `<output-format>` supports [string interpolation](https://en.wikipedia.org/wiki/String_interpolation).

If not specified, the default `<output-format>` is:  
`%{window-id}%{right-padding} | %{app-name}%{right-padding} | %{window-title}`

The following variables can be used inside `<output-format>`:

%{window-id}

: Number. Window unique ID

%{window-id-native}

: Number. macOS native window ID (`CGWindowID`). Useful for integration with other tools that operate on native window IDs. macOS native tabs are separate windows under the hood. AeroSpace-edge treats the whole tab group as a single window with a stable `%{window-id}`, but `%{window-id-native}` changes whenever another tab is brought to the front. Different apps implement tabs differently. Apps that use native tabs: Finder.app, Terminal.app. Apps that don't use native tabs: Safari. Third-party apps usually don't use native tabs

%{window-title}

: String. Window title

%{window-is-fullscreen}

: Boolean. Is window in fullscreen by `aerospace-edge fullscreen` command

%{window-layout}

: String. An alias for `%{window-parent-container-layout}`

%{window-parent-container-layout}

: String. The layout (`v_tiles`, `h_tiles`, `v_accordion`, `h_accordion`, `floating`) of the window’s parent container.

%{window-parent-container-orientation}

: String. The orientation (`horizontal`, `vertical`) of the window’s parent container. Returns `NULL-ORIENTATION` for floating windows and macOS native windows (fullscreen, minimized, hidden).

%{app-bundle-id}

: String. Application unique identifier. [Bundle ID](https://developer.apple.com/documentation/appstoreconnectapi/bundle_ids)

%{app-name}

: String. Application name

%{app-pid}

: Number. [UNIX process identifier](https://en.wikipedia.org/wiki/Process_identifier)

%{app-exec-path}

: String. Application executable path

%{app-bundle-path}

: String. Application bundle path

%{workspace}

: String. Name of the belonging workspace

%{workspace-is-focused}

: Boolean. `true` if the workspace has focus

%{workspace-is-visible}

: Boolean. `true` if the workspace is visible. A workspace can be visible but not focused in a multi-monitor setup

%{workspace-root-container-layout}

: String. The layout (`v_tiles`, `h_tiles`, `v_accordion`, `h_accordion`) of the workspace’s root container

%{monitor-id}

: 1-based Number. Sequential number of the belonging monitor

%{monitor-appkit-nsscreen-screens-id}

: 1-based index of the belonging monitor in `NSScreen.screens` array. Useful for integration with other tools that might be using `NSScreen.screens` ordering (like sketchybar).

%{monitor-name}

: String. Name of the belonging monitor

%{monitor-is-main}

: Boolean. `true` if the monitor is main.

%{right-padding}

: A special variable which expands with a minimum number of spaces required to form a right padding in the appropriate column

%{newline}

: Unicode U+000A newline symbol `\n`

%{tab}

: Unicode U+0009 tab symbol `\t`

%{all}

: Includes all available variables. Can only be used with `--json` flag
