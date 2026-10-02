import Combine
import Foundation

struct TodayStatus: Decodable {
    let generatedAt: String
    let todayWorkS: Double

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case todayWorkS = "today_work_s"
    }
}

enum CommandFailure: Error, LocalizedError {
    case launch(String)
    case failed(Int32, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .launch(let message): return message
        case .failed(let code, let message): return "Command failed with exit code \(code): \(message)"
        case .decode(let message): return "Could not read status output: \(message)"
        }
    }
}

/// Polls `make -s status` (ingest + today's working time) every minute.
final class StatusModel: ObservableObject {
    let settings: AppSettings

    @Published var status: TodayStatus?
    @Published var isRunning = false
    @Published var errorMessage: String?

    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !isRunning else { return }
        isRunning = true
        let repoPath = settings.repoPath
        DispatchQueue.global(qos: .utility).async {
            let result = Shell.make(target: "status", repoPath: repoPath)
            let decoded: Result<TodayStatus, CommandFailure> = result.flatMap { output in
                guard let data = output.data(using: .utf8), !data.isEmpty else {
                    return .failure(.decode("empty output"))
                }
                do {
                    return .success(try JSONDecoder().decode(TodayStatus.self, from: data))
                } catch {
                    return .failure(.decode(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            DispatchQueue.main.async {
                self.isRunning = false
                switch decoded {
                case .success(let status):
                    self.status = status
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

enum Shell {
    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
            environment["PATH"] ?? "",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].filter { !$0.isEmpty }.joined(separator: ":")
        environment["HOME"] = NSHomeDirectory()
        return environment
    }

    /// Run `make -s <target>` in the repo and return stdout.
    static func make(target: String, repoPath: String) -> Result<String, CommandFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["make", "-s", target]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.environment = environment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure(.launch(error.localizedDescription))
        }
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return .failure(.failed(process.terminationStatus, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(output)
    }

    /// Fire-and-forget `make <target>` (used to start Streamlit).
    static func launchMake(target: String, repoPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["make", "-s", target]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.environment = environment()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return String(format: "%dh%02d", hours, minutes) }
    return "\(minutes)m"
}
