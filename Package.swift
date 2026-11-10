// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NgaoCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NgaoCore", targets: ["NgaoCore"]),
    ],
    targets: [
        .target(
            name: "NgaoCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(name: "NgaoCoreTests", dependencies: ["NgaoCore"]),
    ]
)
