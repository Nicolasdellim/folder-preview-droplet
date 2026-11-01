import AppKit

extension PreviewController {
    func verify(demo: URL, output: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checks: [String] = []
        options = ViewOptions(); applyOptions(save: false)
        await open(demo)
        guard nodes.count >= 6 else { throw PreviewError.message("Dossier de démonstration incomplet : \(nodes.count) éléments") }
        checks.append("Initial folder list")
        guard footerIsLaidOut() else { throw PreviewError.message("Barre de chemin ou contrôles du bas sans dimensions") }
        checks.append("Footer path and controls layout")
        guard let folder = nodes.first(where: { $0.entry.name == "Documents" }) else { throw PreviewError.message("Sous-dossier absent") }
        requestChildren(folder)
        for _ in 0..<100 { if folder.children != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard folder.children?.count ?? 0 >= 2 else { throw PreviewError.message("Arborescence non chargée") }
        outline.expandItem(folder)
        guard outline.numberOfRows > nodes.count else { throw PreviewError.message("Arborescence non dépliée") }
        checks.append("Inline tree expansion")
        try await snapshot(output.appendingPathComponent("liste.png"))
        options.visible.insert(.dimensions); options.visible.insert(.created); applyOptions(save: false)
        guard outline.tableColumns.first(where: { $0.identifier.rawValue == "dimensions" })?.isHidden == false else { throw PreviewError.message("Colonne non affichée") }
        checks.append("Configurable metadata columns")
        options.grid = true; applyOptions(save: false)
        try await snapshot(output.appendingPathComponent("grille.png"))
        guard collection.numberOfItems(inSection: 0) == nodes.count else { throw PreviewError.message("Grille incomplète") }
        checks.append("Icon grid")
        let formats: Set<String> = ["png", "svg", "pdf", "mp4"]
        for _ in 0..<160 { if formats.isSubset(of: generatedThumbnailTypes) { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard formats.isSubset(of: generatedThumbnailTypes) else { throw PreviewError.message("Miniatures absentes : \(formats.subtracting(generatedThumbnailTypes)) ; obtenues : \(generatedThumbnailTypes)") }
        checks.append("PNG, SVG, PDF and video thumbnails")
        options.iconSize = 144; applyOptions(save: false)
        guard (collection.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width == 180 else { throw PreviewError.message("Taille des icônes incorrecte") }
        checks.append("Grid icon sizing")
        await open(demo.appendingPathComponent("Exemple.zip"))
        guard archive != nil, nodes.contains(where: { $0.entry.expandable }) else { throw PreviewError.message("Arbre d’archive invalide") }
        options.grid = false; applyOptions(save: false)
        if let folder = nodes.first(where: { $0.entry.expandable }) {
            requestChildren(folder)
            for _ in 0..<100 { if folder.children != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
            outline.expandItem(folder)
        }
        try await snapshot(output.appendingPathComponent("archive.png"))
        checks.append("Archive tree")
        let before = options
        let suiteName = "FolderPreviewDropletVerification-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        before.save(defaults)
        guard ViewOptions.load(defaults).grid == before.grid, ViewOptions.load(defaults).iconSize == before.iconSize else { throw PreviewError.message("Préférences non conservées") }
        defaults.removePersistentDomain(forName: suiteName)
        checks.append("Preferences round trip")
        let report: [String: Any] = ["passed": true, "checks": checks, "system": ProcessInfo.processInfo.operatingSystemVersionString]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        return checks
    }
    private func snapshot(_ url: URL) async throws {
        view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .seconds(2))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw PreviewError.message("Capture impossible") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.message("PNG impossible") }
        try data.write(to: url)
    }
}
