// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowGrids",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WindowGrids", path: "Sources/WindowGrids")
    ]
)
