// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "thunderid_flutter",
    platforms: [.iOS("16.0")],
    products: [
        .library(name: "thunderid-flutter", targets: ["thunderid_flutter"])
    ],
    dependencies: [
        .package(url: "https://github.com/thunder-id/ios-sdks.git", .upToNextMinor(from: "1.0.2"))
    ],
    targets: [
        .target(
            name: "thunderid_flutter",
            dependencies: [
                .product(name: "ThunderID", package: "ios-sdks")
            ],
            path: "../Classes"
        )
    ]
)
