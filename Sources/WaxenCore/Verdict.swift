import Foundation

/// The plain-language answer waxen gives first.
///
/// A verdict is derived from a finished `DiagnosticReport`. It never changes
/// findings or diagnosis semantics; it only decides how to say them to a
/// person who saw a macOS warning and wants to know whether it is real.
public enum VerdictKind: String, Codable, CaseIterable {
    /// Signed, unchanged, and accepted by Gatekeeper.
    case trusted
    /// Signed and unchanged, but macOS will not open it without the user's say-so.
    case cautious
    /// Nobody signed it (or it is ad hoc signed), so macOS cannot tell who made it.
    case unsigned
    /// The signature no longer matches the contents, or Apple revoked it.
    case tampered
    /// The app is structurally broken or packaged incorrectly.
    case broken
    /// waxen could not check enough to answer.
    case unknown
}

public struct VerdictFact: Equatable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct Verdict: Equatable {
    public let kind: VerdictKind
    public let appName: String
    public let headline: String
    public let explanation: String
    public let facts: [VerdictFact]
    /// What the person holding the app can do, using only Apple-supported paths.
    public let userStep: String?
    /// What the person who built the app should change.
    public let developerFix: String?
    /// The finding that decided the verdict, for issue reports and CI.
    public let findingID: String?

    public init(
        kind: VerdictKind,
        appName: String,
        headline: String,
        explanation: String,
        facts: [VerdictFact] = [],
        userStep: String? = nil,
        developerFix: String? = nil,
        findingID: String? = nil
    ) {
        self.kind = kind
        self.appName = appName
        self.headline = headline
        self.explanation = explanation
        self.facts = facts
        self.userStep = userStep
        self.developerFix = developerFix
        self.findingID = findingID
    }

    public func fact(_ label: String) -> String? {
        facts.first { $0.label == label }?.value
    }
}

public struct VerdictBuilder {
    public static let madeByLabel = "Made by"
    public static let appleLabel = "Checked by Apple"
    public static let downloadedLabel = "Downloaded"

