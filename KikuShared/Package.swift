// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KikuShared",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "KikuShared", targets: ["KikuShared"]),
    ],
    targets: [
        .target(
            name: "KikuShared",
            path: "Sources/KikuShared"
        ),
    ]
)
