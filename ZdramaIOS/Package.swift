// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZdramaIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ZdramaCore", targets: ["ZdramaCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.1")
    ],
    targets: [
        .target(
            name: "ZdramaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "ZdramaCoreTests",
            dependencies: ["ZdramaCore"]
        )
    ]
)
