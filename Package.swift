// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeMonitorCore"),
        .executableTarget(
            name: "ClaudeMonitor",
            dependencies: ["ClaudeMonitorCore"]
        ),
        .executableTarget(
            name: "ClaudeMonitorBridge",
            dependencies: ["ClaudeMonitorCore"]
        ),
        // Assertion-based checks. (Full Xcode would allow an XCTest target;
        // Command Line Tools ship neither XCTest nor swift-testing, so this runs
        // as a plain executable: `swift run MonitorCheck`.)
        .executableTarget(
            name: "MonitorCheck",
            dependencies: ["ClaudeMonitorCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
