// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnotchupFeatures",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchShell", targets: ["NotchShell"]),
        .library(name: "WorkingOn", targets: ["WorkingOn"]),
        .library(name: "WorkingOnAdapters", targets: ["WorkingOnAdapters"]),
    ],
    targets: [
        .target(name: "NotchShell"),
        .testTarget(name: "NotchShellTests", dependencies: ["NotchShell"]),
        .target(name: "WorkingOn"),
        .target(name: "WorkingOnAdapters", dependencies: ["WorkingOn"]),
        .testTarget(name: "WorkingOnTests", dependencies: ["WorkingOn", "WorkingOnAdapters"]),
    ]
)
