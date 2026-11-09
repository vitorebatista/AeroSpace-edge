import SwiftUI

struct ExperimentalUISettings {
    /// Where the menu-bar item sits, in points from the right edge of the menu bar — bigger moves
    /// it further left. `0` (the default) means "wherever macOS puts it", which is what every menu
    /// bar item does normally.
    var menuBarItemPosition: Int {
        get { UserDefaults.standard.integer(forKey: ExperimentalUISettingsItems.menuBarItemPosition.rawValue) }
        set {
            UserDefaults.standard.setValue(newValue, forKey: ExperimentalUISettingsItems.menuBarItemPosition.rawValue)
            UserDefaults.standard.synchronize()
        }
    }

    var displayStyle: MenuBarStyle {
        get {
            switch UserDefaults.standard.string(forKey: ExperimentalUISettingsItems.displayStyle.rawValue) {
                case let value?: MenuBarStyle(rawValue: value) ?? .monospacedText
                case nil: .monospacedText
            }
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: ExperimentalUISettingsItems.displayStyle.rawValue)
            UserDefaults.standard.synchronize()
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable, Equatable, Hashable {
    case monospacedText
    case systemText
    case squares
    case i3
    case i3Ordered
    var id: String { rawValue }
    var title: String {
        switch self {
            case .monospacedText: "Monospaced font"
            case .systemText: "System font"
            case .squares: "Square images"
            case .i3: "i3 style grouped"
            case .i3Ordered: "i3 style ordered"
        }
    }
}

enum ExperimentalUISettingsItems: String {
    case displayStyle
    case menuBarItemPosition
}

/// AppKit persists the menu-bar item's position under its autosave name and restores it on every
/// launch — which is why an item that once landed behind the notch, or off in the app-menu strip,
/// stays there forever. Rewriting that key before the status item exists pins it back.
///
/// ponytail: `Item-0` is the autosave name SwiftUI generates for a single `MenuBarExtra`; there is
/// no API to ask for it. A second `MenuBarExtra`, or a SwiftUI rename, makes this silently stop
/// applying — the menu bar item still works, it just goes back to wherever macOS puts it.
let statusItemPositionKey = "NSStatusItem Preferred Position Item-0"

@MainActor
func applyMenuBarItemPosition() {
    guard let position = statusItemPositionToPersist(ExperimentalUISettings().menuBarItemPosition) else { return }
    UserDefaults.standard.setValue(position, forKey: statusItemPositionKey)
}

/// `0` and anything negative mean "leave it to macOS": the key stays untouched, so a position the
/// user set by ⌘-dragging the item survives.
func statusItemPositionToPersist(_ configured: Int) -> Int? {
    configured > 0 ? configured : nil
}

/// A value wider than the display pushes the item off the end of the status area and into the
/// strip where app menus are drawn, where it is invisible and can't be ⌘-dragged back — the exact
/// hole this setting exists to climb out of. Warn instead of clamping: silently changing what
/// someone typed is worse than telling them it won't work.
func menuBarPositionWarning(_ configured: Int, screenWidth: CGFloat?) -> String? {
    guard configured > 0, let screenWidth else { return nil }
    let usable = Int(screenWidth) - 200 // the app menus need the left end of the bar
    guard configured > usable else { return nil }
    return "\(configured) is past the usable end of a \(Int(screenWidth))-point-wide display. "
        + "The item will land behind the app menus, where it can't be seen or dragged. Try \(usable) or less."
}

@MainActor
struct MenuBarStyleButton: View {
    @EnvironmentObject var viewModel: TrayMenuModel
    let style: MenuBarStyle
    let color: Color

    var body: some View {
        Button {
            viewModel.experimentalUISettings.displayStyle = style
        } label: {
            Toggle(isOn: .constant(viewModel.experimentalUISettings.displayStyle == style)) {
                Label {
                    Text(" -  " + style.title)
                } icon: {
                    MenuBarLabel(style: style, color: color)
                        .environmentObject(viewModel)
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}
