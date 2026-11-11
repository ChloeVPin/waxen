import XCTest
@testable import WaxenCore

final class VerdictAlertTests: XCTestCase {
    private final class RecordingRunner: CommandRunning {
        var calls: [(String, [String])] = []
        let reply: CommandResult

        init(reply: CommandResult) {
            self.reply = reply
        }

        func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
            calls.append((executable, arguments))
            return reply
        }
    }

    func testReportTextTravelsAsArgumentsNotScript() throws {
        let runner = RecordingRunner(reply: CommandResult(status: 0, stdout: "Done\n", stderr: "", launchError: nil))
        let outcome = VerdictAlert(runner: runner, copy: { _ in XCTFail("should not copy"); return false })
            .present(makeReport(path: "/tmp/\"; do shell script \"rm -rf ~\".app", status: .targetMissing))

        XCTAssertEqual(outcome, .dismissed)
        let (executable, arguments) = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(executable, "/usr/bin/osascript")
        let scriptLines = stride(from: 1, to: VerdictAlert.script.count * 2, by: 2).map { arguments[$0] }
        XCTAssertEqual(scriptLines, VerdictAlert.script, "the AppleScript is fixed")
        let argv = Array(arguments.suffix(3))
        XCTAssertTrue(argv[1].contains("rm -rf"), "hostile names only appear as data")
        XCTAssertEqual(argv[2], "informational")
    }

    func testCopyButtonCopiesShareText() {
        let runner = RecordingRunner(reply: CommandResult(status: 0, stdout: "Copy Report\n", stderr: "", launchError: nil))
        var copied: String?
        let outcome = VerdictAlert(runner: runner, copy: { copied = $0; return true }).present(makeReport(path: "/Users/someone/Example.app"))
        XCTAssertEqual(outcome, .copied)
        XCTAssertTrue(copied?.hasPrefix("### waxen:") == true)
        XCTAssertFalse(copied?.contains("/Users/someone") == true)
    }

    func testLaunchFailureIsReported() {
        let runner = RecordingRunner(reply: CommandResult(status: -1, stdout: "", stderr: "", launchError: "nope"))
        XCTAssertEqual(VerdictAlert(runner: runner, copy: { _ in true }).present(makeReport(path: "/x.app")), .unavailable("nope"))
    }

    private func makeReport(path: String, status: InspectionStatus = .complete) -> DiagnosticReport {
        DiagnosticReport(
            target: TargetInspection(inputPath: path, resolvedPath: path, kind: .applicationBundle, exists: true, isDirectory: true, isReadable: true),
            inspectionStatus: status,
            launchStatus: .inconclusive,
            bundle: nil,
            findings: [],
            diagnosis: Diagnosis(classification: .inconclusive, summary: "Summary.", confidence: .low),
            evidence: []
        )
    }
}
