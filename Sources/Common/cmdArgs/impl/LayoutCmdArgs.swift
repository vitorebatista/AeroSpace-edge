public struct LayoutCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .layout,
        allowInConfig: true,
        help: layout_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
            "--root": trueBoolFlag(\.root),
            "--for-next-detected-window": trueBoolFlag(\.forNextDetectedWindow),
        ],
        posArgs: [newMandatoryPosArgParser(\.toggleBetween, parseToggleBetween, placeholder: LayoutDescription.unionLiteral)],
        conflictingOptions: [
            ["--root", "--window-id"],

            // todo introduce a flagsAllowlist primitive
            ["--for-next-detected-window", "--window-id"],
            ["--for-next-detected-window", "--root"],
        ],
    )

    public var toggleBetween: Lateinit<[LayoutDescription]> = .uninitialized
    public var root: Bool = false
    public var forNextDetectedWindow: Bool = false

    public init(rawArgs: [String], toggleBetween: [LayoutDescription], root: Bool = false) {
        self.commonState = .init(rawArgs.slice)
        self.toggleBetween = .initialized(toggleBetween)
        self.root = root
    }

    public enum LayoutDescription: String, CaseIterable, Equatable, Sendable, AeroAny {
        case accordion, tiles
        case horizontal, vertical
        case h_accordion, v_accordion, h_tiles, v_tiles
        case tiling, floating
        case sticky
    }
}

public let layoutCommandForNextDetectedWindowFlagIncompatibilityMsg =
    "layout command: --for-next-detected-window allows only one tiling|floating <target-layout> argument"

private func parseToggleBetween(input: PosArgParserInput) -> ParsedCliArgs<[LayoutCmdArgs.LayoutDescription]> {
    let args = input.nonFlagArgs()

    var result: [LayoutCmdArgs.LayoutDescription] = []
    var i = 0
    for arg in args {
        if let layout = arg.parseLayoutDescription() {
            result.append(layout)
        } else {
            return .fail(
                "Can't parse '\(arg)'\nPossible values: \(LayoutCmdArgs.LayoutDescription.unionLiteral)",
                advanceBy: i + 1,
            )
        }
        i += 1
    }

    return .succ(result, advanceBy: args.count)
}

func parseLayoutCmdArgs(_ args: StrArrSlice) -> ParsedCmd<LayoutCmdArgs> {
    parseSpecificCmdArgs(LayoutCmdArgs(rawArgs: args), args).map {
        check(!$0.toggleBetween.val.isEmpty)
        return $0
    }
    .filterNot("'tiling' and 'floating' are incompatible with --root") {
        $0.root && $0.toggleBetween.val.contains(where: { $0 == .tiling || $0 == .floating })
    }
    .filter(layoutCommandForNextDetectedWindowFlagIncompatibilityMsg) { cmdArgs in
        !cmdArgs.forNextDetectedWindow || true == cmdArgs.toggleBetween.val.singleOrNil()?.then {
            switch $0 {
                case .floating, .tiling: true
                case .accordion, .h_accordion, .h_tiles,
                     .horizontal, .tiles, .v_accordion, .v_tiles,
                     .vertical, .sticky: false
            }
        }
    }
}

extension String {
    fileprivate func parseLayoutDescription() -> LayoutCmdArgs.LayoutDescription? {
        if let parsed = LayoutCmdArgs.LayoutDescription(rawValue: self) {
            return parsed
        } else if self == "list" {
            return .tiles
        } else if self == "h_list" {
            return .h_tiles
        } else if self == "v_list" {
            return .v_tiles
        }
        return nil
    }
}
