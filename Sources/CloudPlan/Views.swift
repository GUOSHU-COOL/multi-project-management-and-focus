import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AIProjectSeed {
    var title: String
    var detail: String
}

enum AIAssistantMode {
    case organize
    case createProject(AIProjectSeed)

    var initialInstruction: String {
        switch self {
        case .organize:
            return "帮我整理当前项目，保留已有的好内容，并把下一步拆得更容易开始。"
        case .createProject(let seed):
            let title = seed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = seed.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            var prompt = "请根据下面的目标创建一个完整项目，拆成清晰的阶段、子任务和可以立即开始的动作。"
            if !title.isEmpty { prompt += "\n\n项目名称：\(title)" }
            if !detail.isEmpty { prompt += "\n项目说明：\(detail)" }
            if title.isEmpty && detail.isEmpty { prompt += "\n\n在这里写下你想完成的事情：" }
            return prompt
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @StateObject private var focus = FocusSessionController()
    @State private var showAI = false
    @State private var aiMode = AIAssistantMode.organize
    @State private var focusQuickAdd = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 290)
        } detail: {
            ZStack {
                SkyBackground()
                VStack(spacing: 0) {
                    AdaptiveWorkspace(focusQuickAdd: $focusQuickAdd)
                        .padding(16)
                    FocusRunnerBar()
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Button {
                            NotificationCenter.default.post(name: .newProject, object: nil)
                        } label: {
                            Label("新建项目", systemImage: "folder.badge.plus")
                        }
                        Button {
                            focusQuickAdd = true
                        } label: {
                            Label("新建今日任务", systemImage: "checklist")
                        }
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .help("新建项目或今日任务")
                    Button {
                        showAI = true
                    } label: {
                        Label("AI 整理", systemImage: "sparkles")
                    }
                    .help("让 AI 为你整理、拆分或调整任务（⌘K）")
                }
            }
        }
        .navigationTitle(store.selectedSection == .projects ? store.selectedProject?.title ?? "项目" : store.selectedSection.rawValue)
        .environmentObject(focus)
        .sheet(isPresented: $showAI) {
            AIAssistantView(mode: aiMode)
                .environmentObject(store)
        }
        .sheet(item: $focus.pendingTask) { task in
            FocusDurationSheet(task: task)
                .environmentObject(focus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAI)) { notification in
            if let seed = notification.object as? AIProjectSeed {
                aiMode = .createProject(seed)
            } else {
                aiMode = .organize
            }
            showAI = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTodayTask)) { _ in focusQuickAdd = true }
        .onAppear {
            let environment = ProcessInfo.processInfo.environment
            if environment["CLOUDPLAN_QA_QUADRANTS"] == "1" {
                store.selectedSection = .quadrants
            }
            if environment["CLOUDPLAN_QA_FOCUS"] == "1",
               let taskID = store.data.quadrantPlacements.first?.taskID,
               let task = store.data.planTasks.first(where: { $0.id == taskID }) {
                DispatchQueue.main.async { focus.choose(task) }
            }
        }
        .alert("没有保存", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("好") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showNewProject = false
    @State private var editingProject: Project?
    @State private var projectToDelete: Project?
    @State private var pendingAIProjectSeed: AIProjectSeed?

    var body: some View {
        VStack(spacing: 0) {
            SidebarBrandHeader()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SidebarSectionBlock(title: "空间") {
                        ForEach(SidebarSection.allCases) { section in
                            SidebarNavigationRow(
                                title: section.rawValue,
                                symbol: section.symbol,
                                isSelected: store.selectedSection == section
                            ) {
                                store.selectedSection = section
                            }
                        }
                    }

                    SidebarSectionBlock(title: "我的项目", count: store.data.projects.count) {
                        if store.data.projects.isEmpty {
                            SidebarEmptyProjectsView()
                        } else {
                            ForEach(store.data.projects) { project in
                                SidebarProjectRow(
                                    project: project,
                                    isSelected: store.selectedSection == .projects && store.selectedProjectID == project.id
                                ) {
                                    store.selectedSection = .projects
                                    store.selectedProjectID = project.id
                                }
                                .contextMenu {
                                    Button("编辑项目…") { editingProject = project }
                                    Divider()
                                    Button("删除项目…", role: .destructive) { projectToDelete = project }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)

            SidebarFooter {
                showNewProject = true
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .underPageBackgroundColor).opacity(0.96),
                    SkyTheme.paleSky.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .sheet(isPresented: $showNewProject, onDismiss: {
            guard let seed = pendingAIProjectSeed else { return }
            pendingAIProjectSeed = nil
            NotificationCenter.default.post(name: .openAI, object: seed)
        }) {
            ProjectEditor(project: nil, onAICreate: { title, detail in
                pendingAIProjectSeed = AIProjectSeed(title: title, detail: detail)
                showNewProject = false
            }) { title, detail, symbol in
                store.addProject(title: title, detail: detail, symbol: symbol)
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditor(project: project) { title, detail, symbol in
                var updated = project
                updated.title = title
                updated.detail = detail
                updated.symbol = symbol
                store.updateProject(updated)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in
            showNewProject = true
        }
        .alert("删除这个项目？", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        ), presenting: projectToDelete) { project in
            Button("取消", role: .cancel) { projectToDelete = nil }
            Button("删除", role: .destructive) {
                store.deleteProject(project.id)
                projectToDelete = nil
            }
        } message: { project in
            let count = store.data.planTasks.filter { $0.projectID == project.id }.count
            Text(count == 0 ? "“\(project.title)”会被删除。" : "“\(project.title)”及其中 \(count) 个计划任务会被删除，相关的今日安排也会移除。")
        }
    }
}

private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SkyTheme.sea)
                .frame(width: 34, height: 34)
                .background(SkyTheme.paleSky.opacity(0.78), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(SkyTheme.sky.opacity(0.25), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("云上计划")
                    .font(.headline.weight(.semibold))
                Text("轻一点，走远一点")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct SidebarSectionBlock<Content: View>: View {
    let title: String
    var count: Int?
    let content: Content

    init(title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(SkyTheme.sea.opacity(0.78))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SkyTheme.paleSky.opacity(0.58), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)

            content
        }
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SidebarRowLabel(title: title, symbol: symbol, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(rowBorder)
        .overlay(alignment: .leading) {
            SidebarSelectionStripe(isVisible: isSelected)
        }
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isSelected { return SkyTheme.paleSky.opacity(0.72) }
        return isHovered ? Color.primary.opacity(0.055) : .clear
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(isSelected ? SkyTheme.sky.opacity(0.30) : .clear, lineWidth: 1)
    }
}

private struct SidebarProjectRow: View {
    let project: Project
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SidebarRowLabel(title: project.title, symbol: project.symbol, isSelected: isSelected, allowsTwoLines: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(rowBorder)
        .overlay(alignment: .leading) {
            SidebarSelectionStripe(isVisible: isSelected)
        }
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isSelected { return SkyTheme.paleSky.opacity(0.72) }
        return isHovered ? Color.primary.opacity(0.055) : .clear
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(isSelected ? SkyTheme.sky.opacity(0.30) : .clear, lineWidth: 1)
    }
}

private struct SidebarRowLabel: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    var allowsTwoLines = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? SkyTheme.sea : SkyTheme.sea.opacity(0.82))
                .frame(width: 28, height: 28)
                .background(
                    isSelected ? Color.white.opacity(0.78) : SkyTheme.paleSky.opacity(0.58),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(allowsTwoLines ? 2 : 1)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(SkyTheme.sea)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(!isSelected)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct SidebarSelectionStripe: View {
    let isVisible: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(SkyTheme.sea)
            .frame(width: 3, height: 22)
            .padding(.leading, 4)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: isVisible)
    }
}

private struct SidebarEmptyProjectsView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.sun")
                .foregroundStyle(SkyTheme.sky)
            Text("还没有项目")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SidebarFooter: View {
    let onNewProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .opacity(0.45)

            Button(action: onNewProject) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("新建项目")
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .opacity(0.78)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(SkyTheme.sea, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: SkyTheme.sea.opacity(0.18), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .help("创建一个新项目")

            HStack(spacing: 7) {
                Image(systemName: "cloud.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SkyTheme.sea)
                VStack(alignment: .leading, spacing: 1) {
                    Text("像云一样，轻一点")
                        .font(.caption.weight(.semibold))
                    Text("计划是方向，不是枷锁。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(SkyTheme.sea)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 13)
        .background(.thinMaterial)
    }
}

struct AdaptiveWorkspace: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var focusQuickAdd: Bool

    var body: some View {
        if store.selectedSection == .quadrants {
            QuadrantPanel()
        } else {
            GeometryReader { geometry in
                if geometry.size.width >= 880 {
                    HSplitView {
                        primaryPanel.frame(minWidth: 390)
                        TodayPanel(focusQuickAdd: $focusQuickAdd).frame(minWidth: 330)
                    }
                } else {
                    VSplitView {
                        primaryPanel.frame(minHeight: 280)
                        TodayPanel(focusQuickAdd: $focusQuickAdd).frame(minHeight: 210)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var primaryPanel: some View {
        if store.selectedSection == .routines {
            RoutinePanel()
        } else {
            PlanPanel()
        }
    }
}

struct PanelHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(SkyTheme.sea)
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

struct PlanPanel: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.undoManager) private var undoManager
    @State private var newTask = ""
    @State private var editingTask: PlanTask?
    @State private var addingChildTo: PlanTask?
    @State private var displayMode: PlanDisplayMode = .mindMap
    @State private var isRootDropTarget = false

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                PanelHeader(
                    eyebrow: "Project map",
                    title: store.selectedProject?.title ?? "先创建一个项目",
                    subtitle: store.selectedProject?.detail.isEmpty == false ? store.selectedProject!.detail : "把想法拆成下一步，再拖到今天",
                    trailing: AnyView(headerControls)
                )
                Divider().opacity(0.45)
                if store.selectedProject == nil {
                    ContentUnavailableView("还没有项目", systemImage: "cloud", description: Text("在左侧创建第一个项目。"))
                } else {
                    Group {
                        if displayMode == .mindMap {
                            MindMapView(
                                onSchedule: { store.scheduleToday(planTaskID: $0.id) },
                                onToggleCompletion: { store.setPlanTaskCompleted($0.id, isCompleted: !$0.isCompleted) },
                                onEdit: { editingTask = $0 },
                                onAddChild: { addingChildTo = $0 },
                                onDelete: { store.deletePlanTask($0.id) }
                            )
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    if !treeItems.isEmpty {
                                        if treeItems.contains(where: { $0.task.parentID != nil }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: isRootDropTarget ? "arrow.down.circle.fill" : "arrow.up.to.line")
                                                Text(isRootDropTarget ? "松开放到项目顶层" : "拖到这里，移回项目顶层")
                                                Spacer()
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isRootDropTarget ? SkyTheme.ink : .secondary)
                                            .padding(.horizontal, 11)
                                            .frame(minHeight: 40)
                                            .background(
                                                isRootDropTarget ? SkyTheme.scheduleYellow.opacity(0.82) : Color.primary.opacity(0.035),
                                                in: RoundedRectangle(cornerRadius: 6)
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isRootDropTarget ? SkyTheme.focusYellow : Color.primary.opacity(0.08))
                                            }
                                            .onDrop(
                                                of: [UTType.text.identifier],
                                                delegate: PlanHierarchyDropDelegate(
                                                    targetID: nil,
                                                    store: store,
                                                    undoManager: undoManager,
                                                    isTargeted: $isRootDropTarget
                                                )
                                            )
                                        }
                                        Label("拖到另一任务上可建立父子层级，⌘Z 可撤销", systemImage: "arrow.triangle.branch")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.bottom, 2)
                                    }
                                    ForEach(treeItems) { item in
                                        PlanTaskCard(
                                            task: item.task,
                                            isScheduled: store.data.todayTasks.contains { $0.sourceID == item.task.id },
                                            quadrant: store.placement(for: item.task.id)?.quadrant,
                                            depth: item.depth,
                                            childCount: store.selectedPlanTasks.filter { $0.parentID == item.task.id }.count,
                                            onSchedule: { store.scheduleToday(planTaskID: item.task.id) },
                                            onToggleCompletion: {
                                                store.setPlanTaskCompleted(item.task.id, isCompleted: !item.task.isCompleted)
                                            },
                                            onAddChild: { addingChildTo = item.task },
                                            onMoveToRoot: {
                                                try? store.reparentPlanTask(item.task.id, to: nil, undoManager: undoManager)
                                            },
                                            onEdit: { editingTask = item.task },
                                            onDelete: { store.deletePlanTask(item.task.id) }
                                        )
                                        .onDrop(
                                            of: [UTType.text.identifier],
                                            delegate: PlanHierarchyDropDelegate(
                                                targetID: item.task.id,
                                                store: store,
                                                undoManager: undoManager
                                            )
                                        )
                                    }
                                }
                                .padding(14)
                            }
                        }
                    }
                    Divider().opacity(0.45)
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(SkyTheme.sea)
                        TextField("添加一个可执行的下一步…", text: $newTask)
                            .textFieldStyle(.plain)
                            .onSubmit(addTask)
                        Button("添加", action: addTask)
                            .buttonStyle(.borderedProminent)
                            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(14)
                }
            }
        }
        .padding(6)
        .sheet(item: $editingTask) { task in
            PlanTaskEditor(task: task) { updated in
                store.updatePlanTask(updated)
            }
        }
        .sheet(item: $addingChildTo) { parent in
            NewPlanTaskEditor(parent: parent) { title, note, goal, duration in
                store.addPlanTask(title: title, parentID: parent.id, note: note, goal: goal, durationMinutes: duration)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["CLOUDPLAN_QA_ADD_CHILD"] == "1",
               let parent = store.selectedPlanTasks.last {
                DispatchQueue.main.async { addingChildTo = parent }
            }
        }
    }

    private var headerControls: some View {
        HStack(spacing: 14) {
            Picker("视图", selection: $displayMode) {
                ForEach(PlanDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            planProgress
        }
    }

    private var planProgress: some View {
        let total = store.selectedPlanTasks.count
        let complete = store.selectedPlanTasks.filter(\.isCompleted).count
        return VStack(alignment: .trailing, spacing: 5) {
            Text(total == 0 ? "从第一步开始" : "\(complete) / \(total)")
                .font(.caption.weight(.semibold))
            ProgressView(value: total == 0 ? 0 : Double(complete), total: Double(max(total, 1)))
                .frame(width: 92)
        }
    }

    private var treeItems: [TaskTreeItem] {
        let tasks = store.selectedPlanTasks
        var result: [TaskTreeItem] = []
        var visited = Set<UUID>()
        func appendChildren(of parent: UUID?, depth: Int) {
            for task in tasks.filter({ $0.parentID == parent }) {
                guard visited.insert(task.id).inserted else { continue }
                result.append(TaskTreeItem(task: task, depth: depth))
                appendChildren(of: task.id, depth: depth + 1)
            }
        }
        appendChildren(of: nil, depth: 0)
        result.append(contentsOf: tasks.filter { !visited.contains($0.id) }.map { TaskTreeItem(task: $0, depth: 0) })
        return result
    }

    private func addTask() {
        store.addPlanTask(title: newTask)
        newTask = ""
    }
}

enum PlanDisplayMode: String, CaseIterable, Identifiable {
    case mindMap
    case list
    var id: String { rawValue }
    var title: String { self == .mindMap ? "导图" : "列表" }
    var symbol: String { self == .mindMap ? "point.3.connected.trianglepath.dotted" : "list.bullet.indent" }
}

struct TaskTreeItem: Identifiable {
    let task: PlanTask
    let depth: Int
    var id: UUID { task.id }
}

struct TaskQuickNoteText: View {
    let note: String
    var lineLimit = 2
    @State private var isExpanded = true

    private var canToggleExpansion: Bool {
        note.contains(where: \.isNewline) || note.count > 72
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(SkyTheme.sky)
                    .padding(.top, 2)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("快记：\(note)")
            }

            if canToggleExpansion {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isExpanded ? "收起" : "展开",
                            systemImage: isExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SkyTheme.sea)
                    .help(isExpanded ? "收起快记" : "展开快记")
                    .accessibilityLabel(isExpanded ? "收起快记" : "展开快记")
                }
                .padding(.leading, 19)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}

struct TaskQuickNoteMenu: View {
    let note: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onEdit) {
            Label(hasNote ? "编辑快记…" : "添加快记…", systemImage: "note.text")
        }
        if hasNote {
            Button(role: .destructive, action: onDelete) {
                Label("删除快记", systemImage: "trash")
            }
        }
    }
}

