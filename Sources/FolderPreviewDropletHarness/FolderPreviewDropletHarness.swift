import DroppyKit
import DroppyKitHarness
import FolderPreviewDroplet
@main
struct FolderPreviewDropletHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { FolderPreviewDroplet() }
}
