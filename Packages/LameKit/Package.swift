// swift-tools-version: 5.9
//
// LameKit – a narrow Swift interface around the LAME 3.100 MP3 encoder.
//
// The C sources in Sources/CLame are the unmodified libmp3lame sources from the
// official LAME 3.100 release (see README.md for origin, checksum and license).
// Only config.h is project specific.

import PackageDescription

let package = Package(
    name: "LameKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LameKit", targets: ["LameKit"])
    ],
    targets: [
        .target(
            name: "CLame",
            path: "Sources/CLame",
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .define("NDEBUG", .when(configuration: .release)),
                .headerSearchPath(".")
            ]
        ),
        .target(
            name: "LameKit",
            dependencies: ["CLame"],
            path: "Sources/LameKit"
        ),
        .testTarget(
            name: "LameKitTests",
            dependencies: ["LameKit"],
            path: "Tests/LameKitTests"
        )
    ]
)
