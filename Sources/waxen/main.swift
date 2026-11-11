import Darwin
import Foundation
import WaxenCore

let parser = CLIParser()

func writeOut(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

func writeErr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

func colorEnabled(_ options: CLIOptions) -> Bool {
    guard !options.noColor, isatty(STDOUT_FILENO) == 1 else { return false }
    let environment = ProcessInfo.processInfo.environment
    if environment["NO_COLOR"] != nil { return false }
    return environment["TERM"] != "dumb"
}

func runFinder(_ action: FinderActionCommand) -> Never {
    let finder = FinderAction()
    do {
        switch action {
        case .install:
            let executable = FinderAction.resolveExecutablePath()
            try finder.install(waxenPath: executable)
            FinderAction.refreshServices()
            writeOut("""
            Added "\(FinderAction.menuTitle)" to Finder.

              Right-click an app, .dmg, or .pkg → Quick Actions → \(FinderAction.menuTitle)

            It runs \(executable) and only reads the file you pick.
            If it isn't in the menu yet, relaunch Finder: killall Finder
            Remove it any time with: waxen finder uninstall

            """)
        case .uninstall:
            let removed = try finder.uninstall()
            if removed { FinderAction.refreshServices() }
            writeOut(removed ? "Removed \"\(FinderAction.menuTitle)\" from Finder.\n" : "Nothing to remove. The Quick Action isn't installed.\n")
        }
        exit(WaxenExitCode.ok.rawValue)
    } catch {
        writeErr("waxen: \(error)\n")
        exit(WaxenExitCode.cantCreate.rawValue)
    }
}

do {
    let options = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    if case let .finder(action) = options.command {
        runFinder(action)
    }
    let report = DiagnosticPipeline().diagnose(path: options.path)
    if options.alert {
        // Finder shows a generic error for any nonzero exit, so the alert
        // itself carries the result and the process exits cleanly.
        if case let .unavailable(reason) = VerdictAlert().present(report) {
            writeErr("waxen: couldn't show the alert: \(reason)\n")
            writeOut(ReportRenderer().renderVerdict(report))
        }
        exit(WaxenExitCode.ok.rawValue)
    }
    let output = try ReportRenderer().render(report, options: options, color: colorEnabled(options))
    writeOut(output)
    exit(report.exitCode.rawValue)
} catch CLIParseError.help {
    writeOut(CLIParser.usage + "\n")
    exit(WaxenExitCode.ok.rawValue)
} catch CLIParseError.version {
    writeOut("waxen \(WaxenVersion.current)\n")
    exit(WaxenExitCode.ok.rawValue)
} catch CLIParseError.missingCommand {
    writeErr(CLIParser.usage + "\n")
    exit(WaxenExitCode.usage.rawValue)
} catch let error as CLIParseError {
    writeErr("waxen: \(error.description)\n\n\(CLIParser.usage)\n")
    exit(WaxenExitCode.usage.rawValue)
} catch {
    writeErr("waxen: internal error: \(error.localizedDescription)\n")
    exit(WaxenExitCode.software.rawValue)
}
