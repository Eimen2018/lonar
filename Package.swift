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
            // Sparkle.framework comes from Scripts/fetch-sparkle.sh (pinned
            // official release into .sparkle/) — SPM's binary-artifact
            // downloader is avoided deliberately.
            swiftSettings: [
                .unsafeFlags(["-F", ".sparkle"]),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreDisplay"),
                .unsafeFlags([
                    "-F", ".sparkle",
                    // Installed app: framework embedded in the bundle.
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    // Dev builds run from .build/<config>/: use .sparkle/ directly.
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../.sparkle",
                ]),
            ]
        ),
    ]
)
