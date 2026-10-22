import Foundation
import SwiftUI

enum FocusRunState: Equatable {
    case idle
    case running
    case paused
    case finished

    var title: String {
        switch self {
        case .idle: return "未开始"
        case .running: return "进行中"
        case .paused: return "已暂停"
        case .finished: return "已结束"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "circle"
        case .running: return "waveform"
        case .paused: return "pause.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }
}

struct FocusSession: Equatable, Identifiable {
    let taskID: UUID
    let taskTitle: String
    let durationMinutes: Int
    fileprivate(set) var state: FocusRunState
    fileprivate(set) var remainingSeconds: Int
    fileprivate var deadline: Date?

    var id: UUID { taskID }

    var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}

@MainActor
final class FocusSessionController: ObservableObject {
    @Published var pendingTask: PlanTask?
    @Published private(set) var sessions: [FocusSession] = []

    private var timer: Timer?

    func choose(_ task: PlanTask) {
        pendingTask = task
    }

    func start(task: PlanTask, durationMinutes: Int) {
        tick()
        let minutes = max(5, min(720, durationMinutes))
        let seconds = minutes * 60
        let session = FocusSession(
            taskID: task.id,
            taskTitle: task.title,
            durationMinutes: minutes,
            state: .running,
            remainingSeconds: seconds,
            deadline: Date().addingTimeInterval(TimeInterval(seconds))
        )
        if let index = sessions.firstIndex(where: { $0.taskID == task.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        pendingTask = nil
        ensureTimer()
    }

    func session(for taskID: UUID) -> FocusSession? {
        sessions.first { $0.taskID == taskID }
    }

    func state(for taskID: UUID) -> FocusRunState {
        session(for: taskID)?.state ?? .idle
    }

    func remainingSeconds(for taskID: UUID) -> Int {
        session(for: taskID)?.remainingSeconds ?? 0
    }

    func pauseOrResume(taskID: UUID) {
        tick()
        guard let index = sessions.firstIndex(where: { $0.taskID == taskID }) else { return }
        switch sessions[index].state {
        case .running:
            sessions[index].deadline = nil
            sessions[index].state = .paused
        case .paused:
            sessions[index].deadline = Date().addingTimeInterval(TimeInterval(sessions[index].remainingSeconds))
            sessions[index].state = .running
            ensureTimer()
        case .idle, .finished:
            break
        }
        stopTimerWhenIdle()
    }

    func stop(taskID: UUID) {
        sessions.removeAll { $0.taskID == taskID }
        stopTimerWhenIdle()
    }

    private func ensureTimer() {
        guard timer == nil, sessions.contains(where: { $0.state == .running }) else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = Date()
        for index in sessions.indices where sessions[index].state == .running {
            guard let deadline = sessions[index].deadline else { continue }
            let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            sessions[index].remainingSeconds = seconds
            if seconds == 0 {
                sessions[index].state = .finished
                sessions[index].deadline = nil
            }
        }
        stopTimerWhenIdle()
    }

    private func stopTimerWhenIdle() {
        guard !sessions.contains(where: { $0.state == .running }) else { return }
        timer?.invalidate()
        timer = nil
    }
}

struct FocusDurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var focus: FocusSessionController
    let task: PlanTask
    @State private var durationMinutes: Int

    private let presets = [15, 25, 45, 60]

    init(task: PlanTask) {
        self.task = task
        _durationMinutes = State(initialValue: max(5, min(720, task.durationMinutes)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("开始专注", systemImage: "play.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(SkyTheme.sea)
                Text(task.title)
                    .font(.headline)
                    .lineLimit(3)
            }

            Picker("专注时长", selection: $durationMinutes) {
                ForEach(presets, id: \.self) { minutes in
                    Text("\(minutes) 分").tag(minutes)
                }
            }
            .pickerStyle(.segmented)

            Stepper(value: $durationMinutes, in: 5...720, step: 5) {
                HStack {
                    Label("自定义时长", systemImage: "timer")
                    Spacer()
                    Text("\(durationMinutes) 分钟")
                        .font(.body.monospacedDigit().weight(.semibold))
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    focus.start(task: task, durationMinutes: durationMinutes)
                    dismiss()
                } label: {
                    Label("开始 \(durationMinutes) 分钟", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct FocusRunnerBar: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusSessionController

    var body: some View {
        if !focus.sessions.isEmpty {
            VStack(spacing: 0) {
                Divider()
                ScrollView(.horizontal, showsIndicators: focus.sessions.count > 1) {
                    LazyHStack(spacing: 0) {
                        ForEach(focus.sessions) { session in
                            sessionContent(session)
                            if session.id != focus.sessions.last?.id {
                                Divider()
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: 84)
            }
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
        }
    }

    private func sessionContent(_ session: FocusSession) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                stateLabel(session)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.taskTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("本轮 \(session.durationMinutes) 分钟")
                        .font(.caption2)
                        .foregroundStyle(session.state == .running ? SkyTheme.ink.opacity(0.76) : .secondary)
                }
                Spacer(minLength: 6)
                Text(session.formattedRemaining)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 58)
                controls(session)
            }
            ProgressView(
                value: Double(session.durationMinutes * 60 - session.remainingSeconds),
                total: Double(session.durationMinutes * 60)
            )
            .progressViewStyle(.linear)
            .tint(session.state == .finished ? Color.green : SkyTheme.sea)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 410)
        .background(session.state == .running ? SkyTheme.focusYellow.opacity(0.50) : Color.clear)
    }

    private func stateLabel(_ session: FocusSession) -> some View {
        Group {
            switch session.state {
            case .running:
                Label("进行中", systemImage: "waveform.path.ecg")
            case .paused:
                Label("已暂停", systemImage: "pause.circle.fill")
            case .finished:
                Label("本轮结束", systemImage: "checkmark.circle.fill")
            case .idle:
                EmptyView()
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(session.state == .running ? SkyTheme.ink : session.state == .finished ? Color.green : SkyTheme.sea)
    }

    private func controls(_ session: FocusSession) -> some View {
        HStack(spacing: 8) {
            if session.state == .finished {
                Button {
                    store.setPlanTaskCompleted(session.taskID, isCompleted: true)
                    focus.stop(taskID: session.taskID)
                } label: {
                    Label("标记完成", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    focus.pauseOrResume(taskID: session.taskID)
                } label: {
                    Image(systemName: session.state == .paused ? "play.fill" : "pause.fill")
                }
                .help(session.state == .paused ? "继续" : "暂停")
                .accessibilityLabel(session.state == .paused ? "继续专注" : "暂停专注")
            }
            Button {
                focus.stop(taskID: session.taskID)
            } label: {
                Image(systemName: "xmark")
            }
            .help(session.state == .finished ? "收起" : "结束本轮")
            .accessibilityLabel(session.state == .finished ? "收起专注栏" : "结束本轮专注")
        }
    }
}
