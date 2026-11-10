public struct ListAppsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listApps,
        help: list_apps_help_generated,
        flags: [
            "--macos-native-hidden": boolFlag(\.macosHidden),

            // Formatting flags
            "--format": formatParser(\._format, for: .app),
            "--count": trueBoolFlag(\.outputOnlyCount),
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [],
        conflictingFlags: [
            ["--count", "--format"],
            ["--count", "--json"],
        ],
    )

    public var macosHidden: Bool?
    public var _format: [InterToken<InterVar>] = []
    public var outputOnlyCount: Bool = false
    public var json: Bool = false
}

extension ListAppsCmdArgs {
    public var format: [InterToken<InterVar>] {
        if _format.isEmpty {
            return [
                .interVar(.formatVar(.app(.appPid))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "),
                .interVar(.formatVar(.app(.appBundleId))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "),
                .interVar(.formatVar(.app(.appName))),
            ]
        }
        if _format.contains(.interVar(.plainInterVar(.all))) {
            return AeroObjKind.app.getFormatWithAllVariable()
        }
        return _format
    }
}

func parseListAppsCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ListAppsCmdArgs> {
    parseSpecificCmdArgs(ListAppsCmdArgs(rawArgs: args), args)
        .flatMap { parsed in
            if parsed.json, let msg = getErrorIfFormatIsIncompatibleWithJson(parsed._format) {
                return .failure(msg)
            }
            if let msg = getErrorIfAllFormatVariableIsInvalid(json: parsed.json, format: parsed._format) {
                return .failure(msg)
            }
            return .cmd(parsed)
        }
}

func getErrorIfFormatIsIncompatibleWithJson(_ format: [InterToken<InterVar>]) -> String? {
    for x in format {
        switch x {
            case .interVar(.plainInterVar(.rightPadding)):
                return "%{right-padding} interpolation variable is not allowed when --json is used"
            case .interVar: break // skip
            case .literal(let literal):
                if literal.contains(where: { $0 != " " }) {
                    return "Only interpolation variables and spaces are allowed in '--format' when '--json' is used"
                }
        }
    }
    return nil
}
