// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RatuKidulIDE",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RatuKidulIDE",
            targets: ["RatuKidulIDE"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RatuKidulIDE",
            dependencies: [],
            path: "RatuKidulIDE"
        ),
        .testTarget(
            name: "RatuKidulIDETests",
            dependencies: ["RatuKidulIDE"],
            path: "RatuKidulIDETests"
        )
    ]
)

