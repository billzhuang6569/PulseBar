import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let preferences = DisplayPreferences()
        let sampler = MetricsSampler()
        statusController = StatusBarController(preferences: preferences, sampler: sampler)
        sampler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController?.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
