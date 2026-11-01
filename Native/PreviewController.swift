import AppKit
import Quartz
import OSLog

@MainActor
final class Node: NSObject {
    let entry: Entry
    var children: [Node]?
    var loading = false
    init(_ entry: Entry) { self.entry = entry }
}
final class PreviewOutline: NSOutlineView {
    var copyAction: ((Bool) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { copyAction?(event.modifierFlags.contains(.option)); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return super.menu(for: event)
    }
}
final class PreviewCollection: NSCollectionView {
    var copyAction: ((Bool) -> Void)?
    var enterAction: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { copyAction?(event.modifierFlags.contains(.option)); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { enterAction?(); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(path) { selectionIndexPaths = [path] }
        return super.menu(for: event)
    }
}
@MainActor
class PreviewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSMenuDelegate {
    let extensionMode: Bool
    var options = ViewOptions.load()
    private(set) var rootURL: URL?
    private(set) var currentURL: URL?
    private(set) var currentArchivePath = ""
    private(set) var archive: ArchiveIndex?
    private(set) var nodes: [Node] = []
    private var sizes: [String: Totals] = [:]
    private var total: Totals?
    private var listingNotice: String?
    private var errorText: String?
    private var generation = UUID()
    private var rootTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var childTasks: [String: Task<Void, Never>] = [:]
    private var securityURL: URL?
    let outline = PreviewOutline()
    let collection = PreviewCollection()
    private let listScroll = NSScrollView()
    private let gridScroll = NSScrollView()
    private let content = NSView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let path = NSPathControl()
    private let status = NSTextField(labelWithString: "")
    private let optionsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let slider = NSSlider(value: 96, minValue: 48, maxValue: 192, target: nil, action: nil)
    private let thumbnails = ThumbnailStore()
    private let formatter = ByteCountFormatter()
    private let dates = DateFormatter()
    var generatedThumbnailTypes: Set<String> { thumbnails.successes }
    private var onGrid: Bool { options.grid }
    init(extensionMode: Bool = false) { self.extensionMode = extensionMode; super.init(nibName: nil, bundle: nil) }
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) { extensionMode = false; super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil) }
    required init?(coder: NSCoder) { extensionMode = false; super.init(coder: coder) }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 740))
        dates.dateStyle = .medium; dates.timeStyle = .short; dates.doesRelativeDateFormatting = true
        formatter.countStyle = .file
        setupList(); setupGrid()
        thumbnails.onChange = { [weak self] in self?.refreshVisible() }
        content.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(content)
        for scroll in [listScroll, gridScroll] {
            scroll.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(scroll)
            NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        message.alignment = .center; message.textColor = .secondaryLabelColor; message.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(message)
        NSLayoutConstraint.activate([message.centerXAnchor.constraint(equalTo: content.centerXAnchor), message.centerYAnchor.constraint(equalTo: content.centerYAnchor), message.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48)])
        let footerContent = NSView()
        let footer = NSVisualEffectView()
        footer.material = .headerView; footer.blendingMode = .withinWindow; footer.state = .followsWindowActiveState
        footer.wantsLayer = true; footer.layer?.cornerRadius = 12; footer.layer?.masksToBounds = true
        footerContent.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(footerContent)
        NSLayoutConstraint.activate([footerContent.leadingAnchor.constraint(equalTo: footer.leadingAnchor), footerContent.trailingAnchor.constraint(equalTo: footer.trailingAnchor), footerContent.topAnchor.constraint(equalTo: footer.topAnchor), footerContent.bottomAnchor.constraint(equalTo: footer.bottomAnchor)])
        footer.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(footer)
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        path.setContentHuggingPriority(.defaultLow, for: .horizontal)
        path.pathStyle = .standard; path.isEditable = false; path.target = self; path.doubleAction = #selector(pathClicked)
        path.setAccessibilityLabel("Chemin du dossier")
        path.translatesAutoresizingMaskIntoConstraints = false; footerContent.addSubview(path)
        optionsButton.bezelStyle = .accessoryBarAction; optionsButton.setAccessibilityLabel("Présentation et options")
        optionsButton.translatesAutoresizingMaskIntoConstraints = false; footerContent.addSubview(optionsButton)
        optionsButton.toolTip = "Présentation et options"
        status.alignment = .center; status.font = .systemFont(ofSize: 12, weight: .medium); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail; status.translatesAutoresizingMaskIntoConstraints = false; footerContent.addSubview(status)
        slider.target = self; slider.action = #selector(resizeIcons); slider.isContinuous = true; slider.setAccessibilityLabel("Taille des icônes")
        slider.translatesAutoresizingMaskIntoConstraints = false; footerContent.addSubview(slider)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor), content.trailingAnchor.constraint(equalTo: view.trailingAnchor), content.topAnchor.constraint(equalTo: view.topAnchor), content.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -6),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6), footer.heightAnchor.constraint(equalToConstant: 70),
            path.topAnchor.constraint(equalTo: footerContent.topAnchor, constant: 5), path.leadingAnchor.constraint(equalTo: footerContent.leadingAnchor, constant: 12), path.trailingAnchor.constraint(equalTo: footerContent.trailingAnchor, constant: -12), path.heightAnchor.constraint(equalToConstant: 25),
            optionsButton.leadingAnchor.constraint(equalTo: footerContent.leadingAnchor, constant: 12), optionsButton.bottomAnchor.constraint(equalTo: footerContent.bottomAnchor, constant: -7), optionsButton.widthAnchor.constraint(equalToConstant: 52),
            status.centerXAnchor.constraint(equalTo: footerContent.centerXAnchor), status.centerYAnchor.constraint(equalTo: optionsButton.centerYAnchor), status.leadingAnchor.constraint(greaterThanOrEqualTo: optionsButton.trailingAnchor, constant: 10), status.trailingAnchor.constraint(lessThanOrEqualTo: slider.leadingAnchor, constant: -10),
            slider.trailingAnchor.constraint(equalTo: footerContent.trailingAnchor, constant: -16), slider.centerYAnchor.constraint(equalTo: optionsButton.centerYAnchor), slider.widthAnchor.constraint(equalToConstant: 118)
        ])
        applyOptions(save: false)
    }
    func footerIsLaidOut() -> Bool {
        view.layoutSubtreeIfNeeded()
        return path.bounds.width > 100 && status.bounds.width > 30 && optionsButton.bounds.width > 20 && path.superview!.bounds.height >= 60
    }
    private func setupList() {
        listScroll.hasVerticalScroller = true; listScroll.hasHorizontalScroller = true; listScroll.autohidesScrollers = true
        listScroll.borderType = .noBorder
        outline.dataSource = self; outline.delegate = self; outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = true; outline.allowsMultipleSelection = true
        outline.autosaveName = "FolderPreviewDropletColumns"; outline.autosaveTableColumns = true
        outline.allowsColumnReordering = true; outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.indentationPerLevel = 16
        outline.setAccessibilityLabel("Contenu du dossier en liste arborescente")
        for column in Column.allCases {
            let item = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue)); item.title = column.title; item.width = column.width; item.minWidth = 60
            item.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            outline.addTableColumn(item)
            if column == .name { outline.outlineTableColumn = item }
        }
        let columnMenu = NSMenu(); columnMenu.delegate = self; outline.headerView?.menu = columnMenu
        let context = NSMenu(); context.delegate = self; outline.menu = context
        outline.copyAction = { [weak self] paths in self?.copySelection(pathsOnly: paths) }
        listScroll.documentView = outline
    }
    private func setupGrid() {
        gridScroll.hasVerticalScroller = true; gridScroll.autohidesScrollers = true; gridScroll.borderType = .noBorder
        let layout = NSCollectionViewFlowLayout(); layout.minimumInteritemSpacing = 12; layout.minimumLineSpacing = 16; layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        collection.collectionViewLayout = layout; collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.backgroundColors = [.textBackgroundColor]; collection.dataSource = self; collection.delegate = self
        collection.register(PreviewGridItem.self, forItemWithIdentifier: PreviewGridItem.identifier)
        collection.setAccessibilityLabel("Contenu du dossier en grille")
        let menu = NSMenu(); menu.delegate = self; collection.menu = menu
        collection.copyAction = { [weak self] paths in self?.copySelection(pathsOnly: paths) }
        collection.enterAction = { [weak self] in guard let self, let item = selectedEntries().first, item.expandable else { return }; navigate(to: item) }
        gridScroll.documentView = collection
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        collection.frame.size.width = gridScroll.contentSize.width
    }
    override func viewDidDisappear() {
        super.viewDidDisappear(); stopWork()
        if let securityURL { securityURL.stopAccessingSecurityScopedResource(); self.securityURL = nil }
    }
    private func stopWork() {
        rootTask?.cancel(); sizeTask?.cancel(); copyTask?.cancel(); childTasks.values.forEach { $0.cancel() }; childTasks.removeAll(); thumbnails.cancel()
    }
    func open(_ url: URL) async {
        _ = view; stopWork(); generation = UUID()
        if let securityURL { securityURL.stopAccessingSecurityScopedResource() }
        securityURL = url.startAccessingSecurityScopedResource() ? url : nil
        rootURL = url; currentURL = url; currentArchivePath = ""; archive = nil; nodes = []; sizes = [:]; total = nil; errorText = nil; listingNotice = nil
        await loadCurrent()
    }
    private func loadCurrent() async {
        guard let url = currentURL else { return }
        generation = UUID(); let token = generation
        sizeTask?.cancel(); childTasks.values.forEach { $0.cancel() }; childTasks.removeAll()
        errorText = nil; total = nil; sizes = [:]; nodes = []; outline.reloadData(); collection.reloadData(); message.stringValue = "Chargement…"; message.isHidden = false
        let options = options, cached = archive, virtualPath = currentArchivePath
        let task = Task.detached(priority: .userInitiated) { () throws -> (Listing, ArchiveIndex?) in
            if let cached {
                return (Listing(entries: cached.children(of: virtualPath), partial: cached.partial, skipped: cached.skipped), cached)
            }
            let entry = try Files.entry(url)
            if entry.directory { return (try Files.list(url, hidden: options.hidden, ignored: options.ignoredFolders), nil) }
            guard Files.archiveExtensions.contains(entry.ext) else { throw PreviewError.message("Cet aperçu prend en charge les dossiers et archives.") }
            let raw = try Archives.index(url, limitMB: options.archiveLimitMB)
            let visible = raw.entries.filter { item in
                (options.hidden || !item.id.split(separator: "/").contains(where: { $0.hasPrefix(".") })) && !item.id.split(separator: "/").dropLast(item.directory ? 0 : 1).contains(where: { options.ignoredFolders.contains(String($0)) })
            }
            let index = ArchiveIndex(source: raw.source, entries: visible, partial: raw.partial, skipped: raw.skipped, limitMB: raw.limitMB)
            return (Listing(entries: index.children(of: ""), partial: index.partial, skipped: index.skipped), index)
        }
        do {
            let (listing, index) = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard token == generation, !Task.isCancelled else { return }
            archive = index
            listingNotice = listing.partial || listing.skipped > 0 ? "Résultat partiel · \(listing.skipped) élément(s) ignoré(s)" : nil
            nodes = sorted(filtered(listing.entries)).map(Node.init)
            if let index { total = index.totals(of: currentArchivePath); sizes = index.folderTotals }
            reloadViews(); updatePath(); updateStatus()
            if archive == nil && options.calculateSizes { calculateSizes(url) }
            Logger(subsystem: "be.nicolasdellim.folderpreviewdroplet", category: "preview").notice("Preview ready: \(self.nodes.count) direct items")
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            errorText = error.localizedDescription; message.stringValue = error.localizedDescription; message.isHidden = false; updateStatus(); updatePath()
        }
    }
    private func filtered(_ entries: [Entry]) -> [Entry] { entries.filter { (options.hidden || !$0.name.hasPrefix(".")) && !($0.directory && options.ignoredFolders.contains($0.name)) } }
    private func sorted(_ entries: [Entry]) -> [Entry] { Files.sorted(entries, options: options, sizes: sizes, metadata: thumbnails.metadata) }
    private func calculateSizes(_ url: URL) {
        let token = generation, options = options
        sizeTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { try Files.totals(url, hidden: options.hidden, ignored: options.ignoredFolders) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.total = result.all; self.sizes = result.children; self.updateStatus(); self.refreshVisible()
            } catch { if !Task.isCancelled { self?.listingNotice = "Certains totaux ne sont pas disponibles"; self?.updateStatus() } }
        }
    }
    private func updatePath() {
        if let currentURL { path.url = archive == nil || currentArchivePath.isEmpty ? currentURL : currentURL.appendingPathComponent(currentArchivePath) }
        path.isHidden = !options.showPath
    }
    private func updateStatus() {
        if let errorText { status.stringValue = "Aperçu indisponible"; status.toolTip = errorText; return }
        let partial = total?.partial == true || listingNotice != nil
        if let total { status.stringValue = (partial ? "≥ " : "") + formatter.string(fromByteCount: total.bytes) + ", \(total.count) éléments" }
        else { status.stringValue = "\(nodes.count) éléments" + (options.calculateSizes && archive == nil ? " · calcul…" : "") }
        status.toolTip = listingNotice ?? (partial ? "Certains éléments n’ont pas pu être comptés." : nil)
    }
    private func reloadViews() {
        outline.reloadData(); collection.reloadData()
        message.stringValue = errorText ?? (nodes.isEmpty ? "Ce dossier est vide." : "")
        message.isHidden = !nodes.isEmpty
    }
    private func refreshVisible() {
        guard isViewLoaded else { return }
        if !onGrid {
            let range = outline.rows(in: outline.visibleRect)
            if range.length > 0 { outline.reloadData(forRowIndexes: IndexSet(integersIn: range.location..<min(outline.numberOfRows, range.location + range.length)), columnIndexes: IndexSet(integersIn: 0..<outline.tableColumns.count)) }
        } else {
            let paths = collection.indexPathsForVisibleItems()
            if !paths.isEmpty { collection.reloadItems(at: paths) }
        }
    }
    func applyOptions(save: Bool = true) {
        guard isViewLoaded else { return }
        options.iconSize = min(192, max(48, options.iconSize)); options.textSize = min(20, max(10, options.textSize)); options.rowHeight = min(52, max(20, options.rowHeight))
        if save { options.save() }
        listScroll.isHidden = onGrid; gridScroll.isHidden = !onGrid; slider.isHidden = !onGrid; slider.doubleValue = options.iconSize
        outline.rowHeight = options.rowHeight
        for column in outline.tableColumns { if let type = Column(rawValue: column.identifier.rawValue) { column.isHidden = type != .name && !options.visible.contains(type) } }
        outline.sortDescriptors = [NSSortDescriptor(key: options.sort.rawValue, ascending: options.ascending)]
        if let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout { layout.itemSize = NSSize(width: options.iconSize + 36, height: options.iconSize + 100); layout.invalidateLayout() }
        path.isHidden = !options.showPath
        buildOptionsMenu(); reloadViews()
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return nodes.count }
        if node.children == nil && !node.loading { requestChildren(node) }
        return node.children?.count ?? 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children?[index] ?? nodes[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.entry.expandable == true }
    func requestChildren(_ node: Node) {
        guard node.children == nil, !node.loading else { return }
        node.loading = true
        let token = generation, index = archive, options = options, entry = node.entry
        childTasks[entry.id] = Task { [weak self, weak node] in
            let worker = Task.detached(priority: .userInitiated) { () throws -> [Entry] in
                if let index { return index.children(of: entry.id) }
                guard let url = entry.url else { return [] }
                return try Files.list(url, hidden: options.hidden, ignored: options.ignoredFolders).entries
            }
            do {
                let values = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard let self, let node, self.generation == token, !Task.isCancelled else { return }
                node.children = self.sorted(self.filtered(values)).map(Node.init); node.loading = false
                self.outline.reloadItem(node, reloadChildren: true); self.outline.expandItem(node)
            } catch { node?.loading = false; node?.children = [] }
            self?.childTasks[entry.id] = nil
        }
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node, let tableColumn, let type = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let entry = node.entry, identifier = NSUserInterfaceItemIdentifier("cell." + type.rawValue)
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView { cell = reused }
        else {
            cell = NSTableCellView(); cell.identifier = identifier
            let label = NSTextField(labelWithString: ""); label.translatesAutoresizingMaskIntoConstraints = false; label.lineBreakMode = .byTruncatingMiddle
            cell.textField = label; cell.addSubview(label)
            if type == .name {
                let image = NSImageView(); image.translatesAutoresizingMaskIntoConstraints = false; image.imageScaling = .scaleProportionallyUpOrDown
                cell.addSubview(image); cell.imageView = image
                NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18), label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5)])
            } else { label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5).isActive = true }
            NSLayoutConstraint.activate([label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        cell.textField?.font = .systemFont(ofSize: options.textSize)
        cell.textField?.textColor = type == .name ? .labelColor : .secondaryLabelColor
        cell.textField?.alignment = type == .size ? .right : .left
        cell.textField?.stringValue = value(entry, column: type)
        if type == .name { cell.imageView?.image = thumbnails.image(entry, points: 20, scale: view.window?.backingScaleFactor ?? 2, archive: archive, enabled: options.thumbnails) }
        cell.toolTip = entry.name
        if [.dimensions, .comments].contains(type) { thumbnails.loadMetadata(entry) }
        return cell
    }
    private func value(_ entry: Entry, column: Column) -> String {
        switch column {
        case .name: return displayName(entry)
        case .size: return entry.directory ? sizes[entry.id].map { formatter.string(fromByteCount: $0.bytes) } ?? "—" : formatter.string(fromByteCount: entry.bytes)
        case .kind: return entry.kind
        case .modified: return entry.modified.map(dates.string) ?? "—"
        case .created: return entry.created.map(dates.string) ?? "—"
        case .accessed: return entry.accessed.map(dates.string) ?? "—"
        case .added: return entry.added.map(dates.string) ?? "—"
        case .tags: return entry.tags.joined(separator: ", ")
        case .comments: return thumbnails.metadata[entry.id]?.comment ?? ""
        case .dimensions: return thumbnails.metadata[entry.id]?.dimensions ?? "—"
        }
    }
    private func displayName(_ entry: Entry) -> String { options.showExtensions || entry.directory || entry.ext.isEmpty ? entry.name : (entry.name as NSString).deletingPathExtension }
    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sort = outlineView.sortDescriptors.first, let key = sort.key, let column = Column(rawValue: key) else { return }
        let changed = column != options.sort || sort.ascending != options.ascending
        options.sort = column; options.ascending = sort.ascending
        guard changed else { return }
        options.save()
        func sortNodes(_ nodes: [Node]) -> [Node] {
            let map = Dictionary(uniqueKeysWithValues: nodes.map { ($0.entry.id, $0) })
            let sortedNodes = sorted(nodes.map(\.entry)).compactMap { map[$0.id] }
            for node in sortedNodes { if let children = node.children { node.children = sortNodes(children) } }
            return sortedNodes
        }
        nodes = sortNodes(nodes); reloadViews()
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { nodes.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PreviewGridItem.identifier, for: indexPath) as! PreviewGridItem
        let entry = nodes[indexPath.item].entry
        thumbnails.loadMetadata(entry)
        let detail = entry.directory ? sizes[entry.id].map { "\($0.count) éléments" } ?? "Dossier" : thumbnails.metadata[entry.id]?.dimensions ?? formatter.string(fromByteCount: entry.bytes)
        item.configure(entry: entry, title: displayName(entry), detail: detail, image: thumbnails.image(entry, points: options.iconSize, scale: view.window?.backingScaleFactor ?? 2, archive: archive, enabled: options.thumbnails), font: options.textSize)
        item.doubleClick = { [weak self] entry in if entry.expandable { self?.navigate(to: entry) } }
        return item
    }
    private func navigate(to entry: Entry) {
        guard entry.expandable else { return }
        if archive != nil { currentArchivePath = entry.id }
        else { currentURL = entry.url }
        rootTask?.cancel(); rootTask = Task { await loadCurrent() }
    }
    @objc private func pathClicked() {
        guard let selected = path.clickedPathItem?.url, let rootURL else { return }
        if archive != nil {
            guard selected.path.hasPrefix(rootURL.path) else { return }
            currentArchivePath = String(selected.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            let rootPath = rootURL.resolvingSymlinksInPath().path, selectedPath = selected.resolvingSymlinksInPath().path
            guard selectedPath == rootPath || selectedPath.hasPrefix(rootPath + "/") else { return }
            currentURL = selected
        }
        rootTask?.cancel(); rootTask = Task { await loadCurrent() }
    }
    @objc private func resizeIcons() {
        options.iconSize = slider.doubleValue; options.save()
        if let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout { layout.itemSize = NSSize(width: options.iconSize + 36, height: options.iconSize + 100); layout.invalidateLayout() }
        refreshVisible()
    }
    private func selectedEntries() -> [Entry] {
        if onGrid { return collection.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap { nodes.indices.contains($0.item) ? nodes[$0.item].entry : nil } }
        return outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? Node)?.entry }
    }
    func outlineViewSelectionDidChange(_ notification: Notification) { buildOptionsMenu() }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { buildOptionsMenu() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { buildOptionsMenu() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === outline.headerView?.menu {
            for column in Column.allCases where column != .name {
                if column == .dimensions { menu.addItem(.separator()) }
                let item = menu.addItem(withTitle: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: ""); item.target = self; item.representedObject = column.rawValue; item.state = options.visible.contains(column) ? .on : .off
            }
        } else {
            let selected = selectedEntries()
            if !selected.isEmpty {
                menu.addItem(withTitle: "Copier", action: #selector(copyFiles), keyEquivalent: "").target = self
                menu.addItem(withTitle: "Copier le chemin", action: #selector(copyPaths), keyEquivalent: "").target = self
            }
        }
    }
    @objc private func toggleColumn(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String, let column = Column(rawValue: key) else { return }
        if options.visible.contains(column) { options.visible.remove(column) } else { options.visible.insert(column) }
        applyOptions()
    }
    @objc private func copyFiles() { copySelection(pathsOnly: false) }
    @objc private func copyPaths() { copySelection(pathsOnly: true) }
    private func copySelection(pathsOnly: Bool) {
        let selected = selectedEntries(); guard !selected.isEmpty else { return }
        if pathsOnly {
            let text = selected.map { $0.url?.path ?? (archive?.source.path ?? "Archive") + ":/" + $0.id }.joined(separator: "\n")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); return
        }
        if selected.allSatisfy({ $0.url != nil }) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(selected.compactMap(\.url).map { $0 as NSURL }); return }
        guard let archive else { return }
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            do {
                let cache = try Self.clipboardCache()
                let destination = cache.appendingPathComponent(UUID().uuidString)
                let task = Task.detached(priority: .userInitiated) { try Archives.copySelection(selected, from: archive, into: destination) }
                let urls = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: destination); return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
                self?.status.toolTip = "Fichiers copiés depuis l’archive. La copie temporaire est conservée pendant 24 h."
            } catch { if !Task.isCancelled { self?.status.stringValue = "Copie impossible"; self?.status.toolTip = error.localizedDescription } }
        }
    }
    private static func clipboardCache() throws -> URL {
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("FolderPreviewDroplet-clipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let deadline = Date().addingTimeInterval(-24 * 3600)
        for child in (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if UUID(uuidString: child.lastPathComponent) != nil, let date = try? child.resourceValues(forKeys: [.creationDateKey]).creationDate, date < deadline { try? FileManager.default.removeItem(at: child) }
        }
        return cache
    }
    private func buildOptionsMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Présentation", action: nil, keyEquivalent: ""); title.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Présentation"); menu.addItem(title)
        addOption(menu, title: "En liste", key: "list", checked: !onGrid)
        addOption(menu, title: "En icônes", key: "grid", checked: onGrid)
        menu.addItem(.separator())
        addOption(menu, title: "Afficher les miniatures", key: "thumbnails", checked: options.thumbnails)
        addOption(menu, title: "Afficher les fichiers masqués", key: "hidden", checked: options.hidden)
        addOption(menu, title: "Dossiers en premier", key: "foldersFirst", checked: options.foldersFirst)
        addOption(menu, title: "Afficher les extensions", key: "extensions", checked: options.showExtensions)
        addOption(menu, title: "Afficher le chemin", key: "path", checked: options.showPath)
        addOption(menu, title: "Calculer les tailles des dossiers", key: "sizes", checked: options.calculateSizes)
        let window = NSMenuItem(title: "Taille de la fenêtre", action: nil, keyEquivalent: ""), windows = NSMenu()
        for (title, width, height) in [("Compacte", 800, 600), ("Normale", 1000, 740), ("Grande", 1200, 860)] { addOption(windows, title: title, key: "window:\(width)x\(height)", checked: options.windowWidth == Double(width) && options.windowHeight == Double(height)) }; window.submenu = windows; menu.addItem(window)
        let ignored = NSMenuItem(title: "Dossiers ignorés", action: nil, keyEquivalent: ""), ignoredMenu = NSMenu()
        let selectedNames = Set(selectedEntries().filter(\.expandable).map(\.name))
        if selectedNames.isEmpty && options.ignoredFolders.isEmpty {
            let hint = NSMenuItem(title: "Sélectionnez un dossier à ignorer", action: nil, keyEquivalent: ""); hint.isEnabled = false; ignoredMenu.addItem(hint)
        }
        for name in selectedNames.sorted() where !options.ignoredFolders.contains(name) { addOption(ignoredMenu, title: "Ignorer « \(name) »", key: "ignore:" + name, checked: false) }
        for name in options.ignoredFolders { addOption(ignoredMenu, title: name, key: "ignore:" + name, checked: true) }
        ignored.submenu = ignoredMenu; menu.addItem(ignored)
        let text = NSMenuItem(title: "Taille du texte", action: nil, keyEquivalent: ""), textMenu = NSMenu()
        for value in [11, 12, 13, 14, 16, 18] { addOption(textMenu, title: "\(value) pt", key: "text:\(value)", checked: options.textSize == Double(value)) }; text.submenu = textMenu; menu.addItem(text)
        let rows = NSMenuItem(title: "Hauteur des lignes", action: nil, keyEquivalent: ""), rowMenu = NSMenu()
        for value in [20, 24, 28, 32, 40] { addOption(rowMenu, title: "\(value) pt", key: "row:\(value)", checked: options.rowHeight == Double(value)) }; rows.submenu = rowMenu; menu.addItem(rows)
        let limit = NSMenuItem(title: "Taille maximale des archives", action: nil, keyEquivalent: ""), limits = NSMenu()
        for value in [256, 1024, 2048, 8192] { addOption(limits, title: "\(value) Mo", key: "limit:\(value)", checked: options.archiveLimitMB == value) }; limit.submenu = limits; menu.addItem(limit)
        menu.addItem(.separator()); addOption(menu, title: "Actualiser", key: "refresh", checked: false)
        addOption(menu, title: "Réinitialiser la présentation", key: "reset", checked: false)
        optionsButton.menu = menu
    }
    private func addOption(_ menu: NSMenu, title: String, key: String, checked: Bool) {
        let item = menu.addItem(withTitle: title, action: #selector(changeOption(_:)), keyEquivalent: ""); item.target = self; item.representedObject = key; item.state = checked ? .on : .off
    }
    @objc private func changeOption(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String else { return }
        var reload = false
        switch key {
        case "list": options.grid = false
        case "grid": options.grid = true
        case "thumbnails": options.thumbnails.toggle()
        case "hidden": options.hidden.toggle(); if archive != nil { archive = nil; currentArchivePath = "" }; reload = true
        case "foldersFirst": options.foldersFirst.toggle(); reload = true
        case "extensions": options.showExtensions.toggle()
        case "path": options.showPath.toggle()
        case "sizes": options.calculateSizes.toggle(); reload = true
        case "refresh": thumbnails.cancel(); archive = nil; currentURL = rootURL; currentArchivePath = ""; reload = true
        case "reset": options = ViewOptions(); reload = true
        default:
            if key.hasPrefix("window:") {
                let values = key.dropFirst(7).split(separator: "x").compactMap { Double($0) }
                if values.count == 2 { options.windowWidth = values[0]; options.windowHeight = values[1]; preferredContentSize = NSSize(width: values[0], height: values[1]) }
            }
            if key.hasPrefix("ignore:") {
                let name = String(key.dropFirst(7))
                if options.ignoredFolders.contains(name) { options.ignoredFolders.removeAll { $0 == name } } else { options.ignoredFolders.append(name) }
                if archive != nil { archive = nil; currentArchivePath = "" }; reload = true
            }
            if key.hasPrefix("text:"), let value = Double(key.dropFirst(5)) { options.textSize = value }
            if key.hasPrefix("row:"), let value = Double(key.dropFirst(4)) { options.rowHeight = value }
            if key.hasPrefix("limit:"), let value = Int(key.dropFirst(6)) { options.archiveLimitMB = value; archive = nil; reload = true }
        }
        applyOptions()
        if reload { rootTask?.cancel(); rootTask = Task { await loadCurrent() } }
    }
}
@objc(FolderPreviewExtensionController)
final class FolderPreviewExtensionController: PreviewController, QLPreviewingController {
    init() { super.init(extensionMode: true) }
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) { super.init(extensionMode: true) }
    required init?(coder: NSCoder) { super.init(extensionMode: true) }
    func preparePreviewOfFile(at url: URL) async throws { preferredContentSize = NSSize(width: options.windowWidth, height: options.windowHeight); await open(url) }
}
