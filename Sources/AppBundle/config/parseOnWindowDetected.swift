import Common

struct WindowDetectedCallback: Withable, Equatable {
    var matcher: WindowDetectedCallbackMatcher = .command(.empty)
    var checkFurtherCallbacks: Bool = false
    var rawRun: Shell<any Command>? = nil

    var run: Shell<any Command> {
        rawRun ?? dieT("ID-46D063B2 should have discarded nil")
    }

    var debugJson: Json {
        var result: [String: Json] = [:]
        result["matcher"] = switch matcher {
            case .command(let command): .string(command.shellOfCommandsDescription)
            case .legacy(let legacy): legacy.debugJson
        }
        if let commands = rawRun {
            result["commands"] = .string(commands.shellOfCommandsDescription)
        }
        return .dict(result)
    }

    static func == (lhs: WindowDetectedCallback, rhs: WindowDetectedCallback) -> Bool {
        lhs.matcher == rhs.matcher && lhs.checkFurtherCallbacks == rhs.checkFurtherCallbacks && lhs.run.strictEquals(rhs.run)
    }
}

struct LegacyWindowDetectedCallbackMatcher: Withable, Equatable {
    var appIds: [String]? // Fork: 'app-id' accepts an array of app ids
    var appIdRegexSubstring: CaseInsensitiveRegex? // Fork: 'app-id-regex-substring'
    var appNameRegexSubstring: CaseInsensitiveRegex?
    var windowTitleRegexSubstring: CaseInsensitiveRegex?
    var workspace: String?
    var duringAeroSpaceStartup: Bool?

    // Backward compatibility - computed property for single appId
    var appId: String? {
        get { appIds?.first }
        set { appIds = newValue.map { [$0] } }
    }

    init(
        appIds: [String]? = nil,
        appIdRegexSubstring: CaseInsensitiveRegex? = nil,
        appNameRegexSubstring: CaseInsensitiveRegex? = nil,
        windowTitleRegexSubstring: CaseInsensitiveRegex? = nil,
        workspace: String? = nil,
        duringAeroSpaceStartup: Bool? = nil,
    ) {
        self.appIds = appIds
        self.appIdRegexSubstring = appIdRegexSubstring
        self.appNameRegexSubstring = appNameRegexSubstring
        self.windowTitleRegexSubstring = windowTitleRegexSubstring
        self.workspace = workspace
        self.duringAeroSpaceStartup = duringAeroSpaceStartup
    }

    // Backward compatibility initializer with old single appId parameter
    init(
        appId: String?,
        appIdRegexSubstring: CaseInsensitiveRegex? = nil,
        appNameRegexSubstring: CaseInsensitiveRegex? = nil,
        windowTitleRegexSubstring: CaseInsensitiveRegex? = nil,
        workspace: String? = nil,
        duringAeroSpaceStartup: Bool? = nil,
    ) {
        self.init(
            appIds: appId.map { [$0] },
            appIdRegexSubstring: appIdRegexSubstring,
            appNameRegexSubstring: appNameRegexSubstring,
            windowTitleRegexSubstring: windowTitleRegexSubstring,
            workspace: workspace,
            duringAeroSpaceStartup: duringAeroSpaceStartup,
        )
    }

    var debugJson: Json {
        var resultParts: [String] = []
        if let appIds {
            if appIds.count == 1 {
                resultParts.append("appId=\"\(appIds[0])\"")
            } else {
                resultParts.append("appIds=\(appIds)")
            }
        }
        if let appIdRegexSubstring {
            resultParts.append("appIdRegexSubstring=\"\(appIdRegexSubstring.origin)\"")
        }
        if let appNameRegexSubstring {
            resultParts.append("appNameRegexSubstring=\"\(appNameRegexSubstring.origin)\"")
        }
        if let windowTitleRegexSubstring {
            resultParts.append("windowTitleRegexSubstring=\"\(windowTitleRegexSubstring.origin)\"")
        }
        if let workspace {
            resultParts.append("workspace=\"\(workspace)\"")
        }
        if let duringAeroSpaceStartup {
            resultParts.append("duringAeroSpaceStartup=\(duringAeroSpaceStartup)")
        }
        return .string(resultParts.joined(separator: ", "))
    }
}

enum WindowDetectedCallbackMatcher: Equatable {
    case command(Shell<any Command>)
    case legacy(LegacyWindowDetectedCallbackMatcher)

