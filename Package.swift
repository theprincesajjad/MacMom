// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Appfold",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Appfold", targets: ["Appfold"])
    ],
    targets: [
        .target(name: "CLibProc"),
        .target(
            name: "AppfoldCore",
            dependencies: ["CLibProc"]
        ),
        .executableTarget(
            name: "Appfold",
            dependencies: ["AppfoldCore"]
        ),
        .testTarget(
            name: "AppfoldTests",
            dependencies: ["AppfoldCore"]
        )
    ]
)
