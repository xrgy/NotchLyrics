// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchLyrics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotchLyricsCore", targets: ["NotchLyricsCore"]),
        .executable(name: "NotchLyrics", targets: ["NotchLyricsApp"])
    ],
    targets: [
        .target(
            name: "NotchLyricsCore",
            path: "Sources/NotchLyrics",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "NotchLyricsApp",
            dependencies: ["NotchLyricsCore"],
            path: "Sources/NotchLyricsApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "NotchLyricsSmokeTests",
            dependencies: ["NotchLyricsCore"],
            path: "Sources/NotchLyricsSmokeTests"
        )
    ]
)
