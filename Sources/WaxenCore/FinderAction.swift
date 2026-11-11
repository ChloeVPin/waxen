import Foundation

/// Installs a Finder Quick Action: right-click an app, disk image, or
/// installer, then Quick Actions → Why Won't This Open?
///
/// This is the only part of waxen that writes to disk. It writes one
/// workflow under ~/Library/Services and never touches the app being checked.
public struct FinderAction {
    public enum InstallError: Error, CustomStringConvertible, Equatable {
        case notOurs(String)
        case writeFailed(String)

        public var description: String {
            switch self {
            case let .notOurs(path):
                return "\(path) already exists and wasn't created by waxen. Leaving it alone."
            case let .writeFailed(reason):
                return "couldn't write the Quick Action: \(reason)"
            }
        }
    }

    public static let workflowDirectoryName = "Why Won't This Open.workflow"
    public static let menuTitle = "Why Won’t This Open?"
    /// Marks the workflow as ours so uninstall never deletes someone else's.
    static let ownerKey = "WaxenQuickAction"
    public static let fallbackExecutables = ["/opt/homebrew/bin/waxen", "/usr/local/bin/waxen"]
    static let acceptedTypes = [
        "com.apple.application-bundle",
        "public.disk-image",
        "com.apple.installer-package-archive"
    ]

    /// The key macOS uses for a workflow service in the `pbs` preferences.
    /// Workflows have no bundle identifier, so macOS writes "(null)".
    public static let servicesStatusKey = "(null) - \(menuTitle) - runWorkflowAsService"

    public let servicesDirectory: URL
    /// The preferences domain that stores which services appear where.
    /// macOS uses `pbs`; tests use a throwaway domain.
    public let preferencesDomain: String
    private let fileManager: FileManager

