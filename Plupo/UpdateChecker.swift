import AppKit
import Combine
import Foundation

struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct PublishedRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable { let name: String }

    func newerVersion(than current: String) -> ReleaseVersion? {
        guard !draft, !prerelease,
              assets.contains(where: { $0.name == "Plupo-arm64.dmg" }),
              let remote = ReleaseVersion(tag_name), let installed = ReleaseVersion(current),
              remote > installed else { return nil }
        return remote
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let releasesURL = URL(string: "https://github.com/planetic-labs/plupo/releases/latest")!
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    @Published private(set) var isChecking = false
    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates")
            if automaticallyChecks { checkAutomatically() }
        }
    }

    private init() {
        automaticallyChecks = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
    }

    func start() {
        checkAutomatically()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let checker = self else { return }
            Task { @MainActor in checker.checkAutomatically() }
        }
    }

    func checkAutomatically() {
        guard automaticallyChecks else { return }
        let lastAttempt = defaults.object(forKey: "lastUpdateAttempt") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAttempt) >= 24 * 60 * 60 else { return }
        check(manual: false)
    }

    func check(manual: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        defaults.set(Date(), forKey: "lastUpdateAttempt")
        Task {
            defer { isChecking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/planetic-labs/plupo/releases/latest")!)
                request.timeoutInterval = 20
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Plupo-Update-Checker", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let release = try JSONDecoder().decode(PublishedRelease.self, from: data)
                guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                      ReleaseVersion(current) != nil else { throw URLError(.cannotParseResponse) }
                if release.newerVersion(than: current) != nil {
                    if !manual && defaults.string(forKey: "lastNotifiedUpdate") == release.tag_name { return }
                    // Respect a preference disabled while the request was in flight.
                    guard manual || automaticallyChecks else { return }
                    defaults.set(release.tag_name, forKey: "lastNotifiedUpdate")
                    let alert = NSAlert()
                    alert.messageText = "Plupo \(release.tag_name) is available"
                    alert.informativeText = "You have version \(current). Open the release page to see what changed and download the update. Install it by dragging Plupo into Applications."
                    alert.addButton(withTitle: "View Release")
                    alert.addButton(withTitle: "Later")
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(Self.releasesURL)
                    }
                } else if manual {
                    showMessage("No newer update available", "Installed version: \(current).\nLatest published release: \(release.tag_name).")
                }
            } catch {
                if manual {
                    showMessage("Could not check for updates", "Check your internet connection and try again later.")
                }
            }
        }
    }

    private func showMessage(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