    static func == (lhs: WindowDetectedCallbackMatcher, rhs: WindowDetectedCallbackMatcher) -> Bool {
        switch (lhs, rhs) {
            case (.command(let command1), .command(let command2)): command1.strictEquals(command2)
            case (.legacy(let matcher1), .legacy(let matcher2)): matcher1 == matcher2
            default: false
        }
    }
}

private let windowDetectedParser: [String: any ParserProtocol<WindowDetectedCallback>] = [
    "if": Parser(\.matcher, parseMatcher),
    "check-further-callbacks": Parser(\.checkFurtherCallbacks, parseBool),
    "run": Parser(\.rawRun, parseShellOfCommandsForConfig),
]

private let matcherParsers: [String: any ParserProtocol<LegacyWindowDetectedCallbackMatcher>] = [
    "app-id": Parser(\.appIds, upcast(parseAppIds)),
    "workspace": Parser(\.workspace, upcast(parseString)),
    "app-id-regex-substring": Parser(\.appIdRegexSubstring, upcast(parseCaseInsensitiveRegex)),
    "app-name-regex-substring": Parser(\.appNameRegexSubstring, upcast(parseCaseInsensitiveRegex)),
    "window-title-regex-substring": Parser(\.windowTitleRegexSubstring, upcast(parseCaseInsensitiveRegex)),
    "during-aerospace-startup": Parser(\.duringAeroSpaceStartup, upcast(parseBool)),
]

private func upcast<T>(
    _ fun: @escaping @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<T>,
) -> @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<T?> {
    { fun($0, $1).map(Optional.init) }
}

func parseOnWindowDetectedArray(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [WindowDetectedCallback] {
    if let array = raw.asArrayOrNil {
        return array.enumerated().map { (index, raw) in parseWindowDetectedCallback(raw, backtrace + .index(index), &c) }.filterNotNil()
    } else {
        c.errors += [expectedActualTypeDiagnostic(expected: .array, actual: raw.tomlType, backtrace)]
        return []
    }
}

private func parseCaseInsensitiveRegex(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<CaseInsensitiveRegex> {
    parseString(raw, backtrace).flatMap { CaseInsensitiveRegex.new($0).toParsedConfig(backtrace) }
}

func parseAppIds(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<[String]> {
    if let rawString = raw.asStringOrNil {
        return .success([rawString])
    } else if let rawArray = raw.asArrayOrNil {
        var appIds: [String] = []
        for (index, item) in rawArray.enumerated() {
            guard let str = item.asStringOrNil else {
                return .failure(expectedActualTypeDiagnostic(expected: .string, actual: item.tomlType, backtrace + .index(index)))
            }
            appIds.append(str)
        }
        if appIds.isEmpty {
            return .failure(.init(backtrace, "The array must not be empty"))
        }
        return .success(appIds)
    } else {
        return .failure(expectedActualTypeDiagnostic(expected: [.string, .array], actual: raw.tomlType, backtrace))
    }
}

private func parseMatcher(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> WindowDetectedCallbackMatcher {
    switch raw {
        case .dict(let raw):
            return .legacy(raw.parseTable(LegacyWindowDetectedCallbackMatcher(), matcherParsers, backtrace, &c, allowEmpty: false))
        case .string(let raw):
            return .command(parseCommand(raw, allowExecAndForget: false, allowEval: false).toResult().toParsedConfig(backtrace).getOrNil(appendErrorTo: &c.errors) ?? .empty)
        default:
            // Intentionally skip Table type from the list of expected types
            c.errors.append(.init(backtrace, expectedActualTypeError(expected: .string, actual: raw.tomlType)))
            return .command(.empty)
    }
}

private func parseWindowDetectedCallback(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> WindowDetectedCallback? {
    var myContext = ConfigParserContext(configVersion: c.configVersion, errors: [], warnings: [])
    let callback = parseNonEmptyTable(raw, WindowDetectedCallback(), windowDetectedParser, backtrace, &myContext)

    if callback.matcher == .command(.empty) && !callback.checkFurtherCallbacks {
        let msg = "Omitting 'if' is error prone. You can use `if = 'true'` to preserve the previous behavior.\n" +
            "But heads up! You may have missed 'check-further-callbacks = true'"
        myContext.errors.append(.init(backtrace, msg))
    }

    if callback.rawRun == nil { // ID-46D063B2
        myContext.errors.append(.init(backtrace, "'run' is mandatory key"))
    }

    if !myContext.errors.isEmpty {
        c.errors += myContext.errors
        c.warnings += myContext.warnings
        return nil
    }

    return callback
}
