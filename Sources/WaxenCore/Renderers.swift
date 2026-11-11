import Foundation

public struct ReportRenderer {
    public init() {}

    public func render(_ report: DiagnosticReport, options: CLIOptions, color: Bool = false) throws -> String {
        if options.json {
            return try renderJSON(report)
        }
        if options.share {
            return renderShare(report)
        }
        if options.command == .evidence || options.details || options.verbose {
            return renderText(report, verbose: options.verbose, noColor: options.noColor, evidenceOnly: options.command == .evidence)
        }
        return renderVerdict(report, color: color && !options.noColor)
    }

    // MARK: - Verdict

    /// The default view: one answer a non-developer can act on.
    public func renderVerdict(
        _ report: DiagnosticReport,
        color: Bool = false,
        builder: VerdictBuilder = VerdictBuilder()
    ) -> String {
        let verdict = builder.build(from: report)
        let style = TerminalStyle(enabled: color)
        var lines: [String] = []

        lines.append("\(style.glyph(verdict.kind)) \(style.bold(verdict.headline))")
        lines.append("")
        lines.append(contentsOf: wrap(verdict.explanation, indent: "  "))

        if !verdict.facts.isEmpty {
            lines.append("")
            let width = verdict.facts.map(\.label.count).max() ?? 0
            for fact in verdict.facts {
                let label = fact.label.padding(toLength: width, withPad: " ", startingAt: 0)
                lines.append("  \(style.dim(label))  \(fact.value)")
            }
        }

        if let step = verdict.userStep {
            lines.append("")
            lines.append(contentsOf: wrap(step, indent: "  ", firstPrefix: "→ "))
        }

        if let fix = verdict.developerFix, verdict.kind != .trusted, verdict.kind != .unknown {
            lines.append("")
            lines.append(contentsOf: wrap("If you made this app: \(fix)", indent: "  ").map(style.dim))
        }

        if report.target.exists {
            lines.append("")
            lines.append(style.dim("  Evidence: waxen \(shellQuoted(report.target.inputPath)) --details"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Share

    /// Markdown for a GitHub issue or chat. Contains file names, never full paths.
    public func renderShare(_ report: DiagnosticReport, builder: VerdictBuilder = VerdictBuilder()) -> String {
        let verdict = builder.build(from: report)
        var lines: [String] = []
        lines.append("### waxen: \(verdict.headline)")
        lines.append("")
        var subject = "**\(markdownEscaped(verdict.appName))**"
        if report.container != nil {
            let containerName = URL(fileURLWithPath: report.target.inputPath).lastPathComponent
            if containerName != verdict.appName {
                subject += " (inside \(markdownEscaped(containerName)))"
            }
        }
        lines.append(subject)
        lines.append("")
        lines.append(markdownEscaped(verdict.explanation))
        lines.append("")
        lines.append("- **Verdict:** `\(verdict.kind.rawValue)`")
        for fact in verdict.facts {
            lines.append("- **\(fact.label):** \(markdownEscaped(fact.value))")
        }
        if let findingID = verdict.findingID {
            lines.append("- **Finding:** `\(findingID)`")
        }
        if let fix = verdict.developerFix, verdict.kind != .trusted {
            lines.append("")
            lines.append("**For the developer:** \(fix)")
        }
        lines.append("")
        lines.append("<sub>waxen \(report.toolVersion) · macOS \(report.environment.operatingSystem) · \(report.environment.hostArchitecture)</sub>")
        return lines.joined(separator: "\n") + "\n"
    }

    public func renderJSON(_ report: DiagnosticReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let output = String(data: data, encoding: .utf8) else {
            throw RendererError.encodingFailed
        }
        return output + "\n"
    }

    public func renderText(
        _ report: DiagnosticReport,
        verbose: Bool = false,
        noColor: Bool = false,
        evidenceOnly: Bool = false
    ) -> String {
        var lines: [String] = []
        let status = report.launchStatus == .blocked ? "BLOCKED" : report.launchStatus == .clean ? "NO BLOCKER FOUND" : "INCONCLUSIVE"
        lines.append("Launch status: \(status)")
        lines.append("")
        lines.append("Target:")
        lines.append("  \(report.target.inputPath)")
        if let resolvedPath = report.target.resolvedPath, resolvedPath != report.target.inputPath {
            lines.append("  Resolved: \(resolvedPath)")
        }
        lines.append("  Kind: \(report.target.kind.rawValue)")
        if let container = report.container {
            lines.append("")
            lines.append("Container:")
            lines.append("  Unpack: \(container.unpackMethod)")
            lines.append("  Nested app: \(container.nestedApplicationPath ?? "not found")")
            if let detail = container.detail, !detail.isEmpty {
                lines.append("  Detail: \(detail)")
            }
        }
        lines.append("")
        lines.append("Environment:")
        lines.append("  macOS: \(report.environment.operatingSystem)")
        lines.append("  Architecture: \(report.environment.hostArchitecture)")
        lines.append("  Apple Silicon: \(report.environment.appleSilicon ? "yes" : "no")")
        lines.append("")

        if let bundle = report.bundle {
            lines.append("Bundle:")
            lines.append("  Info.plist: \(bundle.infoPlistValid ? "valid" : bundle.infoPlistReadable ? "invalid" : "unavailable")")
            lines.append("  Bundle identifier: \(bundle.bundleIdentifier ?? "not present")")
            lines.append("  Executable: \(bundle.executableName ?? "not declared")")
            lines.append("  Executable path: \(bundle.executablePath ?? "not resolved")")
            lines.append("  Executable exists: \(bundle.executableExists ? "yes" : "no")")
            lines.append("  Executable readable: \(bundle.executableReadable ? "yes" : "no")")
            if let macho = bundle.macho {
                lines.append("  Mach-O: \(macho.isMachO ? macho.format.rawValue : "not recognized")")
                lines.append("  Architectures: \(macho.architectures.isEmpty ? "none detected" : macho.architectures.joined(separator: ", "))")
                lines.append("  Minimum macOS: \(macho.minimumOSVersion ?? "not present")")
                lines.append("  SDK: \(macho.sdkVersion ?? "not present")")
                lines.append("  LC_CODE_SIGNATURE: \(macho.hasCodeSignatureLoadCommand ? (macho.codeSignatureRangeValid ? "present and in bounds" : "present but invalid") : "absent")")
            }
            if let security = bundle.security {
                lines.append("  Signature: \(security.signature.state.rawValue)")
                lines.append("  Team ID: \(security.signature.teamID ?? "not present")")
                lines.append("  Hardened Runtime: \(security.signature.hardenedRuntime.map { $0 ? "enabled" : "disabled" } ?? "unavailable")")
                lines.append("  Stapled ticket: \(security.notarization.staple.rawValue)")
                lines.append("  Gatekeeper: \(security.gatekeeper.result.rawValue)")
                lines.append("  Quarantine: \(security.quarantine.present ? "present" : "absent")")
            }
            lines.append("")
        }

        if !evidenceOnly {
            lines.append("Findings:")
            for finding in report.findings {
                lines.append("  \(symbol(for: finding.status, noColor: noColor)) \(finding.title) [\(finding.id)]")
                lines.append("    \(finding.explanation)")
                lines.append("    Confidence: \(finding.confidence.rawValue)")
            }
            lines.append("")
            lines.append("Diagnosis:")
            lines.append("  \(report.diagnosis.summary)")
            lines.append("  Classification: \(report.diagnosis.classification.rawValue)")
            lines.append("  Confidence: \(report.diagnosis.confidence.rawValue)")
            if !report.diagnosis.triggerFindingIDs.isEmpty {
                lines.append("  Trigger: \(report.diagnosis.triggerFindingIDs.joined(separator: ", "))")
            }
            if !report.diagnosis.limitations.isEmpty {
                lines.append("  Limitations:")
                report.diagnosis.limitations.forEach { lines.append("    - \($0)") }
            }
            lines.append("")
        }

        lines.append("Evidence:")
        for item in report.evidence {
            lines.append("  [\(item.id)] \(item.source)")
            lines.append("    \(item.detail)")
        }

        if verbose && !report.findings.isEmpty {
            lines.append("")
            lines.append("Suggested actions:")
            for finding in report.findings {
                for action in finding.suggestedActions {
                    lines.append("  - \(action.title): \(action.detail)")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func symbol(for status: FindingStatus, noColor: Bool) -> String {
        switch status {
        case .passed:
            return "✅"
        case .failed:
            return "❌"
        case .warning:
            return "⚠️"
        case .skipped:
            return "➖"
        case .unavailable:
            return "?"
        case .inconclusive:
            return "❔"
        }
    }
}

private enum RendererError: Error {
    case encodingFailed
}

struct TerminalStyle {
    let enabled: Bool

    func glyph(_ kind: VerdictKind) -> String {
        switch kind {
        case .trusted: return paint("✓", "32")
        case .cautious, .unsigned: return paint("●", "33")
        case .tampered, .broken: return paint("✗", "31")
        case .unknown: return paint("?", "90")
        }
    }

    func bold(_ text: String) -> String { paint(text, "1") }
    func dim(_ text: String) -> String { paint(text, "2") }

    private func paint(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}

/// Wraps prose to a readable width so indentation survives in narrow terminals.
func wrap(_ text: String, width: Int = 76, indent: String, firstPrefix: String = "") -> [String] {
    var lines: [String] = []
    var current = indent + firstPrefix
    let continuation = indent + String(repeating: " ", count: firstPrefix.count)
    var lineHasWord = false
    for word in text.split(separator: " ", omittingEmptySubsequences: true) {
        if lineHasWord && current.count + 1 + word.count > width {
            lines.append(current)
            current = continuation + word
        } else {
            current += (lineHasWord ? " " : "") + word
        }
        lineHasWord = true
    }
    lines.append(current)
    return lines
}

func shellQuoted(_ path: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-~+@%"))
    if !path.isEmpty, path.unicodeScalars.allSatisfy(safe.contains) {
        return path
    }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func markdownEscaped(_ text: String) -> String {
    var escaped = ""
    for character in text {
        if "\\`*_[]<>|#".contains(character) {
            escaped.append("\\")
        }
        escaped.append(character)
    }
    return escaped
}