struct TaskQuickNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @FocusState private var noteFocused: Bool

    let taskTitle: String
    let originalNote: String
    let onSave: (String) -> Void

    init(taskTitle: String, note: String, onSave: @escaping (String) -> Void) {
        self.taskTitle = taskTitle
        self.originalNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.onSave = onSave
        _note = State(initialValue: note)
    }

    private var cleanedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExistingNote: Bool { !originalNote.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(
                symbol: "note.text",
                title: hasExistingNote ? "编辑快记" : "添加快记",
                subtitle: taskTitle
            )
            .padding(24)

            Divider().opacity(0.5)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("写下一点背景、想法或下一步…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($noteFocused)
                    .padding(2)
            }
            .frame(minHeight: 150)
            .padding(7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(noteFocused ? SkyTheme.sky : Color.primary.opacity(0.11), lineWidth: noteFocused ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(24)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                if hasExistingNote {
                    Button("删除快记", role: .destructive) {
                        onSave("")
                        dismiss()
                    }
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onSave(cleanedNote)
                    dismiss()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(cleanedNote == originalNote)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 460)
        .background(.background)
        .onAppear { noteFocused = true }
    }
}

struct PlanTaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusSessionController
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuickNoteEditor = false
    let task: PlanTask
    let isScheduled: Bool
    let quadrant: TaskQuadrant?
    let depth: Int
    let childCount: Int
    let onSchedule: () -> Void
    let onToggleCompletion: () -> Void
    let onAddChild: () -> Void
    let onMoveToRoot: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var activeSession: FocusSession? { focus.session(for: task.id) }
    private var isActive: Bool { activeSession != nil }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(task.isCompleted ? SkyTheme.sea : isActive ? SkyTheme.ink : .secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "标记为未完成" : "标记完成")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if task.parentID != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isCompleted)
                    if let activeSession {
                        Label(activeSession.state.title, systemImage: activeSession.state.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(SkyTheme.ink)
                    }
                    if isScheduled {
                        Label("今天", systemImage: "sun.max.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SkyTheme.sea)
                    }
                    if let quadrant {
                        Label("短期", systemImage: "square.grid.2x2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.02))
                            .help("四象限：\(quadrant.title)")
                    }
                }
                if !task.note.isEmpty {
                    TaskQuickNoteText(note: task.note)
                }
                HStack(spacing: 12) {
                    Label("\(task.durationMinutes) 分钟", systemImage: "clock")
                    if !task.goal.isEmpty { Label(task.goal, systemImage: "scope") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            QuietIconButton(symbol: "arrow.turn.down.right", helpText: "添加子任务", action: onAddChild)
            QuietIconButton(
                symbol: isScheduled ? "checkmark" : "sun.max",
                helpText: isScheduled ? "已在今天" : "放到今天",
                isActive: isScheduled,
                isDisabled: isScheduled,
                action: onSchedule
            )
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(cardBorder, lineWidth: isActive ? 2 : 1)
        }
        .opacity(task.isCompleted && !isActive ? 0.52 : 1)
        .padding(.leading, CGFloat(depth) * 22)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onSchedule)
        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
        .contextMenu {
            TaskQuickNoteMenu(
                note: task.note,
                onEdit: { showQuickNoteEditor = true },
                onDelete: { store.setPlanTaskQuickNote(taskID: task.id, note: "") }
            )
            Divider()
            Button(task.isCompleted ? "标记为未完成" : "标记完成", action: onToggleCompletion)
            Divider()
            Button("放到今天", action: onSchedule).disabled(isScheduled)
            Button("添加子任务…", action: onAddChild)
            Button("移到项目顶层", action: onMoveToRoot).disabled(task.parentID == nil)
            Button("编辑…", action: onEdit)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .sheet(isPresented: $showQuickNoteEditor) {
            TaskQuickNoteEditor(taskTitle: task.title, note: task.note) {
                store.setPlanTaskQuickNote(taskID: task.id, note: $0)
            }
        }
        .accessibilityLabel("计划任务：\(task.title)，第 \(depth + 1) 层，\(childCount) 个子任务\(task.isCompleted ? "，已完成" : "")\(isScheduled ? "，已安排到今天" : "")\(quadrant == nil ? "" : "，已进入四象限")")
    }

    private var cardBackground: Color {
        if isActive { return SkyTheme.focusYellow.opacity(colorScheme == .dark ? 0.34 : 0.68) }
        if task.isCompleted { return SkyTheme.completedWash.opacity(colorScheme == .dark ? 0.16 : 0.30) }
        if quadrant != nil { return SkyTheme.scheduleYellow.opacity(colorScheme == .dark ? 0.22 : 0.48) }
        if isScheduled { return SkyTheme.paleSky.opacity(0.25) }
        return Color.primary.opacity(0.035)
    }

    private var cardBorder: Color {
        if isActive { return SkyTheme.focusYellow }
        if quadrant != nil { return Color(red: 0.78, green: 0.58, blue: 0.08).opacity(0.72) }
        if isScheduled { return SkyTheme.sky.opacity(0.45) }
        return Color.primary.opacity(0.06)
    }
}

struct PlanHierarchyDropDelegate: DropDelegate {
    let targetID: UUID?
    let store: TaskStore
    let undoManager: UndoManager?
    var isTargeted: Binding<Bool>? = nil

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        isTargeted?.wrappedValue = true
    }

    func dropExited(info: DropInfo) {
        isTargeted?.wrappedValue = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted?.wrappedValue = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let draggedID = UUID(uuidString: value) else { return }
            Task { @MainActor in
                guard store.data.planTasks.contains(where: { $0.id == draggedID }) else { return }
                try? store.reparentPlanTask(draggedID, to: targetID, undoManager: undoManager)
            }
        }
        return true
    }
}

