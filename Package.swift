// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Note_",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Note_",
            path: "Sources/Note_",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
