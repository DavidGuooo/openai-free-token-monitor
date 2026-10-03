// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeTokenMonitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FreeTokenMonitor", targets: ["TokenMonitor"])],
    targets: [
        .target(name: "MonitorCore"),
        .executableTarget(name: "TokenMonitor", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ]
)
