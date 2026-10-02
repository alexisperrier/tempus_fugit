import AppKit
import Combine
import SwiftUI

final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: PanelWindow
    private let model: StatusModel
    private let sampler: Sampler
    private var cancellables = Set<AnyCancellable>()

    private static let panelSize = NSSize(width: 300, height: 200)

    init(model: StatusModel, sampler: Sampler) {
        self.model = model
        self.sampler = sampler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = PanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: ContentView(model: model, sampler: sampler)
                .frame(width: Self.panelSize.width, height: Self.panelSize.height)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
        }
        updateTitle()

        model.$status.combineLatest(sampler.$paused, sampler.$accessibilityGranted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if sampler.paused {
            button.title = "⏸ TT"
        } else if !sampler.accessibilityGranted {
            button.title = "⚠︎ TT"
        } else if let status = model.status {
            button.title = "⏱ \(formatDuration(status.todayWorkS))"
        } else {
            button.title = "⏱ TT"
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            model.refresh()
            positionUnderStatusItem()
            panel.orderFrontRegardless()
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func positionUnderStatusItem() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = NSPoint(
            x: buttonRect.midX - Self.panelSize.width / 2,
            y: buttonRect.minY - Self.panelSize.height - 4
        )
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var sampler: Sampler?
    private var model: StatusModel?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = AppSettings()
        let sampler = Sampler(settings: settings)
        let model = StatusModel(settings: settings)
        self.settings = settings
        self.sampler = sampler
        self.model = model
        self.statusBar = StatusBarController(model: model, sampler: sampler)
    }
}

@main
struct TimeTrackMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
