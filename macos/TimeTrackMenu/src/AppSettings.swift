import Foundation

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var repoPath: String { didSet { defaults.set(repoPath, forKey: Keys.repoPath) } }
    @Published var sampleSeconds: Int { didSet { defaults.set(sampleSeconds, forKey: Keys.sampleSeconds) } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Keys.idleMinutes) } }
    /// Comma-separated app names whose window titles are never recorded.
    @Published var privateApps: String { didSet { defaults.set(privateApps, forKey: Keys.privateApps) } }

    private enum Keys {
        static let repoPath = "repoPath"
        static let sampleSeconds = "sampleSeconds"
        static let idleMinutes = "idleMinutes"
        static let privateApps = "privateApps"
    }

    /// Repo root, baked into Info.plist by build.sh (the checkout the app was built from).
    static let defaultRepoPath: String = {
        if let path = Bundle.main.object(forInfoDictionaryKey: "TimeTrackRepoPath") as? String, !path.isEmpty {
            return path
        }
        // Fallback: the .app lives in <repo>/macos/TimeTrackMenu/.
        return Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.repoPath: Self.defaultRepoPath,
            Keys.sampleSeconds: 5,
            Keys.idleMinutes: 5,
            Keys.privateApps: "1Password, Keychain Access",
        ])
        // Always follow the checkout the app was built from (no settings UI to change it).
        repoPath = Self.defaultRepoPath
        sampleSeconds = defaults.integer(forKey: Keys.sampleSeconds)
        idleMinutes = defaults.integer(forKey: Keys.idleMinutes)
        privateApps = defaults.string(forKey: Keys.privateApps) ?? ""
    }

    var privateAppSet: Set<String> {
        Set(privateApps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    var dataURL: URL { URL(fileURLWithPath: repoPath).appendingPathComponent("data") }
    var rawURL: URL { dataURL.appendingPathComponent("raw") }
    var pausedFlagURL: URL { dataURL.appendingPathComponent("paused") }
}
