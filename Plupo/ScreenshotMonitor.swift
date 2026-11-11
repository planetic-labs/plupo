import AppKit
import Combine
import ImageIO

final class ScreenshotMonitor: ObservableObject {
    static let shared = ScreenshotMonitor { screenshots in
        WindowManager.shared.addScreenshots(screenshots)
    }

    @Published private(set) var folder: URL?
    @Published private(set) var isMonitoring = false
    @Published private(set) var detectedScreenshot = false
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let onImport: ([ShelfItem]) -> Void
    private let bookmarkKey = "screenshotFolderBookmark"
    private let enabledKey = "screenshotMonitoringEnabled"
    private var timer: Timer?
    private var hasFolderAccess = false
    private var knownFiles = Set<URL>()
    private var pendingFiles: [URL: Date] = [:]

    init(defaults: UserDefaults = .standard, onImport: @escaping ([ShelfItem]) -> Void) {
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
            errorMessage = "Choose the screenshot folder again to restore access."
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Folder Where macOS Saves Screenshots"
        panel.prompt = "Monitor Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
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
            errorMessage = "Plupo could not read the screenshot folder. Choose it again."
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

            var screenshots: [ShelfItem] = []
            // A file can appear before macOS finishes writing its image and metadata.
            for (url, deadline) in pendingFiles.sorted(by: { $0.key.lastPathComponent < $1.key.lastPathComponent }) {
                if !currentFiles.contains(url) {
                    pendingFiles[url] = nil
                } else if let screenshot = Self.readScreenshot(at: url) {
                    pendingFiles[url] = nil
                    screenshots.append(screenshot)
                } else if now >= deadline {
                    pendingFiles[url] = nil
                }
            }
            if !screenshots.isEmpty {
                detectedScreenshot = true
                onImport(screenshots)
            }
        } catch {
            stop()
            errorMessage = "Plupo lost access to the screenshot folder. Choose it again."
        }
    }

    private static func readScreenshot(at url: URL) -> ShelfItem? {
        let attribute = "com.apple.metadata:kMDItemIsScreenCapture"
        guard getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) > 0,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
        return ShelfItem(content: .image(data, name: url.lastPathComponent))
    }
}