    private let locale: Locale
    private let timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    public func build(from report: DiagnosticReport) -> Verdict {
        let name = appName(report)
        let security = report.bundle?.security
        let signature = security?.signature
        let blockers = report.findings.filter { $0.status == .failed && $0.severity == .blocker }
        let blockerIDs = Set(blockers.map(\.id))
        let maker = Self.signer(identity: signature?.identity, teamID: signature?.teamID, state: signature?.state)
        let shortMaker = maker.flatMap(Self.shortName)
        let facts = buildFacts(report, maker: maker)
        let quarantined = security?.quarantine.present == true ||
            report.findings.contains { $0.id == "container.quarantine" }
        let gatekeeperDetail = security?.gatekeeper.detail ?? ""

        // Input problems: there is no app to judge.
        switch report.inspectionStatus {
        case .targetMissing:
            return Verdict(
                kind: .unknown,
                appName: name,
                headline: "There's nothing at that path.",
                explanation: "waxen couldn't find \(name). Check the spelling, or drag the file into the terminal to paste its path.",
                findingID: "target.missing"
            )
        case .invalidTarget where report.bundle == nil:
            if blockerIDs.contains("container.no-app") || report.findings.contains(where: { $0.id == "container.no-app" }) {
                return Verdict(
                    kind: .broken,
                    appName: name,
                    headline: "There's no app inside this.",
                    explanation: "waxen opened \(name) but found no .app inside it.",
                    facts: facts,
                    developerFix: developerFix(report, preferring: ["container.no-app"]),
                    findingID: "container.no-app"
                )
            }
            return Verdict(
                kind: .unknown,
                appName: name,
                headline: "That isn't something waxen can check.",
                explanation: "waxen checks apps (.app), disk images (.dmg), and installer packages (.pkg).",
                findingID: report.diagnosis.primaryFindingID
            )
        case .permissionLimited:
            return Verdict(
                kind: .unknown,
                appName: name,
                headline: "waxen isn't allowed to read this.",
                explanation: "macOS blocked waxen from reading part of \(name), so it can't give a full answer. Try copying the app somewhere you own, like your Desktop, and check the copy.",
                facts: facts,
                findingID: report.diagnosis.primaryFindingID
            )
        default:
            break
        }

        // 1. Contents changed after signing, or Apple pulled the certificate.
        if gatekeeperDetail.localizedCaseInsensitiveContains("revoked") {
            return Verdict(
                kind: .tampered,
                appName: name,
                headline: "Don't open this app.",
                explanation: "Apple has revoked the certificate \(name) was signed with. That usually means Apple found a problem with the developer or with this software.",
                facts: facts,
                userStep: "Move it to the Trash. If you need this app, ask the developer what happened.",
                developerFix: developerFix(report, preferring: ["gatekeeper.assessment"]),
                findingID: "gatekeeper.assessment"
            )
        }
        // "Changed after signing" is only honest when there is evidence the app
        // was signed in the first place. An unreadable executable that codesign
        // rejects outright is a broken app, not a tampered one.
        let wasSigned = signature?.identity != nil || signature?.teamID != nil ||
            report.bundle?.macho?.hasCodeSignatureLoadCommand == true
        if blockerIDs.contains("signature.invalid"), !wasSigned {
            return Verdict(
                kind: .broken,
                appName: name,
                headline: "This app is broken. It won't open.",
                explanation: "macOS can't read the program file inside \(name) well enough to check it. It may be incomplete, corrupted, or not a Mac program at all.",
                facts: facts,
                userStep: "Download it again. If the new copy says the same thing, tell the developer.",
                developerFix: developerFix(report, preferring: ["signature.invalid"]),
                findingID: "signature.invalid"
            )
        }
        if let tamperID = ["signature.invalid", "signature.nested-invalid"].first(where: blockerIDs.contains) {
            let who = shortMaker ?? "its developer"
            return Verdict(
                kind: .tampered,
                appName: name,
                headline: "Don't open this app.",
                explanation: "\(name) no longer matches what \(who) signed. Something inside it changed after signing: a damaged download, a bad build, or tampering. waxen can't tell which.",
                facts: facts,
                userStep: "Delete it and download a fresh copy from \(shortMaker.map { "\($0)'s" } ?? "the developer's") own website.",
                developerFix: developerFix(report, preferring: [tamperID]),
                findingID: tamperID
            )
        }

        // 2. Structurally broken: no amount of trust makes this run.
        let structural = blockers.first { finding in
            ["bundle.", "macho.", "container.", "target."].contains { finding.id.hasPrefix($0) }
        }
        if let structural {
            return Verdict(
                kind: .broken,
                appName: name,
                headline: "This app is broken. It won't open.",
                explanation: Self.plainStructuralReason(structural, name: name),
                facts: facts,
                userStep: "Download it again. If the new copy says the same thing, tell the developer.",
                developerFix: developerFix(report, preferring: [structural.id]),
                findingID: structural.id
            )
        }

        // 3. Nobody vouched for it.
        if let signature, signature.state == .unsigned || signature.state == .adHoc {
            let adHoc = signature.state == .adHoc
            let arm64Only = report.bundle?.macho.map { $0.supportsArm64 && !$0.supportsX86_64 } ?? false
            let headline = "Nobody signed this app."
            var explanation = adHoc
                ? "\(name) has a placeholder signature with no developer name on it, so macOS can't tell who made it."
                : "\(name) has no signature at all, so macOS can't tell who made it or check that nothing changed."
            if quarantined {
                explanation += " macOS calls unsigned downloads \"damaged\". Open-source and hobby apps are often unsigned. A missing signature says nothing about whether the app is safe."
            } else {
                explanation += " Open-source and hobby apps are often unsigned. A missing signature says nothing about whether the app is safe."
            }
            let step: String
            if !adHoc && arm64Only && report.environment.appleSilicon {
                step = "It can't run on this Mac until its developer signs it. Ask them for a signed build."
            } else {
                step = "Only open it if you trust where you got it. Try opening it once, then go to System Settings → Privacy & Security and click Open Anyway."
            }
            return Verdict(
                kind: .unsigned,
                appName: name,
                headline: headline,
                explanation: explanation,
                facts: facts,
                userStep: step,
                developerFix: developerFix(report, preferring: [adHoc ? "signature.ad-hoc" : "signature.unsigned"]),
                findingID: adHoc ? "signature.ad-hoc" : "signature.unsigned"
            )
        }

        // 4. Signed, but the pieces don't agree with each other.
        if let packagingID = ["signature.nested-unsigned", "signature.team-id-mismatch"].first(where: blockerIDs.contains) {
            return Verdict(
                kind: .broken,
                appName: name,
                headline: "This app wasn't put together correctly.",
                explanation: "Parts inside \(name) weren't signed the same way as the app itself, so macOS won't trust the whole thing. The developer has to fix this in their build.",
                facts: facts,
                userStep: "Tell the developer. There's nothing safe you can change on your side.",
                developerFix: developerFix(report, preferring: [packagingID]),
                findingID: packagingID
            )
        }

        // 5. Signed and intact, but Apple never checked it.
        let gatekeeperRejected = security?.gatekeeper.result == .rejected
        let stapleValid = security?.notarization.staple == .valid
        let gatekeeperAccepted = security?.gatekeeper.result == .accepted
        let noTicket = security?.notarization.staple == .absent || security?.notarization.staple == .invalid
        if signature?.state == .valid, gatekeeperRejected, stapleValid {
            return Verdict(
                kind: .unknown,
                appName: name,
                headline: "macOS rejected this app, and waxen can't tell why.",
                explanation: "\(name) is signed by \(shortMaker ?? "its developer") and notarized by Apple, but Gatekeeper still said no. That can mean a policy on this Mac or a problem waxen doesn't recognize yet. The details show exactly what Gatekeeper reported.",
                facts: facts,
                developerFix: developerFix(report, preferring: ["gatekeeper.assessment"]),
                findingID: "gatekeeper.assessment"
            )
        }
        if signature?.state == .valid, (gatekeeperRejected && !stapleValid) || (noTicket && quarantined && !gatekeeperAccepted) {
            let who = shortMaker ?? "a developer"
            return Verdict(
                kind: .cautious,
                appName: name,
                headline: "Apple hasn't checked this app.",
                explanation: "\(name) is signed by \(who) and hasn't changed since. It isn't notarized, so Apple never scanned it for malware and macOS won't open it with a double-click.",
                facts: facts,
                userStep: "If you trust \(who): try opening it once, then go to System Settings → Privacy & Security and click Open Anyway.",
                developerFix: developerFix(report, preferring: ["notarization.staple", "gatekeeper.assessment"]),
                findingID: gatekeeperRejected ? "gatekeeper.assessment" : "notarization.staple"
            )
        }

        // 6. Everything checked out.
        if report.launchStatus == .clean {
            var explanation = "\(name) is signed by \(shortMaker ?? "its developer"), hasn't changed since, and macOS accepts it."
            if gatekeeperDetail.localizedCaseInsensitiveContains("source=Apple System") {
                explanation = "\(name) is part of macOS, signed by Apple, and hasn't changed."
            } else if stapleValid || gatekeeperDetail.localizedCaseInsensitiveContains("notarized developer id") {
                explanation = "\(name) is signed by \(shortMaker ?? "its developer"), hasn't changed since, and Apple checked it for malware."
            }
            var step = "If it still won't open, the problem is inside the app. Contact the developer."
            if quarantined {
                step = "macOS may ask once because it was downloaded. That's normal: click Open. " + step
            }
            return Verdict(
                kind: .trusted,
                appName: name,
                headline: "This app checks out.",
                explanation: explanation,
                facts: facts,
                userStep: step,
                findingID: report.diagnosis.primaryFindingID
            )
        }

        // 7. Not enough evidence to say.
        let reason = report.findings.first { $0.status == .unavailable || $0.status == .inconclusive }
        return Verdict(
            kind: .unknown,
            appName: name,
            headline: "waxen couldn't check everything.",
            explanation: reason.map { "Some checks didn't return a result (\($0.title.lowercased())). Run with --details to see which." }
                ?? "Some checks didn't return a result. Run with --details to see which.",
            facts: facts,
            developerFix: nil,
            findingID: reason?.id ?? report.diagnosis.primaryFindingID
        )
    }

