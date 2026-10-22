import AppKit
import SwiftUI

@main
struct CloudPlanApp: App {
    @StateObject private var store: TaskStore

    init() {
        let customPath = ProcessInfo.processInfo.environment["CLOUDPLAN_WORKSPACE_PATH"]
        let customURL = customPath.map { URL(fileURLWithPath: $0) }
        _store = StateObject(wrappedValue: TaskStore(fileURL: customURL))
    }

    var body: some Scene {
        WindowGroup("云上计划") {
            ContentView()
                .environmentObject(store)
                .tint(SkyTheme.sea)
                .frame(minWidth: 760, minHeight: 560)
                .overlay(WindowQAConfigurator().frame(width: 0, height: 0))
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建项目") {
                    NotificationCenter.default.post(name: .newProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建今日任务") {
                    NotificationCenter.default.post(name: .newTodayTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button("询问 AI 整理") {
                    NotificationCenter.default.post(name: .openAI, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

/// 只在自动视觉检查时改变窗口大小，正常启动没有任何行为。
private struct WindowQAConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowQAView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowQAView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let environment = ProcessInfo.processInfo.environment
        guard environment["CLOUDPLAN_QA_NARROW"] == "1"
                || environment["CLOUDPLAN_QA_WIDE"] == "1"
                || environment["CLOUDPLAN_QA_ADD_CHILD"] == "1"
                || environment["CLOUDPLAN_QA_NEW_PROJECT"] == "1"
                || environment["CLOUDPLAN_QA_AI"] == "1"
                || environment["CLOUDPLAN_QA_FOCUS"] == "1"
                || environment["CLOUDPLAN_QA_QUADRANTS"] == "1" else { return }
        DispatchQueue.main.async { [weak self] in
            if environment["CLOUDPLAN_QA_WIDE"] == "1" {
                self?.window?.setContentSize(NSSize(width: 1240, height: 780))
            }
            if environment["CLOUDPLAN_QA_NARROW"] == "1" {
                self?.window?.setContentSize(NSSize(width: 760, height: 560))
            }
            if environment["CLOUDPLAN_QA_NEW_PROJECT"] == "1" {
                NotificationCenter.default.post(name: .newProject, object: nil)
            }
            if environment["CLOUDPLAN_QA_AI"] == "1" {
                NotificationCenter.default.post(name: .openAI, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let newProject = Notification.Name("CloudPlan.newProject")
    static let newTodayTask = Notification.Name("CloudPlan.newTodayTask")
    static let openAI = Notification.Name("CloudPlan.openAI")
}
