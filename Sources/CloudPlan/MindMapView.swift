import AppKit
import SwiftUI

struct MindMapView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.undoManager) private var undoManager
    let onSchedule: (PlanTask) -> Void
    let onToggleCompletion: (PlanTask) -> Void
    let onEdit: (PlanTask) -> Void
    let onAddChild: (PlanTask) -> Void
    let onDelete: (PlanTask) -> Void

    @State private var dragPositions: [UUID: CGPoint] = [:]
    @State private var dragOriginPositions: [UUID: CGPoint] = [:]
    @State private var draggedTaskID: UUID?
    @State private var draggedBranchIDs = Set<UUID>()
    @State private var hoverParentID: UUID?
    @State private var hoverRoot = false
    @State private var expandedTaskIDs = Set<UUID>()
    @State private var canvasScrollView: NSScrollView?
    @State private var linkModeEnabled = false
    @State private var linkSourceID: UUID?

    private let nodeWidth: CGFloat = 210

    var body: some View {
        GeometryReader { geometry in
            let allTasks = store.selectedPlanTasks
            let visibleTasks = MindMapVisibility.visibleTasks(in: allTasks, expandedTaskIDs: expandedTaskIDs)
            let visibleTaskIDs = Set(visibleTasks.map(\.id))
            let layout = MindMapLayout(tasks: allTasks)
            let restingPositions = persistedPositions(layout: layout)
            let positions = effectivePositions(layout: layout)
            let visiblePositions = positions.filter { visibleTaskIDs.contains($0.key) }
            let canvasSize = requiredCanvasSize(positions: visiblePositions)
            let projectPosition = projectPosition(for: restingPositions, viewportHeight: geometry.size.height)
            let links = store.selectedMapLinks.filter {
                visibleTaskIDs.contains($0.fromTaskID) && visibleTaskIDs.contains($0.toTaskID)
            }

            ZStack(alignment: .topTrailing) {
                ScrollViewReader { scrollProxy in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                        MapConnections(
                            tasks: visibleTasks,
                            positions: positions,
                            projectPosition: projectPosition,
                            nodeWidth: nodeWidth,
                            draggedTaskID: draggedTaskID,
                            previewParentID: hoverParentID,
                            previewRoot: hoverRoot
                        )
                        .frame(width: canvasSize.width, height: canvasSize.height)

                        MapLinkLayer(
                            links: links,
                            positions: positions,
                            nodeWidth: nodeWidth,
                            titles: titlesByID,
                            emphasizedTaskID: linkSourceID,
                            onRemove: { link in
                                store.removeMapLink(link.id, undoManager: undoManager)
                            }
                        )
                        .frame(width: canvasSize.width, height: canvasSize.height)

                        ProjectMapNode(project: store.selectedProject, isDropTarget: hoverRoot)
                            .position(projectPosition)

                        ForEach(visibleTasks) { task in
                            if let position = positions[task.id] {
                                let childCount = allTasks.filter { $0.parentID == task.id }.count
                                let linkedTasks = store.linkedTasks(of: task.id)
                                MapTaskNode(
                                    task: task,
                                    childCount: childCount,
                                    isExpanded: expandedTaskIDs.contains(task.id),
                                    isScheduled: store.data.todayTasks.contains { $0.sourceID == task.id },
                                    isDropTarget: hoverParentID == task.id,
                                    isDragging: draggedTaskID == task.id,
                                    isInDraggedBranch: draggedBranchIDs.contains(task.id),
                                    linkCount: linkedTasks.count,
                                    linkedTasks: linkedTasks,
                                    isLinkMode: linkModeEnabled,
                                    isLinkSource: linkSourceID == task.id,
                                    onSchedule: { onSchedule(task) },
                                    onToggleCompletion: { onToggleCompletion(task) },
                                    onEdit: { onEdit(task) },
                                    onAddChild: { onAddChild(task) },
                                    onToggleChildren: {
                                        toggleChildren(of: task.id, positions: positions, scrollProxy: scrollProxy)
                                    },
                                    onMoveToRoot: {
                                        try? store.reparentPlanTask(task.id, to: nil, undoManager: undoManager)
                                    },
                                    onDelete: { onDelete(task) },
                                    onLinkTap: { handleLinkTap(task.id) },
                                    onStartLink: {
                                        linkModeEnabled = true
                                        linkSourceID = task.id
                                    },
                                    onRemoveLink: { otherID in
                                        store.removeMapLink(between: task.id, and: otherID, undoManager: undoManager)
                                    },
                                    onDragChanged: { translation in
                                        updateDrag(taskID: task.id, translation: translation, layout: layout, projectPosition: projectPosition)
                                    },
                                    onDragEnded: {
                                        finishDrag(taskID: task.id)
                                    }
                                )
                                .frame(width: nodeWidth)
                                .position(position)
                                .id(task.id)
                                .zIndex(draggedBranchIDs.contains(task.id) ? 10 : 0)
                                .transition(.scale(scale: 0.82, anchor: .leading).combined(with: .opacity))
                                .animation(.snappy(duration: 0.18), value: hoverParentID)
                            }
                        }

                        if store.selectedPlanTasks.isEmpty {
                            VStack(spacing: 7) {
                                Image(systemName: "arrow.left")
                                Text("从下方添加第一步，它会从项目中心生长出来。")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .position(x: 360, y: projectPosition.y)
                        }
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .coordinateSpace(name: "mindMap")
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: visibleTaskIDs)
                        .background {
                            ScrollViewAccessor { scrollView in
                                if canvasScrollView !== scrollView {
                                    canvasScrollView = scrollView
                                }
                            }
                            .frame(width: 0, height: 0)
                        }
                    }
                    .background {
                        DotGrid()
                            .opacity(0.35)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    if let hoverParentID,
                       let parent = store.selectedPlanTasks.first(where: { $0.id == hoverParentID }) {
                        Label("接到“\(parent.title)”下", systemImage: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SkyTheme.sea)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    } else if hoverRoot {
                        Label("松开后移到项目顶层", systemImage: "arrow.up.to.line")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SkyTheme.sea)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    }

                    if linkModeEnabled {
                        HStack(spacing: 8) {
                            Label(linkHintText, systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SkyTheme.sea)
                            if linkSourceID != nil {
                                Button("取消") { linkSourceID = nil }
                                    .buttonStyle(.borderless)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                    }

                    Button {
                        toggleLinkMode()
                    } label: {
                        Label(linkModeEnabled ? "结束连线" : "连任务", systemImage: linkModeEnabled ? "link.circle.fill" : "link")
                    }
                    .buttonStyle(.bordered)
                    .tint(linkModeEnabled ? SkyTheme.sea : nil)
                    .help(linkModeEnabled ? "结束自由连线" : "按住顺序点两个任务，给它们连一条线")

                    Button {
                        store.setMapPositions(layout.automaticPositions, undoManager: undoManager)
                    } label: {
                        Label("自动整理", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .help("按任务层级重新排版")
                }
                .padding(12)
            }
        }
        .onChange(of: store.selectedProjectID) { _, _ in
            expandedTaskIDs.removeAll()
            linkSourceID = nil
            resetDrag()
        }
    }

    private var titlesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: store.selectedPlanTasks.map { ($0.id, $0.title) })
    }

    private var linkHintText: String {
        guard let linkSourceID,
              let title = titlesByID[linkSourceID] else {
            return "依次点两个任务，画一条自由连接线"
        }
        return "再点一个任务，和「\(title)」连起来"
    }

    private func toggleLinkMode() {
        linkModeEnabled.toggle()
        linkSourceID = nil
        resetDrag()
    }

    private func handleLinkTap(_ taskID: UUID) {
        guard let source = linkSourceID else {
            linkSourceID = taskID
            return
        }
        guard source != taskID else {
            linkSourceID = nil
            return
        }
        do {
            try store.addMapLink(from: source, to: taskID, undoManager: undoManager)
        } catch {
            store.lastError = "无法连接任务：\(error.localizedDescription)"
        }
        linkSourceID = nil
    }

    private func toggleChildren(
        of taskID: UUID,
        positions: [UUID: CGPoint],
        scrollProxy: ScrollViewProxy
    ) {
        let children = store.selectedPlanTasks.filter { $0.parentID == taskID }
        guard !children.isEmpty else { return }
        let isExpanding = !expandedTaskIDs.contains(taskID)
        resetDrag()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            if isExpanding {
                expandedTaskIDs.insert(taskID)
            } else {
                expandedTaskIDs.remove(taskID)
            }
        }
        let targetID = isExpanding ? children[0].id : taskID
        for delay in [0.08, 0.32] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                scrollTaskIntoView(targetID, positions: positions, fallback: scrollProxy)
            }
        }
    }

    private func scrollTaskIntoView(
        _ taskID: UUID,
        positions: [UUID: CGPoint],
        fallback scrollProxy: ScrollViewProxy
    ) {
        guard let position = positions[taskID],
              let scrollView = canvasScrollView,
              let documentView = scrollView.documentView else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                scrollProxy.scrollTo(taskID, anchor: .center)
            }
            return
        }

        let viewport = scrollView.contentView.bounds.size
        let documentSize = documentView.bounds.size
        let maxX = max(0, documentSize.width - viewport.width)
        let maxY = max(0, documentSize.height - viewport.height)
        let targetY = documentView.isFlipped ? position.y : documentSize.height - position.y
        let targetViewportY = min(
            max(viewport.height / 2, 86),
            max(40, viewport.height - 40)
        )
        let destination = CGPoint(
            x: min(max(0, position.x + nodeWidth / 2 + 24 - viewport.width), maxX),
            y: min(max(0, targetY - targetViewportY), maxY)
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.allowsImplicitAnimation = true
            scrollView.contentView.animator().setBoundsOrigin(destination)
        } completionHandler: {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func persistedPositions(layout: MindMapLayout) -> [UUID: CGPoint] {
        var result = layout.automaticPositions
        for task in store.selectedPlanTasks {
            if let x = task.mapX, let y = task.mapY {
                result[task.id] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    private func effectivePositions(layout: MindMapLayout) -> [UUID: CGPoint] {
        var result = persistedPositions(layout: layout)
        for (id, point) in dragPositions { result[id] = point }
        return result
    }

    private func projectPosition(for positions: [UUID: CGPoint], viewportHeight: CGFloat) -> CGPoint {
        let roots = store.selectedPlanTasks.filter { $0.parentID == nil }.compactMap { positions[$0.id]?.y }
        let idealY = roots.isEmpty ? 120 : roots.reduce(0, +) / CGFloat(roots.count)
        let visibleCenter = max(62, viewportHeight / 2)
        return CGPoint(x: 125, y: min(idealY, visibleCenter))
    }

    private func requiredCanvasSize(positions: [UUID: CGPoint]) -> CGSize {
        let maxX = positions.values.map(\.x).max() ?? 400
        let maxY = positions.values.map(\.y).max() ?? 260
        return CGSize(width: max(900, maxX + 400), height: max(560, maxY + 170))
    }

    private func updateDrag(taskID: UUID, translation: CGSize, layout: MindMapLayout, projectPosition: CGPoint) {
        let basePositions = persistedPositions(layout: layout)
        let visibleIDs = Set(MindMapVisibility.visibleTasks(in: store.selectedPlanTasks, expandedTaskIDs: expandedTaskIDs).map(\.id))
        let interactionPositions = basePositions.filter { visibleIDs.contains($0.key) }
        if draggedTaskID != taskID {
            resetDrag()
            draggedTaskID = taskID
            draggedBranchIDs = branchIDs(rootID: taskID)
            dragOriginPositions = basePositions.filter { draggedBranchIDs.contains($0.key) }
        }
        guard let start = dragOriginPositions[taskID] else { return }
        let raw = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let point = snapped(raw, excluding: draggedBranchIDs, positions: interactionPositions)
        let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
        for id in draggedBranchIDs {
            guard let origin = dragOriginPositions[id] else { continue }
            dragPositions[id] = CGPoint(x: origin.x + delta.width, y: origin.y + delta.height)
        }

        hoverParentID = nearestValidParent(to: point, taskID: taskID, excluding: draggedBranchIDs, positions: interactionPositions)
        hoverRoot = hoverParentID == nil && distance(point, projectPosition) < 175
    }

    private func finishDrag(taskID: UUID) {
        guard dragPositions[taskID] != nil else {
            resetDrag(taskID)
            return
        }
        let branchPositions = dragPositions.filter { draggedBranchIDs.contains($0.key) }
        do {
            if let hoverParentID {
                try store.movePlanTaskBranch(
                    taskID,
                    to: hoverParentID,
                    positions: branchPositions,
                    undoManager: undoManager
                )
            } else if hoverRoot {
                try store.movePlanTaskBranch(
                    taskID,
                    to: nil,
                    positions: branchPositions,
                    undoManager: undoManager
                )
            } else {
                store.setMapPositions(branchPositions, undoManager: undoManager)
            }
        } catch {
            store.lastError = "无法移动任务：\(error.localizedDescription)"
        }
        resetDrag(taskID)
    }

    private func resetDrag(_ taskID: UUID? = nil) {
        dragPositions.removeAll()
        dragOriginPositions.removeAll()
        draggedTaskID = nil
        draggedBranchIDs.removeAll()
        hoverParentID = nil
        hoverRoot = false
    }

    private func snapped(_ raw: CGPoint, excluding excludedIDs: Set<UUID>, positions: [UUID: CGPoint]) -> CGPoint {
        var point = CGPoint(x: (raw.x / 20).rounded() * 20, y: (raw.y / 20).rounded() * 20)
        for (otherID, other) in positions where !excludedIDs.contains(otherID) {
            if abs(point.x - other.x) < 14 { point.x = other.x }
            if abs(point.y - other.y) < 14 { point.y = other.y }
        }
        point.x = max(100, point.x)
        point.y = max(80, point.y)
        return point
    }

    private func nearestValidParent(to point: CGPoint, taskID: UUID, excluding excludedIDs: Set<UUID>, positions: [UUID: CGPoint]) -> UUID? {
        positions
            .filter {
                !excludedIDs.contains($0.key)
                    && abs(point.x - $0.value.x) < nodeWidth * 0.75
                    && abs(point.y - $0.value.y) < 70
                    && store.canReparentPlanTask(taskID, to: $0.key)
            }
            .min { distance(point, $0.value) < distance(point, $1.value) }?
            .key
    }

    private func branchIDs(rootID: UUID) -> Set<UUID> {
        var result = Set([rootID])
        var frontier = [rootID]
        while let parentID = frontier.popLast() {
            for task in store.selectedPlanTasks where task.parentID == parentID && result.insert(task.id).inserted {
                frontier.append(task.id)
            }
        }
        return result
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private struct ScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        resolve(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolve(from: nsView)
    }

    private func resolve(from view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let scrollView = view?.enclosingScrollView else { return }
            onResolve(scrollView)
        }
    }
}

struct MindMapVisibility {
    static func visibleTasks(in tasks: [PlanTask], expandedTaskIDs: Set<UUID>) -> [PlanTask] {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        return tasks.filter { task in
            var ancestorID = task.parentID
            var visited = Set<UUID>()
            while let currentID = ancestorID {
                guard visited.insert(currentID).inserted else { return false }
                guard let ancestor = byID[currentID] else { return true }
                guard expandedTaskIDs.contains(currentID) else { return false }
                ancestorID = ancestor.parentID
            }
            return true
        }
    }
}

struct MindMapLayout {
    let automaticPositions: [UUID: CGPoint]

    init(tasks: [PlanTask]) {
        let sorted = tasks.sorted { lhs, rhs in
            lhs.order == rhs.order ? lhs.title < rhs.title : lhs.order < rhs.order
        }
        let children = Dictionary(grouping: sorted, by: \.parentID)
        var positions: [UUID: CGPoint] = [:]
        var visited = Set<UUID>()
        // Keep the first row below the floating map controls.
        var nextY: CGFloat = 105

        @discardableResult
        func place(_ task: PlanTask, depth: Int) -> CGFloat {
            guard visited.insert(task.id).inserted else { return nextY }
            let childTasks = children[task.id] ?? []
            let y: CGFloat
            if childTasks.isEmpty {
                y = nextY
                nextY += 150
            } else {
                let childYs = childTasks.map { place($0, depth: depth + 1) }
                y = (childYs.first! + childYs.last!) / 2
            }
            positions[task.id] = CGPoint(x: 390 + CGFloat(depth) * 245, y: y)
            return y
        }

        for root in children[nil] ?? [] { place(root, depth: 0) }
        for orphan in sorted where !visited.contains(orphan.id) { place(orphan, depth: 0) }
        automaticPositions = positions
    }
}

private struct MapConnections: View {
    let tasks: [PlanTask]
    let positions: [UUID: CGPoint]
    let projectPosition: CGPoint
    let nodeWidth: CGFloat
    let draggedTaskID: UUID?
    let previewParentID: UUID?
    let previewRoot: Bool

    var body: some View {
        Canvas { context, _ in
            for task in tasks {
                guard let child = positions[task.id] else { continue }
                let parent: CGPoint
                if task.id == draggedTaskID, previewRoot {
                    parent = projectPosition
                } else if task.id == draggedTaskID, let previewParentID, let preview = positions[previewParentID] {
                    parent = preview
                } else {
                    parent = task.parentID.flatMap { positions[$0] } ?? projectPosition
                }
                var path = Path()
                path.move(to: CGPoint(x: parent.x + nodeWidth / 2 - 8, y: parent.y))
                let end = CGPoint(x: child.x - nodeWidth / 2 + 8, y: child.y)
                let middle = (parent.x + end.x) / 2
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: middle, y: parent.y),
                    control2: CGPoint(x: middle, y: child.y)
                )
                let isPreview = task.id == draggedTaskID && (previewRoot || previewParentID != nil)
                context.stroke(
                    path,
                    with: .color(SkyTheme.sea.opacity(isPreview ? 0.90 : 0.42)),
                    style: StrokeStyle(lineWidth: isPreview ? 3 : 2, lineCap: .round, dash: isPreview ? [7, 5] : [])
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 自由连接线的几何：端点贴在两个节点的边缘，曲线从中间穿过。
enum MapLinkGeometry {
    static let nodeHeight: CGFloat = 74

    static func anchors(
        from start: CGPoint,
        to end: CGPoint,
        nodeWidth: CGFloat,
        nodeHeight: CGFloat = MapLinkGeometry.nodeHeight
    ) -> (start: CGPoint, end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) >= abs(dy) {
            let direction: CGFloat = dx >= 0 ? 1 : -1
            return (
                CGPoint(x: start.x + direction * nodeWidth / 2, y: start.y),
                CGPoint(x: end.x - direction * nodeWidth / 2, y: end.y)
            )
        }
        let direction: CGFloat = dy >= 0 ? 1 : -1
        return (
            CGPoint(x: start.x, y: start.y + direction * nodeHeight / 2),
            CGPoint(x: end.x, y: end.y - direction * nodeHeight / 2)
        )
    }

    static func path(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) >= abs(dy) {
            let middle = (start.x + end.x) / 2
            path.addCurve(
                to: end,
                control1: CGPoint(x: middle, y: start.y),
                control2: CGPoint(x: middle, y: end.y)
            )
        } else {
            let middle = (start.y + end.y) / 2
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x, y: middle),
                control2: CGPoint(x: end.x, y: middle)
            )
        }
        return path
    }

    /// 曲线中点，用来放断开标记。
    static func midpoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) >= abs(dy) {
            let middle = (start.x + end.x) / 2
            return cubicPoint(
                start,
                CGPoint(x: middle, y: start.y),
                CGPoint(x: middle, y: end.y),
                end
            )
        }
        let middle = (start.y + end.y) / 2
        return cubicPoint(
            start,
            CGPoint(x: start.x, y: middle),
            CGPoint(x: end.x, y: middle),
            end
        )
    }

    private static func cubicPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let t: CGFloat = 0.5
        let inverse = 1 - t
        let first = inverse * inverse * inverse
        let second = 3 * inverse * inverse * t
        let third = 3 * inverse * t * t
        let fourth = t * t * t
        return CGPoint(
            x: first * p0.x + second * p1.x + third * p2.x + fourth * p3.x,
            y: first * p0.y + second * p1.y + third * p2.y + fourth * p3.y
        )
    }
}

