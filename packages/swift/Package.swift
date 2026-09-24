// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpensmsSDK",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "Opensms", targets: ["Opensms"])
    ],
    targets: [
        .target(name: "Opensms"),
        .testTarget(
            name: "OpensmsTests",
            dependencies: ["Opensms"]
        )
    ]
)
