// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrollbackCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
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