private struct MapLinkLayer: View {
    let links: [MapLink]
    let positions: [UUID: CGPoint]
    let nodeWidth: CGFloat
    let titles: [UUID: String]
    let emphasizedTaskID: UUID?
    let onRemove: (MapLink) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(links) { link in
                if let from = positions[link.fromTaskID], let to = positions[link.toTaskID] {
                    let anchors = MapLinkGeometry.anchors(from: from, to: to, nodeWidth: nodeWidth)
                    MapLinkCurve(
                        start: anchors.start,
                        end: anchors.end,
                        isEmphasized: emphasizedTaskID.map { link.touches($0) } ?? false,
                        label: "连接线：\(titles[link.fromTaskID] ?? "任务") 与 \(titles[link.toTaskID] ?? "任务")",
                        onRemove: { onRemove(link) }
                    )
                }
            }
        }
    }
}

private struct MapLinkCurve: View {
    let start: CGPoint
    let end: CGPoint
    let isEmphasized: Bool
    let label: String
    let onRemove: () -> Void
    @State private var isHovered = false

    private var path: Path { MapLinkGeometry.path(from: start, to: end) }
    private var isActive: Bool { isHovered || isEmphasized }

    var body: some View {
        ZStack {
            path
                .stroke(
                    isActive ? SkyTheme.sea : SkyTheme.sky,
                    style: StrokeStyle(lineWidth: isActive ? 2.6 : 2, lineCap: .round, dash: isActive ? [7, 4] : [6, 5])
                )
            if isHovered {
                Image(systemName: "scissors")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(SkyTheme.sea, in: Circle())
                    .position(MapLinkGeometry.midpoint(from: start, to: end))
            }
        }
        .opacity(isEmphasized ? 1 : 0.86)
        .contentShape(path.strokedPath(StrokeStyle(lineWidth: 18, lineCap: .round)))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture(perform: onRemove)
        .help("点击断开这条连接线")
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityHint("点按断开连接")
    }
}

