import Foundation

/// Shows a verdict in a native macOS alert. Used by the Finder Quick Action so
/// people who never open Terminal still get the answer.
public struct VerdictAlert {
    public enum Outcome: Equatable {
        case dismissed
        case copied
        case copyFailed
        case unavailable(String)
    }

    static let copyButton = "Copy Report"
    static let doneButton = "Done"

    /// The AppleScript is fixed. Report text only ever arrives through `argv`,
    /// so nothing in an app's name or signature can be interpreted as script.
    static let script: [String] = [
        "on run argv",
        "set theTitle to item 1 of argv",
        "set theMessage to item 2 of argv",
        "activate",
        "if item 3 of argv is \"critical\" then",
        "set reply to display alert theTitle message theMessage as critical buttons {\"\(copyButton)\", \"\(doneButton)\"} default button \"\(doneButton)\"",
        "else",
        "set reply to display alert theTitle message theMessage buttons {\"\(copyButton)\", \"\(doneButton)\"} default button \"\(doneButton)\"",
        "end if",
        "return button returned of reply",
        "end run"
    ]

    private let runner: CommandRunning
    private let copy: (String) -> Bool

    public init() {
        self.init(runner: ReadOnlyCommandRunner(), copy: VerdictAlert.copyToPasteboard)
    }

    init(runner: CommandRunning, copy: @escaping (String) -> Bool) {
        self.runner = runner
        self.copy = copy
    }

    @discardableResult
    public func present(_ report: DiagnosticReport, builder: VerdictBuilder = VerdictBuilder()) -> Outcome {
        let verdict = builder.build(from: report)
        var arguments: [String] = []
        for line in Self.script {
            arguments += ["-e", line]
        }
        arguments += [
            verdict.headline,
            Self.message(for: verdict),
            verdict.kind == .tampered || verdict.kind == .broken ? "critical" : "informational"
        ]
        // A person may leave the alert open for a while; give them ten minutes.
        let result = runner.run("/usr/bin/osascript", arguments: arguments, timeout: 600)
        if let launchError = result.launchError {
            return .unavailable(launchError)
        }
        guard result.status == 0 else {
            return .unavailable(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == Self.copyButton else {
            return .dismissed
        }
        let share = ReportRenderer().renderShare(report, builder: builder)
        return copy(share) ? .copied : .copyFailed
    }

    static func message(for verdict: Verdict) -> String {
        var parts = [verdict.explanation]
        if !verdict.facts.isEmpty {
            parts.append(verdict.facts.map { "\($0.label): \($0.value)" }.joined(separator: "\n"))
        }
        if let step = verdict.userStep {
            parts.append(step)
        }
        return parts.joined(separator: "\n\n")
    }

    static func copyToPasteboard(_ text: String) -> Bool {
        #if os(macOS)
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        process.standardInput = input
        do {
            try process.run()
        } catch {
            return false
        }
        input.fileHandleForWriting.write(Data(text.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
        #else
        return false
        #endif
    }
}
