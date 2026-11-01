import Foundation
import UniformTypeIdentifiers
import Darwin

struct FileMetadata: Sendable {
    var dimensions: String?
    var comment: String?
    var lastOpened: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var area: Double { Double(pixelWidth ?? 0) * Double(pixelHeight ?? 0) }
}
struct Entry: Sendable, Hashable {
    let id: String
    let name: String
    let url: URL?
    let directory: Bool
    let package: Bool
    let link: Bool
    let bytes: Int64
    let modified: Date?
    let created: Date?
    let accessed: Date?
    let added: Date?
    let tags: [String]
    let cloudOnly: Bool
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var expandable: Bool { directory && !package && !link }
    var kind: String { link ? "Lien symbolique" : directory ? (package ? "Paquet" : "Dossier") : UTType(filenameExtension: ext)?.localizedDescription ?? "Fichier" }
    static func virtual(_ path: String, directory: Bool, size: Int64 = 0, modified: Date? = nil) -> Entry {
        Entry(id: path, name: (path as NSString).lastPathComponent, url: nil, directory: directory, package: false, link: false, bytes: size, modified: modified, created: nil, accessed: nil, added: nil, tags: [], cloudOnly: false)
    }
}
struct Listing: Sendable { var entries: [Entry]; var partial: Bool; var skipped: Int = 0 }
struct Totals: Sendable { var bytes: Int64 = 0; var count = 0; var partial = false }
struct TreeTotals: Sendable { var all: Totals; var children: [String: Totals] }
enum PreviewError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
enum Column: String, CaseIterable, Codable {
    case name, modified, created, accessed, added, size, kind, comments, tags, dimensions
    var title: String {
        switch self {
        case .name: return "Nom"
        case .modified: return "Date de modification"
        case .created: return "Date de création"
        case .accessed: return "Dernière ouverture"
        case .added: return "Date d’ajout"
        case .size: return "Taille"
        case .kind: return "Type"
        case .comments: return "Commentaires"
        case .tags: return "Tags"
        case .dimensions: return "Dimensions"
        }
    }
    var width: CGFloat { self == .name ? 285 : [.modified, .created, .accessed, .added].contains(self) ? 190 : self == .size ? 100 : 150 }
}
struct ViewOptions: Codable {
    var grid = false
    var iconSize = 96.0
    var textSize = 13.0
    var rowHeight = 24.0
    var thumbnails = true
    var hidden = false
    var foldersFirst = false
    var showExtensions = true
    var calculateSizes = true
    var showPath = true
    var sort = Column.name
    var ascending = true
    var visible: Set<Column> = [.name, .modified, .size, .kind]
    var ignoredFolders: [String] = []
    var archiveLimitMB = 2048
    var windowWidth = 1000.0
    var windowHeight = 740.0
    static func load(_ defaults: UserDefaults = .standard) -> ViewOptions {
        guard let data = defaults.data(forKey: "viewOptions.v1"), let options = try? JSONDecoder().decode(ViewOptions.self, from: data) else { return ViewOptions() }
        return options
    }
    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "viewOptions.v1") }
    }
}
enum Files {
    static let maximumEntries = 50_000
    static let maximumPreviewBytes: Int64 = 50 * 1024 * 1024
    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "7z", "rar", "jar", "alfredworkflow"]
    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentAccessDateKey, .addedToDirectoryDateKey, .tagNamesKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    static func entry(_ url: URL) throws -> Entry {
        let v = try url.resourceValues(forKeys: keys)
        return Entry(id: url.path, name: url.lastPathComponent, url: url, directory: v.isDirectory == true, package: v.isPackage == true, link: v.isSymbolicLink == true, bytes: Int64(v.fileSize ?? 0), modified: v.contentModificationDate, created: v.creationDate, accessed: v.contentAccessDate, added: v.addedToDirectoryDate, tags: v.tagNames ?? [], cloudOnly: v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus == .notDownloaded)
    }
    static func isHidden(_ url: URL) -> Bool {
        if url.lastPathComponent.hasPrefix(".") { return true }
        var attributes = stat()
        return lstat(url.path, &attributes) == 0 && attributes.st_flags & UInt32(UF_HIDDEN) != 0
    }
    static func list(_ url: URL, hidden: Bool, ignored: [String] = []) throws -> Listing {
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in failure = error; return false }) else { throw PreviewError.message("Ce dossier ne peut pas être lu.") }
        var entries: [Entry] = [], partial = false, skipped = 0
        let deadline = Date().addingTimeInterval(8)
        while let child = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if entries.count >= maximumEntries || Date() > deadline { partial = true; break }
            if !hidden && isHidden(child) { continue }
            do {
                let item = try entry(child)
                if item.directory && ignored.contains(item.name) { continue }
                entries.append(item)
            } catch { skipped += 1 }
        }
        if let failure, entries.isEmpty { throw failure }
        return Listing(entries: entries, partial: partial || failure != nil, skipped: skipped)
    }
    static func totals(_ root: URL, hidden: Bool, ignored: [String]) throws -> TreeTotals {
        var count = 0, visited: Set<String> = [], folderStats: [String: Totals] = [:]
        let deadline = Date().addingTimeInterval(20)
        func walk(_ url: URL, depth: Int) throws -> Totals {
            try Task.checkCancellation()
            guard depth <= 64, count < 200_000, Date() < deadline else { return Totals(partial: true) }
            var attributes = stat()
            guard lstat(url.path, &attributes) == 0 else { return Totals(partial: true) }
            if attributes.st_mode & S_IFMT == S_IFLNK { return Totals() }
            if attributes.st_mode & S_IFMT != S_IFDIR { return Totals(bytes: max(0, attributes.st_size)) }
            let identity = "\(attributes.st_dev):\(attributes.st_ino)"
            guard visited.insert(identity).inserted else { return Totals(partial: true) }
            let listing = try list(url, hidden: hidden, ignored: ignored)
            var result = Totals(partial: listing.partial || listing.skipped > 0)
            for child in listing.entries {
                count += 1; result.count += 1
                guard count <= 200_000, Date() < deadline else { result.partial = true; break }
                guard let path = child.url, !child.cloudOnly, !child.link else { result.partial = result.partial || child.cloudOnly; continue }
                if child.directory {
                    do { let value = try walk(path, depth: depth + 1); result.bytes = safeByteSum(result.bytes, value.bytes); result.count += value.count; result.partial = result.partial || value.partial }
                    catch is CancellationError { throw CancellationError() }
                    catch { result.partial = true }
                } else { result.bytes = safeByteSum(result.bytes, child.bytes) }
            }
            folderStats[url.path] = result
            return result
        }
        let direct = try list(root, hidden: hidden, ignored: ignored)
        var result = TreeTotals(all: Totals(count: direct.entries.count, partial: direct.partial || direct.skipped > 0), children: [:])
        for item in direct.entries {
            try Task.checkCancellation()
            guard let url = item.url, !item.link, !item.cloudOnly else { result.all.partial = result.all.partial || item.cloudOnly; continue }
            if item.directory {
                if root.path == "/Applications" && item.package { continue }
                do {
                    let total = try walk(url, depth: 0)
                    result.children[item.id] = total; result.all.bytes = safeByteSum(result.all.bytes, total.bytes); result.all.count += total.count; result.all.partial = result.all.partial || total.partial
                } catch is CancellationError { throw CancellationError() }
                catch { result.all.partial = true }
            } else { result.all.bytes = safeByteSum(result.all.bytes, item.bytes) }
        }
        result.children.merge(folderStats) { _, new in new }
        return result
    }
    static func sorted(_ entries: [Entry], options: ViewOptions, sizes: [String: Totals] = [:], metadata: [String: FileMetadata] = [:]) -> [Entry] {
        entries.sorted { a, b in
            if options.foldersFirst && a.directory != b.directory { return a.directory }
            let comparison: ComparisonResult
            switch options.sort {
            case .size:
                let x = sizes[a.id]?.bytes ?? a.bytes, y = sizes[b.id]?.bytes ?? b.bytes
                comparison = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            case .modified: comparison = (a.modified ?? .distantPast).compare(b.modified ?? .distantPast)
            case .created: comparison = (a.created ?? .distantPast).compare(b.created ?? .distantPast)
            case .accessed: comparison = (metadata[a.id]?.lastOpened ?? .distantPast).compare(metadata[b.id]?.lastOpened ?? .distantPast)
            case .added: comparison = (a.added ?? .distantPast).compare(b.added ?? .distantPast)
            case .kind: comparison = a.kind.localizedStandardCompare(b.kind)
            case .comments: comparison = (metadata[a.id]?.comment ?? "").localizedStandardCompare(metadata[b.id]?.comment ?? "")
            case .dimensions:
                let x = metadata[a.id]?.area ?? 0, y = metadata[b.id]?.area ?? 0
                comparison = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            case .tags: comparison = a.tags.joined().localizedStandardCompare(b.tags.joined())
            default: comparison = a.name.localizedStandardCompare(b.name)
            }
            let result = comparison == .orderedSame ? a.id.localizedStandardCompare(b.id) : comparison
            return options.ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
    static func read(_ url: URL, limit: Int64 = maximumPreviewBytes) throws -> Data {
        let e = try entry(url)
        guard !e.cloudOnly, !e.link, !e.directory else { throw PreviewError.message("Fichier non local, lien ou dossier : lecture refusée.") }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PreviewError.message("Lecture impossible.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size <= limit else { throw PreviewError.message("Fichier spécial ou dépassant la limite de lecture.") }
        let data = try handle.read(upToCount: Int(limit) + 1) ?? Data()
        guard data.count <= limit else { throw PreviewError.message("Limite de lecture atteinte.") }
        return data
    }
}
