// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dir_picker",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "dir-picker", targets: ["dir_picker"]),
    ],
    targets: [
        // Internal C target — exposes DartApiDl module to Swift, and has the
        // Objective-C class DirPickerFFISymbols, which gives Dart the addresses
        // of the functions of dir_picker_ffi.h.
        .target(
            name: "DartApiDl",
            path: "Sources/DartApiDl",
            publicHeadersPath: "include"
        ),
        // Main plugin target
        .target(
            name: "dir_picker",
            dependencies: ["DartApiDl"],
            path: "Sources/dir_picker",
            resources: [
                // Declares the file timestamps listEntries reads.
                .process("PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
    ]
)
