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
                .copy("Resources/claude_attention.png"),
                .copy("Resources/claude_idle.png"),
                .copy("Resources/claude_wink.png"),
                .copy("Resources/claude_pet_blink.png"),
                .copy("Resources/claude_pet_sip.png"),
                .copy("Resources/claude_pet_bubble.png"),
                .copy("Resources/claude_pet_celebrate.png"),
                .copy("Resources/qoder_mascot.png"),
                .copy("Resources/cursor_mascot.png"),
                .copy("Resources/island.png"),
                .copy("Resources/Sounds")
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
