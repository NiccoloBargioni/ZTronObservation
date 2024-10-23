// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZTronObservation",
    platforms: [
        .macOS(.v11),
        .iOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ZTronObservation",
            targets: ["ZTronObservation"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(
            url: "https://github.com/NickTheFreak97/SwiftGraph", branch: "msa"
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ZTronObservation",
            dependencies: [
                .product(name: "SwiftGraph", package: "SwiftGraph")
            ],
            swiftSettings: [
                /// Xcode 15 & 16. Remove `=targeted` to use the default `complete`. Potentially isolate to a platform to further reduce scope.
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
        ),
        
        .testTarget(
            name: "ZTronObservationTests",
            dependencies: ["ZTronObservation", .product(name: "SwiftGraph", package: "SwiftGraph")]),
        .testTarget(
            name: "MSATests",
            dependencies: ["ZTronObservation", .product(name: "SwiftGraph", package: "SwiftGraph")]),
    ]
)
