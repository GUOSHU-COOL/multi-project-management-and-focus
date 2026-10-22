import SwiftUI
import UniformTypeIdentifiers

struct QuadrantPanel: View {
    @EnvironmentObject private var store: TaskStore
    @State private var projectFilter = "all"
    @State private var newTaskProject: Project?

    private let columns = [
        GridItem(.flexible(minimum: 210), spacing: 10),
        GridItem(.flexible(minimum: 210), spacing: 10)
    ]

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                PanelHeader(
                    eyebrow: "Priority map",
                    title: "重要 × 紧急",
                    subtitle: "把注意力留给此刻真正值得推进的事",
                    trailing: AnyView(summary)
                )
                Divider().opacity(0.45)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        taskShelf
                        VStack(spacing: 8) {
                            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                                ForEach(TaskQuadrant.allCases) { quadrant in
                                    QuadrantCell(quadrant: quadrant)
                                }
                            }
                            QuadrantRemovalEdge()
                        }
                        OtherTasksSection(tasks: store.quadrantOtherTasks)
                    }
                    .padding(14)
                }
            }
        }
        .padding(6)
        .sheet(item: $newTaskProject) { project in
            NewPlanTaskEditor(projectTitle: project.title) { title, note, goal, duration in
                store.addPlanTask(
                    title: title,
                    projectID: project.id,
                    note: note,
                    goal: goal,
                    durationMinutes: duration
                )
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(store.data.quadrantPlacements.count + store.data.todayTasks.filter { $0.quadrant != nil }.count) 个象限任务")
                .font(.caption.weight(.semibold))
            Text("\(store.data.quadrantOtherTaskIDs.count) 个其他任务")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var filteredTasks: [PlanTask] {
        store.data.planTasks
            .filter { projectFilter == "all" || $0.projectID.uuidString == projectFilter }
            .sorted { lhs, rhs in
                if lhs.projectID == rhs.projectID { return lhs.order < rhs.order }
                let lhsProject = store.data.projects.firstIndex { $0.id == lhs.projectID } ?? .max
                let rhsProject = store.data.projects.firstIndex { $0.id == rhs.projectID } ?? .max
                return lhsProject < rhsProject
            }
    }

    private var taskShelf: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Label("项目任务", systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Spacer()
                Picker("项目筛选", selection: $projectFilter) {
                    Text("全部项目").tag("all")
                    ForEach(store.data.projects) { project in
                        Text(project.title).tag(project.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            if filteredTasks.isEmpty {
                ContentUnavailableView("还没有项目任务", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .contentShape(Rectangle())
                    .contextMenu { newTaskMenuItem }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(filteredTasks) { task in
                            QuadrantSourceTask(task: task, fixedWidth: 230)
                        }
                    }
                }
                .frame(height: 110)
                .contentShape(Rectangle())
                .contextMenu { newTaskMenuItem }
            }
        }
    }

    @ViewBuilder
    private var newTaskMenuItem: some View {
        if let project = filteredProject {
            Button {
                newTaskProject = project
            } label: {
                Label("新建任务…", systemImage: "checklist")
            }
        } else if store.data.projects.isEmpty {
            Button("还没有可用项目", systemImage: "exclamationmark.circle") {}
                .disabled(true)
        } else {
            Menu {
                ForEach(store.data.projects) { project in
                    Button {
                        newTaskProject = project
                    } label: {
                        Label(project.title, systemImage: project.symbol)
                    }
                }
            } label: {
                Label("新建任务到…", systemImage: "checklist")
            }
        }
    }

    private var filteredProject: Project? {
        guard projectFilter != "all" else { return nil }
        return store.data.projects.first { $0.id.uuidString == projectFilter }
    }
}

private struct QuadrantRemovalEdge: View {
    @EnvironmentObject private var store: TaskStore
    @State private var isDropTarget = false

    private let removalColor = Color(red: 0.74, green: 0.23, blue: 0.22)

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isDropTarget ? "xmark.circle.fill" : "xmark.circle")
            Text(isDropTarget ? "松开，移出四象限" : "拖到此边界可移出四象限")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isDropTarget ? removalColor : .secondary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(removalColor.opacity(isDropTarget ? 0.10 : 0.018))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isDropTarget ? removalColor : Color.primary.opacity(0.11),
                    style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [] : [6, 5])
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrop(
            of: [UTType.text.identifier],
            delegate: QuadrantRemovalDropDelegate(store: store, isTargeted: $isDropTarget)
        )
        .animation(.easeOut(duration: 0.16), value: isDropTarget)
        .accessibilityLabel("移出四象限拖放边界")
    }
}

