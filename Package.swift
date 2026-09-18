// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "strafe",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "strafe-tatoalo", targets: ["strafe"]),
        // Exposes the CStrafe target so the standalone `bench/` measurement
        // package (a dev tool, not part of the shipped strafe app) can import
        // the exact same synthesis code path via `.package(path: "..")`. This
        // is the only concession the main package makes to bench; the app
        // itself does not consume this product.
        .library(name: "CStrafe", targets: ["CStrafe"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "CStrafe",
            path: "Sources/CStrafe",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "strafe",
            dependencies: ["CStrafe", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/strafe",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "strafeTests",
            dependencies: ["strafe", "CStrafe"],
            path: "Tests/strafeTests"
        )
    ]
)
