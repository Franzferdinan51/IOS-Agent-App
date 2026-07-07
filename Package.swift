// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DualAgent",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "DualAgent",
            targets: ["DualAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/launchdarkly/swift-eventsource.git", from: "2.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.0.0"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.18.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        // WebRTC is large; we will conditionally link it later via XCFramework if needed.
        // For now we'll leave it out and use a feature flag.
    ],
    targets: [
        .target(
            name: "DualAgent",
            dependencies: [
                .product(name: "EventSource", package: "swift-eventsource"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            path: "DualAgent"
        ),
        .testTarget(
            name: "DualAgentTests",
            dependencies: ["DualAgent"],
            path: "DualAgentTests")
    ]
)
