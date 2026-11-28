import AppKit
import Combine
import UniformTypeIdentifiers

class ShelfViewModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = [] {
        didSet {
            let ids = Set(items.map(\.id))
            selectedIDs.formIntersection(ids)
            stacks = stacks.compactMap { stack in
                let members = stack.members.filter { ids.contains($0) }
                return members.count > 1 ? Stack(id: stack.id, members: members) : nil
            }
            expandedStacks.formIntersection(stacks.map(\.id))
        }
    }
    struct Stack: Identifiable, Codable {
        let id: UUID
        let members: [UUID]
    }

    @Published private(set) var stacks: [Stack] = []
    @Published private(set) var expandedStacks = Set<UUID>()

    func toggleStack(_ id: UUID) {
        if expandedStacks.remove(id) == nil { expandedStacks.insert(id) }
    }

    func splitStack(_ id: UUID) {
        stacks.removeAll { $0.id == id }
        expandedStacks.remove(id)
    }

    func stackItems(_ stack: Stack) -> [ShelfItem] {
        let members = Set(stack.members)
        return items.filter { members.contains($0.id) }
    }

    private struct RemovedBatch {
        let entries: [(index: Int, item: ShelfItem)]
        let stacks: [Stack]
        let expandedStacks: Set<UUID>
    }

    private var lastRemoved: RemovedBatch?
    var canRestoreLastRemoved: Bool { lastRemoved != nil }

    private func rememberRemoval(_ entries: [(index: Int, item: ShelfItem)]) {
        guard !entries.isEmpty else { return }
        let removedIDs = Set(entries.map { $0.item.id })
        let affectedStacks = stacks.filter { !removedIDs.isDisjoint(with: $0.members) }
        lastRemoved = RemovedBatch(entries: entries, stacks: affectedStacks, expandedStacks: expandedStacks)
    }

    @discardableResult
    func restoreLastRemoved() -> Bool {
        guard let batch = lastRemoved else { return false }
        lastRemoved = nil
        var restored = items
        for entry in batch.entries {
            restored.insert(entry.item, at: min(entry.index, restored.count))
        }
        items = restored
        let ids = Set(items.map(\.id))
        for stack in batch.stacks {
            let members = stack.members.filter { ids.contains($0) }
            guard members.count > 1 else { continue }
            stacks.removeAll { $0.id == stack.id }
            stacks.append(Stack(id: stack.id, members: members))
            if batch.expandedStacks.contains(stack.id) { expandedStacks.insert(stack.id) }
        }
        onItemsChanged?()
        return true
    }

    private func removeItems(where shouldRemove: (ShelfItem) -> Bool) {
        let removed = items.enumerated().filter { shouldRemove($0.element) }
        guard !removed.isEmpty else { return }
        rememberRemoval(removed.map { (index: $0.offset, item: $0.element) })
        items.removeAll(where: shouldRemove)
        onItemsChanged?()
    }

    @Published private(set) var selectedIDs = Set<UUID>()
    @Published var isPointerDropTarget = false
    @Published var isNativeFileDropTargeted = false
    @Published private(set) var dropError: String?
    private var pendingDrops = 0
    var usesCompactLayout: Bool { items.isEmpty && dropError == nil }

    var onItemsChanged: (() -> Void)?
    var onDropStarted: (() -> Void)?
    var onDropFinished: (() -> Void)?

    var isLoadingDrop: Bool { pendingDrops > 0 }

    func restoreSavedItems(_ saved: [ShelfItem], stacks savedStacks: [Stack]) {
        items.insert(contentsOf: saved, at: 0)
        let ids = Set(saved.map(\.id))
        stacks.insert(contentsOf: savedStacks.compactMap { stack in
            let members = stack.members.filter { ids.contains($0) }
            return members.count > 1 ? Stack(id: stack.id, members: members) : nil
        }, at: 0)
        onItemsChanged?()
    }

    func addItems(_ newItems: [ShelfItem]) {
        items.append(contentsOf: newItems)
        onItemsChanged?()
    }

    func toggleLock(for item: ShelfItem, allItems: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let shouldLock = !items[index].isLocked
        if allItems {
            items = items.map { item in
                var updated = item
                updated.isLocked = shouldLock
                return updated
            }
        } else {
            items[index].isLocked = shouldLock
        }
    }

    func removeItem(_ item: ShelfItem) {
        removeItems { $0.id == item.id }
    }

    func dismissDropError() {
        dropError = nil
        onItemsChanged?()
    }

    func clearAll() {
        removeItems { !$0.isLocked }
    }

    func select(_ id: UUID, extending: Bool) {
        if extending {
            if selectedIDs.remove(id) == nil { selectedIDs.insert(id) }
        } else {
            selectedIDs = [id]
        }
    }

    func itemsForDrag(startingAt id: UUID) -> [ShelfItem] {
        items.filter { selectedIDs.contains(id) ? selectedIDs.contains($0.id) : $0.id == id }
    }

    func finishDrag(itemID: UUID, operation: NSDragOperation, keepItems: Bool) {
        finishDrag(itemIDs: [itemID], operation: operation, keepItems: keepItems)
    }

    func finishDrag(itemIDs: Set<UUID>, operation: NSDragOperation, keepItems: Bool) {
        guard !operation.isEmpty, !keepItems else { return }
        removeItems { itemIDs.contains($0.id) && !$0.isLocked }
    }

    func finishFileMove(itemIDs: Set<UUID>, references: [UUID: NSURL], keepItems: Bool) {
        var removed: [(index: Int, item: ShelfItem)] = []
        let remaining = items.enumerated().compactMap { index, item -> ShelfItem? in
            guard itemIDs.contains(item.id) else { return item }
            // A file reference can follow a Finder move within the same volume.
            guard let url = references[item.id]?.filePathURL else { return nil }
            var updated = ShelfItem(id: item.id, content: .file(url))
            updated.isLocked = item.isLocked
            if keepItems || item.isLocked { return updated }
            removed.append((index, updated))
            return nil
        }
        rememberRemoval(removed)
        items = remaining
        onItemsChanged?()
    }

    @discardableResult
    func importClipboard(_ pasteboard: NSPasteboard) -> Bool {
        let priorities: [UTType] = [.fileURL, .url, .image, .plainText]
        let imported = (pasteboard.pasteboardItems ?? []).compactMap { entry -> ShelfItem? in
            for priority in priorities {
                for type in entry.types where UTType(type.rawValue)?.conforms(to: priority) == true {
                    let value: NSSecureCoding?
                    if priority == .image {
                        value = entry.data(forType: type) as NSData?
                    } else {
                        value = entry.string(forType: type) as NSString?
                    }
                    if let content = Self.decode(value, type: type.rawValue, name: nil) {
                        return ShelfItem(content: content)
                    }
                }
            }
            return nil
        }
        guard !imported.isEmpty else { return false }
        addItems(imported)
        return true
    }

    static func supportedTypes(for provider: NSItemProvider) -> [String] {
        let identifiers = provider.registeredTypeIdentifiers
        // Prefer original file references over image/text representations of the same file.
        let priorities: [UTType] = [.fileURL, .url, .image, .plainText]
        var result: [String] = []
        for priority in priorities {
            for identifier in identifiers where UTType(identifier)?.conforms(to: priority) == true {
                if !result.contains(identifier) { result.append(identifier) }
            }
        }
        if identifiers.contains(UTType.text.identifier) { result.append(UTType.text.identifier) }
        // Finder may advertise the file's content type without public.file-url.
        for identifier in identifiers {
            guard let type = UTType(identifier), type.conforms(to: .item),
                  !type.conforms(to: .text), !result.contains(identifier) else { continue }
            result.append(identifier)
        }
        return result
    }

    @discardableResult
    func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let candidates = providers.filter { !Self.supportedTypes(for: $0).isEmpty }
        guard !candidates.isEmpty else { return false }
        dropError = nil
        pendingDrops += 1
        onDropStarted?()
        let group = DispatchGroup()
        var results: [Int: ShelfItem] = [:]
        for (index, provider) in candidates.enumerated() {
            group.enter()
            load(provider, types: Self.supportedTypes(for: provider)) { item in
                if let item { results[index] = item }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let imported = results.keys.sorted().compactMap { results[$0] }
            self.items.append(contentsOf: imported)
            if imported.count > 1, imported.allSatisfy({ item in
                if case .file = item.content { return true }
                return false
            }) {
                self.stacks.append(Stack(id: UUID(), members: imported.map(\.id)))
            }
            self.pendingDrops -= 1
            if results.count < providers.count {
                self.dropError = "Some items could not be added. Try dragging the original file or plain text."
            }
            self.onDropFinished?()
            self.onItemsChanged?()
        }
        return true
    }

    private func load(_ provider: NSItemProvider, types: [String], completion: @escaping (ShelfItem?) -> Void) {
        guard let type = types.first else { completion(nil); return }
        let contentType = UTType(type)
        if let contentType, !contentType.conforms(to: .url),
           !contentType.conforms(to: .image), !contentType.conforms(to: .text) {
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, inPlace, error in
                // Non-in-place URLs expire when this callback returns. Copy before leaving it.
                let retainedURL = error == nil ? url.flatMap {
                    inPlace ? $0 : PlupoTemporaryFiles.copyImport($0)
                } : nil
                DispatchQueue.main.async {
                    if let retainedURL {
                        completion(ShelfItem(content: .file(retainedURL)))
                    } else {
                        self.load(provider, types: Array(types.dropFirst()), completion: completion)
                    }
                }
            }
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: type) { value, error in
            DispatchQueue.main.async {
                if error == nil, let content = Self.decode(value as NSData?, type: type, name: provider.suggestedName) {
                    completion(ShelfItem(content: content))
                } else {
                    self.load(provider, types: Array(types.dropFirst()), completion: completion)
                }
            }
        }
    }

    static func decode(_ value: NSSecureCoding?, type identifier: String, name: String?) -> ShelfItem.Content? {
        guard let type = UTType(identifier) else { return nil }
        if type.conforms(to: .fileURL) || type.conforms(to: .url) {
            let url: URL?
            if let value = value as? URL { url = value }
            else if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let string = value as? String { url = URL(string: string) }
            else { url = nil }
            guard let url, url.scheme != nil else { return nil }
            if type.conforms(to: .fileURL), !url.isFileURL { return nil }
            return url.isFileURL ? .file(url) : .link(url, title: name)
        }
        if type.conforms(to: .image) {
            let data = (value as? Data) ?? (value as? NSImage)?.tiffRepresentation
            guard let data, NSImage(data: data) != nil else { return nil }
            let ext = (value is NSImage ? "tiff" : type.preferredFilenameExtension) ?? "png"
            let original = name.map { ($0 as NSString).lastPathComponent }
            let fileName = original.flatMap { $0.isEmpty ? nil : $0 } ?? "Image.\(ext)"
            let finalName = (fileName as NSString).pathExtension.isEmpty ? fileName + "." + ext : fileName
            return .image(data, name: finalName)
        }
        if type.conforms(to: .plainText) || type == .text {
            if let text = value as? String { return .text(text) }
            if let data = value as? Data {
                let encoding: String.Encoding = identifier.contains("utf16") ? .utf16 : .utf8
                if let text = String(data: data, encoding: encoding) { return .text(text) }
            }
        }
        return nil
    }
}
