// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPTVCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IPTVCore", targets: ["IPTVCore"]),
    ],
    targets: [
        .target(name: "IPTVCore"),
        .testTarget(
            name: "IPTVCoreTests",
            dependencies: ["IPTVCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