    // MARK: - Facts

    private func buildFacts(_ report: DiagnosticReport, maker: String?) -> [VerdictFact] {
        var facts: [VerdictFact] = []
        guard let security = report.bundle?.security else { return facts }

        switch security.signature.state {
        case .unsigned:
            facts.append(VerdictFact(label: Self.madeByLabel, value: "Nobody (unsigned)"))
        case .adHoc:
            facts.append(VerdictFact(label: Self.madeByLabel, value: "Nobody (placeholder signature)"))
        case .valid, .invalid:
            if let maker {
                facts.append(VerdictFact(label: Self.madeByLabel, value: maker))
            }
        case .unavailable, .inconclusive:
            break
        }

        if let apple = Self.appleCheck(security) {
            facts.append(VerdictFact(label: Self.appleLabel, value: apple))
        }

        if let downloaded = downloaded(security.quarantine) {
            facts.append(VerdictFact(label: Self.downloadedLabel, value: downloaded))
        } else if report.findings.contains(where: { $0.id == "container.quarantine" }) {
            facts.append(VerdictFact(label: Self.downloadedLabel, value: "Yes"))
        }
        return facts
    }

    static func appleCheck(_ security: SecurityInspection) -> String? {
        let detail = security.gatekeeper.detail ?? ""
        if detail.localizedCaseInsensitiveContains("source=Mac App Store") {
            return "Yes (Mac App Store)"
        }
        if detail.localizedCaseInsensitiveContains("source=Apple System") {
            return "Yes (part of macOS)"
        }
        if security.signature.state == .invalid,
           security.notarization.staple == .valid || detail.localizedCaseInsensitiveContains("notarized") {
            return "Once, but the app has changed since"
        }
        if security.notarization.staple == .valid || detail.localizedCaseInsensitiveContains("source=Notarized") {
            return "Yes (notarized)"
        }
        if detail.localizedCaseInsensitiveContains("Unnotarized") {
            return "No (not notarized)"
        }
        switch security.notarization.staple {
        case .absent where security.gatekeeper.result == .accepted:
            return "Accepted by Gatekeeper"
        case .absent, .invalid:
            return "No"
        case .unavailable, .inconclusive:
            return security.gatekeeper.result == .accepted ? "Accepted by Gatekeeper" : "Couldn't tell"
        case .valid:
            return "Yes (notarized)"
        }
    }