struct TodayPanel: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var focusQuickAdd: Bool
    @State private var quickTask = ""
    @State private var editingTask: TodayTask?
    @State private var draggedTodayTitle: String?
    @State private var isRemoveZoneTargeted = false
    @State private var dragWatchTimer: Timer?
    @FocusState private var isQuickAddFocused: Bool

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                PanelHeader(
                    eyebrow: "Today",
                    title: "今天，轻轻向前",
                    subtitle: Date.now.formatted(.dateTime.month().day().weekday(.wide)),
                    trailing: AnyView(todaySummary)
                )
                Divider().opacity(0.45)
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if store.orderedTodayTasks.isEmpty {
                            ContentUnavailableView("今天还是一片空白", systemImage: "wind", description: Text("从计划拖进来，或随手写下一件事。"))
                                .padding(.top, 36)
                        }
                        ForEach(store.orderedTodayTasks) { task in
                            TodayTaskRow(
                                task: task,
                                onToggle: { store.toggleToday(task.id) },
                                onEdit: { editingTask = task },
                                onDelete: { store.deleteToday(task.id) },
                                onDragStarted: { beginTodayDrag(title: task.title) }
                            )
                            .onDrop(of: [UTType.text.identifier], delegate: TodayDropDelegate(targetID: task.id, store: store))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                }
                .onDrop(of: [UTType.text.identifier], delegate: TodayDropDelegate(targetID: nil, store: store))
                .overlay(alignment: .bottom) {
                    if let draggedTodayTitle {
                        TodayRemoveDropZone(
                            title: draggedTodayTitle,
                            isTargeted: $isRemoveZoneTargeted,
                            onRemove: { id in
                                if store.data.todayTasks.contains(where: { $0.id == id }) {
                                    store.deleteToday(id)
                                }
                                endTodayDrag()
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: draggedTodayTitle)
                Divider().opacity(0.45)
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SkyTheme.sea)
                    TextField("临时想到什么，就放在这里…", text: $quickTask)
                        .textFieldStyle(.plain)
                        .focused($isQuickAddFocused)
                        .onSubmit(addQuickTask)
                    Button("记下", action: addQuickTask)
                        .buttonStyle(.borderedProminent)
                        .disabled(quickTask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
            }
        }
        .padding(6)
        .onChange(of: focusQuickAdd) { _, shouldFocus in
            if shouldFocus {
                isQuickAddFocused = true
                focusQuickAdd = false
            }
        }
        .sheet(item: $editingTask) { task in
            TodayTaskEditor(task: task) { store.updateTodayTask($0) }
        }
    }

    private var todaySummary: some View {
        let total = store.data.todayTasks.count
        return VStack(alignment: .trailing, spacing: 3) {
            Text(total == 0 ? "自由的一天" : "\(store.completedCount) / \(total) 完成")
                .font(.caption.weight(.semibold))
            Text("约 \(store.data.todayTasks.reduce(0) { $0 + $1.durationMinutes }) 分钟")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func addQuickTask() {
        store.addTodayTask(title: quickTask)
        quickTask = ""
        isQuickAddFocused = true
    }

    /// 拖动今日任务时放出移除区，松手（无论落在哪里）后收起。
    private func beginTodayDrag(title: String) {
        isRemoveZoneTargeted = false
        draggedTodayTitle = title
        guard dragWatchTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            endTodayDrag()
        }
        // 拖放期间运行循环处于事件跟踪模式，需要挂到 .common 才会继续触发。
        RunLoop.main.add(timer, forMode: .common)
        dragWatchTimer = timer
    }

    private func endTodayDrag() {
        dragWatchTimer?.invalidate()
        dragWatchTimer = nil
        draggedTodayTitle = nil
        isRemoveZoneTargeted = false
    }
}

