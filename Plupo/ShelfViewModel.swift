import AppKit
import Combine
import UniformTypeIdentifiers

class ShelfViewModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var dropError: String?
    private var pendingDrops = 0
    var usesCompactLayout: Bool { items.isEmpty && dropError == nil }

    var onItemsChanged: (() -> Void)?
    var onDropStarted: (() -> Void)?
    var onDropFinished: (() -> Void)?

    var isLoadingDrop: Bool { pendingDrops > 0 }

    func addItems(_ newItems: [ShelfItem]) {
        items.append(contentsOf: newItems)
        onItemsChanged?()
    }

    func toggleLock(for item: ShelfItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isLocked.toggle()
        }
    }

    func removeItem(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        onItemsChanged?()
    }

    func dismissDropError() {
        dropError = nil
        onItemsChanged?()
    }

    func clearAll() {
        items.removeAll { !$0.isLocked }
        onItemsChanged?()
    }

    func finishDrag(itemID: UUID, operation: NSDragOperation, keepItems: Bool) {
        guard !operation.isEmpty, !keepItems,
              let item = items.first(where: { $0.id == itemID }), !item.isLocked else { return }
        removeItem(item)
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
            self.items.append(contentsOf: results.keys.sorted().compactMap { results[$0] })
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
