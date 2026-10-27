// swift-tools-version: 6.0
// For editors and `swift build` checks. Use ./build.sh to make the app bundle.
import PackageDescription

let package = Package(
    name: "Copycat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Copycat", path: "Sources/Copycat"),
    ]
)
