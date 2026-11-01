import AppKit
import QuickLookThumbnailing
import ImageIO
import CoreServices
import UniformTypeIdentifiers

@MainActor
final class ThumbnailStore {
    private var generation = UUID()
    private let cache = NSCache<NSString, NSImage>()
    private var icons: [String: NSImage] = [:]
    private var jobs: [String: Task<Void, Never>] = [:]
    private var requests: [String: QLThumbnailGenerator.Request] = [:]
    private var failed: Set<String> = []
    private(set) var metadata: [String: FileMetadata] = [:]
    private var metadataJobs: Set<String> = []
    private var temporary: URL?
    var onChange: (() -> Void)?
    var successes: Set<String> = []
    init() { cache.totalCostLimit = 80 * 1024 * 1024; cache.countLimit = 400 }
    func icon(_ entry: Entry) -> NSImage {
        if let value = icons[entry.id] { return value }
        let image: NSImage
        if let url = entry.url { image = NSWorkspace.shared.icon(forFile: url.path) }
        else { image = NSWorkspace.shared.icon(for: entry.directory ? .folder : UTType(filenameExtension: entry.ext) ?? .data) }
        icons[entry.id] = image
        return image
    }
    func image(_ entry: Entry, points: CGFloat, scale: CGFloat, archive: ArchiveIndex?, enabled: Bool) -> NSImage {
        let fallback = icon(entry)
        guard enabled, !entry.directory, !entry.link, !entry.cloudOnly, entry.bytes <= Files.maximumPreviewBytes else { return fallback }
        let pixels = min(768, max(64, Int((points * scale / 64).rounded(.up)) * 64))
        let key = "\(entry.id):\(entry.modified?.timeIntervalSince1970 ?? 0):\(entry.bytes):\(pixels)"
        if let image = cache.object(forKey: key as NSString) { return image }
        guard jobs[key] == nil, !failed.contains(key), jobs.count < 48 else { return fallback }
        let token = generation
        jobs[key] = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.jobs[key] = nil; self.requests[key] = nil; self.onChange?() } }
            do {
                let url: URL
                if let path = entry.url { url = path }
                else {
                    guard let archive else { throw PreviewError.message("Source d’archive absente.") }
                    let directory = try temporaryDirectory()
                    let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(entry.ext)
                    let worker = Task.detached(priority: .utility) { () throws -> URL in
                        let data = try Archives.data(archive, path: entry.id)
                        try Task.checkCancellation()
                        try data.write(to: target, options: .atomic)
                        return target
                    }
                    url = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                }
                try Task.checkCancellation()
                let request = QLThumbnailGenerator.Request(fileAt: url, size: NSSize(width: pixels, height: pixels), scale: 1, representationTypes: .all)
                requests[key] = request
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                let image = representation.nsImage
                try Task.checkCancellation()
                guard token == self.generation else { return }
                cache.setObject(image, forKey: key as NSString, cost: pixels * pixels * 4)
                if representation.type != .icon { successes.insert(entry.ext) }
            } catch { if token == self.generation { failed.insert(key) } }
        }
        return fallback
    }
    func loadMetadata(_ entry: Entry) {
        guard let url = entry.url, !entry.directory, !entry.cloudOnly, !entry.link, metadata[entry.id] == nil, metadataJobs.insert(entry.id).inserted else { return }
        let token = generation
        Task { [weak self] in
            let value = await Task.detached(priority: .utility) { () -> FileMetadata in
                var output = FileMetadata()
                if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
                    output.dimensions = "\(width.formatted()) × \(height.formatted())"
                    output.pixelWidth = width; output.pixelHeight = height
                }
                if entry.ext == "svg", let data = try? Files.read(url, limit: 256 * 1024), let text = String(data: data, encoding: .utf8), !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") {
                    let dimensions = SVGDimensions(); let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = dimensions; _ = parser.parse()
                    if let width = dimensions.width, let height = dimensions.height {
                        output.dimensions = "\(width.formatted()) × \(height.formatted())"; output.pixelWidth = width; output.pixelHeight = height
                    }
                }
                if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL), let comment = MDItemCopyAttribute(item, kMDItemFinderComment) as? String { output.comment = comment }
                return output
            }.value
            guard let self, token == self.generation else { return }
            self.metadata[entry.id] = value; self.onChange?()
        }
    }
    func cancel() {
        generation = UUID()
        jobs.values.forEach { $0.cancel() }
        requests.values.forEach { QLThumbnailGenerator.shared.cancel($0) }
        jobs.removeAll(); requests.removeAll(); metadataJobs.removeAll(); failed.removeAll()
        icons.removeAll(); cache.removeAllObjects(); metadata.removeAll()
        if let temporary { try? FileManager.default.removeItem(at: temporary) }; temporary = nil
    }
    private func temporaryDirectory() throws -> URL {
        if let temporary { return temporary }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FolderPreviewDroplet-thumbnails-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        temporary = url
        return url
    }
}

private final class SVGDimensions: NSObject, XMLParserDelegate {
    var width: Int?, height: Int?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName.lowercased() == "svg" else { return }
        func numeric(_ value: String?) -> Int? {
            guard let value, !value.contains("%"), let n = Double(value.prefix(while: { $0.isNumber || $0 == "." })), n > 0, n < 100_000_000 else { return nil }; return Int(n)
        }
        width = numeric(attributes["width"]); height = numeric(attributes["height"])
        if width == nil || height == nil, let values = attributes["viewBox"]?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) }), values.count == 4, values[2] > 0, values[3] > 0, values[2] < 100_000_000, values[3] < 100_000_000 { width = Int(values[2]); height = Int(values[3]) }
        parser.abortParsing()
    }
}
