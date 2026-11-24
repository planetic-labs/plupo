import AppKit
import Combine
import OSLog

final class ShelfPersistence {
    private struct Snapshot: Codable {
        let items: [Entry]
        let stacks: [ShelfViewModel.Stack]
    }

    private struct Entry: Codable {
        enum Content: Codable {
            case file(bookmark: Data, scoped: Bool)
            case text(String)
            case link(URL, title: String?)
            case image(Data, name: String)
        }

        let id: UUID
        let isLocked: Bool
        let content: Content
    }

    private let model: ShelfViewModel
    private let location = URL.applicationSupportDirectory
        .appendingPathComponent("Plupo", isDirectory: true)
        .appendingPathComponent("Shelf.plist")
    private let logger = Logger(subsystem: "org.plupo.Plupo", category: "SavedShelf")
    private let preferenceKey = "rememberShelfBetweenLaunches"
    private var scopes: [URL] = []
    private var subscription: AnyCancellable?
    var isEnabled: Bool { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }

    init(model: ShelfViewModel) {
        self.model = model
        if isEnabled { restore() }
        subscription = model.$items.combineLatest(model.$stacks)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.save() }
    }

    func setEnabled(_ enabled: Bool) throws {
        if !enabled {
            do { try FileManager.default.removeItem(at: location) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { }
        }
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled { save() }
    }

    func save() {
        guard isEnabled else { return }
        let entries = model.items.compactMap(makeEntry)
        do {
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try PropertyListEncoder().encode(Snapshot(items: entries, stacks: model.stacks))
            try data.write(to: location, options: .atomic)
        } catch {
            logger.error("Could not save the shelf: \((error as NSError).code)")
        }
    }

    func close() {
        save()
        subscription?.cancel()
        for url in scopes { url.stopAccessingSecurityScopedResource() }
        scopes.removeAll()
    }

    private func makeEntry(_ item: ShelfItem) -> Entry? {
        let content: Entry.Content
        switch item.content {
        case .file(let url):
            let temporaryPath = PlupoTemporaryFiles.directory.resolvingSymlinksInPath().path
            guard !url.resolvingSymlinksInPath().path.hasPrefix(temporaryPath + "/") else { return nil }
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
                content = .file(bookmark: bookmark, scoped: true)
            } else if let bookmark = try? url.bookmarkData() {
                content = .file(bookmark: bookmark, scoped: false)
            } else {
                return nil
            }
        case .text(let text): content = .text(text)
        case .link(let url, let title): content = .link(url, title: title)
        case .image(let data, let name): content = .image(data, name: name)
        }
        return Entry(id: item.id, isLocked: item.isLocked, content: content)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: location),
              let snapshot = try? PropertyListDecoder().decode(Snapshot.self, from: data) else { return }
        let items = snapshot.items.compactMap { entry -> ShelfItem? in
            let content: ShelfItem.Content
            switch entry.content {
            case .file(let bookmark, let scoped):
                var stale = false
                var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
                if scoped { options.insert(.withSecurityScope) }
                guard let url = try? URL(resolvingBookmarkData: bookmark, options: options,
                                         relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
                let hasScope = scoped && url.startAccessingSecurityScopedResource()
                guard FileManager.default.fileExists(atPath: url.path) else {
                    if hasScope { url.stopAccessingSecurityScopedResource() }
                    return nil
                }
                // Keep access for Restore Last Removed even when an item leaves the shelf.
                if hasScope { scopes.append(url) }
                content = .file(url)
            case .text(let text): content = .text(text)
            case .link(let url, let title): content = .link(url, title: title)
            case .image(let data, let name): content = .image(data, name: name)
            }
            var item = ShelfItem(id: entry.id, content: content)
            item.isLocked = entry.isLocked
            return item
        }
        model.restoreSavedItems(items, stacks: snapshot.stacks)
    }
}