    private func downloaded(_ quarantine: QuarantineInspection) -> String? {
        guard quarantine.present else { return nil }
        let agent = quarantine.agent.flatMap(Self.agentName)
        let date = quarantine.timestamp.map(formatDate)
        switch (agent, date) {
        case let (agent?, date?): return "\(agent) · \(date)"
        case let (agent?, nil): return agent
        case let (nil, date?): return date
        case (nil, nil): return "Yes"
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return formatter.string(from: date)
    }

    // MARK: - Naming

    static func agentName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let known: [String: String] = [
            "sharingd": "AirDrop",
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Google Chrome",
            "org.mozilla.firefox": "Firefox",
            "com.apple.mail": "Mail",
            "com.apple.Messages": "Messages"
        ]
        return known[trimmed] ?? trimmed
    }

    /// `Developer ID Application: Jane Doe (ABCDE12345)` → `Jane Doe (ABCDE12345)`.
    public static func signer(identity: String?, teamID: String?, state: SignatureState?) -> String? {
        if let identity, !identity.isEmpty {
            switch identity {
            case "Software Signing", "macOS Software Signing", "Apple Software Signing":
                return "Apple"
            case "Apple Mac OS Application Signing":
                return "Mac App Store developer\(teamID.map { " (\($0))" } ?? "")"
            default:
                break
            }
            if let separator = identity.range(of: ": ") {
                let name = String(identity[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
            return identity
        }
        if let teamID, !teamID.isEmpty, state != .adHoc {
            return "Team \(teamID)"
        }
        return nil
    }

    /// `Jane Doe (ABCDE12345)` → `Jane Doe`, for use inside sentences.
    static func shortName(_ signer: String) -> String {
        guard signer.hasSuffix(")"), let open = signer.range(of: " (", options: .backwards) else {
            return signer
        }
        let short = String(signer[..<open.lowerBound])
        return short.isEmpty ? signer : short
    }

    private func appName(_ report: DiagnosticReport) -> String {
        let path = report.bundle?.bundlePath
            ?? report.container?.nestedApplicationPath
            ?? report.target.resolvedPath
            ?? report.target.inputPath
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    static func plainStructuralReason(_ finding: Finding, name: String) -> String {
        switch finding.id {
        case "macho.not-mach-o", "macho.malformed":
            return "The program file inside \(name) isn't a valid Mac program. It may be incomplete or corrupted."
        case "macho.code-signature-range-invalid":
            return "The signature data inside \(name)'s program file is corrupted."
        case "bundle.executable-missing", "bundle.executable-not-regular-file":
            return "\(name) is missing the program file it says it runs. The download or copy is incomplete."
        case "bundle.contents-missing", "bundle.contents-not-directory":
            return "\(name) is just an empty shell. Its Contents folder is missing."
        case "bundle.info-plist-missing", "bundle.info-plist-invalid", "bundle.info-plist-not-regular-file":
            return "\(name) is missing or has a broken Info.plist, the file that tells macOS what the app is."
        case "container.no-app":
            return "There's no app inside \(name)."
        default:
            return "Part of \(name) is missing or malformed: \(finding.title.prefix(1).lowercased() + finding.title.dropFirst())."
        }
    }

    private func developerFix(_ report: DiagnosticReport, preferring ids: [String]) -> String? {
        let ordered = ids.compactMap { id in report.findings.first { $0.id == id } } +
            report.findings.filter { $0.status == .failed || $0.status == .warning }
        guard let action = ordered.lazy.compactMap(\.suggestedActions.first).first else { return nil }
        let detail = action.detail.trimmingCharacters(in: .whitespaces)
        return detail.isEmpty ? action.title : "\(action.title). \(detail)"
    }
}