/// 今日任务拖出列表后可以放下的移除区。
struct TodayRemoveDropZone: View {
    let title: String
    @Binding var isTargeted: Bool
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isTargeted ? "trash.fill" : "trash")
                .font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(isTargeted ? "松开，从今天移除" : "拖到这里，从今天移除")
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isTargeted ? Color.white.opacity(0.9) : Color.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.to.line")
                .font(.caption2.weight(.bold))
                .opacity(isTargeted ? 1 : 0.55)
        }
        .foregroundStyle(isTargeted ? Color.white : SkyTheme.sea)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(SkyTheme.sea) : AnyShapeStyle(.regularMaterial))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.white.opacity(0.75) : SkyTheme.sky.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 4])
                )
        }
        .shadow(color: SkyTheme.sea.opacity(0.18), radius: 10, y: 4)
        .onDrop(of: [UTType.text.identifier], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let value = object as? String, let id = UUID(uuidString: value) else { return }
                Task { @MainActor in onRemove(id) }
            }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("移除区：把今日任务拖到这里可以从今天移除")
    }
}

struct TodayTaskRow: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showQuickNoteEditor = false
    @State private var isEditingTime = false
    @State private var draftTime = ""
    @State private var timeInputError = false
    @FocusState private var timeFocused: Bool
    let task: TodayTask
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDragStarted: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? SkyTheme.sea : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                if !task.note.isEmpty {
                    TaskQuickNoteText(note: task.note)
                }
                HStack(spacing: 8) {
                    SourcePill(source: task.source)
                    timeControl
                    Text("\(task.durationMinutes) 分钟")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("拖动调整顺序")
        }
        .padding(11)
        .background(Color.primary.opacity(task.isCompleted ? 0.025 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .contextMenu {
            TaskQuickNoteMenu(
                note: task.note,
                onEdit: { showQuickNoteEditor = true },
                onDelete: { store.setTodayTaskQuickNote(taskID: task.id, note: "") }
            )
            Divider()
            Button(task.isCompleted ? "标记为未完成" : "完成", action: onToggle)
            Button("编辑…", action: onEdit)
            Divider()
            Button("从今天移除", role: .destructive, action: onDelete)
        }
        .sheet(isPresented: $showQuickNoteEditor) {
            TaskQuickNoteEditor(taskTitle: task.title, note: task.note) {
                store.setTodayTaskQuickNote(taskID: task.id, note: $0)
            }
        }
        .onChange(of: timeFocused) { _, isFocused in
            if !isFocused && isEditingTime {
                commitTime()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.isCompleted ? "已完成" : "未完成")，\(task.title)，\(task.time)")
    }

    @ViewBuilder
    private var timeControl: some View {
        if isEditingTime {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundStyle(timeInputError ? .red : SkyTheme.sky)
                TextField("09:30", text: $draftTime)
                    .textFieldStyle(.plain)
                    .frame(width: 48)
                    .focused($timeFocused)
                    .onSubmit(commitTime)
                    .onChange(of: draftTime) { _, _ in
                        timeInputError = false
                    }
                Button {
                    commitTime()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SkyTheme.sea)
                .help("保存时间")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(timeInputError ? Color.red.opacity(0.75) : SkyTheme.sky.opacity(0.55), lineWidth: 1)
            }
            .help(timeInputError ? "请输入有效时间，例如 09:30" : "输入时间，例如 09:30")
            .onExitCommand {
                draftTime = task.time
                timeInputError = false
                isEditingTime = false
                timeFocused = false
            }
        } else {
            Button {
                draftTime = task.time
                timeInputError = false
                isEditingTime = true
                DispatchQueue.main.async {
                    timeFocused = true
                }
            } label: {
                Label(task.time.isEmpty ? "设置时间" : task.time, systemImage: "clock")
            }
            .buttonStyle(.plain)
            .foregroundStyle(task.time.isEmpty ? .tertiary : .secondary)
            .help("点击调整时间")
            .accessibilityLabel(task.time.isEmpty ? "设置时间" : "时间 \(task.time)，点击调整")
        }
    }

    private func commitTime() {
        guard isEditingTime else { return }
        guard let normalized = normalizedTime(draftTime) else {
            timeInputError = true
            DispatchQueue.main.async {
                timeFocused = true
            }
            return
        }

        if normalized != task.time {
            var updated = task
            updated.time = normalized
            store.updateTodayTask(updated)
        }
        timeInputError = false
        isEditingTime = false
        timeFocused = false
    }

    private func normalizedTime(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "" }

        let parts: [Int]
        if cleaned.contains(":"), cleaned.split(separator: ":", omittingEmptySubsequences: false).count == 2 {
            parts = cleaned.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        } else if let compact = Int(cleaned), cleaned.count == 3 || cleaned.count == 4 {
            let hour = compact / 100
            let minute = compact % 100
            parts = [hour, minute]
        } else {
            return nil
        }

        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        return String(format: "%02d:%02d", parts[0], parts[1])
    }
}

