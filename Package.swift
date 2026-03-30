// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProcessGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ProcessGuard")
    ]
)