    public init(
        servicesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true),
        preferencesDomain: String = "pbs",
        fileManager: FileManager = .default
    ) {
        self.servicesDirectory = servicesDirectory
        self.preferencesDomain = preferencesDomain
        self.fileManager = fileManager
    }

    public var workflowURL: URL {
        servicesDirectory.appendingPathComponent(Self.workflowDirectoryName, isDirectory: true)
    }

    @discardableResult
    public func install(waxenPath: String) throws -> URL {
        if fileManager.fileExists(atPath: workflowURL.path) {
            guard isOurs() else { throw InstallError.notOurs(workflowURL.path) }
            try? fileManager.removeItem(at: workflowURL)
        }
        let contents = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        do {
            try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
            try Self.infoPlist().write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
            try Self.documentWorkflow(script: Self.shellScript(waxenPath: waxenPath))
                .write(to: contents.appendingPathComponent("document.wflow"), options: .atomic)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
        setServicesStatus(enabled: true)
        return workflowURL
    }

    /// Returns false when there was nothing to remove.
    @discardableResult
    public func uninstall() throws -> Bool {
        guard fileManager.fileExists(atPath: workflowURL.path) else { return false }
        guard isOurs() else { throw InstallError.notOurs(workflowURL.path) }
        do {
            try fileManager.removeItem(at: workflowURL)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
        setServicesStatus(enabled: false)
        return true
    }

    /// Finder lists a service under right-click → Quick Actions only when its
    /// context-menu flag is on. This is the same setting as System Settings →
    /// Keyboard → Keyboard Shortcuts → Services. Uninstall removes our entry.
    func setServicesStatus(enabled: Bool) {
        let name = "NSServicesStatus" as CFString
        let domain = preferencesDomain as CFString
        var status = (CFPreferencesCopyAppValue(name, domain) as? [String: Any]) ?? [:]
        if enabled {
            status[Self.servicesStatusKey] = [
                "enabled_context_menu": true,
                "enabled_services_menu": true,
                "presentation_modes": [
                    "ContextMenu": true,
                    "ServicesMenu": true,
                    "FinderPreview": true,
                    "TouchBar": true
                ]
            ]
        } else {
            status.removeValue(forKey: Self.servicesStatusKey)
        }
        CFPreferencesSetAppValue(name, status.isEmpty ? nil : status as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
    }

    func servicesStatus() -> [String: Any]? {
        let status = CFPreferencesCopyAppValue("NSServicesStatus" as CFString, preferencesDomain as CFString) as? [String: Any]
        return status?[Self.servicesStatusKey] as? [String: Any]
    }

    /// Ask macOS to pick up the new Services menu item without logging out.
    public static func refreshServices() {
        #if os(macOS)
        let runner = ReadOnlyCommandRunner()
        _ = runner.run("/System/Library/CoreServices/pbs", arguments: ["-flush"], timeout: 20)
        _ = runner.run("/System/Library/CoreServices/pbs", arguments: ["-update"], timeout: 20)
        #endif
    }

    func isOurs() -> Bool {
        let info = workflowURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return plist[Self.ownerKey] as? Bool == true
    }

    /// Prefer the stable Homebrew symlink over a versioned Cellar path, so the
    /// Quick Action keeps working after `brew upgrade`.
    public static func resolveExecutablePath(
        current: String? = Bundle.main.executablePath,
        candidates: [String] = fallbackExecutables,
        fileManager: FileManager = .default
    ) -> String {
        let resolvedCurrent = current.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            if resolvedCurrent == nil || resolved == resolvedCurrent {
                return candidate
            }
        }
        return resolvedCurrent ?? candidates[0]
    }

    // MARK: - Templates

    static func shellScript(waxenPath: String) -> String {
        let candidates = ([waxenPath] + fallbackExecutables.filter { $0 != waxenPath })
            .map(singleQuoted)
            .joined(separator: " ")
        return """
        # Installed by `waxen finder install`. Remove with `waxen finder uninstall`.
        for f in "$@"; do
          found=0
          for ldx in \(candidates); do
            if [ -x "$ldx" ]; then "$ldx" "$f" --alert; found=1; break; fi
          done
          if [ "$found" = 0 ]; then
            /usr/bin/osascript -e 'display alert "waxen is not installed" message "Build and install Waxen from: https://github.com/ChloeVPin/waxen"'
            exit 0
          fi
        done
        exit 0
        """
    }

    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func infoPlist() throws -> Data {
        let plist: [String: Any] = [
            ownerKey: true,
            "NSServices": [[
                "NSIconName": "NSActionTemplate",
                "NSMenuItem": ["default": menuTitle],
                "NSMessage": "runWorkflowAsService",
                "NSRequiredContext": ["NSApplicationIdentifier": "com.apple.finder"],
                "NSSendFileTypes": acceptedTypes
            ]]
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Mirrors the structure Automator writes for a one-step "Run Shell Script"
    /// Quick Action that receives files from Finder as arguments.
    static func documentWorkflow(script: String) throws -> Data {
        func argument(_ uuid: String, _ name: String, _ defaultValue: Any) -> [String: Any] {
            ["default value": defaultValue, "name": name, "required": "0", "type": "0", "uuid": uuid]
        }
        let action: [String: Any] = [
            "AMAccepts": ["Container": "List", "Optional": true, "Types": ["com.apple.cocoa.string"]],
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": [
                "COMMAND_STRING": [String: Any](),
                "CheckedForUserDefaultShell": [String: Any](),
                "inputMethod": [String: Any](),
                "shell": [String: Any](),
                "source": [String: Any]()
            ],
            "AMProvides": ["Container": "List", "Types": ["com.apple.cocoa.string"]],
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": [
                "COMMAND_STRING": script,
                "CheckedForUserDefaultShell": true,
                "inputMethod": 1,
                "shell": "/bin/bash",
                "source": ""
            ],
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": false,
            "CanShowWhenRun": true,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": "5B0C3D5E-6F55-4D3B-9C61-1C5F2D9E7A01",
            "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
            "OutputUUID": "5B0C3D5E-6F55-4D3B-9C61-1C5F2D9E7A02",
            "UUID": "5B0C3D5E-6F55-4D3B-9C61-1C5F2D9E7A03",
            "UnlocalizedApplications": ["Automator"],
            "arguments": [
                "0": argument("0", "inputMethod", 0),
                "1": argument("1", "CheckedForUserDefaultShell", false),
                "2": argument("2", "source", ""),
                "3": argument("3", "COMMAND_STRING", ""),
                "4": argument("4", "shell", "/bin/sh")
            ],
            "conversionLabel": 0,
            "isViewVisible": 1,
            "location": "309.000000:305.000000",
            "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib"
        ]
        let document: [String: Any] = [
            "AMApplicationBuild": "534",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [["action": action, "isViewVisible": 1]],
            "connectors": [String: Any](),
            "workflowMetaData": [
                "applicationBundleIDsByPath": [String: Any](),
                "applicationPaths": [String](),
                "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": false,
                "serviceApplicationBundleID": "com.apple.finder",
                "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
                "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": false,
                "systemImageName": "NSActionTemplate",
                "useAutomaticInputType": false,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"
            ]
        ]
        return try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
    }
}
