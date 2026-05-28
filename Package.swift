// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionCove",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SessionCove",
            path: "SessionCove",
            exclude: ["Info.plist", "SessionCove.entitlements"],
            resources: [
                .copy("Resources/claude_working.png"),
                .copy("Resources/claude_sleeping.png"),
                .copy("Resources/island.png")
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=targeted"])
            ]
        ),
        .testTarget(
            name: "SessionCoveTests",
            dependencies: ["SessionCove"],
            path: "SessionCoveTests"
        )
    ]
)
