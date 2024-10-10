// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Gameball",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v11) // Specify the desired iOS version here
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Gameball",
            targets: ["Gameball"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Gameball",
            dependencies: [],
            resources: [
                Resource.process("Resources/Assets/Images"),
                .process("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "GameballTests",
            dependencies: ["Gameball"]),
    ],
    swiftLanguageVersions: [
        .v4_2 // Specify the desired Swift version here
    ]
)
