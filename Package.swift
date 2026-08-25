// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Huayi",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Huayi", targets: ["Huayi"]),
    ],
    targets: [
        .executableTarget(
            name: "Huayi",
            path: "Sources/Huayi",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Translation"),
                .linkedFramework("Vision"),
            ]
        ),
        .testTarget(
            name: "HuayiTests",
            dependencies: ["Huayi"],
            path: "Tests/HuayiTests"
        ),
    ]
)