struct TodayDropDelegate: DropDelegate {
    let targetID: UUID?
    let store: TaskStore

    func dropEntered(info: DropInfo) {
        loadID(info) { id in
            guard let targetID else { return }
            if store.data.todayTasks.contains(where: { $0.id == id }) {
                store.moveToday(draggedID: id, before: targetID)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        loadID(info) { id in
            if store.data.planTasks.contains(where: { $0.id == id }) {
                store.scheduleToday(planTaskID: id)
            } else if let targetID, store.data.todayTasks.contains(where: { $0.id == id }) {
                store.moveToday(draggedID: id, before: targetID)
            }
        }
        return true
    }

    private func loadID(_ info: DropInfo, completion: @escaping @MainActor (UUID) -> Void) {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let id = UUID(uuidString: value) else { return }
            Task { @MainActor in completion(id) }
        }
    }
}

struct RoutinePanel: View {
    @EnvironmentObject private var store: TaskStore
    @State private var title = ""
    @State private var repeatRule = "每周 3 次"
    @State private var editingRoutine: RoutineTask?

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                PanelHeader(eyebrow: "Long view", title: "长期主义", subtitle: "不追求每天完美，只让方向持续发生")
                Divider().opacity(0.45)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.data.routines) { routine in
                            HStack(spacing: 12) {
                                Image(systemName: "infinity")
                                    .font(.title2.weight(.medium))
                                    .foregroundStyle(SkyTheme.sea)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(routine.title).font(.body.weight(.semibold))
                                    HStack(spacing: 10) {
                                        Button {
                                            editingRoutine = routine
                                        } label: {
                                            Label(routine.repeatRule, systemImage: "repeat")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(SkyTheme.sea)
                                        .help("点击调整频率")
                                        if !routine.milestone.isEmpty { Label(routine.milestone, systemImage: "flag") }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("放到今天") { store.scheduleRoutine(routine) }
                                    .buttonStyle(.bordered)
                            }
                            .padding(13)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(14)
                }
                Divider().opacity(0.45)
                HStack(spacing: 8) {
                    TextField("新的长期任务", text: $title)
                    TextField("频率", text: $repeatRule).frame(maxWidth: 120)
                    Button("添加") {
                        store.addRoutine(title: title, repeatRule: repeatRule)
                        title = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
            }
        }
        .padding(6)
        .sheet(item: $editingRoutine) { routine in
            RoutineFrequencyEditor(routine: routine) { updatedRule in
                var updated = routine
                updated.repeatRule = updatedRule
                store.updateRoutine(updated)
            }
        }
    }
}

struct RoutineFrequencyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var customRule: String

    let routine: RoutineTask
    let onSave: (String) -> Void

    private let presets = [
        "每天",
        "每周",
        "每周 2 次",
        "每周 3 次",
        "每周 5 次",
        "每周日",
        "每月"
    ]
    private let customTag = "__custom__"

    init(routine: RoutineTask, onSave: @escaping (String) -> Void) {
        self.routine = routine
        self.onSave = onSave
        let current = routine.repeatRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if [
            "每天", "每周", "每周 2 次", "每周 3 次", "每周 5 次", "每周日", "每月"
        ].contains(current) {
            _selection = State(initialValue: current)
            _customRule = State(initialValue: "")
        } else {
            _selection = State(initialValue: customTag)
            _customRule = State(initialValue: current)
        }
    }

