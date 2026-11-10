import Common
import CoreGraphics
import Foundation

@MainActor private var cache: [UInt32: MacOsWindowLevel] = [:]
@MainActor private var wip: AwaitableOneTimeBroadcastLatch? = nil
/// True once the cache has been re-enumerated during the current refresh session. (fork 62e757a1)
@MainActor private var cacheIsFresh = false

/// Called at the top of every refresh session. The cache is a snapshot of the WindowServer window list, so it
/// does have to be re-read once per session - but only once.
@MainActor func invalidateWindowLevelCache() { cacheIsFresh = false }

@MainActor func getWindowLevel(forNativeId windowId: UInt32, _ cm: CancellationMode) async throws -> MacOsWindowLevel? {
    if let existing = cache[windowId] { return existing }
    // A miss right after an enumeration in this session means WindowServer doesn't know the window (it's
    // already gone, or not yet there). Without this guard every such window re-enumerates the entire window
    // list, gets nothing, and the next one does it again. (fork 62e757a1)
    if cacheIsFresh && wip == nil { return nil }
    return try await refreshWindowLevelCache(cm)[windowId]
}

/// Re-enumerates the cache (once per refresh session) and returns all known window levels
@MainActor func getAllWindowLevels(_ cm: CancellationMode) async throws -> [UInt32: MacOsWindowLevel] {
    try await refreshWindowLevelCache(cm)
}

@MainActor private func refreshWindowLevelCache(_ cm: CancellationMode) async throws -> [UInt32: MacOsWindowLevel] {
    if let wip {
        try await wip.await(cm)
        return cache
    }
    let latch = AwaitableOneTimeBroadcastLatch()
    wip = latch
    cache = await computeCache()
    cacheIsFresh = true
    wip = nil
    // Upstream be3e58df set `wip = nil` before `await wip?.signalToAll()`, which signalled nobody, so concurrent
    // callers awaited the latch forever. Signal the latch captured above instead.
    await latch.signalToAll()
    return cache
}

/// CGWindowListCopyWindowInfo is expensive ("Generating the dictionaries for system windows is a relatively
/// expensive operation"), so it runs off the main thread (upstream be3e58df)
@concurrent private func computeCache() async -> [UInt32: MacOsWindowLevel] {
    var result: [UInt32: MacOsWindowLevel] = [:]
    // .optionAll (upstream b686e0f2): minimized windows, hidden apps and windows on other macOS Spaces get their
    // real level too, instead of none
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionAll)
    guard let cfArray = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [CFDictionary] else { return [:] }
    for elem in cfArray {
        let dict = elem as NSDictionary

        guard let _windowLayer = dict[kCGWindowLayer] else { continue }
        let windowLayer = ((_windowLayer as! CFNumber) as NSNumber).intValue

        guard let _windowId = dict[kCGWindowNumber] else { continue }
        let windowId = ((_windowId as! CFNumber) as NSNumber).uint32Value

        result[windowId] = .new(windowLevel: windowLayer)
    }
    return result
}

enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: Json) -> MacOsWindowLevel? {
        switch json {
            case .string("normalWindow"): .normalWindow
            case .string("alwaysOnTopWindow"): .alwaysOnTopWindow
            case .int(let int): .new(windowLevel: Int(exactly: int).orDie())
            default: nil
        }
    }

    func toJson() -> Json {
        switch self {
            case .normalWindow: .string("normalWindow")
            case .alwaysOnTopWindow: .string("alwaysOnTopWindow")
            case .unknown(let layerNumber): .int(layerNumber)
        }
    }
}
