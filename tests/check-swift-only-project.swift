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
let mainSwift = try String(contentsOfFile: "swift-helper/main.swift", encoding: .utf8)
let installScript = try String(contentsOfFile: "install-daemon.sh", encoding: .utf8)
let readmeForbidden = try NSRegularExpression(pattern: #"Raycast|raycast|npm|TypeScript|trigger\.ts|package\.json|no-view|HUD"#)
let swiftForbidden = try NSRegularExpression(pattern: #"Raycast|raycast|TypeScript"#)

require(
    readmeForbidden.firstMatch(in: readme, range: NSRange(readme.startIndex..<readme.endIndex, in: readme)) == nil,
    "README should describe only the Swift implementation"
)
require(
    swiftForbidden.firstMatch(in: mainSwift, range: NSRange(mainSwift.startIndex..<mainSwift.endIndex, in: mainSwift)) == nil,
    "Swift source should not describe removed integrations"
)
require(readme.contains("swift-helper/main.swift"), "README should document the Swift helper as the implementation entrypoint")
require(readme.contains("pushtotalk full-flow"), "README should keep the Swift one-shot CLI entrypoint documented")
require(FileManager.default.fileExists(atPath: "restart-daemon.sh"), "restart-daemon.sh should provide a reload path that does not rebuild")
require(readme.contains("./restart-daemon.sh"), "README should document the daemon restart command")
require(readme.contains("PUSHTOTALK_CODESIGN_IDENTITY"), "README should document optional stable code signing")
require(installScript.contains("PUSHTOTALK_CODESIGN_IDENTITY"), "install script should support optional stable code signing")
require(installScript.contains("codesign --force --sign"), "install script should codesign the installed binary when an identity is provided")

print("project is Swift-only")
