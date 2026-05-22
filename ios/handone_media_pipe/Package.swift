// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "handone_media_pipe",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "handone-media-pipe", targets: ["handone_media_pipe"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/paescebu/SwiftTasksVision.git", revision: "2cba94cf7d38ace98e32dc08d1de7a6895f05057")
    ],
    targets: [
        .target(
            name: "handone_media_pipe",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "SwiftTasksVision", package: "SwiftTasksVision")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
