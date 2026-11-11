import Foundation

public enum CLIParseError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingPath
    case missingFinderAction
    case multiplePaths
    case unknownOption(String)
    case help
    case version

    public var description: String {
        switch self {
        case .missingCommand:
            return "give waxen an app, disk image, or installer to check"
        case let .unknownCommand(command):
            return "unknown command: \(command)"
        case .missingPath:
            return "a target path is required"
        case .missingFinderAction:
            return "finder needs an action: install or uninstall"
        case .multiplePaths:
            return "only one target path may be provided"
        case let .unknownOption(option):
            return "unknown option: \(option)"
        case .help:
            return "help requested"
        case .version:
            return "version requested"
        }
    }
}

public struct CLIParser {
    public init() {}

    public func parse(_ arguments: [String]) throws -> CLIOptions {
        guard let first = arguments.first else {
            throw CLIParseError.missingCommand
        }
        if first == "--help" || first == "-h" {
            throw CLIParseError.help
        }
        if first == "--version" || first == "-V" {
            throw CLIParseError.version
        }

        let command: CLICommand
        let rest: ArraySlice<String>
        switch first {
        case "diagnose":
            command = .diagnose
            rest = arguments.dropFirst()
        case "evidence":
            command = .evidence
            rest = arguments.dropFirst()
        case "finder":
            return try parseFinder(Array(arguments.dropFirst()))
        default:
            // `waxen MyApp.app` is the everyday form of `waxen diagnose MyApp.app`.
            command = .diagnose
            rest = arguments[...]
        }

        var path: String?
        var json = false
        var verbose = false
        var noColor = false
        var details = false
        var share = false
        var alert = false

        for argument in rest {
            switch argument {
            case "--json":
                json = true
            case "--verbose":
                verbose = true
            case "--no-color":
                noColor = true
            case "--details":
                details = true
            case "--share":
                share = true
            case "--alert":
                alert = true
            case "--help", "-h":
                throw CLIParseError.help
            case "--version", "-V":
                throw CLIParseError.version
            case let option where option.hasPrefix("-"):
                throw CLIParseError.unknownOption(option)
            default:
                guard path == nil else {
                    throw CLIParseError.multiplePaths
                }
                path = argument
            }
        }

        guard let path, !path.isEmpty else {
            throw CLIParseError.missingPath
        }

        return CLIOptions(
            command: command,
            path: path,
            json: json,
            verbose: verbose,
            noColor: noColor,
            details: details,
            share: share,
            alert: alert
        )
    }

    private func parseFinder(_ arguments: [String]) throws -> CLIOptions {
        if arguments.contains("--help") || arguments.contains("-h") {
            throw CLIParseError.help
        }
        guard let name = arguments.first else {
            throw CLIParseError.missingFinderAction
        }
        guard let action = FinderActionCommand(rawValue: name) else {
            throw CLIParseError.unknownCommand("finder \(name)")
        }
        if let extra = arguments.dropFirst().first {
            throw extra.hasPrefix("-") ? CLIParseError.unknownOption(extra) : CLIParseError.multiplePaths
        }
        return CLIOptions(command: .finder(action), path: "")
    }

    public static let usage = """
    Usage:
      waxen <MyApp.app|MyApp.dmg|MyApp.pkg>      Why won't it open? One plain answer.
      waxen <path> --details                      The full evidence report
      waxen <path> --share                        Markdown to paste into an issue
      waxen <path> --json                         Machine-readable report
      waxen evidence <path>                       Evidence only, no diagnosis
      waxen finder install                        Add "Why Won't This Open?" to Finder
      waxen finder uninstall                      Remove it again
      waxen --version

    Options: --details  --verbose  --share  --json  --no-color
    waxen only reads. It never changes the app you check.
    """
}
