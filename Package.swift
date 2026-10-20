// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StashKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "StashKit", targets: ["StashKit"]),
        .library(name: "StashKitUI", targets: ["StashKitUI"]),
    ],
    targets: [
        .target(name: "StashKit", linkerSettings: [.linkedFramework("NetFS")]),
        .target(name: "StashKitUI", dependencies: ["StashKit"]),
        .testTarget(
            name: "StashKitTests",
            dependencies: ["StashKit", "StashKitUI"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