private struct OtherTasksSection: View {
    @EnvironmentObject private var store: TaskStore
    let tasks: [PlanTask]
    @State private var isDropTarget = false

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: isDropTarget ? "arrow.down.circle.fill" : "tray.full.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isDropTarget ? .white : SkyTheme.sea)
                    .frame(width: 32, height: 32)
                    .background(
                        isDropTarget ? SkyTheme.sea : SkyTheme.paleSky.opacity(0.62),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("其他")
                        .font(.headline)
                    Text(isDropTarget ? "松开放入其他" : "手动收纳，不会自动加入任务")
                        .font(.caption)
                        .foregroundStyle(isDropTarget ? SkyTheme.sea : .secondary)
                }
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: isDropTarget ? "arrow.down.circle.fill" : "tray")
                        .font(.title2.weight(.medium))
                    Text(isDropTarget ? "松开放入其他" : "这里暂时是空的")
                        .font(.caption.weight(.semibold))
                    if !isDropTarget {
                        Text("将想暂存的任务拖到这里")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(isDropTarget ? SkyTheme.sea : .secondary)
                .frame(maxWidth: .infinity, minHeight: 92)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(tasks) { task in
                        PriorityTaskCard(task: task, quadrant: nil)
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: OtherTasksDropDelegate(
                                    targetID: task.id,
                                    store: store,
                                    isTargeted: .constant(false)
                                )
                            )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
        .background(SkyTheme.sky.opacity(isDropTarget ? 0.12 : 0.025))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isDropTarget ? SkyTheme.sea : Color.primary.opacity(0.10),
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SkyTheme.sky.opacity(isDropTarget ? 0.95 : 0.48))
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrop(
            of: [UTType.text.identifier],
            delegate: OtherTasksDropDelegate(targetID: nil, store: store, isTargeted: $isDropTarget)
        )
        .animation(.easeOut(duration: 0.16), value: isDropTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("其他，\(tasks.count) 个手动收纳的任务")
    }
}