    private var resolvedRule: String {
        selection == customTag ? customRule.trimmingCharacters(in: .whitespacesAndNewlines) : selection
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(
                symbol: "repeat",
                title: "调整频率",
                subtitle: routine.title
            )
            .padding(28)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 18) {
                EditorField("重复频率", symbol: "repeat") {
                    Picker("重复频率", selection: $selection) {
                        ForEach(presets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                        Divider()
                        Text("自定义…").tag(customTag)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if selection == customTag {
                    EditorField("自定义频率", symbol: "textformat") {
                        TextField("例如：每两周一次", text: $customRule)
                            .quietInput()
                    }
                }
            }
            .padding(28)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onSave(resolvedRule)
                    dismiss()
                } label: {
                    Label("保存频率", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(resolvedRule.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 430)
        .background(.background)
    }
}

struct ProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var detail: String
    @State private var symbol: String
    @FocusState private var titleFocused: Bool
    private let isEditing: Bool
    let onAICreate: ((String, String) -> Void)?
    let onSave: (String, String, String) -> Void

    private let symbols = [
        "cloud.sun.fill", "flag.checkered", "book.closed.fill", "figure.run",
        "airplane", "leaf.fill", "camera.fill", "music.note",
        "hammer.fill", "graduationcap.fill", "paintpalette.fill", "sparkles"
    ]

    init(
        project: Project?,
        onAICreate: ((String, String) -> Void)? = nil,
        onSave: @escaping (String, String, String) -> Void
    ) {
        _title = State(initialValue: project?.title ?? "")
        _detail = State(initialValue: project?.detail ?? "")
        _symbol = State(initialValue: project?.symbol ?? "cloud.sun.fill")
        isEditing = project != nil
        self.onAICreate = onAICreate
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(
                symbol: symbol,
                title: isEditing ? "编辑项目" : "新建项目",
                subtitle: isEditing ? "调整它现在的方向与表达" : "为一个长期方向留出清晰的位置"
            )
            .padding(28)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 19) {
                EditorField("项目名称", symbol: "textformat") {
                    TextField("例如：完成我的第一本书", text: $title)
                        .focused($titleFocused)
                        .onSubmit(save)
                        .quietInput(isFocused: titleFocused)
                }

                EditorField("一句话说明", symbol: "quote.bubble") {
                    TextField("为什么这件事对你重要？", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                        .quietInput(minHeight: 68)
                }

                EditorField("项目图标", symbol: "square.grid.3x3") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(symbols, id: \.self) { candidate in
                        Button {
                            symbol = candidate
                        } label: {
                            Image(systemName: candidate)
                                .font(.title3.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(symbol == candidate ? SkyTheme.sea : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(symbol == candidate ? SkyTheme.sky : Color.primary.opacity(0.08), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(symbol == candidate ? Color.white : Color.secondary)
                        .accessibilityLabel("项目图标 \(candidate)")
                        .accessibilityAddTraits(symbol == candidate ? .isSelected : [])
                    }
                    }
                }
            }
            .padding(28)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                if !isEditing, let onAICreate {
                    Button {
                        onAICreate(title, detail)
                    } label: {
                        Label("用 AI 创建", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Label(isEditing ? "保存项目" : "创建项目", systemImage: isEditing ? "checkmark" : "plus")
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 520)
        .background(.background)
        .onAppear { titleFocused = true }
    }

    private func save() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        onSave(cleaned, detail, symbol)
        dismiss()
    }
}

struct NewPlanTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    let parent: PlanTask?
    let projectTitle: String?
    let onSave: (String, String, String, Int) -> Void
    @State private var title = ""
    @State private var note = ""
    @State private var goal = ""
    @State private var durationMinutes = 30
    @FocusState private var titleFocused: Bool

    init(
        parent: PlanTask? = nil,
        projectTitle: String? = nil,
        onSave: @escaping (String, String, String, Int) -> Void
    ) {
        self.parent = parent
        self.projectTitle = projectTitle
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(
                symbol: parent == nil ? "checklist" : "arrow.turn.down.right",
                title: parent == nil ? "新建任务" : "添加子任务",
                subtitle: "把下一步写到足够容易开始"
            )
            .padding(28)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 11) {
                    Rectangle()
                        .fill(SkyTheme.sky)
                        .frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(parent == nil ? "所属项目" : "上级任务")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(parent?.title ?? projectTitle ?? "项目")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                }

                EditorField("任务名称", symbol: "checkmark.circle") {
                    TextField("下一步是什么？", text: $title)
                        .focused($titleFocused)
                        .onSubmit(save)
                        .quietInput(isFocused: titleFocused)
                }
                EditorField("说明", symbol: "text.alignleft") {
                    TextField("补充必要的背景（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .quietInput(minHeight: 66)
                }
                EditorField("完成目标", symbol: "scope") {
                    TextField("做到什么算完成？（可选）", text: $goal)
                        .quietInput()
                }
                DurationControl(minutes: $durationMinutes)
            }
            .padding(28)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Label(
                        parent == nil ? "创建任务" : "添加子任务",
                        systemImage: parent == nil ? "plus" : "arrow.turn.down.right"
                    )
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 500)
        .background(.background)
        .onAppear { titleFocused = true }
    }

    private func save() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        onSave(cleaned, note, goal, durationMinutes)
        dismiss()
    }
}

struct PlanTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanTask
    @FocusState private var titleFocused: Bool
    let onSave: (PlanTask) -> Void

    init(task: PlanTask, onSave: @escaping (PlanTask) -> Void) {
        _draft = State(initialValue: task)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(symbol: "pencil.line", title: "编辑计划任务", subtitle: "保留方向，只调整现在需要的信息")
                .padding(28)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 18) {
                EditorField("任务名称", symbol: "checkmark.circle") {
                    TextField("任务标题", text: $draft.title)
                        .focused($titleFocused)
                        .quietInput(isFocused: titleFocused)
                }
                EditorField("说明", symbol: "text.alignleft") {
                    TextField("必要的背景或提示", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                        .quietInput(minHeight: 66)
                }
                EditorField("完成目标", symbol: "scope") {
                    TextField("做到什么算完成？", text: $draft.goal)
                        .quietInput()
                }
                DurationControl(minutes: $draft.durationMinutes)
                Toggle(isOn: $draft.isCompleted) {
                    Label("已经完成", systemImage: "checkmark.circle.fill")
                }
                .toggleStyle(.switch)
            }
            .padding(28)
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { onSave(draft); dismiss() } label: {
                    Label("保存", systemImage: "checkmark")
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 500)
        .background(.background)
        .onAppear { titleFocused = true }
    }
}

struct TodayTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodayTask
    @FocusState private var titleFocused: Bool
    let onSave: (TodayTask) -> Void

    init(task: TodayTask, onSave: @escaping (TodayTask) -> Void) {
        _draft = State(initialValue: task)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(symbol: "sun.max.fill", title: "编辑今日任务", subtitle: "让时间清楚，但不过度安排")
                .padding(28)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 18) {
                EditorField("任务名称", symbol: "checkmark.circle") {
                    TextField("任务标题", text: $draft.title)
                        .focused($titleFocused)
                        .quietInput(isFocused: titleFocused)
                }
                EditorField("说明", symbol: "text.alignleft") {
                    TextField("必要的背景或提示", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                        .quietInput(minHeight: 66)
                }
                EditorField("开始时间", symbol: "clock") {
                    TextField("例如 09:30", text: $draft.time)
                        .quietInput()
                }
                DurationControl(minutes: $draft.durationMinutes)
                Toggle(isOn: $draft.isCompleted) {
                    Label("已经完成", systemImage: "checkmark.circle.fill")
                }
                .toggleStyle(.switch)
            }
            .padding(28)
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { onSave(draft); dismiss() } label: {
                    Label("保存", systemImage: "checkmark")
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 500)
        .background(.background)
        .onAppear { titleFocused = true }
    }
}

