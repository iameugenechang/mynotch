// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnotchupFeatures",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShelfFeature", targets: ["ShelfFeature"]),
        .library(name: "ShelfAdapters", targets: ["ShelfAdapters"]),
        .library(name: "CameraFeature", targets: ["CameraFeature"]),
        .library(name: "CalendarFeature", targets: ["CalendarFeature"]),
        .library(name: "MediaFeature", targets: ["MediaFeature"]),
        .library(name: "NotchShell", targets: ["NotchShell"]),
        .library(name: "NotchShellAdapters", targets: ["NotchShellAdapters"]),
        .library(name: "WorkingOn", targets: ["WorkingOn"]),
        .library(name: "WorkingOnAdapters", targets: ["WorkingOnAdapters"]),
    ],
    targets: [
        .target(name: "ShelfFeature"),
        .target(name: "ShelfAdapters", dependencies: ["ShelfFeature"]),
        .testTarget(name: "ShelfFeatureTests", dependencies: ["ShelfFeature", "ShelfAdapters"]),
        .target(name: "CameraFeature"),
        .testTarget(name: "CameraFeatureTests", dependencies: ["CameraFeature"]),
        .target(name: "CalendarFeature"),
        .testTarget(name: "CalendarFeatureTests", dependencies: ["CalendarFeature"]),
        .target(name: "MediaFeature"),
        .testTarget(name: "MediaFeatureTests", dependencies: ["MediaFeature"]),
        .target(name: "NotchShell"),
        .target(name: "NotchShellAdapters", dependencies: ["NotchShell"]),
        .testTarget(name: "NotchShellTests", dependencies: ["NotchShell", "NotchShellAdapters"]),
        .target(name: "WorkingOn"),
        .target(name: "WorkingOnAdapters", dependencies: ["WorkingOn"]),
        .testTarget(name: "WorkingOnTests", dependencies: ["WorkingOn", "WorkingOnAdapters"]),
    ]
)
