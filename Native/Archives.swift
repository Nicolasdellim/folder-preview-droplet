import Foundation
import CArchive
import Darwin

func safeByteSum(_ a: Int64, _ b: Int64) -> Int64 {
    let value = a.addingReportingOverflow(b)
    return value.overflow ? Int64.max : max(0, value.partialValue)
}
struct ArchiveIndex: Sendable {
    let source: URL
    let entries: [Entry]
    let partial: Bool
    let skipped: Int
    let limitMB: Int
    let folderTotals: [String: Totals]
    private let childMap: [String: [Entry]]
    init(source: URL, entries: [Entry], partial: Bool, skipped: Int, limitMB: Int = 2048) {
        self.source = source; self.entries = entries; self.partial = partial; self.skipped = skipped; self.limitMB = limitMB
        var totals: [String: Totals] = ["": Totals(count: entries.count, partial: partial || skipped > 0)]
        var map: [String: [Entry]] = [:]
        for entry in entries {
            let parent = (entry.id as NSString).deletingLastPathComponent
            map[parent, default: []].append(entry)
            if entry.directory && totals[entry.id] == nil { totals[entry.id] = Totals(partial: partial) }
            if !entry.directory { totals[""]!.bytes = safeByteSum(totals[""]!.bytes, entry.bytes) }
            let parts = entry.id.split(separator: "/")
            if parts.count > 1 {
                for length in 1..<parts.count {
                    let prefix = parts.prefix(length).joined(separator: "/")
                    var value = totals[prefix] ?? Totals(partial: partial)
                    value.count += 1
                    if !entry.directory { value.bytes = safeByteSum(value.bytes, entry.bytes) }
                    totals[prefix] = value
                }
            }
        }
        folderTotals = totals; childMap = map
    }
    func children(of path: String) -> [Entry] { childMap[path] ?? [] }
    func totals(of path: String = "") -> Totals { folderTotals[path] ?? Totals(partial: partial) }

}
enum Archives {
    static func safePath(_ path: String) -> String? {
        guard !path.hasPrefix("/"), !path.contains("\\"), path.utf8.count < 4096 else { return nil }
        let components = path.split(separator: "/").map(String.init)
        guard components.count <= 64, !components.contains(".."), !components.isEmpty, !(components.first?.contains(":") ?? false) else { return nil }
        let clean = components.filter { $0 != "." }.joined(separator: "/")
        return clean.isEmpty ? nil : clean
    }
    static func withReader<T>(_ url: URL, limitMB: Int = 2048, body: (OpaquePointer) throws -> T) throws -> T {
        let info = try Files.entry(url)
        guard !info.cloudOnly, !info.link, info.bytes <= Int64(limitMB) * 1024 * 1024 else { throw PreviewError.message("Archive non téléchargée, lien ou taille dépassant la limite définie.") }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw PreviewError.message("Archive inaccessible.") }
        defer { Darwin.close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw PreviewError.message("Cette archive n’est pas un fichier ordinaire.") }
        guard let reader = archive_read_new() else { throw PreviewError.message("Moteur d’archives indisponible.") }
        defer { archive_read_free(reader) }
        archive_read_support_filter_all(reader)
        archive_read_support_format_all(reader)
        if ["gz", "bz2", "xz"].contains(url.pathExtension.lowercased()) { archive_read_support_format_raw(reader) }
        guard archive_read_open_fd(reader, descriptor, 64 * 1024) == ARCHIVE_OK else { throw PreviewError.message("Archive illisible, chiffrée ou format non pris en charge.") }
        return try body(reader)
    }
    private static func entryPath(_ entry: OpaquePointer, reader: OpaquePointer, source: URL) -> String? {
        if archive_format(reader) == ARCHIVE_FORMAT_RAW {
            guard archive_filter_count(reader) > 1 else { return nil }
            return safePath(source.deletingPathExtension().lastPathComponent)
        }
        guard let string = archive_entry_pathname(entry) else { return nil }
        return safePath(String(cString: string))
    }
    static func index(_ url: URL, limitMB: Int = 2048) throws -> ArchiveIndex {
        try withReader(url, limitMB: limitMB) { reader in
            var entry: OpaquePointer?, found: [String: Entry] = [:], count = 0, skipped = 0, partial = false
            let deadline = Date().addingTimeInterval(12)
            while true {
                try Task.checkCancellation()
                let status = archive_read_next_header(reader, &entry)
                if status == ARCHIVE_EOF { break }
                guard status >= ARCHIVE_WARN, let entry else { throw PreviewError.message("Archive endommagée, chiffrée ou codec non pris en charge.") }
                count += 1
                if count > Files.maximumEntries || found.count >= Files.maximumEntries || Date() > deadline { partial = true; break }
                guard let path = entryPath(entry, reader: reader, source: url), archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil else { skipped += 1; continue }
                let type = archive_entry_filetype(entry)
                guard type == 0o040000 || type == 0o100000 else { skipped += 1; continue }
                let parts = path.split(separator: "/")
                if parts.count > 1 {
                    for length in 1..<parts.count {
                        let parent = parts.prefix(length).joined(separator: "/")
                        if found[parent] == nil { found[parent] = Entry.virtual(parent, directory: true) }
                    }
                }
                if found[path] == nil || type == 0o040000 {
                    found[path] = Entry.virtual(path, directory: type == 0o040000, size: max(0, archive_entry_size(entry)), modified: Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))))
                } else { skipped += 1 }
            }
            return ArchiveIndex(source: url, entries: Array(found.values), partial: partial, skipped: skipped, limitMB: limitMB)
        }
    }
    static func data(_ index: ArchiveIndex, path: String, limit: Int = Int(Files.maximumPreviewBytes)) throws -> Data {
        try withReader(index.source, limitMB: index.limitMB) { reader in
            var entry: OpaquePointer?
            let deadline = Date().addingTimeInterval(10)
            var scanned = 0
            while true {
                try Task.checkCancellation()
                let status = archive_read_next_header(reader, &entry)
                if status == ARCHIVE_EOF { break }
                guard status >= ARCHIVE_WARN, let entry else { throw PreviewError.message("Archive illisible.") }
                scanned += 1
                guard scanned <= Files.maximumEntries, Date() < deadline else { throw PreviewError.message("Budget de lecture atteint.") }
                guard entryPath(entry, reader: reader, source: index.source) == path else { continue }
                guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil, archive_entry_filetype(entry) == 0o100000, archive_entry_size(entry) <= limit else { throw PreviewError.message("Cette entrée ne peut pas être prévisualisée.") }
                var output = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
                while true {
                    try Task.checkCancellation()
                    guard Date() < deadline else { throw PreviewError.message("Temps de lecture dépassé.") }
                    let read = archive_read_data(reader, &buffer, buffer.count)
                    guard read >= 0 else { throw PreviewError.message("Fichier chiffré ou endommagé.") }
                    if read == 0 { return output }
                    guard output.count + read <= limit else { throw PreviewError.message("Fichier trop volumineux pour cet aperçu.") }
                    output.append(contentsOf: buffer.prefix(read))
                }
            }
            throw PreviewError.message("Entrée absente de l’archive.")
        }
    }
    /// Selected archive members are materialized into a fresh, private destination.
    /// The caller retains this directory while the pasteboard references its files.
    static func copySelection(_ selected: [Entry], from index: ArchiveIndex, into directory: URL) throws -> [URL] {
        let chosen = selected.filter { item in !selected.contains { $0.directory && item.id.hasPrefix($0.id + "/") } }
        guard !index.partial || !chosen.contains(where: \.directory) else { throw PreviewError.message("Une archive partielle ne permet pas de copier un dossier complet.") }
        guard !chosen.isEmpty, chosen.allSatisfy({ safePath($0.id) == $0.id }) else { throw PreviewError.message("Sélection invalide.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let all = index.entries.filter { item in chosen.contains { item.id == $0.id || ($0.directory && item.id.hasPrefix($0.id + "/")) } }
            guard all.count <= 10_000, all.reduce(Int64(0), { safeByteSum($0, $1.directory ? 0 : $1.bytes) }) <= 256 * 1024 * 1024 else { throw PreviewError.message("Copie limitée à 10 000 éléments et 256 Mo.") }
            let targets = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            for folder in all.filter(\.directory) { try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder.id), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            try withReader(index.source, limitMB: index.limitMB) { reader in
                var entry: OpaquePointer?, written: Set<String> = [], total = 0
                let deadline = Date().addingTimeInterval(15)
                while true {
                    try Task.checkCancellation()
                    let status = archive_read_next_header(reader, &entry)
                    if status == ARCHIVE_EOF { break }
                    guard status >= ARCHIVE_WARN, let entry else { throw PreviewError.message("Archive illisible pendant la copie.") }
                    guard Date() < deadline else { throw PreviewError.message("Temps de copie dépassé.") }
                    guard let path = entryPath(entry, reader: reader, source: index.source), let item = targets[path], !item.directory, !written.contains(path) else { continue }
                    guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil, archive_entry_filetype(entry) == 0o100000 else { throw PreviewError.message("Lien ou fichier spécial refusé.") }
                    let destination = directory.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let fd = Darwin.open(destination.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
                    guard fd >= 0 else { throw PreviewError.message("Création du fichier temporaire impossible.") }
                    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                    do {
                        var buffer = [UInt8](repeating: 0, count: 64 * 1024), bytes = 0
                        while true {
                            try Task.checkCancellation()
                            guard Date() < deadline else { throw PreviewError.message("Temps de copie dépassé.") }
                            let n = archive_read_data(reader, &buffer, buffer.count)
                            guard n >= 0 else { throw PreviewError.message("Entrée endommagée ou chiffrée.") }
                            if n == 0 { break }
                            total += n; bytes += n
                            guard total <= 256 * 1024 * 1024, bytes <= 50 * 1024 * 1024 else { throw PreviewError.message("Limite de copie atteinte.") }
                            try handle.write(contentsOf: Data(buffer.prefix(n)))
                        }
                        try handle.close(); written.insert(path)
                    } catch { try? handle.close(); throw error }
                }
                guard all.filter({ !$0.directory }).allSatisfy({ written.contains($0.id) }) else { throw PreviewError.message("Certaines entrées n’ont pas pu être copiées.") }
            }
            return chosen.map { directory.appendingPathComponent($0.id) }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
