import AppKit
import NotchLyricsCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController?.show()
    }
}

@main
struct NotchLyricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel(config: AppConfig.load())
        _model = StateObject(wrappedValue: model)
        let controller = NotchPanelController(viewModel: model)
        appDelegate.panelController = controller
        model.start()
    }

    var body: some Scene {
        MenuBarExtra("NotchLyrics", systemImage: "music.note") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About NotchLyrics") {}
            }
        }
        .onChange(of: model.track?.id) { _, _ in
            appDelegate.panelController?.refresh()
        }
        .onChange(of: model.activeLineIndex) { _, _ in
            appDelegate.panelController?.refresh()
        }
    }
}