private enum AIContextScope: String, CaseIterable, Identifiable {
    case currentProject = "当前项目"
    case workspace = "整个工作区"

    var id: String { rawValue }
}

private enum NotionImportDestination: String, CaseIterable, Identifiable {
    case currentProject = "当前项目"
    case newProjects = "创建新项目"

    var id: String { rawValue }
}

private enum AIConnectionState {
    case success(String)
    case failure(String)
}

struct AIAssistantView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ai.baseURL") private var baseURL = AIConfiguration.officialBaseURL
    @AppStorage("ai.model") private var model = "gpt-5.6-sol"
    @AppStorage("ai.reasoningEffort") private var reasoningEffort = "xhigh"
    @AppStorage("ai.serviceTier") private var serviceTier = "default"
    @AppStorage("ai.disableResponseStorage") private var disableResponseStorage = true

    @State private var apiKey = ""
    @State private var instruction: String
    @State private var contextScope = AIContextScope.currentProject
    @State private var notionDestination = NotionImportDestination.currentProject
    @State private var notionPayload: NotionImportPayload?
    @State private var showNotionImporter = false
    @State private var proposal: AIProposal?
    @State private var isLoading = false
    @State private var isTestingConnection = false
    @State private var connectionState: AIConnectionState?
    @State private var errorMessage: String?

    private let service = OpenAIService()

    init(mode: AIAssistantMode = .organize) {
        _instruction = State(initialValue: mode.initialInstruction)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                EditorHeader(
                    symbol: "sparkles",
                    title: "云朵 AI",
                    subtitle: notionPayload == nil ? "整理、拆分或创建任务" : "从 Notion 整理成可执行计划"
                )
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            Divider().opacity(0.6)

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        serviceSection
                        Divider()
                        scopeAndImportSection
                        Divider()
                        promptSection
                    }
                    .padding(20)
                }
                .frame(minWidth: 350, idealWidth: 390, maxHeight: .infinity, alignment: .topLeading)

                proposalSection
                    .frame(minWidth: 360, idealWidth: 430, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(.background)
        .fileImporter(
            isPresented: $showNotionImporter,
            allowedContentTypes: notionContentTypes,
            allowsMultipleSelection: true,
            onCompletion: loadNotionFiles
        )
        .onAppear {
            if apiKey.isEmpty { apiKey = KeychainStore.loadAPIKey(for: baseURL) }
            if store.selectedProjectID == nil { notionDestination = .newProjects }
        }
        .alert("暂时没整理好", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionTitle("AI 服务", symbol: "network")
            EditorField("API 地址", symbol: "link") {
                HStack(spacing: 8) {
                    TextField("https://api.openai.com/v1", text: $baseURL)
                        .quietInput()
                    QuietIconButton(symbol: "arrow.counterclockwise", helpText: "恢复 OpenAI 官方地址") {
                        baseURL = AIConfiguration.officialBaseURL
                        apiKey = KeychainStore.loadAPIKey(for: baseURL)
                        connectionState = nil
                    }
                }
            }
            EditorField("API Key", symbol: "key.fill") {
                HStack(spacing: 8) {
                    SecureField("只保存在 macOS 钥匙串", text: $apiKey)
                        .quietInput()
                    QuietIconButton(symbol: "key.viewfinder", helpText: "读取此地址已保存的密钥") {
                        apiKey = KeychainStore.loadAPIKey(for: baseURL)
                    }
                }
            }
            EditorField("模型", symbol: "cpu") {
                TextField("服务商支持的模型名称", text: $model)
                    .quietInput()
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("推理强度").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("推理强度", selection: $reasoningEffort) {
                        ForEach(["none", "minimal", "low", "medium", "high", "xhigh"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务等级").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("服务等级", selection: $serviceTier) {
                        ForEach(["default", "auto", "flex", "priority"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Toggle(isOn: $disableResponseStorage) {
                Label("不保存模型响应", systemImage: "lock.shield")
                    .font(.callout)
            }
            .toggleStyle(.switch)

            if isCustomEndpoint {
                Label("任务内容会发送到 \(providerHost)", systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("密钥只存钥匙串，不进入任务存档", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    testConnection()
                } label: {
                    if isTestingConnection {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("测试连接", systemImage: "bolt.horizontal.circle")
                    }
                }
                .disabled(isTestingConnection || isLoading)
                connectionStatus
            }
        }
    }

    private var scopeAndImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionTitle("内容范围", symbol: "scope")
            Picker("发送范围", selection: $contextScope) {
                ForEach(AIContextScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.selectedProjectID == nil)

            HStack(spacing: 10) {
                Button {
                    showNotionImporter = true
                } label: {
                    Label(notionPayload == nil ? "选择 Notion 导出" : "重新选择", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                if notionPayload != nil {
                    QuietIconButton(symbol: "xmark", helpText: "移除 Notion 导入") {
                        notionPayload = nil
                        proposal = nil
                    }
                }
            }

            if let notionPayload {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("\(notionPayload.files.count) 个文件", systemImage: "doc.on.doc")
                        Spacer()
                        Text("\(notionPayload.characterCount) 字")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(notionPayload.files.map(\.name).joined(separator: "、"))
                        .font(.caption)
                        .lineLimit(2)
                    Picker("导入到", selection: $notionDestination) {
                        ForEach(NotionImportDestination.allCases) { destination in
                            Text(destination.rawValue).tag(destination)
                                .disabled(destination == .currentProject && store.selectedProjectID == nil)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(11)
                .background(SkyTheme.paleSky.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionTitle("你想怎么整理", symbol: "text.bubble")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    AIPromptChip(title: "创建完整项目", symbol: "folder.badge.plus") {
                        instruction = "请根据我的目标创建一个完整项目，拆成清晰的阶段、子任务和可以立即开始的动作。"
                    }
                    AIPromptChip(title: "拆成任务树", symbol: "arrow.triangle.branch") {
                        instruction = "请把当前项目拆成清晰的多层任务树，保留已有合理内容，补全阶段和可立即开始的动作。"
                    }
                    AIPromptChip(title: "重组层级", symbol: "point.3.connected.trianglepath.dotted") {
                        instruction = "请检查当前项目的任务层级，把放错位置的任务重新归类，避免重复。"
                    }
                    AIPromptChip(title: "规划四象限", symbol: "square.grid.2x2") {
                        instruction = "请根据重要性和紧急性整理已有任务，把适合的任务放入对应四象限，并说明判断理由。"
                    }
                    AIPromptChip(title: "安排今天", symbol: "sun.max") {
                        instruction = "请挑出今天最值得推进且不过载的任务，安排到今天，并给出合理时间。"
                    }
                }
            }
            TextEditor(text: $instruction)
                .font(.body)
                .scrollContentBackground(.hidden)
                .quietInput(minHeight: 118)
            Button {
                requestProposal()
            } label: {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(notionPayload == nil ? "正在整理" : "正在读取 Notion")
                    }
                } else {
                    Label(notionPayload == nil ? "生成整理建议" : "生成导入预览", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || isTestingConnection || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AISectionTitle("变更预览", symbol: "list.bullet.rectangle")
                Spacer()
                if let proposal {
                    Text("\(proposal.operations.count) 项")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let proposal {
                Text(proposal.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))

                if proposal.operations.isEmpty {
                    ContentUnavailableView("没有需要修改", systemImage: "checkmark.circle", description: Text("当前计划已经很清楚。"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(proposal.operations) { operation in
                                OperationRow(operation: operation)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button("放弃") { self.proposal = nil }
                        Spacer()
                        Button {
                            applyProposal(proposal)
                        } label: {
                            Label("确认执行 \(proposal.operations.count) 项修改", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在把想法整理成可检查的修改")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "等待你的想法",
                    systemImage: notionPayload == nil ? "sparkles" : "doc.text.magnifyingglass",
                    description: Text("建议会逐项列出，确认后才会改变任务。")
                )
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch connectionState {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    private var currentConfiguration: AIConfiguration {
        AIConfiguration(
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            reasoningEffort: reasoningEffort,
            serviceTier: serviceTier,
            disableResponseStorage: disableResponseStorage
        )
    }

    private var providerHost: String {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "自定义服务商"
    }

    private var isCustomEndpoint: Bool {
        baseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))).lowercased()
            != AIConfiguration.officialBaseURL.lowercased()
    }

    private var notionContentTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }

    private func testConnection() {
        isTestingConnection = true
        connectionState = nil
        let configuration = currentConfiguration
        KeychainStore.saveAPIKey(apiKey, for: baseURL)
        Task {
            do {
                try await service.testConnection(configuration: configuration)
                connectionState = .success("连接成功")
            } catch {
                connectionState = .failure(error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    private func loadNotionFiles(_ result: Result<[URL], Error>) {
        do {
            notionPayload = try NotionImportService.load(urls: result.get())
            proposal = nil
            instruction = notionDestination == .currentProject
                ? "请把这些 Notion 任务整理后导入当前项目，保留层级、说明和合理的预计时长，合并明显重复的内容。"
                : "请识别这些 Notion 内容中的项目边界，创建相应项目和多层任务树，保留说明并合并明显重复的内容。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestProposal() {
        isLoading = true
        proposal = nil
        errorMessage = nil
        connectionState = nil
        KeychainStore.saveAPIKey(apiKey, for: baseURL)

        let configuration = currentConfiguration
        let projectID = contextScope == .currentProject ? store.selectedProjectID : nil
        let workspace = store.exportAIContext(projectID: projectID)
        let sourceMaterial = notionPayload?.sourceMaterial
        var prompt = instruction
        if notionPayload != nil {
            switch notionDestination {
            case .currentProject:
                guard let selectedProjectID = store.selectedProjectID else {
                    errorMessage = "请先选择一个项目，或改为创建新项目。"
                    isLoading = false
                    return
                }
                prompt += "\n导入目标是已有项目 \(selectedProjectID.uuidString)。不要创建新项目，所有计划任务都使用这个 projectID。"
            case .newProjects:
                prompt += "\n请按内容创建一个或多个新项目。每个 create_project 先声明 clientID，随后任务用 projectClientID 引用。"
            }
        }

        Task {
            do {
                let result = try await service.propose(
                    instruction: prompt,
                    workspaceJSON: workspace,
                    sourceMaterial: sourceMaterial,
                    configuration: configuration
                )
                try store.validate(result)
                proposal = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func applyProposal(_ proposal: AIProposal) {
        do {
            try store.apply(proposal)
            self.proposal = nil
            notionPayload = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AISectionTitle: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(SkyTheme.ink)
    }
}

private struct AIPromptChip: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct OperationRow: View {
    @EnvironmentObject private var store: TaskStore
    let operation: TaskOperation

    private var targetTitle: String? {
        guard let targetID = operation.targetID else { return nil }
        return store.data.projects.first(where: { $0.id == targetID })?.title
            ?? store.data.planTasks.first(where: { $0.id == targetID })?.title
            ?? store.data.todayTasks.first(where: { $0.id == targetID })?.title
            ?? store.data.routines.first(where: { $0.id == targetID })?.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: operation.kind.symbol)
                .foregroundStyle(operation.kind.isDestructive ? .red : SkyTheme.sea)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(operation.kind.displayName)
                        .font(.caption.weight(.bold))
                    if let quadrant = operation.quadrant {
                        Label(quadrant.title, systemImage: quadrant.symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(operation.title ?? targetTitle ?? operation.reason)
                    .font(.body.weight(.medium))
                if operation.title != nil || targetTitle != nil {
                    Text(operation.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(operation.kind.isDestructive ? Color.red : SkyTheme.sky)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private extension OperationKind {
    var isDestructive: Bool {
        self == .deleteProject || self == .deletePlanTask || self == .deleteTodayTask
    }

    var symbol: String {
        switch self {
        case .createProject: return "folder.badge.plus"
        case .updateProject: return "folder"
        case .deleteProject: return "trash"
        case .createPlanTask: return "plus.circle"
        case .updatePlanTask: return "pencil"
        case .reparentPlanTask: return "arrow.triangle.branch"
        case .setTaskQuadrant: return "square.grid.2x2"
        case .deletePlanTask: return "trash"
        case .scheduleToday: return "sun.max"
        case .createTodayTask: return "plus.circle"
        case .updateTodayTask: return "clock"
        case .completeTodayTask: return "checkmark.circle"
        case .deleteTodayTask: return "trash"
        case .createRoutine: return "infinity.circle"
        case .updateRoutine: return "infinity"
        }
    }

    var displayName: String {
        switch self {
        case .createProject: return "新建项目"
        case .updateProject: return "修改项目"
        case .deleteProject: return "删除项目"
        case .createPlanTask: return "新建计划任务"
        case .updatePlanTask: return "修改计划任务"
        case .reparentPlanTask: return "调整任务层级"
        case .setTaskQuadrant: return "设置任务象限"
        case .deletePlanTask: return "删除计划任务"
        case .scheduleToday: return "安排到今天"
        case .createTodayTask: return "新建今日任务"
        case .updateTodayTask: return "调整今日任务"
        case .completeTodayTask: return "完成今日任务"
        case .deleteTodayTask: return "移除今日任务"
        case .createRoutine: return "新建长期任务"
        case .updateRoutine: return "修改长期任务"
        }
    }
}
