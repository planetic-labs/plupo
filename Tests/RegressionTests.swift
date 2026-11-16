import AppKit
import UniformTypeIdentifiers

@main
struct RegressionTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        func load(_ model: ShelfViewModel, _ providers: [NSItemProvider]) async -> Bool {
            await withCheckedContinuation { continuation in
                model.onDropFinished = { continuation.resume(returning: true) }
                if !model.handleDroppedProviders(providers) { continuation.resume(returning: false) }
            }
        }
        func text(_ item: ShelfItem) -> String? {
            if case .text(let value) = item.content { return value }
            return nil
        }

        var visibility = ShelfVisibilityState()
        expect(visibility.canAutoHide, "Empty idle shelf should auto-hide")
        visibility.apply(mode: .always)
        expect(visibility.desiredVisible && !visibility.canAutoHide, "Always mode must show immediately and reject old hide tasks")
        visibility.apply(mode: .shortcut)
        expect(!visibility.desiredVisible && !visibility.canAutoHide, "Manual mode must hide on entry and disable auto-hide")
        visibility.itemCount = 1
        visibility.apply(mode: .dragStarts)
        expect(visibility.desiredVisible && !visibility.canAutoHide, "Returning to drag mode must show existing items")
        visibility.itemCount = 0
        visibility.dragSources = ["monitor", "shelf"]
        expect(!visibility.canAutoHide, "An active drag blocks auto-hide")
        visibility.dragSources.remove("monitor")
        expect(!visibility.canAutoHide, "One drag monitor ending must not end the native session")
        visibility.dragSources.removeAll()
        visibility.isLoadingDrop = true
        expect(!visibility.canAutoHide, "Slow provider loading blocks auto-hide")
        visibility.isLoadingDrop = false
        expect(visibility.canAutoHide, "Hide becomes eligible when the last load finishes")

        visibility.hasDropError = true
        expect(!visibility.canAutoHide, "A drop error must remain visible until dismissed")
        visibility.hasDropError = false

        let stackModel = ShelfViewModel()
        let fileProviders = ["One.pdf", "Two.pdf"].map { name in
            let provider = NSItemProvider()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { done in
                done(Data(url.absoluteString.utf8), nil)
                return nil
            }
            return provider
        }
        let acceptedStack = await load(stackModel, fileProviders)
        expect(acceptedStack && stackModel.stacks.count == 1, "One drop of multiple files should create one stack")
        let stack = stackModel.stacks[0]
        expect(stackModel.stackItems(stack).map(\.title) == ["One.pdf", "Two.pdf"], "Stack drag preserves original drop order")
        stackModel.toggleStack(stack.id)
        expect(stackModel.expandedStacks.contains(stack.id), "A stack can expand")
        stackModel.removeItem(stackModel.items[0])
        expect(stackModel.stacks.isEmpty && stackModel.expandedStacks.isEmpty && stackModel.items.count == 1,
               "A stack dissolves when only one file remains")

        expect(stackModel.restoreLastRemoved() && stackModel.stacks.count == 1,
               "Restoring a removed stack member should rebuild its group")
        let stackIDs = Set(stackModel.items.map(\.id))
        stackModel.finishDrag(itemIDs: stackIDs, operation: [], keepItems: false)
        expect(!stackModel.canRestoreLastRemoved && stackModel.items.count == 2,
               "Cancelling a drag should not record a removal")
        stackModel.finishDrag(itemIDs: stackIDs, operation: .copy, keepItems: false)
        expect(stackModel.items.isEmpty && stackModel.restoreLastRemoved(), "Restore the entire last drag")
        expect(stackModel.items.map(\.title) == ["One.pdf", "Two.pdf"] && stackModel.stacks.count == 1,
               "Restoring a batch should keep the order and stack")
        expect(!stackModel.restoreLastRemoved(), "Restore is consumed once")

        let model = ShelfViewModel()
        let unsupported = NSItemProvider()
        unsupported.registerDataRepresentation(forTypeIdentifier: "com.plupo.opaque", visibility: .all) { done in
            done(Data([1]), nil); return nil
        }
        expect(!model.handleDroppedProviders([unsupported]), "Unknown-only drops must be rejected")
        let multi = NSItemProvider()
        multi.registerDataRepresentation(forTypeIdentifier: "com.plupo.opaque", visibility: .all) { done in
            done(Data([1]), nil); return nil
        }
        multi.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { done in
            done(Data("hello".utf8), nil); return nil
        }
        let acceptedMulti = await load(model, [multi])
        expect(acceptedMulti && model.items.count == 1 && text(model.items[0]) == "hello", "Supported text after an opaque type must load")
        let fallback = NSItemProvider()
        fallback.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { done in
            done(nil, NSError(domain: "RegressionTest", code: 1)); return nil
        }
        fallback.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { done in
            done(Data("fallback".utf8), nil); return nil
        }
        let acceptedFallback = await load(model, [fallback])
        expect(acceptedFallback && text(model.items.last!) == "fallback", "A failed preferred representation must try the next supported type")

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-test-" + UUID().uuidString, isDirectory: true)
            .appendingPathComponent("курсар.tar.gz")
        try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let archiveBytes = Data([0x1f, 0x8b, 0x08, 0x00])
        try archiveBytes.write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        for inPlace in [true, false] {
            let archive = NSItemProvider()
            archive.registerFileRepresentation(forTypeIdentifier: UTType.gzip.identifier,
                                               fileOptions: inPlace ? .openInPlace : [], visibility: .all) { done in
                done(archiveURL, inPlace, nil)
                return nil
            }
            let archiveModel = ShelfViewModel()
            let acceptedArchive = await load(archiveModel, [archive])
            expect(acceptedArchive && archiveModel.items.count == 1 && archiveModel.dropError == nil,
                   "Archives without a file-URL representation must appear on the shelf")
            guard case .file(let loadedURL) = archiveModel.items[0].content else {
                fatalError("Archive must remain a file")
            }
            expect(loadedURL.lastPathComponent == "курсар.tar.gz", "Compound extensions and Unicode filenames must survive")
            let loadedBytes = try Data(contentsOf: loadedURL)
            expect(loadedBytes == archiveBytes, "Imported archive bytes must remain unchanged")
            if !inPlace {
                expect(loadedURL != archiveURL, "Temporary provider files must be retained before their URL expires")
                try? FileManager.default.removeItem(at: loadedURL.deletingLastPathComponent())
            }
        }

        let item = model.items[0]
        model.finishDrag(itemID: item.id, operation: [], keepItems: false)
        expect(model.items.count == 2, "Rejected/cancelled drags must keep shelf content")
        model.toggleLock(for: item)
        model.finishDrag(itemID: item.id, operation: .copy, keepItems: false)
        expect(model.items.count == 2, "Locked items must survive a successful drag")
        model.toggleLock(for: item)
        expect(!model.items[0].isLocked, "The same toggle must unlock an item")
        model.finishDrag(itemID: item.id, operation: .copy, keepItems: true)
        expect(model.items.count == 2, "Keep-items preference must preserve accepted drags")
        model.finishDrag(itemID: item.id, operation: .copy, keepItems: false)
        expect(model.items.count == 1, "An accepted drag removes an unlocked item when requested")
        // Use current lock state, not the copy captured at drag start.
        let second = model.items[0]
        model.toggleLock(for: second)
        model.clearAll()
        expect(model.items.count == 1, "Clear all must retain locked items")

        let failed = NSItemProvider()
        failed.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { done in
            done(nil, NSError(domain: "RegressionTest", code: 2)); return nil
        }
        _ = await load(model, [failed])
        expect(model.dropError != nil && !model.isLoadingDrop, "Failed supported drops must finish and present feedback")

        if case .text(let value) = ShelfViewModel.decode("custom:plain text" as NSString, type: UTType.plainText.identifier, name: nil) {
            expect(value == "custom:plain text", "Plain text with a colon must remain text")
        } else { fatalError("Text was misclassified as a URL") }
        expect(ShelfViewModel.decode("https://example.com" as NSString, type: UTType.fileURL.identifier, name: nil) == nil,
               "Web links must not be accepted as local files")
        model.dismissDropError()
        expect(model.dropError == nil, "The user must be able to dismiss drop feedback")
        let richOnly = NSItemProvider()
        richOnly.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { done in
            done(Data("{\\rtf1 raw}".utf8), nil); return nil
        }
        expect(!model.handleDroppedProviders([richOnly]), "Rich-text bytes must not be shown as plain text")
        let safeID = UUID()
        let export = PlupoTemporaryFiles.writeExport(Data("private".utf8), itemID: safeID, fileName: "../../outside.txt")!
        defer { try? FileManager.default.removeItem(at: export.deletingLastPathComponent()) }
        expect(export.deletingLastPathComponent().lastPathComponent == safeID.uuidString, "Export filenames must not escape their directory")
        let permissions = try FileManager.default.attributesOfItem(atPath: export.path)[.posixPermissions] as! NSNumber
        expect(permissions.intValue == 0o600, "Temporary exports must be private")
        let writer = ShelfItem(content: .text("original text")).pasteboardWriter() as? NSPasteboardItem
        expect(writer?.string(forType: .string) == "original text" && writer?.string(forType: .fileURL) != nil,
               "Text must export both plain text and a Finder-compatible file")
        if let path = writer?.string(forType: .fileURL).flatMap(URL.init(string:)) {
            try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
        }
        print("Passed \(checks) regression checks")
    }
}
