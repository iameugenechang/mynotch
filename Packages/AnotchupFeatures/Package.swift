// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnotchupFeatures",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchShell", targets: ["NotchShell"]),
        .library(name: "NotchShellAdapters", targets: ["NotchShellAdapters"]),
        .library(name: "WorkingOn", targets: ["WorkingOn"]),
        .library(name: "WorkingOnAdapters", targets: ["WorkingOnAdapters"]),
    ],
    targets: [
        .target(name: "NotchShell"),
        .target(name: "NotchShellAdapters", dependencies: ["NotchShell"]),
        .testTarget(name: "NotchShellTests", dependencies: ["NotchShell", "NotchShellAdapters"]),
        .target(name: "WorkingOn"),
        .target(name: "WorkingOnAdapters", dependencies: ["WorkingOn"]),
        .testTarget(name: "WorkingOnTests", dependencies: ["WorkingOn", "WorkingOnAdapters"]),
    ]
)
