// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RatuKidulIDE",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "RatuKidulIDE",
            targets: ["RatuKidulIDE"]
        )
    ],
    dependencies: [
        // CodeEdit's tree-sitter powered source editor
        .package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor", from: "0.15.0"),
        // Language definitions for syntax highlighting
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", from: "0.1.20")
    ],
    targets: [
        .executableTarget(
            name: "RatuKidulIDE",
            dependencies: [
                "CodeEditSourceEditor",
                "CodeEditLanguages"
            ],
            path: "RatuKidulIDE"
        ),
        .testTarget(
            name: "RatuKidulIDETests",
            dependencies: ["RatuKidulIDE"],
            path: "RatuKidulIDETests"
        )
    ]
)

