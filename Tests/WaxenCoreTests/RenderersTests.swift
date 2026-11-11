import XCTest
@testable import WaxenCore

final class RenderersTests: XCTestCase {
    func testJSONRendererProducesStableTopLevelFields() throws {
        let report = makeReport()
        let options = CLIOptions(command: .diagnose, path: "Valid.app", json: true)
        let output = try ReportRenderer().render(report, options: options)

        XCTAssertTrue(output.contains("\"schemaVersion\" : \"1.0\""))
        XCTAssertTrue(output.contains("\"launchStatus\" : \"inconclusive\""))
        XCTAssertTrue(output.hasSuffix("\n"))
    }

    func testDefaultRendererPrintsVerdictNotEvidenceDump() throws {
        let report = makeReport()
        let output = try ReportRenderer().render(report, options: CLIOptions(command: .diagnose, path: "Valid.app"))

        XCTAssertFalse(output.contains("Launch status:"))
        XCTAssertTrue(output.hasPrefix("? "))
        XCTAssertTrue(output.contains("--details"))
        XCTAssertFalse(output.contains("\u{1B}["), "no ANSI codes unless color is requested")
    }

    func testVerdictColorOnlyWhenRequested() throws {
        let report = makeReport()
        let colored = try ReportRenderer().render(report, options: CLIOptions(command: .diagnose, path: "Valid.app"), color: true)
        XCTAssertTrue(colored.contains("\u{1B}["))
        let suppressed = try ReportRenderer().render(report, options: CLIOptions(command: .diagnose, path: "Valid.app", noColor: true), color: true)
        XCTAssertFalse(suppressed.contains("\u{1B}["))
    }

    func testVerboseImpliesDetails() throws {
        let output = try ReportRenderer().render(makeReport(), options: CLIOptions(command: .diagnose, path: "Valid.app", verbose: true))
        XCTAssertTrue(output.contains("Launch status: INCONCLUSIVE"))
    }

    func testWrapKeepsIndentAndWidth() {
        let lines = wrap(String(repeating: "word ", count: 40), width: 30, indent: "  ", firstPrefix: "→ ")
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("  → "))
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix("    ") })
        XCTAssertTrue(lines.allSatisfy { $0.count <= 30 })
    }

    func testShellQuoting() {
        XCTAssertEqual(shellQuoted("/Applications/Foo.app"), "/Applications/Foo.app")
        XCTAssertEqual(shellQuoted("/Applications/My App.app"), "'/Applications/My App.app'")
        XCTAssertEqual(shellQuoted("it's.app"), "'it'\\''s.app'")
    }

    func testDetailsRendererIncludesDiagnosisAndEvidence() throws {
        let report = makeReport()
        let options = CLIOptions(command: .diagnose, path: "Valid.app", details: true)
        let output = try ReportRenderer().render(report, options: options)

        XCTAssertTrue(output.contains("Launch status: INCONCLUSIVE"))
        XCTAssertTrue(output.contains("Diagnosis:"))
        XCTAssertTrue(output.contains("Evidence:"))
        XCTAssertTrue(output.contains("bundle.info-plist-valid"))
    }

    private func makeReport() -> DiagnosticReport {
        let evidence = Evidence(
            id: "bundle.info-plist-valid",
            kind: .infoPlist,
            source: "Valid.app/Contents/Info.plist",
            detail: "Info.plist is valid."
        )
        let finding = Finding(
            id: "bundle.structure-valid",
            status: .passed,
            severity: .information,
            confidence: .high,
            title: "App bundle structure is valid",
            explanation: "The bundle passed structural checks.",
            evidenceReferences: [evidence.id]
        )
        return DiagnosticReport(
            target: TargetInspection(
                inputPath: "Valid.app",
                resolvedPath: "Valid.app",
                kind: .applicationBundle,
                exists: true,
                isDirectory: true,
                isReadable: true
            ),
            inspectionStatus: .complete,
            launchStatus: .inconclusive,
            bundle: nil,
            findings: [finding],
            diagnosis: Diagnosis(
                classification: .inconclusive,
                summary: "No blocker.",
                confidence: .high
            ),
            evidence: [evidence]
        )
    }
}
