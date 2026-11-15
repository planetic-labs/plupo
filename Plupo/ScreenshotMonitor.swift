import AppKit
import Combine
import ImageIO

final class ScreenshotMonitor: ObservableObject {
    static let shared = ScreenshotMonitor { screenshots in
        WindowManager.shared.addMonitoredItems(screenshots)
    }

    static let downloads = ScreenshotMonitor(screenshotsOnly: false) { files in
        WindowManager.shared.addMonitoredItems(files)
    }

    @Published private(set) var folder: URL?
    @Published private(set) var isMonitoring = false
    @Published private(set) var detectedScreenshot = false
    @Published private(set) var errorMessage: String?

    private let screenshotsOnly: Bool
    private let defaults: UserDefaults
    private let onImport: ([ShelfItem]) -> Void
    private var bookmarkKey: String { screenshotsOnly ? "screenshotFolderBookmark" : "monitoredFolderBookmark" }
    private var enabledKey: String { screenshotsOnly ? "screenshotMonitoringEnabled" : "folderMonitoringEnabled" }
    private var timer: Timer?
    private var hasFolderAccess = false
    private var knownFiles = Set<URL>()
    private var pendingFiles: [URL: Date] = [:]
    private var importedURLs = Set<URL>()
    private var fileSnapshots: [URL: FileSnapshot] = [:]

    private struct FileSnapshot: Equatable {
        let size: Int
        let modified: Date?
    }

    init(defaults: UserDefaults = .standard, screenshotsOnly: Bool = true, onImport: @escaping ([ShelfItem]) -> Void) {
        self.screenshotsOnly = screenshotsOnly
        self.defaults = defaults
        self.onImport = onImport
    }

    func restore() {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            folder = url
            if stale {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                defaults.set(try makeBookmark(for: url), forKey: bookmarkKey)
            }
            if defaults.bool(forKey: enabledKey) { setEnabled(true) }
        } catch {
            errorMessage = "Choose the folder again to restore access."
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = screenshotsOnly ? "Choose the Folder Where macOS Saves Screenshots" : "Choose a Folder to Monitor"
        panel.prompt = "Monitor Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder ?? FileManager.default.urls(for: screenshotsOnly ? .desktopDirectory : .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try makeBookmark(for: url)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
            defaults.set(bookmark, forKey: bookmarkKey)
            stop()
            folder = resolved
            setEnabled(true)
        } catch {
            errorMessage = "Plupo could not save access to that folder. Choose it again."
        }
    }

    func setEnabled(_ enabled: Bool) {
        stop()
        errorMessage = nil
        detectedScreenshot = false
        defaults.set(enabled, forKey: enabledKey)
        guard enabled, let folder else { return }
        do {
            try start(in: folder)
        } catch {
            errorMessage = "Plupo could not read the selected folder. Choose it again."
        }
    }

    func start(in folder: URL) throws {
        stop()
        self.folder = folder
        hasFolderAccess = folder.startAccessingSecurityScopedResource()
        do {
            knownFiles = try files(in: folder)
        } catch {
            stop()
            throw error
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isMonitoring = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if hasFolderAccess { folder?.stopAccessingSecurityScopedResource() }
        hasFolderAccess = false
        isMonitoring = false
        knownFiles.removeAll()
        pendingFiles.removeAll()
        fileSnapshots.removeAll()
        importedURLs.removeAll()
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
    }

    private func files(in folder: URL) throws -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]))
    }

    private func scan() {
        guard let folder else { return }
        do {
            let currentFiles = try files(in: folder)
            let now = Date()
            for url in currentFiles.subtracting(knownFiles) {
                pendingFiles[url] = now.addingTimeInterval(5)
            }
            knownFiles = currentFiles

            importedURLs.formIntersection(currentFiles)
            let other = screenshotsOnly ? Self.downloads : Self.shared
            let sharedFolder = other.isMonitoring && other.folder.map { Self.sameFolder($0, folder) } == true
            var imported: [ShelfItem] = []
            // A file can appear before macOS finishes writing its image and metadata.
            for (url, deadline) in pendingFiles.sorted(by: { $0.key.lastPathComponent < $1.key.lastPathComponent }) {
                if !currentFiles.contains(url)
                    || (sharedFolder && other.importedURLs.contains(where: {
                        $0.lastPathComponent == url.lastPathComponent
                    })) {
                    pendingFiles[url] = nil
                    fileSnapshots[url] = nil
                } else if screenshotsOnly, let screenshot = Self.readScreenshot(at: url) {
                    pendingFiles[url] = nil
                    importedURLs.insert(url)
                    imported.append(screenshot)
                } else if !screenshotsOnly {
                    if let file = readyFile(at: url, deferScreenshotsToOtherMonitor: sharedFolder) {
                        pendingFiles[url] = nil
                        fileSnapshots[url] = nil
                        importedURLs.insert(url)
                        imported.append(file)
                    }
                } else if now >= deadline {
                    pendingFiles[url] = nil
                }
            }
            if !imported.isEmpty {
                detectedScreenshot = screenshotsOnly
                onImport(imported)
            }
        } catch {
            stop()
            errorMessage = "Plupo lost access to the selected folder. Choose it again."
        }
    }

    private static func sameFolder(_ first: URL, _ second: URL) -> Bool {
        if first.resolvingSymlinksInPath().standardizedFileURL
            == second.resolvingSymlinksInPath().standardizedFileURL { return true }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        guard let a = try? first.resourceValues(forKeys: keys),
              let b = try? second.resourceValues(forKeys: keys),
              let identity = a.fileResourceIdentifier, let volume = a.volumeIdentifier else { return false }
        return identity.isEqual(b.fileResourceIdentifier) && volume.isEqual(b.volumeIdentifier)
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW) > 0
    }

    private func readyFile(at url: URL, deferScreenshotsToOtherMonitor: Bool) -> ShelfItem? {
        let incompleteExtensions = ["download", "crdownload", "part", "partial", "tmp"]
        guard !incompleteExtensions.contains(url.pathExtension.lowercased()),
              let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                                             .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize else {
            pendingFiles[url] = nil
            fileSnapshots[url] = nil
            return nil
        }
        if deferScreenshotsToOtherMonitor && Self.isScreenshot(url) {
            pendingFiles[url] = nil
            fileSnapshots[url] = nil
            return nil
        }
        let snapshot = FileSnapshot(size: size, modified: values.contentModificationDate)
        let previous = fileSnapshots.updateValue(snapshot, forKey: url)
        guard snapshot == previous else { return nil }
        return ShelfItem(content: .file(url))
    }

    private static func readScreenshot(at url: URL) -> ShelfItem? {
        guard isScreenshot(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
        return ShelfItem(content: .image(data, name: url.lastPathComponent))
    }
}
