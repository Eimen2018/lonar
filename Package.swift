// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lonar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LonarObjC",
            path: "Sources/LonarObjC",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Lonar",
            dependencies: ["LonarObjC"],
            path: "Sources/Lonar",
            exclude: ["Vendor/LICENSE-AppleSiliconDDC"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreDisplay"),
            ]
        ),
    ]
)
