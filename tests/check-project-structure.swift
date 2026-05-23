import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func swiftSource(in directory: String) throws -> String {
    let root = URL(fileURLWithPath: directory)
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
        .map { $0.path }
        .sorted() ?? []

    return try files
        .map { try String(contentsOfFile: $0, encoding: .utf8) }
        .joined(separator: "\n")
}

let removedPaths = [
    "src",
    "swift-helper",
    "assets",
    "install-app.sh",
    "uninstall-app.sh",
    "install-daemon.sh",
    "restart-daemon.sh",
    "uninstall-daemon.sh",
    "package-dmg.sh",
    "package.json",
    "package-lock.json",
    "tsconfig.json",
    "raycast-env.d.ts",
    "extension-icon.png",
]

for path in removedPaths {
    require(!FileManager.default.fileExists(atPath: path), "\(path) should not exist in the reorganized project")
}

let requiredPaths = [
    "Sources/PushToTalk/App/AppDelegate.swift",
    "Sources/PushToTalk/App/AppStateManager.swift",
    "Sources/PushToTalk/App/MenuView.swift",
    "Sources/PushToTalk/CLI/CLIArguments.swift",
    "Sources/PushToTalk/Core/Configuration.swift",
    "Sources/PushToTalk/Core/InputSources.swift",
    "Sources/PushToTalk/Core/KeySimulation.swift",
    "Sources/PushToTalk/Core/Logging.swift",
    "Sources/PushToTalk/Core/Permissions.swift",
    "Sources/PushToTalk/Daemon/DaemonController.swift",
    "Sources/PushToTalk/Daemon/DaemonState.swift",
    "Sources/PushToTalk/Resources/AppIcon.icns",
    "Sources/PushToTalk/Resources/Info.plist",
    "Sources/PushToTalk/main.swift",
    "scripts/install-app.sh",
    "scripts/uninstall-app.sh",
    "scripts/install-daemon.sh",
    "scripts/restart-daemon.sh",
    "scripts/uninstall-daemon.sh",
    "packaging/Makefile",
    "packaging/package-dmg.sh",
    "packaging/dmg_background.tiff",
    "dist/pushtotalk",
    "dist/PushToTalk.app",
    "docs/architecture.md",
    "docs/installation.md",
    "docs/configuration.md",
    "docs/troubleshooting.md",
    "docs/development.md",
]

for path in requiredPaths {
    require(FileManager.default.fileExists(atPath: path), "\(path) should exist")
}

let readme = try read("README.md")
let source = try swiftSource(in: "Sources/PushToTalk")
let installScript = try read("scripts/install-daemon.sh")
let installAppScript = try read("scripts/install-app.sh")
let packageDmgScript = try read("packaging/package-dmg.sh")
let makefile = try read("packaging/Makefile")
let ci = try read(".github/workflows/ci.yml")
let installation = try read("docs/installation.md")
let troubleshooting = try read("docs/troubleshooting.md")
let development = try read("docs/development.md")

let readmeForbidden = try NSRegularExpression(pattern: #"Raycast|raycast|npm|TypeScript|trigger\.ts|package\.json|no-view|HUD"#)
let swiftForbidden = try NSRegularExpression(pattern: #"Raycast|raycast|TypeScript"#)

require(
    readmeForbidden.firstMatch(in: readme, range: NSRange(readme.startIndex..<readme.endIndex, in: readme)) == nil,
    "README should describe only the Swift implementation"
)
require(
    swiftForbidden.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)) == nil,
    "Swift source should not describe removed integrations"
)

require(readme.contains("Sources/PushToTalk"), "README should document the source root")
require(readme.contains("./scripts/install-app.sh"), "README should document the GUI installer")
require(readme.contains("make -C packaging"), "README should document the new build command")
require(readme.contains("swift tests/check-project-structure.swift"), "README should document the structure check")
require(readme.contains("[Installation](docs/installation.md)"), "README should link installation docs")
require(readme.contains("[Architecture](docs/architecture.md)"), "README should link architecture docs")

