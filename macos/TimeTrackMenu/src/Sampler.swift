import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

struct Sample: Encodable {
    let ts: Double
    let app: String
    let bundleId: String?
    let title: String?
    let url: String?
    let idle: Bool
    let interval: Double

    enum CodingKeys: String, CodingKey {
        case ts, app, title, url, idle, interval
        case bundleId = "bundle_id"
    }
}

/// Samples the frontmost app / window / browser URL every few seconds and
/// appends one JSON line per sample to <repo>/data/raw/YYYY-MM-DD.jsonl.
final class Sampler: ObservableObject {
    @Published private(set) var lastSample: Sample?
    @Published private(set) var paused: Bool
    @Published private(set) var suspendedReason: String?
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var lastError: String?

    private let settings: AppSettings
    private var timer: Timer?
    private var screenLocked = false
    private var asleep = false
    private let encoder = JSONEncoder()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Browsers whose active-tab URL can be read through AppleScript.
    private static let urlScripts: [String: String] = [
        "com.google.Chrome": "tell application id \"com.google.Chrome\" to get URL of active tab of front window",
    ]

    init(settings: AppSettings) {
        self.settings = settings
        paused = FileManager.default.fileExists(atPath: settings.pausedFlagURL.path)
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        observeSystemEvents()
        requestAccessibility()
        schedule()
    }

    func schedule() {
        timer?.invalidate()
        let interval = TimeInterval(max(settings.sampleSeconds, 1))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.5
        tick()
    }

    func setPaused(_ value: Bool) {
        paused = value
        let url = settings.pausedFlagURL
        try? FileManager.default.createDirectory(at: settings.dataURL, withIntermediateDirectories: true)
        if value {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    private func observeSystemEvents() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = true }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = false }
        }
    }

    private func tick() {
        accessibilityGranted = AXIsProcessTrusted()
        lastError = nil
        if paused { suspendedReason = "Paused"; return }
        if screenLocked { suspendedReason = "Screen locked"; return }
        if asleep { suspendedReason = "Asleep"; return }
        suspendedReason = nil

        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let appName = front.localizedName ?? front.bundleIdentifier ?? "Unknown"
        let bundleId = front.bundleIdentifier
        let isPrivate = settings.privateAppSet.contains(appName.lowercased())

        let title = isPrivate ? nil : windowTitle(pid: front.processIdentifier)
        var url: String? = nil
        if !isPrivate, let bundleId, let script = Self.urlScripts[bundleId] {
            url = runAppleScript(script)
        }

        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: ~0)!
        )
        let sample = Sample(
            ts: Date().timeIntervalSince1970,
            app: appName,
            bundleId: bundleId,
            title: title,
            url: url,
            idle: idleSeconds >= Double(settings.idleMinutes * 60),
            interval: Double(max(settings.sampleSeconds, 1))
        )
        lastSample = sample
        append(sample)
    }

    private func windowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let value = title as? String, !value.isEmpty else { return nil }
        return value
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -1728: no window/tab (e.g. Chrome open without windows) is not worth reporting.
            if (error[NSAppleScript.errorNumber] as? Int) != -1728 {
                lastError = "AppleScript: \(error[NSAppleScript.errorMessage] ?? "failed")"
            }
            return nil
        }
        guard let value = result?.stringValue, !value.isEmpty else { return nil }
        return value
    }

    private func append(_ sample: Sample) {
        do {
            try FileManager.default.createDirectory(at: settings.rawURL, withIntermediateDirectories: true)
            let file = settings.rawURL.appendingPathComponent("\(dayFormatter.string(from: Date())).jsonl")
            var line = try encoder.encode(sample)
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file)
            }
        } catch {
            lastError = "Write failed: \(error.localizedDescription)"
        }
    }
}