private struct QuadrantSourceTask: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusSessionController
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuickNoteEditor = false
    @State private var showDeleteConfirmation = false
    let task: PlanTask
    var fixedWidth: CGFloat? = nil

    private var project: Project? {
        store.data.projects.first { $0.id == task.projectID }
    }

    private var activeSession: FocusSession? { focus.session(for: task.id) }
    private var isActive: Bool { activeSession != nil }
    private var placement: QuadrantPlacement? { store.placement(for: task.id) }
    private var isInOther: Bool { store.isInQuadrantOther(task.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                Button {
                    store.setPlanTaskCompleted(task.id, isCompleted: !task.isCompleted)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? SkyTheme.sea : SkyTheme.ink)
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .help(task.isCompleted ? "标记为未完成" : "标记完成")
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 2)
                Menu {
                    ForEach(TaskQuadrant.allCases.filter { $0 != placement?.quadrant }) { quadrant in
                        Button {
                            store.placeInQuadrant(taskID: task.id, quadrant: quadrant)
                        } label: {
                            Label(quadrant.title, systemImage: quadrant.symbol)
                        }
                    }
                    Divider()
                    if isInOther {
                        Button {
                            store.removeFromQuadrantOther(taskID: task.id)
                        } label: {
                            Label("移出其他", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button {
                            store.placeInQuadrantOther(taskID: task.id)
                        } label: {
                            Label("放入其他", systemImage: "tray.and.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("安排任务")
            }

            if !task.note.isEmpty {
                TaskQuickNoteText(note: task.note, lineLimit: 1)
            }

            HStack(spacing: 7) {
                Label(project?.title ?? "项目", systemImage: project?.symbol ?? "folder")
                    .lineLimit(1)
                Spacer(minLength: 2)
                sourceStatus
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(
            minWidth: fixedWidth,
            maxWidth: fixedWidth ?? .infinity,
            minHeight: 96,
            alignment: .leading
        )
        .background(sourceBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(sourceStroke, lineWidth: isActive ? 2 : 1)
        }
        .opacity(task.isCompleted && !isActive ? 0.52 : 1)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
        .contextMenu {
            TaskQuickNoteMenu(
                note: task.note,
                onEdit: { showQuickNoteEditor = true },
                onDelete: { store.setPlanTaskQuickNote(taskID: task.id, note: "") }
            )
            Divider()
            Button(task.isCompleted ? "标记为未完成" : "标记完成") {
                store.setPlanTaskCompleted(task.id, isCompleted: !task.isCompleted)
            }
            if task.isCompleted || activeSession?.state == .finished {
                Button("重新开始", systemImage: "arrow.clockwise") {
                    store.setPlanTaskCompleted(task.id, isCompleted: false)
                    var restarted = task
                    restarted.isCompleted = false
                    focus.start(task: restarted, durationMinutes: activeSession?.durationMinutes ?? task.durationMinutes)
                }
            }
            Button("开始专注…") { focus.choose(task) }
                .disabled(task.isCompleted || isActive)
            Divider()
            Button("删除任务…", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .sheet(isPresented: $showQuickNoteEditor) {
            TaskQuickNoteEditor(taskTitle: task.title, note: task.note) {
                store.setPlanTaskQuickNote(taskID: task.id, note: $0)
            }
        }
        .alert("删除这个任务？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deletePlanTask(task.id)
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .accessibilityLabel("项目任务：\(task.title)，\(locationDescription)")
    }

    @ViewBuilder
    private var sourceStatus: some View {
        if let activeSession {
            Label(activeSession.state.title, systemImage: activeSession.state.symbol)
                .foregroundStyle(SkyTheme.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else if let placement {
            Label(placement.quadrant.actionTitle, systemImage: placement.quadrant.symbol)
                .foregroundStyle(placement.quadrant.accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else if isInOther {
            Label("其他", systemImage: "tray.full.fill")
                .foregroundStyle(SkyTheme.sea)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var sourceBackground: Color {
        if isActive { return SkyTheme.focusYellow.opacity(colorScheme == .dark ? 0.34 : 0.68) }
        if task.isCompleted { return SkyTheme.completedWash.opacity(colorScheme == .dark ? 0.14 : 0.28) }
        if placement != nil {
            return SkyTheme.scheduleYellow.opacity(colorScheme == .dark ? 0.17 : 0.34)
        }
        if isInOther { return SkyTheme.paleSky.opacity(colorScheme == .dark ? 0.13 : 0.34) }
        return Color.primary.opacity(0.045)
    }

    private var sourceStroke: Color {
        if isActive { return SkyTheme.focusYellow }
        if placement != nil { return Color(red: 0.72, green: 0.52, blue: 0.05).opacity(0.54) }
        if isInOther { return SkyTheme.sky.opacity(0.62) }
        return Color.primary.opacity(0.08)
    }

    private var locationDescription: String {
        if let placement { return "位于\(placement.quadrant.title)" }
        if isInOther { return "位于其他" }
        return "尚未安排"
    }

    private var deleteConfirmationMessage: String {
        if store.data.planTasks.contains(where: { $0.parentID == task.id }) {
            return "“\(task.title)”及其所有子任务会从项目中删除，相关的四象限位置和今日安排也会移除。"
        }
        return "“\(task.title)”会从项目中删除，相关的四象限位置和今日安排也会移除。"
    }
}

private struct QuadrantCell: View {
    @EnvironmentObject private var store: TaskStore
    let quadrant: TaskQuadrant
    @State private var isDropTarget = false
    @State private var showNewQuickNote = false

    private var tasks: [PlanTask] { store.tasks(in: quadrant) }

    private var quickNotes: [TodayTask] { store.orderedTodayTasks.filter { $0.quadrant == quadrant } }
    private var taskCount: Int { tasks.count + quickNotes.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: quadrant.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(quadrant.accentColor)
                    .frame(width: 32, height: 32)
                    .background(quadrant.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(quadrant.title)
                        .font(.headline)
                    Text(quadrant.actionTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(taskCount)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty && quickNotes.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: isDropTarget ? "arrow.down.circle.fill" : "square.dashed")
                        .font(.title2)
                    Text(isDropTarget ? "松开放入" : "暂无任务")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(isDropTarget ? quadrant.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(quickNotes) { task in
                        QuadrantQuickNoteCard(task: task)
                    }
                    ForEach(tasks) { task in
                        PriorityTaskCard(task: task, quadrant: quadrant)
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: QuadrantDropDelegate(
                                    quadrant: quadrant,
                                    targetID: task.id,
                                    store: store,
                                    isTargeted: .constant(false)
                                )
                            )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
        .background(quadrant.accentColor.opacity(isDropTarget ? 0.12 : 0.028))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isDropTarget ? quadrant.accentColor : Color.primary.opacity(0.10),
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(quadrant.accentColor.opacity(isDropTarget ? 0.95 : 0.52))
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrop(
            of: [UTType.text.identifier],
            delegate: QuadrantDropDelegate(
                quadrant: quadrant,
                targetID: nil,
                store: store,
                isTargeted: $isDropTarget
            )
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("添加无归属快记…", systemImage: "square.and.pencil") {
                showNewQuickNote = true
            }
        }
        .sheet(isPresented: $showNewQuickNote) {
            TaskQuickNoteEditor(taskTitle: "无归属 · 同步到每日任务", note: "") {
                store.addQuadrantQuickNote($0, quadrant: quadrant)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isDropTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(quadrant.title)，\(taskCount) 个任务")
    }
}

private struct QuadrantQuickNoteCard: View {
    @EnvironmentObject private var store: TaskStore
    @State private var isEditing = false
    let task: TodayTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button {
                    store.toggleToday(task.id)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .help(task.isCompleted ? "标记为未完成" : "标记完成")
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(task.isCompleted)
                Spacer(minLength: 0)
            }
            if !task.note.isEmpty && task.note != task.title {
                TaskQuickNoteText(note: task.note)
            }
            Label("无归属快记 · 每日任务", systemImage: "note.text")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .opacity(task.isCompleted ? 0.52 : 1)
        .contentShape(Rectangle())
        .contextMenu {
            Button("编辑…", systemImage: "pencil") { isEditing = true }
            Button(task.isCompleted ? "重新开始" : "标记完成",
                   systemImage: task.isCompleted ? "arrow.clockwise" : "checkmark") {
                store.toggleToday(task.id)
            }
            ForEach(TaskQuadrant.allCases.filter { $0 != task.quadrant }) { destination in
                Button("移到\(destination.title)") {
                    var updated = task
                    updated.quadrant = destination
                    store.updateTodayTask(updated)
                }
            }
            Button("移出四象限", systemImage: "xmark.circle") {
                var updated = task
                updated.quadrant = nil
                store.updateTodayTask(updated)
            }
        }
        .sheet(isPresented: $isEditing) {
            TodayTaskEditor(task: task) { store.updateTodayTask($0) }
        }
    }
}

private struct PriorityTaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusSessionController
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuickNoteEditor = false
    @State private var showDeleteConfirmation = false
    let task: PlanTask
    let quadrant: TaskQuadrant?

    private var project: Project? {
        store.data.projects.first { $0.id == task.projectID }
    }

    private var activeSession: FocusSession? { focus.session(for: task.id) }
    private var isActive: Bool { activeSession != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    store.setPlanTaskCompleted(task.id, isCompleted: !task.isCompleted)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : isActive ? "waveform.path.ecg" : "circle")
                        .foregroundStyle(task.isCompleted ? SkyTheme.sea : isActive ? SkyTheme.ink : .secondary)
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .help(task.isCompleted ? "标记为未完成" : "标记完成")
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .lineLimit(2)
                Spacer(minLength: 2)
                Menu {
                    ForEach(TaskQuadrant.allCases.filter { $0 != quadrant }) { destination in
                        Button {
                            store.placeInQuadrant(taskID: task.id, quadrant: destination)
                        } label: {
                            Label(destination.title, systemImage: destination.symbol)
                        }
                    }
                    Divider()
                    if quadrant == nil {
                        Button {
                            store.removeFromQuadrantOther(taskID: task.id)
                        } label: {
                            Label("移出其他", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button {
                            store.placeInQuadrantOther(taskID: task.id)
                        } label: {
                            Label("移到其他", systemImage: "tray.and.arrow.down")
                        }
                        Button {
                            store.removeFromQuadrant(taskID: task.id)
                        } label: {
                            Label("移出四象限", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("移动或移出")
            }

            if !task.note.isEmpty {
                TaskQuickNoteText(note: task.note)
            }

            HStack(spacing: 8) {
                Label(project?.title ?? "项目", systemImage: project?.symbol ?? "folder")
                    .lineLimit(1)
                Label("\(task.durationMinutes) 分", systemImage: "clock")
                Spacer(minLength: 2)
                if let activeSession {
                    Label(activeSession.state.title, systemImage: activeSession.state.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SkyTheme.ink)
                } else if !task.isCompleted {
                    Button {
                        focus.choose(task)
                    } label: {
                        Label("开始", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .background(taskHighlight, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? SkyTheme.focusYellow : Color.primary.opacity(0.08), lineWidth: isActive ? 2 : 1)
        }
        .opacity(task.isCompleted && !isActive ? 0.52 : 1)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
        .contextMenu {
            TaskQuickNoteMenu(
                note: task.note,
                onEdit: { showQuickNoteEditor = true },
                onDelete: { store.setPlanTaskQuickNote(taskID: task.id, note: "") }
            )
            Divider()
            Button(task.isCompleted ? "标记为未完成" : "标记完成") {
                store.setPlanTaskCompleted(task.id, isCompleted: !task.isCompleted)
            }
            Divider()
            if task.isCompleted || activeSession?.state == .finished {
                Button("重新开始", systemImage: "arrow.clockwise") {
                    store.setPlanTaskCompleted(task.id, isCompleted: false)
                    var restarted = task
                    restarted.isCompleted = false
                    focus.start(task: restarted, durationMinutes: activeSession?.durationMinutes ?? task.durationMinutes)
                }
            }
            Button("开始专注…") { focus.choose(task) }
                .disabled(task.isCompleted || isActive)
            ForEach(TaskQuadrant.allCases.filter { $0 != quadrant }) { destination in
                Button("移到\(destination.title)") {
                    store.placeInQuadrant(taskID: task.id, quadrant: destination)
                }
            }
            Divider()
            if quadrant == nil {
                Button("移出其他") { store.removeFromQuadrantOther(taskID: task.id) }
            } else {
                Button("移到其他") { store.placeInQuadrantOther(taskID: task.id) }
                Button("移出四象限") { store.removeFromQuadrant(taskID: task.id) }
            }
            Divider()
            Button("删除任务…", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .sheet(isPresented: $showQuickNoteEditor) {
            TaskQuickNoteEditor(taskTitle: task.title, note: task.note) {
                store.setPlanTaskQuickNote(taskID: task.id, note: $0)
            }
        }
        .alert("删除这个任务？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deletePlanTask(task.id)
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .accessibilityLabel("\(task.title)，位于\(quadrant?.title ?? "其他")\(isActive ? "，正在专注" : "")")
    }

    private var deleteConfirmationMessage: String {
        if store.data.planTasks.contains(where: { $0.parentID == task.id }) {
            return "“\(task.title)”及其所有子任务会从项目中删除，相关的四象限位置和今日安排也会移除。"
        }
        return "“\(task.title)”会从项目中删除，相关的四象限位置和今日安排也会移除。"
    }

    private var taskHighlight: Color {
        if isActive { return SkyTheme.focusYellow.opacity(colorScheme == .dark ? 0.34 : 0.68) }
        if task.isCompleted { return SkyTheme.completedWash.opacity(colorScheme == .dark ? 0.14 : 0.28) }
        if quadrant != nil { return SkyTheme.scheduleYellow.opacity(colorScheme == .dark ? 0.11 : 0.18) }
        return SkyTheme.paleSky.opacity(colorScheme == .dark ? 0.10 : 0.24)
    }
}

private struct QuadrantDropDelegate: DropDelegate {
    let quadrant: TaskQuadrant
    let targetID: UUID?
    let store: TaskStore
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let taskID = UUID(uuidString: value) else { return }
            Task { @MainActor in
                store.placeInQuadrant(taskID: taskID, quadrant: quadrant, before: targetID)
            }
        }
        return true
    }
}

private struct OtherTasksDropDelegate: DropDelegate {
    let targetID: UUID?
    let store: TaskStore
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let taskID = UUID(uuidString: value) else { return }
            Task { @MainActor in
                store.placeInQuadrantOther(taskID: taskID, before: targetID)
            }
        }
        return true
    }
}

private struct QuadrantRemovalDropDelegate: DropDelegate {
    let store: TaskStore
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let taskID = UUID(uuidString: value) else { return }
            Task { @MainActor in
                store.removeFromQuadrant(taskID: taskID)
            }
        }
        return true
    }
}

private extension TaskQuadrant {
    var accentColor: Color {
        switch self {
        case .importantUrgent: return Color(red: 0.78, green: 0.24, blue: 0.22)
        case .importantNotUrgent: return SkyTheme.sea
        case .notImportantUrgent: return Color(red: 0.72, green: 0.47, blue: 0.08)
        case .notImportantNotUrgent: return Color.secondary
        }
    }
}
