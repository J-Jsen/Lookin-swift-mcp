// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lookin-swift-mcp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "lookin-swift",
            path: "Sources/lookin-swift"
        )
    ]
)
