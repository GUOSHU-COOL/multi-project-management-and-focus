import Foundation
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var data: WorkspaceData
    @Published var selectedProjectID: UUID?
    @Published var selectedSection: SidebarSection = .projects
    @Published var lastError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private weak var registeredUndoManager: UndoManager?

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudPlan", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("workspace.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        var shouldPersistMigration = false
        if let saved = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode(WorkspaceData.self, from: saved) {
            var migrated = decoded
            if migrated.schemaVersion < 2 {
                migrated.schemaVersion = 2
                shouldPersistMigration = true
            }
            if migrated.schemaVersion < 3 {
                migrated.quadrantPlacements = []
                migrated.schemaVersion = 3
                shouldPersistMigration = true
            }
            if migrated.schemaVersion < 4 {
                migrated.quadrantOtherTaskIDs = []
                migrated.schemaVersion = 4
                shouldPersistMigration = true
            }
            if migrated.schemaVersion < 5 {
                migrated.schemaVersion = 5
                shouldPersistMigration = true
            }
            if migrated.schemaVersion < 6 {
                // 第六版之前没有导图连接线，迁移后从空连接开始。
                migrated.mapLinks = []
                migrated.schemaVersion = 6
                shouldPersistMigration = true
            }
            Self.sanitizeQuadrantPlacements(in: &migrated)
            Self.sanitizeMapLinks(in: &migrated)
            data = migrated
        } else {
            data = WorkspaceData(projects: [], planTasks: [], todayTasks: [], routines: [], schemaVersion: 6)
        }
        selectedProjectID = data.projects.first?.id
        if shouldPersistMigration { persist() }
    }

    var selectedProject: Project? {
        data.projects.first { $0.id == selectedProjectID }
    }

    var selectedPlanTasks: [PlanTask] {
        data.planTasks
            .filter { $0.projectID == selectedProjectID }
            .sorted { $0.order < $1.order }
    }

    var orderedTodayTasks: [TodayTask] {
        data.todayTasks.filter { !isExpiredCompleted($0) }.sorted { $0.order < $1.order }
    }

    var completedCount: Int { orderedTodayTasks.filter(\.isCompleted).count }

    private func isExpiredCompleted(_ task: TodayTask) -> Bool {
        task.isCompleted && task.completedAt.map { Date().timeIntervalSince($0) >= 15 * 60 } == true
    }

    func purgeExpiredCompletedTodayTasks() {
        let expired = data.todayTasks.filter(isExpiredCompleted).map(\.id)
        guard !expired.isEmpty else { return }
        mutate { data in
            data.todayTasks.removeAll { expired.contains($0.id) }
            for index in data.todayTasks.indices { data.todayTasks[index].order = index }
        }
    }

    /// 当前项目里两端都还存在的导图连接线。
    var selectedMapLinks: [MapLink] {
        let taskIDs = Set(selectedPlanTasks.map(\.id))
        return data.mapLinks.filter { taskIDs.contains($0.fromTaskID) && taskIDs.contains($0.toTaskID) }
    }

    /// 与某个任务直接相连、并且仍在同一个项目里的任务。
    func linkedTasks(of taskID: UUID) -> [PlanTask] {
        let partners = Set(
            data.mapLinks
                .filter { $0.touches(taskID) }
                .map { $0.fromTaskID == taskID ? $0.toTaskID : $0.fromTaskID }
        )
        return data.planTasks
            .filter { partners.contains($0.id) }
            .sorted { $0.title < $1.title }
    }

    func linkCount(for taskID: UUID) -> Int {
        data.mapLinks.filter { $0.touches(taskID) }.count
    }

    func placement(for taskID: UUID) -> QuadrantPlacement? {
        data.quadrantPlacements.first { $0.taskID == taskID }
    }

    func tasks(in quadrant: TaskQuadrant) -> [PlanTask] {
        let byID = Dictionary(uniqueKeysWithValues: data.planTasks.map { ($0.id, $0) })
        return data.quadrantPlacements
            .filter { $0.quadrant == quadrant }
            .sorted { $0.order < $1.order }
            .compactMap { byID[$0.taskID] }
    }

    var quadrantOtherTasks: [PlanTask] {
        let byID = Dictionary(uniqueKeysWithValues: data.planTasks.map { ($0.id, $0) })
        return data.quadrantOtherTaskIDs.compactMap { byID[$0] }
    }

    func isInQuadrantOther(_ taskID: UUID) -> Bool {
        data.quadrantOtherTaskIDs.contains(taskID)
    }

    func addProject(title: String, detail: String = "", symbol: String = "cloud.fill") {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let project = Project(id: UUID(), title: cleaned, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol)
        mutate {
            $0.projects.append(project)
            selectedProjectID = project.id
            selectedSection = .projects
        }
    }

    func updateProject(_ project: Project) {
        let cleaned = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        mutate { data in
            guard let index = data.projects.firstIndex(where: { $0.id == project.id }) else { return }
            var updated = project
            updated.title = cleaned
            updated.detail = updated.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            data.projects[index] = updated
        }
    }

    func deleteProject(_ id: UUID) {
        mutate { data in
            let taskIDs = Set(data.planTasks.filter { $0.projectID == id }.map(\.id))
            data.projects.removeAll { $0.id == id }
            data.planTasks.removeAll { $0.projectID == id }
            data.quadrantPlacements.removeAll { taskIDs.contains($0.taskID) }
            data.quadrantOtherTaskIDs.removeAll { taskIDs.contains($0) }
            data.mapLinks.removeAll { taskIDs.contains($0.fromTaskID) || taskIDs.contains($0.toTaskID) }
            data.todayTasks.removeAll { item in
                guard let sourceID = item.sourceID else { return false }
                return taskIDs.contains(sourceID)
            }
            if selectedProjectID == id {
                selectedProjectID = data.projects.first?.id
            }
        }
    }

    @discardableResult
    func addPlanTask(
        title: String,
        projectID requestedProjectID: UUID? = nil,
        parentID: UUID? = nil,
        note: String = "",
        goal: String = "",
        durationMinutes: Int = 30,
        expectedDate: Date? = nil
    ) -> UUID? {
        guard let projectID = requestedProjectID ?? selectedProjectID,
              data.projects.contains(where: { $0.id == projectID }) else { return nil }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let parentID, !data.planTasks.contains(where: { $0.id == parentID && $0.projectID == projectID }) { return nil }
        let order = data.planTasks.filter { $0.projectID == projectID && $0.parentID == parentID }.count
        let task = PlanTask(id: UUID(), projectID: projectID, parentID: parentID, title: cleaned, note: note, goal: goal, expectedDate: expectedDate, durationMinutes: max(5, min(720, durationMinutes)), isCompleted: false, order: order)
        mutate { $0.planTasks.append(task) }
        return task.id
    }

    func updatePlanTask(_ task: PlanTask) {
        mutate { data in
            guard let index = data.planTasks.firstIndex(where: { $0.id == task.id }) else { return }
            var updated = task
            updated.note = Self.cleanedQuickNote(task.note)
            data.planTasks[index] = updated
            for todayIndex in data.todayTasks.indices
            where data.todayTasks[todayIndex].source == .project
                && data.todayTasks[todayIndex].sourceID == task.id {
                data.todayTasks[todayIndex].note = updated.note
            }
        }
    }

    func setPlanTaskQuickNote(taskID: UUID, note: String) {
        let cleaned = Self.cleanedQuickNote(note)
        mutate { data in
            guard let index = data.planTasks.firstIndex(where: { $0.id == taskID }) else { return }
            data.planTasks[index].note = cleaned
            for todayIndex in data.todayTasks.indices
            where data.todayTasks[todayIndex].source == .project
                && data.todayTasks[todayIndex].sourceID == taskID {
                data.todayTasks[todayIndex].note = cleaned
            }
        }
    }

    func deletePlanTask(_ id: UUID) {
        mutate { data in
            let removedIDs = descendantIDs(of: id, in: data.planTasks).union([id])
            data.planTasks.removeAll { removedIDs.contains($0.id) }
            data.quadrantPlacements.removeAll { removedIDs.contains($0.taskID) }
            data.quadrantOtherTaskIDs.removeAll { removedIDs.contains($0) }
            data.mapLinks.removeAll { removedIDs.contains($0.fromTaskID) || removedIDs.contains($0.toTaskID) }
            data.todayTasks.removeAll { item in
                guard let sourceID = item.sourceID else { return false }
                return removedIDs.contains(sourceID)
            }
        }
    }

    func reparentPlanTask(_ taskID: UUID, to newParentID: UUID?, undoManager: UndoManager? = nil) throws {
        guard data.planTasks.first(where: { $0.id == taskID })?.parentID != newParentID else { return }
        var draft = data
        try reparentPlanTask(taskID, to: newParentID, in: &draft)
        try validateTaskGraph(draft.planTasks)
        commit(draft, undoManager: undoManager, actionName: "调整任务层级")
    }

    /// 将任务树重挂与整条分支的位置变化作为一次原子修改提交。
    func movePlanTaskBranch(
        _ taskID: UUID,
        to newParentID: UUID?,
        positions: [UUID: CGPoint],
        undoManager: UndoManager? = nil
    ) throws {
        var draft = data
        try reparentPlanTask(taskID, to: newParentID, in: &draft)
        let branchIDs = descendantIDs(of: taskID, in: draft.planTasks).union([taskID])
        for index in draft.planTasks.indices {
            guard branchIDs.contains(draft.planTasks[index].id),
                  let point = positions[draft.planTasks[index].id] else { continue }
            draft.planTasks[index].mapX = max(80, point.x)
            draft.planTasks[index].mapY = max(70, point.y)
        }
        try validateTaskGraph(draft.planTasks)
        commit(draft, undoManager: undoManager, actionName: "移动任务分支")
    }

    func canReparentPlanTask(_ taskID: UUID, to newParentID: UUID?) -> Bool {
        var draft = data
        do {
            try reparentPlanTask(taskID, to: newParentID, in: &draft)
            try validateTaskGraph(draft.planTasks)
            return true
        } catch {
            return false
        }
    }

    func setMapPosition(taskID: UUID, x: Double, y: Double) {
        mutate { data in
            guard let index = data.planTasks.firstIndex(where: { $0.id == taskID }) else { return }
            data.planTasks[index].mapX = max(80, x)
            data.planTasks[index].mapY = max(70, y)
        }
    }

    func setMapPositions(_ positions: [UUID: CGPoint], undoManager: UndoManager? = nil) {
        var draft = data
        for index in draft.planTasks.indices {
            guard let point = positions[draft.planTasks[index].id] else { continue }
            draft.planTasks[index].mapX = point.x
            draft.planTasks[index].mapY = point.y
        }
        guard draft != data else { return }
        commit(draft, undoManager: undoManager, actionName: "移动任务")
    }

    /// 在两个任务之间画一条自由连接线。连接线不改变层级，只表达关联。
    func addMapLink(from firstID: UUID, to secondID: UUID, undoManager: UndoManager? = nil) throws {
        guard firstID != secondID else { throw StoreError.linkSelf }
        guard let first = data.planTasks.first(where: { $0.id == firstID }),
              let second = data.planTasks.first(where: { $0.id == secondID }) else {
            throw StoreError.targetNotFound
        }
        guard first.projectID == second.projectID else { throw StoreError.linkAcrossProjects }
        guard !data.mapLinks.contains(where: { $0.connects(firstID, secondID) }) else {
            throw StoreError.linkDuplicate
        }
        var draft = data
        draft.mapLinks.append(MapLink(id: UUID(), fromTaskID: firstID, toTaskID: secondID))
        try validateMapLinks(draft.mapLinks, tasks: draft.planTasks)
        commit(draft, undoManager: undoManager, actionName: "连接任务")
    }

    func removeMapLink(_ linkID: UUID, undoManager: UndoManager? = nil) {
        guard data.mapLinks.contains(where: { $0.id == linkID }) else { return }
        var draft = data
        draft.mapLinks.removeAll { $0.id == linkID }
        commit(draft, undoManager: undoManager, actionName: "断开连接")
    }

    /// 断开两个任务之间的连接（不关心当初的端点顺序）。
    func removeMapLink(between firstID: UUID, and secondID: UUID, undoManager: UndoManager? = nil) {
        guard data.mapLinks.contains(where: { $0.connects(firstID, secondID) }) else { return }
        var draft = data
        draft.mapLinks.removeAll { $0.connects(firstID, secondID) }
        commit(draft, undoManager: undoManager, actionName: "断开连接")
    }

    func placeInQuadrant(taskID: UUID, quadrant: TaskQuadrant, before targetID: UUID? = nil) {
        guard data.planTasks.contains(where: { $0.id == taskID }), taskID != targetID else { return }
        mutate { data in
            data.quadrantPlacements.removeAll { $0.taskID == taskID }
            data.quadrantOtherTaskIDs.removeAll { $0 == taskID }
            var destination = data.quadrantPlacements
                .filter { $0.quadrant == quadrant }
                .sorted { $0.order < $1.order }
            let placement = QuadrantPlacement(taskID: taskID, quadrant: quadrant, order: destination.count)
            if let targetID, let targetIndex = destination.firstIndex(where: { $0.taskID == targetID }) {
                destination.insert(placement, at: targetIndex)
            } else {
                destination.append(placement)
            }
            data.quadrantPlacements.removeAll { $0.quadrant == quadrant }
            for index in destination.indices { destination[index].order = index }
            data.quadrantPlacements.append(contentsOf: destination)
            normalizeQuadrantOrder(in: &data)
        }
    }

    func placeInQuadrantOther(taskID: UUID, before targetID: UUID? = nil) {
        guard data.planTasks.contains(where: { $0.id == taskID }), taskID != targetID else { return }
        mutate { data in
            data.quadrantPlacements.removeAll { $0.taskID == taskID }
            var destination = data.quadrantOtherTaskIDs.filter { $0 != taskID }
            if let targetID, let targetIndex = destination.firstIndex(of: targetID) {
                destination.insert(taskID, at: targetIndex)
            } else {
                destination.append(taskID)
            }
            data.quadrantOtherTaskIDs = destination
            normalizeQuadrantOrder(in: &data)
        }
    }

    func removeFromQuadrantOther(taskID: UUID) {
        guard data.quadrantOtherTaskIDs.contains(taskID) else { return }
        mutate { data in
            data.quadrantOtherTaskIDs.removeAll { $0 == taskID }
        }
    }

    func removeFromQuadrant(taskID: UUID) {
        guard data.quadrantPlacements.contains(where: { $0.taskID == taskID }) else { return }
        mutate { data in
            data.quadrantPlacements.removeAll { $0.taskID == taskID }
            normalizeQuadrantOrder(in: &data)
        }
    }

    func setPlanTaskCompleted(_ taskID: UUID, isCompleted: Bool) {
        mutate { data in
            guard let index = data.planTasks.firstIndex(where: { $0.id == taskID }) else { return }
            data.planTasks[index].isCompleted = isCompleted
            data.planTasks[index].completedAt = isCompleted ? Date() : nil
            for todayIndex in data.todayTasks.indices where data.todayTasks[todayIndex].sourceID == taskID {
                data.todayTasks[todayIndex].isCompleted = isCompleted
                data.todayTasks[todayIndex].completedAt = isCompleted ? Date() : nil
            }
        }
    }

    func scheduleToday(planTaskID: UUID) {
        guard let plan = data.planTasks.first(where: { $0.id == planTaskID }) else { return }
        if data.todayTasks.contains(where: { $0.sourceID == planTaskID }) { return }
        let item = TodayTask(id: UUID(), sourceID: plan.id, source: .project, title: plan.title, note: plan.note, time: nextSuggestedTime(), durationMinutes: plan.durationMinutes, isCompleted: false, order: data.todayTasks.count)
        mutate { $0.todayTasks.append(item) }
    }

    func addQuadrantQuickNote(_ note: String, quadrant: TaskQuadrant) {
        let cleaned = Self.cleanedQuickNote(note)
        guard !cleaned.isEmpty else { return }
        let title = String(cleaned.split(separator: "\n", maxSplits: 1).first ?? "")
        let item = TodayTask(
            quadrant: quadrant, id: UUID(), sourceID: nil, source: .spontaneous,
            title: title, note: cleaned, time: nextSuggestedTime(),
            durationMinutes: 30, isCompleted: false, order: data.todayTasks.count
        )
        mutate { $0.todayTasks.append(item) }
    }

    func addTodayTask(title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let item = TodayTask(id: UUID(), sourceID: nil, source: .spontaneous, title: cleaned, note: "", time: nextSuggestedTime(), durationMinutes: 30, isCompleted: false, order: data.todayTasks.count)
        mutate { $0.todayTasks.append(item) }
    }

    func updateTodayTask(_ task: TodayTask) {
        mutate { data in
            guard let index = data.todayTasks.firstIndex(where: { $0.id == task.id }) else { return }
            var updated = task
            updated.note = Self.cleanedQuickNote(task.note)
            data.todayTasks[index] = updated
            if updated.source == .project,
               let sourceID = updated.sourceID,
               let planIndex = data.planTasks.firstIndex(where: { $0.id == sourceID }) {
                data.planTasks[planIndex].note = updated.note
            }
        }
    }

    func setTodayTaskQuickNote(taskID: UUID, note: String) {
        let cleaned = Self.cleanedQuickNote(note)
        mutate { data in
            guard let index = data.todayTasks.firstIndex(where: { $0.id == taskID }) else { return }
            data.todayTasks[index].note = cleaned
            guard data.todayTasks[index].source == .project,
                  let sourceID = data.todayTasks[index].sourceID,
                  let planIndex = data.planTasks.firstIndex(where: { $0.id == sourceID }) else { return }
            data.planTasks[planIndex].note = cleaned
        }
    }

    func toggleToday(_ id: UUID) {
        mutate { data in
            guard let index = data.todayTasks.firstIndex(where: { $0.id == id }) else { return }
            data.todayTasks[index].isCompleted.toggle()
            data.todayTasks[index].completedAt = data.todayTasks[index].isCompleted ? Date() : nil
            if let sourceID = data.todayTasks[index].sourceID,
               let planIndex = data.planTasks.firstIndex(where: { $0.id == sourceID }) {
                data.planTasks[planIndex].isCompleted = data.todayTasks[index].isCompleted
                data.planTasks[planIndex].completedAt = data.todayTasks[index].completedAt
            }
        }
    }

    func deleteToday(_ id: UUID) {
        mutate { $0.todayTasks.removeAll { $0.id == id } }
        normalizeTodayOrder()
    }

    func moveToday(draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var items = orderedTodayTasks
        guard let source = items.firstIndex(where: { $0.id == draggedID }),
              let target = items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = items.remove(at: source)
        items.insert(item, at: source < target ? max(0, target - 1) : target)
        for index in items.indices { items[index].order = index }
        mutate { $0.todayTasks = items }
    }

    func addRoutine(title: String, repeatRule: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let routine = RoutineTask(id: UUID(), title: cleaned, detail: "", repeatRule: repeatRule, milestone: "", isEnabled: true)
        mutate { $0.routines.append(routine) }
    }

    func updateRoutine(_ routine: RoutineTask) {
        let cleanedTitle = routine.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRule = routine.repeatRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, !cleanedRule.isEmpty else { return }
        mutate { data in
            guard let index = data.routines.firstIndex(where: { $0.id == routine.id }) else { return }
            var updated = routine
            updated.title = cleanedTitle
            updated.repeatRule = cleanedRule
            data.routines[index] = updated
        }
    }

    func scheduleRoutine(_ routine: RoutineTask) {
        if data.todayTasks.contains(where: { $0.sourceID == routine.id }) { return }
        let item = TodayTask(id: UUID(), sourceID: routine.id, source: .routine, title: routine.title, note: routine.detail, time: nextSuggestedTime(), durationMinutes: 30, isCompleted: false, order: data.todayTasks.count)
        mutate { $0.todayTasks.append(item) }
    }

    func deleteRoutine(_ routineID: UUID) {
        mutate { data in
            data.routines.removeAll { $0.id == routineID }
            data.todayTasks.removeAll { $0.sourceID == routineID }
            for index in data.todayTasks.indices { data.todayTasks[index].order = index }
        }
    }

    func exportAIContext(projectID: UUID? = nil) -> String {
        let context: WorkspaceData
        if let projectID, let project = data.projects.first(where: { $0.id == projectID }) {
            let tasks = data.planTasks.filter { $0.projectID == projectID }
            let taskIDs = Set(tasks.map(\.id))
            context = WorkspaceData(
                projects: [project],
                planTasks: tasks,
                todayTasks: data.todayTasks.filter { item in
                    guard let sourceID = item.sourceID else { return false }
                    return taskIDs.contains(sourceID)
                },
                routines: [],
                quadrantPlacements: data.quadrantPlacements.filter { taskIDs.contains($0.taskID) },
                quadrantOtherTaskIDs: data.quadrantOtherTaskIDs.filter { taskIDs.contains($0) },
                mapLinks: data.mapLinks.filter {
                    taskIDs.contains($0.fromTaskID) && taskIDs.contains($0.toTaskID)
                },
                schemaVersion: data.schemaVersion
            )
        } else {
            context = data
        }
        guard let json = try? encoder.encode(context) else { return "{}" }
        return String(decoding: json, as: UTF8.self)
    }

    func validate(_ proposal: AIProposal) throws {
        _ = try draftApplying(proposal)
    }

    func apply(_ proposal: AIProposal) throws {
        data = try draftApplying(proposal)
        persist()
    }

    private func draftApplying(_ proposal: AIProposal) throws -> WorkspaceData {
        try validateStructure(proposal)
        var draft = data
        var createdIDs: [String: UUID] = [:]
        for operation in proposal.operations {
            try apply(operation, to: &draft, createdIDs: &createdIDs)
        }
        try validateTaskGraph(draft.planTasks)
        for index in draft.todayTasks.indices { draft.todayTasks[index].order = index }
        normalizeQuadrantOrder(in: &draft)
        Self.sanitizeMapLinks(in: &draft)
        return draft
    }

    private func validateStructure(_ proposal: AIProposal) throws {
        guard proposal.operations.count <= 50 else { throw StoreError.tooManyOperations }
        let clientIDs = proposal.operations.compactMap(\.clientID)
        guard Set(clientIDs).count == clientIDs.count else { throw StoreError.duplicateClientID }
        var projectClientIDs = Set<String>()
        var taskClientIDs = Set<String>()
        for operation in proposal.operations {
            if let title = operation.title, title.count > 200 { throw StoreError.titleTooLong }
            if let minutes = operation.durationMinutes, !(5...720).contains(minutes) { throw StoreError.invalidDuration }
            switch operation.kind {
            case .createProject:
                guard operation.title?.isBlank == false else { throw StoreError.missingTitle }
                if let clientID = operation.clientID { projectClientIDs.insert(clientID) }
            case .updateProject, .deleteProject:
                guard operation.targetID != nil else { throw StoreError.missingTarget }
            case .createPlanTask:
                guard operation.title?.isBlank == false else { throw StoreError.missingTitle }
                guard (operation.projectID == nil) != (operation.projectClientID == nil) else { throw StoreError.missingFields }
                if let projectClientID = operation.projectClientID, !projectClientIDs.contains(projectClientID) { throw StoreError.missingClientID }
                if operation.parentID != nil && operation.parentClientID != nil { throw StoreError.invalidParent }
                if let parentClientID = operation.parentClientID, !taskClientIDs.contains(parentClientID) { throw StoreError.missingClientID }
                if let clientID = operation.clientID { taskClientIDs.insert(clientID) }
            case .reparentPlanTask:
                guard operation.targetID != nil else { throw StoreError.missingTarget }
                if operation.parentID != nil && operation.parentClientID != nil { throw StoreError.invalidParent }
                if let parentClientID = operation.parentClientID, !taskClientIDs.contains(parentClientID) { throw StoreError.missingClientID }
            case .setTaskQuadrant:
                guard operation.targetID != nil else { throw StoreError.missingTarget }
                guard operation.quadrant != nil else { throw StoreError.missingFields }
            case .updatePlanTask, .deletePlanTask, .scheduleToday, .updateTodayTask,
                 .completeTodayTask, .deleteTodayTask, .updateRoutine:
                guard operation.targetID != nil else { throw StoreError.missingTarget }
            case .createTodayTask, .createRoutine:
                guard operation.title?.isBlank == false else { throw StoreError.missingTitle }
            }
        }
    }

    private func apply(_ op: TaskOperation, to draft: inout WorkspaceData, createdIDs: inout [String: UUID]) throws {
        switch op.kind {
        case .createProject:
            let projectID = UUID()
            draft.projects.append(Project(id: projectID, title: op.title!, detail: op.note ?? "", symbol: "cloud.fill"))
            if let clientID = op.clientID { createdIDs[clientID] = projectID }
        case .updateProject:
            guard let index = draft.projects.firstIndex(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            if let title = op.title { draft.projects[index].title = title }
            if let detail = op.note { draft.projects[index].detail = detail }
        case .deleteProject:
            guard draft.projects.contains(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            let taskIDs = Set(draft.planTasks.filter { $0.projectID == op.targetID }.map(\.id))
            draft.projects.removeAll { $0.id == op.targetID }
            draft.planTasks.removeAll { $0.projectID == op.targetID }
            draft.quadrantPlacements.removeAll { taskIDs.contains($0.taskID) }
            draft.quadrantOtherTaskIDs.removeAll { taskIDs.contains($0) }
            draft.mapLinks.removeAll { taskIDs.contains($0.fromTaskID) || taskIDs.contains($0.toTaskID) }
            draft.todayTasks.removeAll { item in
                guard let sourceID = item.sourceID else { return false }
                return taskIDs.contains(sourceID)
            }
        case .createPlanTask:
            let projectID = try resolvedProjectID(for: op, createdIDs: createdIDs)
            guard draft.projects.contains(where: { $0.id == projectID }) else { throw StoreError.targetNotFound }
            let parentID = try resolvedParentID(for: op, createdIDs: createdIDs)
            if let parentID, !draft.planTasks.contains(where: { $0.id == parentID && $0.projectID == projectID }) { throw StoreError.invalidParent }
            let newID = UUID()
            draft.planTasks.append(PlanTask(id: newID, projectID: projectID, parentID: parentID, title: op.title!, note: op.note ?? "", goal: op.goal ?? "", expectedDate: nil, durationMinutes: op.durationMinutes ?? 30, isCompleted: false, order: draft.planTasks.filter { $0.projectID == projectID && $0.parentID == parentID }.count))
            if let clientID = op.clientID { createdIDs[clientID] = newID }
        case .updatePlanTask:
            guard let index = draft.planTasks.firstIndex(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            if let title = op.title { draft.planTasks[index].title = title }
            if let note = op.note { draft.planTasks[index].note = note }
            if let goal = op.goal { draft.planTasks[index].goal = goal }
            if let minutes = op.durationMinutes { draft.planTasks[index].durationMinutes = minutes }
        case .reparentPlanTask:
            let newParentID = try resolvedParentID(for: op, createdIDs: createdIDs)
            try reparentPlanTask(op.targetID!, to: newParentID, in: &draft)
        case .setTaskQuadrant:
            guard draft.planTasks.contains(where: { $0.id == op.targetID }), let quadrant = op.quadrant else { throw StoreError.targetNotFound }
            draft.quadrantPlacements.removeAll { $0.taskID == op.targetID }
            draft.quadrantOtherTaskIDs.removeAll { $0 == op.targetID }
            let order = draft.quadrantPlacements.filter { $0.quadrant == quadrant }.count
            draft.quadrantPlacements.append(QuadrantPlacement(taskID: op.targetID!, quadrant: quadrant, order: order))
        case .deletePlanTask:
            guard draft.planTasks.contains(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            let removedIDs = descendantIDs(of: op.targetID!, in: draft.planTasks).union([op.targetID!])
            draft.planTasks.removeAll { removedIDs.contains($0.id) }
            draft.quadrantPlacements.removeAll { removedIDs.contains($0.taskID) }
            draft.quadrantOtherTaskIDs.removeAll { removedIDs.contains($0) }
            draft.mapLinks.removeAll { removedIDs.contains($0.fromTaskID) || removedIDs.contains($0.toTaskID) }
            draft.todayTasks.removeAll { item in
                guard let sourceID = item.sourceID else { return false }
                return removedIDs.contains(sourceID)
            }
        case .scheduleToday:
            guard let plan = draft.planTasks.first(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            if !draft.todayTasks.contains(where: { $0.sourceID == plan.id }) {
                draft.todayTasks.append(TodayTask(id: UUID(), sourceID: plan.id, source: .project, title: plan.title, note: plan.note, time: op.time ?? "09:00", durationMinutes: op.durationMinutes ?? plan.durationMinutes, isCompleted: false, order: draft.todayTasks.count))
            }
        case .createTodayTask:
            draft.todayTasks.append(TodayTask(id: UUID(), sourceID: nil, source: .spontaneous, title: op.title!, note: op.note ?? "", time: op.time ?? "", durationMinutes: op.durationMinutes ?? 30, isCompleted: false, order: draft.todayTasks.count))
        case .updateTodayTask:
            guard let index = draft.todayTasks.firstIndex(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            if let title = op.title { draft.todayTasks[index].title = title }
            if let note = op.note { draft.todayTasks[index].note = note }
            if let time = op.time { draft.todayTasks[index].time = time }
            if let minutes = op.durationMinutes { draft.todayTasks[index].durationMinutes = minutes }
        case .completeTodayTask:
            guard let index = draft.todayTasks.firstIndex(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            draft.todayTasks[index].isCompleted = true
        case .deleteTodayTask:
            guard draft.todayTasks.contains(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            draft.todayTasks.removeAll { $0.id == op.targetID }
        case .createRoutine:
            draft.routines.append(RoutineTask(id: UUID(), title: op.title!, detail: op.note ?? "", repeatRule: op.repeatRule ?? "每周", milestone: op.milestone ?? "", isEnabled: true))
        case .updateRoutine:
            guard let index = draft.routines.firstIndex(where: { $0.id == op.targetID }) else { throw StoreError.targetNotFound }
            if let title = op.title { draft.routines[index].title = title }
            if let note = op.note { draft.routines[index].detail = note }
            if let rule = op.repeatRule { draft.routines[index].repeatRule = rule }
            if let milestone = op.milestone { draft.routines[index].milestone = milestone }
        }
    }

    private func resolvedParentID(for operation: TaskOperation, createdIDs: [String: UUID]) throws -> UUID? {
        if let parentClientID = operation.parentClientID {
            guard let resolved = createdIDs[parentClientID] else { throw StoreError.missingClientID }
            return resolved
        }
        return operation.parentID
    }

    private func resolvedProjectID(for operation: TaskOperation, createdIDs: [String: UUID]) throws -> UUID {
        if let projectClientID = operation.projectClientID {
            guard let resolved = createdIDs[projectClientID] else { throw StoreError.missingClientID }
            return resolved
        }
        guard let projectID = operation.projectID else { throw StoreError.missingFields }
        return projectID
    }

    private func reparentPlanTask(_ taskID: UUID, to newParentID: UUID?, in draft: inout WorkspaceData) throws {
        guard let index = draft.planTasks.firstIndex(where: { $0.id == taskID }) else { throw StoreError.targetNotFound }
        if taskID == newParentID { throw StoreError.taskCycle }
        if let newParentID {
            guard let parent = draft.planTasks.first(where: { $0.id == newParentID }) else { throw StoreError.targetNotFound }
            guard parent.projectID == draft.planTasks[index].projectID else { throw StoreError.invalidParent }
            if descendantIDs(of: taskID, in: draft.planTasks).contains(newParentID) { throw StoreError.taskCycle }
        }
        draft.planTasks[index].parentID = newParentID
        draft.planTasks[index].order = draft.planTasks.filter {
            $0.projectID == draft.planTasks[index].projectID && $0.parentID == newParentID && $0.id != taskID
        }.count
    }

    private func descendantIDs(of rootID: UUID, in tasks: [PlanTask]) -> Set<UUID> {
        var result = Set<UUID>()
        var frontier = [rootID]
        while let parentID = frontier.popLast() {
            for child in tasks where child.parentID == parentID && !result.contains(child.id) {
                result.insert(child.id)
                frontier.append(child.id)
            }
        }
        return result
    }

    private func validateTaskGraph(_ tasks: [PlanTask]) throws {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for task in tasks {
            var visited = Set<UUID>([task.id])
            var current = task
            while let parentID = current.parentID {
                guard let parent = byID[parentID], parent.projectID == task.projectID else { throw StoreError.invalidParent }
                guard visited.insert(parentID).inserted else { throw StoreError.taskCycle }
                current = parent
            }
        }
    }

    /// 连接线只允许在同一项目、两个不同任务之间，且同一对任务只有一条。
    private func validateMapLinks(_ links: [MapLink], tasks: [PlanTask]) throws {
        let projectByTask = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.projectID) })
        var seenPairs = Set<Set<UUID>>()
        for link in links {
            guard link.fromTaskID != link.toTaskID else { throw StoreError.linkSelf }
            guard let fromProject = projectByTask[link.fromTaskID],
                  let toProject = projectByTask[link.toTaskID] else { throw StoreError.targetNotFound }
            guard fromProject == toProject else { throw StoreError.linkAcrossProjects }
            guard seenPairs.insert(link.endpointIDs).inserted else { throw StoreError.linkDuplicate }
        }
    }

    private func mutate(_ change: (inout WorkspaceData) -> Void) {
        change(&data)
        persist()
    }

    private func commit(_ draft: WorkspaceData, undoManager: UndoManager?, actionName: String) {
        let previous = data
        data = draft
        persist()
        guard let undoManager else { return }
        registeredUndoManager = undoManager
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(previous, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    private func restore(_ snapshot: WorkspaceData, actionName: String) {
        let inverse = data
        data = snapshot
        persist()
        guard let undoManager = registeredUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(inverse, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(data).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    private func normalizeTodayOrder() {
        mutate { data in
            data.todayTasks.sort { $0.order < $1.order }
            for index in data.todayTasks.indices { data.todayTasks[index].order = index }
        }
    }

    private func normalizeQuadrantOrder(in data: inout WorkspaceData) {
        for quadrant in TaskQuadrant.allCases {
            let ordered = data.quadrantPlacements
                .filter { $0.quadrant == quadrant }
                .sorted { $0.order < $1.order }
            for (order, placement) in ordered.enumerated() {
                guard let index = data.quadrantPlacements.firstIndex(where: { $0.taskID == placement.taskID }) else { continue }
                data.quadrantPlacements[index].order = order
            }
        }
    }

    private static func sanitizeQuadrantPlacements(in data: inout WorkspaceData) {
        let taskIDs = Set(data.planTasks.map(\.id))
        var seen = Set<UUID>()
        data.quadrantPlacements = data.quadrantPlacements.filter {
            taskIDs.contains($0.taskID) && seen.insert($0.taskID).inserted
        }
        for quadrant in TaskQuadrant.allCases {
            let ordered = data.quadrantPlacements
                .filter { $0.quadrant == quadrant }
                .sorted { $0.order < $1.order }
            for (order, placement) in ordered.enumerated() {
                guard let index = data.quadrantPlacements.firstIndex(where: { $0.taskID == placement.taskID }) else { continue }
                data.quadrantPlacements[index].order = order
            }
        }
        let quadrantTaskIDs = Set(data.quadrantPlacements.map(\.taskID))
        var seenOther = Set<UUID>()
        data.quadrantOtherTaskIDs = data.quadrantOtherTaskIDs.filter {
            taskIDs.contains($0) && !quadrantTaskIDs.contains($0) && seenOther.insert($0).inserted
        }
    }

    /// 丢弃指向已删除任务、跨项目或重复的导图连接线，不触碰任务层级。
    private static func sanitizeMapLinks(in data: inout WorkspaceData) {
        let projectByTask = Dictionary(uniqueKeysWithValues: data.planTasks.map { ($0.id, $0.projectID) })
        var seenPairs = Set<Set<UUID>>()
        data.mapLinks = data.mapLinks.filter { link in
            guard link.fromTaskID != link.toTaskID,
                  let fromProject = projectByTask[link.fromTaskID],
                  let toProject = projectByTask[link.toTaskID],
                  fromProject == toProject else { return false }
            return seenPairs.insert(link.endpointIDs).inserted
        }
    }

    private func nextSuggestedTime() -> String {
        guard let last = orderedTodayTasks.last, !last.time.isEmpty else { return "09:00" }
        let parts = last.time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return "09:00" }
        let minutes = min(23 * 60 + 45, parts[0] * 60 + parts[1] + last.durationMinutes)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func cleanedQuickNote(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case projects = "项目"
    case quadrants = "四象限"
    case routines = "长期主义"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .projects: return "point.3.connected.trianglepath.dotted"
        case .quadrants: return "square.grid.2x2.fill"
        case .routines: return "infinity"
        }
    }
}

enum StoreError: LocalizedError {
    case tooManyOperations, titleTooLong, invalidDuration, missingTitle, missingFields, missingTarget, targetNotFound
    case taskCycle, invalidParent, duplicateClientID, missingClientID
    case linkSelf, linkDuplicate, linkAcrossProjects
    var errorDescription: String? {
        switch self {
        case .tooManyOperations: return "一次最多执行 50 个修改。"
        case .titleTooLong: return "任务标题不能超过 200 个字。"
        case .invalidDuration: return "任务时长需在 5 分钟到 12 小时之间。"
        case .missingTitle: return "缺少标题。"
        case .missingFields: return "创建任务所需信息不完整。"
        case .missingTarget: return "缺少要修改的对象。"
        case .targetNotFound: return "AI 指向的任务已经不存在，请重新整理。"
        case .taskCycle: return "任务不能成为自己或自己子任务的子任务。"
        case .invalidParent: return "父任务必须存在于同一个项目中。"
        case .duplicateClientID: return "AI 建议中的临时任务编号重复。"
        case .missingClientID: return "AI 建议引用了尚未创建的父任务。"
        case .linkSelf: return "连接线需要两个不同的任务。"
        case .linkDuplicate: return "这两个任务之间已经有连接线了。"
        case .linkAcrossProjects: return "只能连接同一个项目里的任务。"
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
