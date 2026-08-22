// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SFPoint",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SFPoint",
            path: "Sources/SFPoint",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
