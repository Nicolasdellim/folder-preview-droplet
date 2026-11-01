import Foundation
@main
struct CoreTests {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); count += 1 }
        check(Archives.safePath("../escape") == nil, "Traversal rejected")
        check(Archives.safePath("/absolute") == nil, "Absolute path rejected")
        check(Archives.safePath("a\\b") == nil, "Backslash path rejected")
        check(Archives.safePath("safe/./file") == "safe/file", "Safe path normalized")
        check(Archives.safePath("C:/file") == nil, "Drive path rejected")
        check(safeByteSum(Int64.max, 1) == Int64.max, "Size accumulation saturates safely")
        let sample = root.appendingPathComponent("sample")
        let listing = try Files.list(sample, hidden: false)
        check(listing.entries.count == 4, "Direct visible children: \(listing.entries.map(\.name))")
        check(listing.entries.contains(where: { $0.name == "cycle" && $0.link }), "Link recognized")
        let hidden = try Files.list(sample, hidden: true)
        check(hidden.entries.count == 5, "Hidden child enabled")
        let ignored = try Files.list(sample, hidden: false, ignored: ["Sous-dossier"])
        check(ignored.entries.count == 3, "Ignored directory excluded")
        var options = ViewOptions(); options.foldersFirst = true
        let sorted = Files.sorted(listing.entries, options: options)
        check(sorted[0].directory && !sorted[0].link, "Folders first")
        check(sorted.firstIndex(where: { $0.name == "fichier2.txt" })! < sorted.firstIndex(where: { $0.name == "fichier10.txt" })!, "Natural sorting")
        let read = try Files.read(sample.appendingPathComponent("fichier2.txt"))
        check(String(data: read, encoding: .utf8) == "deux", "Read-only regular file")
        do { _ = try Files.read(sample.appendingPathComponent("cycle")); preconditionFailure("Link followed") } catch { count += 1 }
        let sizes = try Files.totals(sample, hidden: false, ignored: [])
        check(sizes.all.count == 5, "Recursive count includes directory children")
        let folderID = listing.entries.first(where: { $0.name == "Sous-dossier" })!.id
        check(sizes.children[folderID]?.bytes == 6, "Directory size computed: \(sizes.children)")
        let hostile = try Archives.index(root.appendingPathComponent("hostile.zip"))
        check(hostile.skipped == 3, "Unsafe archive paths rejected")
        check(hostile.children(of: "").count == 2, "Virtual archive root")
        let text = try Archives.data(hostile, path: "ok/fichier2.txt")
        check(String(data: text, encoding: .utf8) == "test", "Archive member read")
        do { _ = try Archives.data(hostile, path: "large.txt"); preconditionFailure("Oversized member read") } catch { count += 1 }
        do { _ = try Archives.data(hostile, path: "absent.txt"); preconditionFailure("Missing member accepted") } catch { count += 1 }
        let destination = root.appendingPathComponent("clipboard-" + UUID().uuidString)
        let urls = try Archives.copySelection(hostile.children(of: "ok"), from: hostile, into: destination)
        check(urls.count == 1 && (try? String(contentsOf: urls[0], encoding: .utf8)) == "test", "Selected member safely materialized")
        try FileManager.default.removeItem(at: destination)
        for name in ["Exemple.tar", "Exemple.tar.gz", "Exemple.tar.bz2", "Exemple.tar.xz"] {
            let archive = try Archives.index(root.appendingPathComponent(name))
            check(archive.children(of: "demo").count == 1, "\(name) supported")
            let bytes = try Archives.data(archive, path: "demo/texte.txt")
            check(String(data: bytes, encoding: .utf8) == "tar sample", "\(name) content read")
        }
        for name in ["sample.7z", "sample.rar", "sample-rar5.rar"] {
            let index = try Archives.index(URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(name))
            check(!index.entries.isEmpty, "\(name) format read")
            if let file = index.entries.first(where: { !$0.directory }) {
                let data = try Archives.data(index, path: file.id)
                check(!data.isEmpty, "\(name) data decoded")
            }
        }
        let cancelled = Task { () throws -> Listing in
            while !Task.isCancelled { await Task.yield() }
            return try Files.list(sample, hidden: true)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancellation ignored") } catch is CancellationError { count += 1 }
        print("PASS: \(count) core checks")
    }
}
