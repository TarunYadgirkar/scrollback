// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScrollbackCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ScrollbackCore", targets: ["ScrollbackCore"]),
        .executable(name: "scrollback", targets: ["scrollback"]),
    ],
    targets: [
        .target(name: "ScrollbackCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "scrollback", dependencies: ["ScrollbackCore"]),
        .testTarget(name: "ScrollbackCoreTests", dependencies: ["ScrollbackCore"]),
    ]
)
