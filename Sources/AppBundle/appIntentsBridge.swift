import AppKit
import Common

/// Entry point for the App Intents layer (Shortcuts, Spotlight, Focus filters).
///
/// Intents deliberately reuse the exact parse -> run path as the CLI and the socket server, rather
/// than defining their own action vocabulary. There is no second command surface to keep in sync:
/// anything you can type in a terminal works in a Shortcut, and every future command is exposed for
/// free without touching this file.
///
/// Returns the command's stdout on success, or a human-readable message on failure — App Intents
/// surfaces the failure text directly in the Shortcuts UI, so it has to read like a sentence.
@MainActor
public func runAeroSpaceCommandFromAppIntent(_ rawCommand: String) async -> Result<String, String> {
    // Same rationale as the socket server: exec-and-forget would turn any Shortcut into arbitrary
    // shell execution routed through us. Shortcuts already ships "Run Shell Script" for that.
    if rawCommand.trimmingCharacters(in: .whitespaces).starts(with: "exec-and-forget") {
        return .failure("exec-and-forget is not available from Shortcuts. Use the built-in \"Run Shell Script\" action instead.")
    }
    let shell: Shell<any Command>
    switch parseCommand(rawCommand, allowExecAndForget: false, allowEval: false) {
        case .help(let help): return .success(help)
        case .failure(let err): return .failure(err.msg)
        case .cmd(let parsed): shell = parsed
    }
    let singleCommand: (any Command)? = if case .cmd(let it) = shell { it } else { nil }
    guard let token: RunSessionGuard = .isServerEnabled(orIsEnableCommand: singleCommand) else {
        return .failure("\(aeroSpaceAppName) is disabled and doesn't accept commands. Run '\(aeroSpaceCliName) enable on' to enable it.")
    }
    let result: Result<CmdResult, Error> = await Result {
        try await runLightSession(.appIntent(rawCommand), token) {
            await shell.run(.defaultEnv, .emptyStdin)
        }
    }
    switch result {
        case .success(let cmdResult) where cmdResult.exitCode.rawValue == 0:
            return .success(cmdResult.stdout.joined(separator: "\n"))
        case .success(let cmdResult):
            let stderr = cmdResult.stderr.joined(separator: "\n")
            return .failure(stderr.isEmpty ? "'\(rawCommand)' failed with exit code \(cmdResult.exitCode.rawValue)" : stderr)
        case .failure(let err):
            return .failure("Failed to run '\(rawCommand)'. \(err.localizedDescription)")
    }
}

/// Workspace names offered as suggestions in the Shortcuts and Focus filter UI.
@MainActor
public func appIntentWorkspaceSuggestions() -> [String] {
    Workspace.all.map(\.name)
}
