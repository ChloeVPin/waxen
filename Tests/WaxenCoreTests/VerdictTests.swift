import XCTest
@testable import WaxenCore

final class VerdictTests: XCTestCase {
    private let builder = VerdictBuilder(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)
    private let identity = "Developer ID Application: Jane Doe (ABCDE12345)"

    // MARK: - One test per kind

    func testTrustedNotarizedApp() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .accepted, gatekeeperDetail: "accepted\nsource=Notarized Developer ID",
            launchStatus: .clean
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .trusted)
        XCTAssertEqual(verdict.fact(VerdictBuilder.madeByLabel), "Jane Doe (ABCDE12345)")
        XCTAssertEqual(verdict.fact(VerdictBuilder.appleLabel), "Yes (notarized)")
        XCTAssertNil(verdict.fact(VerdictBuilder.downloadedLabel))
        XCTAssertNil(verdict.developerFix)
    }

    func testTrustedQuarantinedAppShowsDownloadSource() {
        let downloaded = Date(timeIntervalSince1970: 1_793_664_000) // 3 Nov 2026 00:00 UTC
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .accepted,
            quarantine: QuarantineInspection(present: true, flags: 0x83, timestamp: downloaded, agent: "Safari", eventIdentifier: UUID().uuidString),
            launchStatus: .clean
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .trusted)
        XCTAssertEqual(verdict.fact(VerdictBuilder.downloadedLabel), "Safari · 3 Nov 2026")
    }

    func testCautiousWhenSignedButNotNotarized() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .absent, gatekeeper: .rejected, gatekeeperDetail: "rejected\nsource=Unnotarized Developer ID",
            quarantine: QuarantineInspection(present: true, agent: "Safari"),
            extraFindings: [
                finding("gatekeeper.assessment", .failed, .blocker, action: "Inspect signature and notarization evidence"),
                finding("notarization.staple", .warning, .warning, action: "Staple the notarization ticket")
            ],
            launchStatus: .blocked
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .cautious)
        XCTAssertEqual(verdict.fact(VerdictBuilder.appleLabel), "No (not notarized)")
        XCTAssertEqual(verdict.findingID, "gatekeeper.assessment")
        XCTAssertTrue(verdict.developerFix?.hasPrefix("Staple the notarization ticket") == true, "notarization fix is preferred")
        XCTAssertTrue(verdict.userStep?.contains("Open Anyway") == true)
        XCTAssertTrue(verdict.userStep?.contains("Jane Doe") == true)
    }

    func testRejectedDespiteNotarizationIsUnknownNotCautious() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .rejected, gatekeeperDetail: "rejected",
            extraFindings: [finding("gatekeeper.assessment", .failed, .blocker)],
            launchStatus: .blocked
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .unknown)
        XCTAssertEqual(verdict.findingID, "gatekeeper.assessment")
    }

    func testUnavailableNotarizationIsNotCautious() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .unavailable, gatekeeper: .inconclusive,
            quarantine: QuarantineInspection(present: true, agent: "Safari"),
            extraFindings: [finding("notarization.staple", .unavailable, .error)],
            launchStatus: .inconclusive, inspectionStatus: .securityUnavailable
        )
        XCTAssertEqual(builder.build(from: report).kind, .unknown)
    }

    func testUnsignedQuarantinedApp() {
        let report = makeReport(
            signature: .unsigned, staple: .absent, gatekeeper: .rejected,
            quarantine: QuarantineInspection(present: true, agent: "sharingd"),
            extraFindings: [finding("signature.unsigned", .failed, .blocker, action: "Sign the completed app")],
            launchStatus: .blocked
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .unsigned)
        XCTAssertEqual(verdict.headline, "Nobody signed this app.")
        XCTAssertTrue(verdict.explanation.contains("damaged"), "explains the macOS wording")
        XCTAssertEqual(verdict.fact(VerdictBuilder.madeByLabel), "Nobody (unsigned)")
        XCTAssertEqual(verdict.fact(VerdictBuilder.downloadedLabel), "AirDrop")
        XCTAssertEqual(verdict.findingID, "signature.unsigned")
        XCTAssertTrue(verdict.developerFix?.hasPrefix("Sign the completed app") == true)
    }

    func testUnsignedArm64OnlyAppCannotRunOnAppleSilicon() {
        let report = makeReport(
            signature: .unsigned, staple: .absent, gatekeeper: .rejected,
            extraFindings: [finding("signature.unsigned", .failed, .blocker)],
            launchStatus: .blocked, arm64Only: true, appleSilicon: true
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .unsigned)
        XCTAssertEqual(verdict.headline, "Nobody signed this app.")
        XCTAssertTrue(verdict.userStep?.contains("can't run on this Mac") == true)
    }

    func testAdHocAppOffersOpenAnyway() {
        let report = makeReport(
            signature: .adHoc, staple: .absent, gatekeeper: .rejected,
            extraFindings: [finding("signature.ad-hoc", .warning, .warning, action: "Sign with Developer ID")],
            launchStatus: .blocked, arm64Only: true, appleSilicon: true
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .unsigned)
        XCTAssertEqual(verdict.fact(VerdictBuilder.madeByLabel), "Nobody (placeholder signature)")
        XCTAssertTrue(verdict.userStep?.contains("Open Anyway") == true)
        XCTAssertEqual(verdict.findingID, "signature.ad-hoc")
    }

    func testTamperedWhenSignedContentsChanged() {
        let report = makeReport(
            signature: .invalid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .rejected,
            extraFindings: [finding("signature.invalid", .failed, .blocker, action: "Re-sign the final bundle")],
            launchStatus: .blocked
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .tampered)
        XCTAssertEqual(verdict.headline, "Don't open this app.")
        XCTAssertEqual(verdict.fact(VerdictBuilder.appleLabel), "Once, but the app has changed since")
        XCTAssertTrue(verdict.explanation.contains("Jane Doe"))
        XCTAssertFalse(verdict.explanation.contains("ABCDE12345"), "prose uses the short name")
        XCTAssertEqual(verdict.findingID, "signature.invalid")
    }

    func testRevokedCertificateIsTampered() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .rejected, gatekeeperDetail: "rejected\nCSSMERR_TP_CERT_REVOKED",
            extraFindings: [finding("gatekeeper.assessment", .failed, .blocker)],
            launchStatus: .blocked
        )
        XCTAssertEqual(builder.build(from: report).kind, .tampered)
    }

    func testInvalidSignatureWithoutSigningEvidenceIsBrokenNotTampered() {
        let report = makeReport(
            signature: .invalid, staple: .absent, gatekeeper: .rejected,
            extraFindings: [finding("signature.invalid", .failed, .blocker)],
            launchStatus: .blocked, hasSignatureLoadCommand: false
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .broken)
        XCTAssertEqual(verdict.findingID, "signature.invalid")
    }

    func testBrokenBundleBeatsSignatureState() {
        let report = makeReport(
            signature: .unsigned, staple: .absent, gatekeeper: .rejected,
            extraFindings: [
                finding("bundle.executable-missing", .failed, .blocker, action: "Restore the main executable"),
                finding("signature.unsigned", .failed, .blocker)
            ],
            launchStatus: .blocked
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .broken)
        XCTAssertEqual(verdict.findingID, "bundle.executable-missing")
        XCTAssertTrue(verdict.developerFix?.hasPrefix("Restore the main executable") == true)
    }

    func testNestedPackagingProblemIsBroken() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .absent, gatekeeper: .rejected,
            extraFindings: [finding("signature.nested-unsigned", .failed, .blocker, action: "Sign all nested code")],
            launchStatus: .blocked
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .broken)
        XCTAssertEqual(verdict.findingID, "signature.nested-unsigned")
    }

    func testUnknownWhenChecksUnavailable() {
        let report = makeReport(
            signature: .unavailable, staple: .unavailable, gatekeeper: .unavailable,
            extraFindings: [finding("signature.unavailable", .unavailable, .error)],
            launchStatus: .inconclusive, inspectionStatus: .securityUnavailable
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .unknown)
        XCTAssertEqual(verdict.findingID, "signature.unavailable")
        XCTAssertNil(verdict.fact(VerdictBuilder.madeByLabel))
    }

    func testMissingTarget() {
        let report = makeReport(
            signature: .unavailable, staple: .unavailable, gatekeeper: .unavailable,
            launchStatus: .inconclusive, inspectionStatus: .targetMissing, withBundle: false
        )
        let verdict = builder.build(from: report)
        XCTAssertEqual(verdict.kind, .unknown)
        XCTAssertEqual(verdict.findingID, "target.missing")
    }

    // MARK: - Naming

    func testSignerParsing() {
        XCTAssertEqual(VerdictBuilder.signer(identity: identity, teamID: nil, state: .valid), "Jane Doe (ABCDE12345)")
        XCTAssertEqual(VerdictBuilder.signer(identity: "Apple Development: dev@example.com (TEAM1)", teamID: nil, state: .valid), "dev@example.com (TEAM1)")
        XCTAssertEqual(VerdictBuilder.signer(identity: "Software Signing", teamID: nil, state: .valid), "Apple")
        XCTAssertEqual(VerdictBuilder.signer(identity: nil, teamID: "TEAM1", state: .valid), "Team TEAM1")
        XCTAssertNil(VerdictBuilder.signer(identity: nil, teamID: nil, state: .valid))
        XCTAssertNil(VerdictBuilder.signer(identity: nil, teamID: "TEAM1", state: .adHoc))
    }

    func testShortName() {
        XCTAssertEqual(VerdictBuilder.shortName("Jane Doe (ABCDE12345)"), "Jane Doe")
        XCTAssertEqual(VerdictBuilder.shortName("Apple"), "Apple")
    }

    func testAgentNames() {
        XCTAssertEqual(VerdictBuilder.agentName("sharingd"), "AirDrop")
        XCTAssertEqual(VerdictBuilder.agentName("Firefox"), "Firefox")
        XCTAssertNil(VerdictBuilder.agentName("  "))
    }

    // MARK: - Share

    func testShareContainsNoFullPaths() {
        let report = makeReport(
            signature: .invalid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .rejected,
            extraFindings: [finding("signature.invalid", .failed, .blocker, action: "Re-sign the final bundle")],
            launchStatus: .blocked,
            path: "/Users/someone/Downloads/My_App.app"
        )
        let share = ReportRenderer().renderShare(report, builder: builder)
        XCTAssertFalse(share.contains("/Users/someone"))
        XCTAssertTrue(share.contains("**My\\_App.app**"))
        XCTAssertTrue(share.contains("- **Verdict:** `tampered`"))
        XCTAssertTrue(share.contains("- **Finding:** `signature.invalid`"))
        XCTAssertTrue(share.contains("**For the developer:** Re-sign the final bundle"))
    }

    func testVerdictRenderingIncludesFactsAndStep() {
        let report = makeReport(
            signature: .valid, identity: identity, teamID: "ABCDE12345",
            staple: .valid, gatekeeper: .accepted, launchStatus: .clean
        )
        let text = ReportRenderer().renderVerdict(report, builder: builder)
        XCTAssertTrue(text.hasPrefix("✓ This app checks out."))
        XCTAssertTrue(text.contains("Made by           Jane Doe (ABCDE12345)"))
        XCTAssertTrue(text.contains("→ "))
        XCTAssertFalse(text.contains("If you made this app"), "no developer line when nothing is wrong")
    }

    // MARK: - Helpers

    private func finding(_ id: String, _ status: FindingStatus, _ severity: Severity, action: String? = nil) -> Finding {
        Finding(
            id: id,
            status: status,
            severity: severity,
            confidence: .confirmed,
            title: id,
            explanation: id,
            suggestedActions: action.map { [SuggestedAction(id: id, title: $0, detail: "Detail.")] } ?? []
        )
    }

    private func makeReport(
        signature state: SignatureState,
        identity: String? = nil,
        teamID: String? = nil,
        staple: StapleStatus,
        gatekeeper: AssessmentResult,
        gatekeeperDetail: String? = nil,
        quarantine: QuarantineInspection = QuarantineInspection(present: false),
        extraFindings: [Finding] = [],
        launchStatus: LaunchStatus,
        inspectionStatus: InspectionStatus = .complete,
        withBundle: Bool = true,
        arm64Only: Bool = false,
        appleSilicon: Bool = true,
        hasSignatureLoadCommand: Bool = true,
        path: String = "/Applications/Example.app"
    ) -> DiagnosticReport {
        let security = SecurityInspection(
            signature: SignatureInspection(state: state, identity: identity, teamID: teamID),
            notarization: NotarizationInspection(staple: staple),
            gatekeeper: GatekeeperInspection(result: gatekeeper, detail: gatekeeperDetail),
            quarantine: quarantine
        )
        let macho = MachOInspection(
            path: path + "/Contents/MacOS/Example",
            format: .thin,
            isMachO: true,
            isMalformed: false,
            architectures: arm64Only ? ["arm64"] : ["arm64", "x86_64"],
            supportsArm64: true,
            supportsX86_64: !arm64Only,
            minimumOSVersion: "13.0",
            sdkVersion: "15.0",
            hasCodeSignatureLoadCommand: hasSignatureLoadCommand,
            codeSignatureRangeValid: hasSignatureLoadCommand,
            slices: [],
            error: nil
        )
        let bundle = BundleInspection(
            bundlePath: path,
            infoPlistPath: path + "/Contents/Info.plist",
            infoPlistReadable: true,
            infoPlistValid: true,
            bundleIdentifier: "com.example.app",
            executableName: "Example",
            executablePath: path + "/Contents/MacOS/Example",
            executableExists: true,
            executableIsRegularFile: true,
            executableReadable: true,
            macho: macho,
            security: security
        )
        let primary = extraFindings.first { $0.status == .failed && $0.severity == .blocker }
        return DiagnosticReport(
            target: TargetInspection(
                inputPath: path,
                resolvedPath: path,
                kind: withBundle ? .applicationBundle : .missing,
                exists: withBundle,
                isDirectory: withBundle,
                isReadable: withBundle
            ),
            environment: EnvironmentInfo(operatingSystem: "Version 26.1", hostArchitecture: appleSilicon ? "arm64" : "x86_64", appleSilicon: appleSilicon),
            inspectionStatus: inspectionStatus,
            launchStatus: launchStatus,
            bundle: withBundle ? bundle : nil,
            findings: extraFindings,
            diagnosis: Diagnosis(
                classification: launchStatus == .blocked ? .confirmedBlocker : launchStatus == .clean ? .clean : .inconclusive,
                primaryFindingID: primary?.id,
                summary: "Summary.",
                confidence: .high
            ),
            evidence: []
        )
    }
}
