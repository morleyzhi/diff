import AppKit
import Darwin
import SwiftUI

@main
struct DiffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if CommandLine.arguments.contains("--self-test") {
            let passed = DiffEngine.runSelfTests()
            if passed {
                fputs("self-test: ok\n", stdout)
            }
            Darwin.exit(passed ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: AppModel.shared)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            DiffCommands()
        }
    }
}

struct DiffCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open into Left…") {
                AppModel.shared.openFile(into: .left)
            }
            .keyboardShortcut("o", modifiers: [.command])
            Button("Open into Right…") {
                AppModel.shared.openFile(into: .right)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .pasteboard) {
            Button("Paste into Left") {
                AppModel.shared.paste(into: .left)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("Paste into Right") {
                AppModel.shared.paste(into: .right)
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
            Button("Clear Left") {
                AppModel.shared.clear(side: .left)
            }
            Button("Clear Right") {
                AppModel.shared.clear(side: .right)
            }
        }
        CommandMenu("Diff") {
            Button("Next Change") {
                AppModel.shared.nextHunk()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            Button("Previous Change") {
                AppModel.shared.prevHunk()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            Toggle("Ignore Whitespace", isOn: Bindable(AppModel.shared).ignoreWhitespace)
                .keyboardShortcut("i", modifiers: [.command])
            Divider()
            Button("Larger Text") {
                AppModel.shared.adjustFont(by: 1)
            }
            .keyboardShortcut("+", modifiers: [.command])
            Button("Smaller Text") {
                AppModel.shared.adjustFont(by: -1)
            }
            .keyboardShortcut("-", modifiers: [.command])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveNow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            let model = AppModel.shared
            do {
                try Snapshot.render(model: model, size: CGSize(width: 1280, height: 820), to: URL(fileURLWithPath: path))
                fputs("snapshot: \(path)\n", stdout)
                Darwin.exit(0)
            } catch {
                fputs("snapshot failed: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