private struct ProjectMapNode: View {
    let project: Project?
    let isDropTarget: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: project?.symbol ?? "cloud.fill")
                .font(.title2)
            Text(project?.title ?? "项目")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 190)
        .frame(minHeight: 82)
        .background(SkyTheme.sea, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTarget ? Color.white : Color.clear, lineWidth: 3)
                .shadow(color: isDropTarget ? SkyTheme.sea.opacity(0.7) : .clear, radius: 8)
        }
        .shadow(color: SkyTheme.sea.opacity(0.2), radius: 10, y: 5)
        .accessibilityLabel("项目中心：\(project?.title ?? "项目")")
    }
}

private struct MapTaskNode: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusSessionController
    @Environment(\.colorScheme) private var colorScheme
    let task: PlanTask
    let childCount: Int
    let isExpanded: Bool
    let isScheduled: Bool
    let isDropTarget: Bool
    let isDragging: Bool
    let isInDraggedBranch: Bool
    let linkCount: Int
    let linkedTasks: [PlanTask]
    let isLinkMode: Bool
    let isLinkSource: Bool
    let onSchedule: () -> Void
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void
    let onAddChild: () -> Void
    let onToggleChildren: () -> Void
    let onMoveToRoot: () -> Void
    let onDelete: () -> Void
    let onLinkTap: () -> Void
    let onStartLink: () -> Void
    let onRemoveLink: (UUID) -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void
    @State private var isHovered = false
    @State private var showQuickNoteEditor = false

    private var quadrant: TaskQuadrant? {
        store.placement(for: task.id)?.quadrant
    }

    private var activeSession: FocusSession? { focus.session(for: task.id) }
    private var isActive: Bool { activeSession != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            nodeHeader
            if !task.note.isEmpty {
                TaskQuickNoteText(note: task.note)
            }
            nodeFooter
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .background(nodeHighlight, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(borderColor, lineWidth: isDropTarget || isDragging || isActive || isLinkSource ? 2 : 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(linkAccent)
                .frame(height: 2)
                .padding(.horizontal, 8)
        }
        .shadow(
            color: shadowColor,
            radius: isDropTarget || isInDraggedBranch ? 12 : 5,
            y: 3
        )
        .scaleEffect(isDragging ? 1.025 : 1)
        .opacity(task.isCompleted && !isActive ? 0.52 : 1)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("mindMap"))
                .onChanged { onDragChanged($0.translation) }
                .onEnded { _ in onDragEnded() }
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture(count: 2) {
            guard !isLinkMode else { return }
            onEdit()
        }
        .onTapGesture {
            guard isLinkMode else { return }
            onLinkTap()
        }
        .contextMenu {
            TaskQuickNoteMenu(
                note: task.note,
                onEdit: { showQuickNoteEditor = true },
                onDelete: { store.setPlanTaskQuickNote(taskID: task.id, note: "") }
            )
            Divider()
            Button(task.isCompleted ? "标记为未完成" : "标记完成", action: onToggleCompletion)
            Divider()
            Button("添加子任务…", action: onAddChild)
            Button("放到今天", action: onSchedule).disabled(isScheduled)
            Button("移到项目顶层", action: onMoveToRoot).disabled(task.parentID == nil)
            Button("编辑…", action: onEdit)
            Divider()
            Button("从这里连到别的任务…", action: onStartLink)
            if !linkedTasks.isEmpty {
                Menu("断开连接（\(linkedTasks.count)）") {
                    ForEach(linkedTasks) { other in
                        Button("与「\(other.title)」断开", role: .destructive) {
                            onRemoveLink(other.id)
                        }
                    }
                }
            }
            Divider()
            Button("删除任务树", role: .destructive, action: onDelete)
        }
        .sheet(isPresented: $showQuickNoteEditor) {
            TaskQuickNoteEditor(taskTitle: task.title, note: task.note) {
                store.setPlanTaskQuickNote(taskID: task.id, note: $0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("思维导图任务：\(task.title)，\(childCount) 个子任务\(childCount > 0 ? isExpanded ? "，已展开" : "，已收起" : "")\(linkCount > 0 ? "，\(linkCount) 条连接线" : "")\(isLinkSource ? "，已选为连线起点" : "")")
    }

    private var nodeHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? SkyTheme.sea : isActive ? SkyTheme.ink : .secondary)
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "标记为未完成" : "标记完成")
            if childCount > 0 {
                Button(action: onToggleChildren) {
                    HStack(spacing: 5) {
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(task.isCompleted)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "收起子任务" : "展开 \(childCount) 个子任务")
            } else {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .lineLimit(3)
            }
            Spacer(minLength: 2)
            if isLinkSource {
                Label("起点", systemImage: "link.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SkyTheme.sea)
            } else if linkCount > 0 {
                Label("\(linkCount)", systemImage: "link")
                    .font(.caption2)
                    .foregroundStyle(SkyTheme.sea.opacity(0.9))
                    .help("与 \(linkCount) 个任务有连接线")
            }
            Image(systemName: isDragging ? "hand.raised.fill" : "cursorarrow.motionlines")
                .font(.caption)
                .foregroundStyle(isDragging ? SkyTheme.sea : Color.secondary.opacity(0.75))
                .opacity(isHovered || isDragging ? 1 : 0.55)
        }
    }

    private var nodeFooter: some View {
        HStack(spacing: 9) {
            Label("\(task.durationMinutes)分", systemImage: "clock")
            if childCount > 0 { Label("\(childCount)", systemImage: "square.stack.3d.up") }
            if isScheduled { Label("今天", systemImage: "sun.max.fill") }
            if let quadrant {
                Label("短期", systemImage: "square.grid.2x2.fill")
                    .help("四象限：\(quadrant.title)")
            }
            if let activeSession {
                Label(activeSession.state.title, systemImage: activeSession.state.symbol)
            }
            Spacer(minLength: 2)
            if childCount > 0 {
                QuietIconButton(
                    symbol: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle",
                    helpText: isExpanded ? "收起子任务" : "展开 \(childCount) 个子任务",
                    isActive: isExpanded,
                    action: onToggleChildren
                )
            }
            QuietIconButton(symbol: "arrow.turn.down.right", helpText: "添加子任务", action: onAddChild)
            QuietIconButton(
                symbol: isScheduled ? "checkmark" : "sun.max",
                helpText: isScheduled ? "已在今天" : "放到今天",
                isActive: isScheduled,
                isDisabled: isScheduled,
                action: onSchedule
            )
        }
        .font(.caption2)
        .foregroundStyle(isActive ? SkyTheme.ink : quadrant != nil ? Color(red: 0.55, green: 0.38, blue: 0.02) : isScheduled ? SkyTheme.sea : .secondary)
    }

    private var borderColor: Color {
        if isDropTarget { return SkyTheme.sea }
        if isLinkSource { return SkyTheme.sea }
        if isDragging { return SkyTheme.sky }
        if isActive { return SkyTheme.focusYellow }
        if isLinkMode { return SkyTheme.sky.opacity(0.8) }
        if quadrant != nil { return Color(red: 0.78, green: 0.58, blue: 0.08).opacity(0.72) }
        if isScheduled { return SkyTheme.sky.opacity(0.55) }
        return Color.primary.opacity(0.11)
    }

    private var linkAccent: Color {
        if isDropTarget || isLinkSource { return SkyTheme.sea }
        if isDragging || isLinkMode { return SkyTheme.sky }
        if isActive { return SkyTheme.focusYellow }
        return SkyTheme.sky.opacity(0.55)
    }

    private var shadowColor: Color {
        isDropTarget || isInDraggedBranch ? SkyTheme.sea.opacity(0.22) : Color.black.opacity(0.055)
    }

    private var nodeHighlight: Color {
        if isActive { return SkyTheme.focusYellow.opacity(colorScheme == .dark ? 0.30 : 0.62) }
        if task.isCompleted { return SkyTheme.completedWash.opacity(colorScheme == .dark ? 0.12 : 0.24) }
        if quadrant != nil { return SkyTheme.scheduleYellow.opacity(colorScheme == .dark ? 0.18 : 0.42) }
        return .clear
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let color = Color.secondary.opacity(0.22)
            for x in stride(from: 10.0, through: size.width, by: 20.0) {
                for y in stride(from: 10.0, through: size.height, by: 20.0) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
