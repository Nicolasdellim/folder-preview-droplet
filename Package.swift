// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "FolderPreviewDroplet",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FolderPreviewDroplet", type: .dynamic, targets: ["FolderPreviewDroplet"])],
    dependencies: [.package(url: "https://gitlab.com/droppyformac1/droppykit.git", exact: "1.20.1")],
    targets: [
        .target(name: "FolderPreviewDroplet", dependencies: [.product(name: "DroppyKit", package: "droppykit")]),
        .executableTarget(
            name: "FolderPreviewDropletHarness",
            dependencies: ["FolderPreviewDroplet", .product(name: "DroppyKitHarness", package: "droppykit")]
        )
    ]
)
