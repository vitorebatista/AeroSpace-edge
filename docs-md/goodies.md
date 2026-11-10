---
title: Goodies
---

# Goodies

Do you have a cool automatization, AeroSpace integration, or workflow? Feel free to open an issue or pull request to add it to this list! The source code of the page can be found in the [`docs-md`](https://github.com/vitorebatista/AeroSpace-edge/tree/main/docs-md) directory.

## Move windows by dragging any part of the window

``` bash
defaults write -g NSWindowShouldDragOnGesture -bool true
```

Now, you can move windows by holding `ctrl + cmd` and dragging any part of the window (not necessarily the window title)

## Non-native fullscreen in Firefox

Change the following settings in `about:config`:

    // Disable macOS native fullscreen in Firefox
    full-screen-api.macos-native-full-screen = false

    // Disable fullscreen transition animations
    full-screen-api.transition-duration.enter = 0 0
    full-screen-api.transition-duration.leave = 0 0

`full-screen-api.ignore-widgets` is also an interesting config knob that might be of your preference.

## Highlight focused windows with colored borders

To highlight the focused window with colored border you can use [JankyBorders](https://github.com/FelixKratz/JankyBorders).

You can also use `after-startup-command` to start JankyBorders together with AeroSpace

``` toml
after-startup-command = [
    # JankyBorders has a built-in detection of already running process,
    # so it won't be run twice on AeroSpace restart
    'exec-and-forget borders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0'
]
```

## AeroSpace Raycast extension

There is a third party Raycast extension for AeroSpace. <https://www.raycast.com/limonkufu/aerospace>

If you struggle remembering shortcuts, it’s useful to search for commands until they become muscle memory.

## Disable windows opening animations

Observable in Google Chrome

``` bash
defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
```

## Use trackpad gestures to switch workspaces

The following commands focus next or previous workspaces on monitors where the mouse is located

``` bash
aerospace-edge eval 'list-workspaces --monitor mouse --visible | workspace --stdin next; workspace next --wrap-around'

aerospace-edge eval 'list-workspaces --monitor mouse --visible | workspace --stdin next; workspace prev --wrap-around'
```

Use the software of your choice to assign trackpad gestures to the respective commands. Here are a few third party options in alphabetical order:

- <https://github.com/jomatsu/aerokit> (menu-bar app; also bundles a workspace switcher with previews and Exposé-style overviews)

- <https://github.com/acsandmann/aerospace-swipe>

- [BetterTouchTool](https://folivora.ai/) can assign arbitrary commands to trackpad gestures. Beware that you might need to specify full path to aerospace-edge executable <https://community.folivora.ai/t/how-to-execute-terminal-command-to-switch-workspaces-with-aerospace/35914>

- <https://github.com/MediosZ/SwipeAeroSpace>

!!! warning

    Make sure that you trust project authors before running the distributed binaries. Alternatively, inspect the source code, and build it yourself.

## Show AeroSpace workspaces in Sketchybar

You can integrate AeroSpace workspace indicators with [Sketchybar](https://github.com/FelixKratz/SketchyBar). Use these snippets as a starting point.

**~/.aerospace-edge.toml**

``` toml
## Run Sketchybar together with AeroSpace

## sketchybar has a built-in detection of already running process,

## so it won't be run twice on AeroSpace restart

after-startup-command = ['exec-and-forget sketchybar']

## Notify Sketchybar about workspace change

exec-on-workspace-change = ['/bin/bash', '-c',
    'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE'
]
```

**~/.config/sketchybar/sketchybarrc**

``` bash
sketchybar --add event aerospace_workspace_change

for sid in $(aerospace-edge list-workspaces --all); do
    sketchybar --add item space.$sid left   
        --subscribe space.$sid aerospace_workspace_change   
        --set space.$sid   
        background.color=0x44ffffff   
        background.corner_radius=5   
        background.height=20   
        background.drawing=off   
        label="$sid"   
        click_script="aerospace-edge workspace $sid"   
        script="$CONFIG_DIR/plugins/aerospace.sh $sid"
done
```

**~/.config/sketchybar/plugins/aerospace.sh**

``` bash
#!/usr/bin/env bash

## make sure it's executable with:

## chmod +x ~/.config/sketchybar/plugins/aerospace.sh

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME background.drawing=on
else
    sketchybar --set $NAME background.drawing=off
fi
```

## Show AeroSpace workspaces in simple-bar

[simple-bar](https://github.com/Jean-Tinland/simple-bar) can be used to display AeroSpace workspaces.

In order to sync simple-bar with AeroSpace, add these lines to your AeroSpace config file:

**~/.aerospace-edge.toml**

``` toml
## Notify simple-bar about window focus change

on-focus-changed = [
  "exec-and-forget osascript -e 'tell application id \"tracesOf.Uebersicht\" to refresh widget id \"simple-bar-index-jsx\"'",
]

# Notify simple-bar about workspace change
exec-on-workspace-change = [
  '/bin/zsh',
  '-c',
  '/usr/bin/osascript -e "tell application id \"tracesOf.Uebersicht\" to refresh widget id \"simple-bar-index-jsx\""',
]
```

## Open a new window with AppleScript

Invoking Safari/Terminal with a command the obvious way (`exec-and-forget open -a Safari`) results in an outcome that is probably not the intended one. Namely, that any workspace already containing an instance of Safari/Terminal is brought in focus.

Opening **a new window** of a program that can support multiple windows (such as Safari or Terminal.app) can be accomplished with an AppleScript inlined in `aerospace-edge.toml` as follows:

- Safari

  ``` toml
  ctrl-g = '''exec-and-forget osascript -e '
  tell application "Safari"
      make new document at end of documents
      activate
  end tell'
  '''
  ```

- Terminal

  ``` toml
  ctrl-g = '''exec-and-forget osascript -e \
  'tell application "Terminal" to tell (do script) to activate' '''
  ```

- Ghostty

  ``` toml
  ctrl-g = '''exec-and-forget osascript -e '
  tell application "Ghostty"
      new window
  end tell'
  '''
  ```

## Disable annoying and useless "hide application" shortcut

If `automatically-unhide-macos-hidden-apps` isn’t enough, you can disable `cmd-h` altogether (which will make this hotkey unavailable for apps that might use it for other purposes)

**~/.aerospace-edge.toml**

``` toml
[mode.main.binding]
    cmd-h = [] # Disable "hide application"
    cmd-alt-h = [] # Disable "hide others"
```

## Take screenshots to clipboard using keyboard shortcut

You can configure a custom shortcut to take a screenshot. `screencapture` is a built-in macOS command.

**~/.aerospace-edge.toml**

``` toml
alt-shift-s = 'exec-and-forget screencapture -i -c'
```

## i3 like config

[Download i3-like-config.toml](config-examples/i3-like-config-example.toml)

``` toml
# Reference: https://github.com/i3/i3/blob/next/etc/config

config-version = 2

# In i3, all workspaces are phantom
persistent-workspaces = []

# i3 doesn't have "normalizations" feature that why we disable them here.
# But the feature is very helpful.
# Normalizations eliminate all sorts of weird tree configurations that don't make sense.
# Give normalizations a chance and enable them back.
enable-normalization-flatten-containers = false
enable-normalization-opposite-orientation-for-nested-containers = false

# Mouse follows focus when focused monitor changes
on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

[mode.main.binding]
    # See: https://vitorebatista.github.io/AeroSpace-edge/goodies/#open-a-new-window-with-applescript
    alt-enter = '''exec-and-forget osascript -e \
    'tell application "Terminal" to tell (do script) to activate' '''

    # i3 wraps focus by default
    alt-j =         'focus --wrap-around left'
    alt-k =         'focus --wrap-around down'
    alt-l =         'focus --wrap-around up'
    alt-semicolon = 'focus --wrap-around right'

    alt-shift-j = 'move left'
    alt-shift-k = 'move down'
    alt-shift-l = 'move up'
    alt-shift-semicolon = 'move right'

    # Consider using 'join-with' command as a 'split' replacement if you want to enable
    # normalizations
    alt-h = 'split horizontal'
    alt-v = 'split vertical'

    alt-f = 'fullscreen'

    alt-s = 'layout v_accordion' # 'layout stacking' in i3
    alt-w = 'layout h_accordion' # 'layout tabbed' in i3
    alt-e = 'layout tiles horizontal vertical' # 'layout toggle split' in i3

    alt-shift-space = 'layout floating tiling' # 'floating toggle' in i3

    # Not supported, because this command is redundant in AeroSpace mental model.
    # See: https://vitorebatista.github.io/AeroSpace-edge/guide/#floating-windows
    #alt-space = 'focus toggle_tiling_floating'

    # `focus parent`/`focus child` are not yet supported, and it's not clear whether they
    # should be supported at all https://github.com/nikitabobko/AeroSpace/issues/5
    # alt-a = 'focus parent'

    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'
    alt-0 = 'workspace 10'

    alt-shift-1 = 'move-node-to-workspace 1'
    alt-shift-2 = 'move-node-to-workspace 2'
    alt-shift-3 = 'move-node-to-workspace 3'
    alt-shift-4 = 'move-node-to-workspace 4'
    alt-shift-5 = 'move-node-to-workspace 5'
    alt-shift-6 = 'move-node-to-workspace 6'
    alt-shift-7 = 'move-node-to-workspace 7'
    alt-shift-8 = 'move-node-to-workspace 8'
    alt-shift-9 = 'move-node-to-workspace 9'
    alt-shift-0 = 'move-node-to-workspace 10'

    alt-shift-c = 'reload-config'

    alt-r = 'mode resize'

[mode.resize.binding]
    h = 'resize width -50'
    j = 'resize height +50'
    k = 'resize height -50'
    l = 'resize width +50'
    enter = 'mode main'
    esc = 'mode main'
```

## Spacelist

[Spacelist](https://github.com/magicmark/spacelist) is a terminal UI application that provides a searchable interface to view all open windows organized by workspace. You can hit enter on a selected application to switch to that workspace.

## List of Apple application IDs

The list is useful to compose custom [on-window-detected callback](guide.md#on-window-detected-callback).

| Application name | Application ID |
| --- | --- |
| Activity Monitor | `com.apple.ActivityMonitor` |
| AirPort Utility | `com.apple.airport.airportutility` |
| App Store | `com.apple.AppStore` |
| Audio MIDI Setup | `com.apple.audio.AudioMIDISetup` |
| Automator | `com.apple.Automator` |
| Books | `com.apple.iBooksX` |
| Calculator | `com.apple.calculator` |
| Calendar | `com.apple.iCal` |
| Chess | `com.apple.Chess` |
| Clock | `com.apple.clock` |
| ColorSync Utility | `com.apple.ColorSyncUtility` |
| Console | `com.apple.Console` |
| Contacts | `com.apple.AddressBook` |
| Dictionary | `com.apple.Dictionary` |
| Disk Utility | `com.apple.DiskUtility` |
| FaceTime | `com.apple.FaceTime` |
| Find My | `com.apple.findmy` |
| Finder | `com.apple.finder` |
| Freeform | `com.apple.freeform` |
| Grapher | `com.apple.grapher` |
| Home | `com.apple.Home` |
| iMovie | `com.apple.iMovieApp` |
| Keychain Access | `com.apple.keychainaccess` |
| Keynote | `com.apple.iWork.Keynote` |
| Mail | `com.apple.mail` |
| Maps | `com.apple.Maps` |
| Messages | `com.apple.MobileSMS` |
| Music | `com.apple.Music` |
| Notes | `com.apple.Notes` |
| Pages | `com.apple.iWork.Pages` |
| Photo Booth | `com.apple.PhotoBooth` |
| Photos | `com.apple.Photos` |
| Podcasts | `com.apple.podcasts` |
| Preview | `com.apple.Preview` |
| QuickTime Player | `com.apple.QuickTimePlayerX` |
| Reminders | `com.apple.reminders` |
| Safari | `com.apple.Safari` |
| Shortcuts | `com.apple.shortcuts` |
| Stocks | `com.apple.stocks` |
| System Settings | `com.apple.systempreferences` |
| Terminal | `com.apple.Terminal` |
| TextEdit | `com.apple.TextEdit` |
| Time Machine | `com.apple.backup.launcher` |
| TV | `com.apple.TV` |
| VoiceMemos | `com.apple.VoiceMemos` |
| VoiceOver Utility | `com.apple.VoiceOverUtility` |
| Weather | `com.apple.weather` |
| Xcode | `com.apple.dt.Xcode` |