require(installation.contains("PUSHTOTALK_CODESIGN_IDENTITY"), "installation docs should document optional stable code signing")
require(installation.contains("./scripts/restart-daemon.sh"), "installation docs should document daemon restart")
require(troubleshooting.contains("dist/pushtotalk list-sources"), "troubleshooting docs should use the new binary path")
require(development.contains("make -C packaging"), "development docs should document the new build command")
require(development.contains("./packaging/package-dmg.sh"), "development docs should document the new package command")

require(installScript.contains("PUSHTOTALK_CODESIGN_IDENTITY"), "install script should support optional stable code signing")
require(installScript.contains("codesign --force --sign"), "install script should codesign the installed binary when an identity is provided")
require(installScript.contains("REPO_ROOT="), "install daemon script should resolve repository root from scripts/")
require(installScript.contains("$REPO_ROOT/dist/pushtotalk"), "install daemon script should install from dist")
require(installScript.contains("make -C \"$REPO_ROOT/packaging\""), "install daemon script should build from packaging")
require(!installScript.contains("/tmp/pushtotalk"), "install script should not write daemon logs directly under /tmp")
require(installScript.contains("LOG_DIR=\"$HOME/Library/Logs/pushtotalk\""), "install script should write daemon logs under the user Library Logs directory")
require(installScript.contains("mkdir -p \"$LOG_DIR\""), "install script should create the daemon log directory")
require(installScript.contains("$LOG_DIR/pushtotalk-daemon.log"), "install script should configure daemon stdout in the log directory")
require(installScript.contains("$LOG_DIR/pushtotalk-daemon.err"), "install script should configure daemon stderr in the log directory")

require(installAppScript.contains("BUNDLE_ID=\"com.pushtotalk.PushToTalk\""), "GUI installer should use a stable bundle identifier for signing and TCC")
require(installAppScript.contains("REPO_ROOT="), "GUI installer should resolve repository root from scripts/")
require(installAppScript.contains("$REPO_ROOT/dist/PushToTalk.app"), "GUI installer should install from dist")
require(!installAppScript.contains("tccutil reset Accessibility"), "GUI installer should not reset Accessibility after the user grants it")

require(packageDmgScript.contains("BUNDLE_ID=\"com.pushtotalk.PushToTalk\""), "DMG packaging should sign the app with the stable bundle identifier before distribution")
require(packageDmgScript.contains("$REPO_ROOT/dist/PushToTalk.app"), "DMG packaging should stage the app from dist")
require(packageDmgScript.contains("$SCRIPT_DIR/dmg_background.tiff"), "DMG packaging should use packaging artwork")
require(makefile.contains("SOURCE_ROOT := $(ROOT)/Sources/PushToTalk"), "Makefile should compile from Sources/PushToTalk")
require(makefile.contains("$(DIST)/pushtotalk"), "Makefile should write the binary to dist")
require(makefile.contains("__info_plist"), "Swift GUI executable should embed Info.plist so code signing uses the app bundle identifier")

require(ci.contains("make -C packaging"), "CI should build from packaging")
require(ci.contains("swift tests/check-project-structure.swift"), "CI should run the renamed structure check")
require(ci.contains("./packaging/package-dmg.sh"), "CI should run the moved package script")
require(ci.contains("scripts"), "CI zip should include operational scripts")
require(ci.contains("dist/pushtotalk"), "CI zip should include the built binary from dist")
require(ci.contains("dist/PushToTalk.app"), "CI zip should include the app bundle from dist")

require(source.contains("func applicationDidResignActive"), "GUI should close its popover when the app loses focus")
require(source.contains("closePopover"), "GUI should centralize popover closing for focus-loss handling")
require(!source.contains("./restart-daemon.sh"), "Swift source should not point users to the removed root restart script")
require(source.contains("./scripts/restart-daemon.sh"), "Swift source should point users to the moved restart script")

print("project structure is correct")
