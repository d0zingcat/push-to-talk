import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}

let removedFiles = [
    "src/trigger.ts",
    "package.json",
    "package-lock.json",
    "tsconfig.json",
    "raycast-env.d.ts",
    "extension-icon.png",
]

for file in removedFiles {
    require(!FileManager.default.fileExists(atPath: file), "\(file) should be removed from the Swift-only project")
}

let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
let helperSource = try FileManager.default
    .contentsOfDirectory(atPath: "swift-helper")
    .filter { $0.hasSuffix(".swift") }
    .sorted()
    .map { try String(contentsOfFile: "swift-helper/\($0)", encoding: .utf8) }
    .joined(separator: "\n")
let installScript = try String(contentsOfFile: "install-daemon.sh", encoding: .utf8)
let installAppScript = try String(contentsOfFile: "install-app.sh", encoding: .utf8)
let packageDmgScript = try String(contentsOfFile: "package-dmg.sh", encoding: .utf8)
let makefile = try String(contentsOfFile: "swift-helper/Makefile", encoding: .utf8)
let readmeForbidden = try NSRegularExpression(pattern: #"Raycast|raycast|npm|TypeScript|trigger\.ts|package\.json|no-view|HUD"#)
let swiftForbidden = try NSRegularExpression(pattern: #"Raycast|raycast|TypeScript"#)

require(
    readmeForbidden.firstMatch(in: readme, range: NSRange(readme.startIndex..<readme.endIndex, in: readme)) == nil,
    "README should describe only the Swift implementation"
)
require(
    swiftForbidden.firstMatch(in: helperSource, range: NSRange(helperSource.startIndex..<helperSource.endIndex, in: helperSource)) == nil,
    "Swift source should not describe removed integrations"
)
require(readme.contains("swift-helper/main.swift"), "README should document the Swift helper as the implementation entrypoint")
require(readme.contains("pushtotalk full-flow"), "README should keep the Swift one-shot CLI entrypoint documented")
require(FileManager.default.fileExists(atPath: "restart-daemon.sh"), "restart-daemon.sh should provide a reload path that does not rebuild")
require(readme.contains("./restart-daemon.sh"), "README should document the daemon restart command")
require(readme.contains("PUSHTOTALK_CODESIGN_IDENTITY"), "README should document optional stable code signing")
require(installScript.contains("PUSHTOTALK_CODESIGN_IDENTITY"), "install script should support optional stable code signing")
require(installScript.contains("codesign --force --sign"), "install script should codesign the installed binary when an identity is provided")
require(installAppScript.contains("BUNDLE_ID=\"com.pushtotalk.PushToTalk\""), "GUI installer should use a stable bundle identifier for signing and TCC")
require(packageDmgScript.contains("BUNDLE_ID=\"com.pushtotalk.PushToTalk\""), "DMG packaging should sign the app with the stable bundle identifier before distribution")
require(makefile.contains("__info_plist"), "Swift GUI executable should embed Info.plist so code signing uses the app bundle identifier")
require(!installAppScript.contains("tccutil reset Accessibility"), "GUI installer should not reset Accessibility after the user grants it")
require(installScript.contains("LOG_DIR=\"$HOME/Library/Logs/pushtotalk\""), "install script should write daemon logs under the user Library Logs directory")
require(installScript.contains("mkdir -p \"$LOG_DIR\""), "install script should create the daemon log directory")
require(installScript.contains("$LOG_DIR/pushtotalk-daemon.log"), "install script should configure daemon stdout in the log directory")
require(installScript.contains("$LOG_DIR/pushtotalk-daemon.err"), "install script should configure daemon stderr in the log directory")
require(!installScript.contains("/tmp/pushtotalk"), "install script should not write daemon logs directly under /tmp")
require(readme.contains("~/Library/Logs/pushtotalk/pushtotalk-daemon.log"), "README should document the user Library stdout log path")
require(readme.contains("~/Library/Logs/pushtotalk/pushtotalk-daemon.err"), "README should document the user Library stderr log path")
require(!readme.contains("/tmp/pushtotalk"), "README should not document /tmp daemon log paths")

print("project is Swift-only")
