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

    var downloadURL: URL? {
        guard ReleaseVersion(tag_name) != nil,
              let asset = ["Plupo-universal.dmg", "Plupo-arm64.dmg"].first(where: { name in
                  assets.contains { $0.name == name }
              }) else { return nil }
        return URL(string: "https://github.com/planetic-labs/plupo/releases/download/\(tag_name)/\(asset)")
    }

    func newerVersion(than current: String) -> ReleaseVersion? {
        guard !draft, !prerelease,
              downloadURL != nil,
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
    private var didStart = false
    @Published private(set) var isChecking = false
    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates")
        }
    }

    private init() {
        automaticallyChecks = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        if automaticallyChecks { check(manual: false) }
    }

    func check(manual: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
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
                if release.newerVersion(than: current) != nil, let downloadURL = release.downloadURL {
                    if !manual && defaults.string(forKey: "lastNotifiedUpdate") == release.tag_name { return }
                    // Respect a preference disabled while the request was in flight.
                    guard manual || automaticallyChecks else { return }
                    defaults.set(release.tag_name, forKey: "lastNotifiedUpdate")
                    let alert = NSAlert()
                    alert.messageText = "Plupo \(release.tag_name) is available"
                    alert.informativeText = "You have version \(current). Download the update, open the DMG, then drag Plupo into Applications to replace your current copy."
                    alert.addButton(withTitle: "Download Update")
                    alert.addButton(withTitle: "View Release Notes")
                    alert.addButton(withTitle: "Later")
                    NSApp.activate(ignoringOtherApps: true)
                    switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        if !NSWorkspace.shared.open(downloadURL) {
                            showMessage("Could not open the download", "Open the release page and download the DMG from Assets.")
                        }
                    case .alertSecondButtonReturn:
                        NSWorkspace.shared.open(Self.releasesURL)
                    default:
                        break
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
