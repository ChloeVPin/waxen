import XCTest
@testable import WaxenCore

final class FinderActionTests: XCTestCase {
    private var services: URL!
    private var domain: String!

    override func setUpWithError() throws {
        services = FileManager.default.temporaryDirectory
            .appendingPathComponent("waxen-services-\(UUID().uuidString)", isDirectory: true)
        domain = "dev.waxen.tests.pbs-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: services)
        CFPreferencesSetAppValue("NSServicesStatus" as CFString, nil, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    private func makeAction() -> FinderAction {
        FinderAction(servicesDirectory: services, preferencesDomain: domain)
    }

    func testInstallEnablesContextMenuAndUninstallRemovesIt() throws {
        let action = makeAction()
        try action.install(waxenPath: "/opt/homebrew/bin/waxen")
        let status = try XCTUnwrap(action.servicesStatus())
        XCTAssertEqual(status["enabled_context_menu"] as? Bool, true)
        XCTAssertEqual((status["presentation_modes"] as? [String: Bool])?["ContextMenu"], true)

        try action.uninstall()
        XCTAssertNil(action.servicesStatus())
    }

    func testStatusKeyMatchesMenuTitle() {
        XCTAssertEqual(FinderAction.servicesStatusKey, "(null) - Why Won’t This Open? - runWorkflowAsService")
    }

    func testInstallWritesValidWorkflow() throws {
        let action = makeAction()
        let url = try action.install(waxenPath: "/opt/homebrew/bin/waxen")
        XCTAssertEqual(url.lastPathComponent, FinderAction.workflowDirectoryName)

        let info = try plist(url.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(info[FinderAction.ownerKey] as? Bool, true)
        let service = try XCTUnwrap((info["NSServices"] as? [[String: Any]])?.first)
        XCTAssertEqual((service["NSMenuItem"] as? [String: String])?["default"], FinderAction.menuTitle)
        XCTAssertEqual(service["NSIconName"] as? String, FinderAction.iconName)
        let icon = try Data(contentsOf: url.appendingPathComponent("Contents/Resources/workflowCustomImage.png"))
        XCTAssertEqual(Array(icon.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10], "A real PNG is bundled with the workflow")
        XCTAssertEqual(service["NSMessage"] as? String, "runWorkflowAsService")
        XCTAssertEqual(service["NSSendFileTypes"] as? [String], FinderAction.acceptedTypes)

        let document = try plist(url.appendingPathComponent("Contents/document.wflow"))
        let actions = try XCTUnwrap(document["actions"] as? [[String: Any]])
        let parameters = try XCTUnwrap((actions.first?["action"] as? [String: Any])?["ActionParameters"] as? [String: Any])
        XCTAssertEqual(parameters["inputMethod"] as? Int, 1, "files arrive as arguments")
        let script = try XCTUnwrap(parameters["COMMAND_STRING"] as? String)
        XCTAssertTrue(script.contains("'/opt/homebrew/bin/waxen'"))
        XCTAssertTrue(script.contains("--alert"))
        XCTAssertEqual((document["workflowMetaData"] as? [String: Any])?["workflowTypeIdentifier"] as? String, "com.apple.Automator.servicesMenu")
    }

    func testInstallTwiceReplacesOwnWorkflow() throws {
        let action = makeAction()
        try action.install(waxenPath: "/a/waxen")
        try action.install(waxenPath: "/b/waxen")
        let document = try plist(action.workflowURL.appendingPathComponent("Contents/document.wflow"))
        let script = ((document["actions"] as? [[String: Any]])?.first?["action"] as? [String: Any])
            .flatMap { $0["ActionParameters"] as? [String: Any] }?["COMMAND_STRING"] as? String
        XCTAssertTrue(script?.contains("'/b/waxen'") == true)
        XCTAssertFalse(script?.contains("'/a/waxen'") == true)
    }

    func testUninstallRemovesOnlyItsWorkflow() throws {
        let action = makeAction()
        let neighbor = services.appendingPathComponent("Other.workflow", isDirectory: true)
        try FileManager.default.createDirectory(at: neighbor, withIntermediateDirectories: true)
        try action.install(waxenPath: "/opt/homebrew/bin/waxen")

        XCTAssertTrue(try action.uninstall())
        XCTAssertFalse(FileManager.default.fileExists(atPath: action.workflowURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbor.path))
        XCTAssertFalse(try action.uninstall(), "second uninstall has nothing to do")
    }

    func testRefusesToTouchSomeoneElsesWorkflow() throws {
        let action = makeAction()
        let contents = action.workflowURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("<plist><dict/></plist>".utf8).write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertThrowsError(try action.uninstall()) { error in
            XCTAssertEqual(error as? FinderAction.InstallError, .notOurs(action.workflowURL.path))
        }
        XCTAssertThrowsError(try action.install(waxenPath: "/x"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contents.path))
    }

    func testInstallMigratesOriginalLaunchDXWorkflow() throws {
        let action = makeAction()
        let contents = action.workflowURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let old = try PropertyListSerialization.data(fromPropertyList: ["LaunchDXQuickAction": true], format: .xml, options: 0)
        try old.write(to: contents.appendingPathComponent("Info.plist"))
        try action.install(waxenPath: "/a/waxen")
        let info = try plist(contents.appendingPathComponent("Info.plist"))
        XCTAssertEqual(info[FinderAction.ownerKey] as? Bool, true)
        XCTAssertNil(info["LaunchDXQuickAction"])
    }

    func testShellScriptQuotesPaths() {
        let script = FinderAction.shellScript(waxenPath: "/Users/o'brien/bin/waxen")
        XCTAssertTrue(script.contains("'/Users/o'\\''brien/bin/waxen'"))
    }

    func testResolvePrefersStableSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waxen-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("Cellar-waxen")
        try Data("#!/bin/sh\n".utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real.path)
        let link = dir.appendingPathComponent("waxen")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertEqual(FinderAction.resolveExecutablePath(current: real.path, candidates: [link.path]), link.path)
        let unrelated = FinderAction.resolveExecutablePath(current: "/somewhere/else/waxen", candidates: [link.path])
        XCTAssertEqual(unrelated, "/somewhere/else/waxen")
    }

    private func plist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
