// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpeechAnalyzerWrapper",
    platforms: [
        .macOS(.v14)  // macOS 26.0 = .v14
    ],
    products: [
        .library(
            name: "SpeechAnalyzerWrapper",
            type: .dynamic,
            targets: ["SpeechAnalyzerWrapper"]
        )
    ],
    targets: [
        .target(
            name: "SpeechAnalyzerWrapper",
            dependencies: [],
            path: "Sources/SpeechAnalyzerWrapper",
            swiftSettings: [
                .unsafeFlags(
                    [
                        "-emit-clang-header-path",
                        ".build/SpeechAnalyzerWrapper/SpeechAnalyzerWrapper.h",
                    ], .when(configuration: .release))
            ]
        )
    ]
)
