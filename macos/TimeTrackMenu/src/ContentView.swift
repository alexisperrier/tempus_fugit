import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StatusModel
    @ObservedObject var sampler: Sampler

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WORKED TODAY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stateLabel).font(.caption).foregroundStyle(stateColor)
            }
            Text(formatDuration(model.status?.todayWorkS ?? 0))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
            if !sampler.accessibilityGranted {
                Button("Grant Accessibility…") {
                    sampler.requestAccessibility()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button(action: { sampler.setPaused(!sampler.paused) }) {
                    Label(sampler.paused ? "Resume" : "Pause", systemImage: sampler.paused ? "play.fill" : "pause.fill")
                }
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                Button(action: { NSApp.terminate(nil) }) { Image(systemName: "power") }
                    .help("Quit (stops tracking)")
                Spacer()
                Button(action: openDashboard) { Label("Dashboard", systemImage: "chart.bar.xaxis") }
            }
            .buttonStyle(.borderless)
            if let error = model.errorMessage ?? sampler.lastError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var stateColor: Color {
        if !sampler.accessibilityGranted { return .orange }
        return sampler.suspendedReason == nil ? .green : .secondary
    }

    private var stateLabel: String {
        if !sampler.accessibilityGranted { return "No Accessibility" }
        return sampler.suspendedReason ?? "Tracking"
    }

    private func openDashboard() {
        let url = URL(string: "http://localhost:8600")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        let repoPath = model.settings.repoPath
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if response == nil {
                Shell.launchMake(target: "app", repoPath: repoPath)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { NSWorkspace.shared.open(url) }
            } else {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }.resume()
    }
}
