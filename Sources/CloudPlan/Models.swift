import Foundation

struct WorkspaceData: Codable, Equatable {
    var projects: [Project]
    var planTasks: [PlanTask]
    var todayTasks: [TodayTask]
    var routines: [RoutineTask]
    var quadrantPlacements: [QuadrantPlacement] = []
    var quadrantOtherTaskIDs: [UUID] = []
    var mapLinks: [MapLink] = []
    var schemaVersion: Int = 6

    static let sample = WorkspaceData(
        projects: [
            Project(id: UUID(), title: "把生活过成喜欢的样子", detail: "不追赶风，只决定今天往哪里走。", symbol: "cloud.sun.fill")
        ],
        planTasks: [],
        todayTasks: [
            TodayTask(id: UUID(), sourceID: nil, source: .spontaneous, title: "留二十分钟给自己", note: "散步、发呆，或者看看云", time: "16:30", durationMinutes: 20, isCompleted: false, order: 0)
        ],
        routines: [
            RoutineTask(id: UUID(), title: "每周回望", detail: "看看这一周走了多远，而不是只看还有多远。", repeatRule: "每周日", milestone: "持续 12 周", isEnabled: true)
        ]
    )
}

extension WorkspaceData {
    private enum CodingKeys: String, CodingKey {
        case projects, planTasks, todayTasks, routines, quadrantPlacements, quadrantOtherTaskIDs, mapLinks, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decode([Project].self, forKey: .projects)
        planTasks = try container.decode([PlanTask].self, forKey: .planTasks)
        todayTasks = try container.decode([TodayTask].self, forKey: .todayTasks)
        routines = try container.decode([RoutineTask].self, forKey: .routines)
        quadrantPlacements = try container.decodeIfPresent([QuadrantPlacement].self, forKey: .quadrantPlacements) ?? []
        quadrantOtherTaskIDs = try container.decodeIfPresent([UUID].self, forKey: .quadrantOtherTaskIDs) ?? []
        mapLinks = try container.decodeIfPresent([MapLink].self, forKey: .mapLinks) ?? []
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var detail: String
    var symbol: String
}

struct PlanTask: Codable, Identifiable, Hashable {
    var id: UUID
    var projectID: UUID
    var parentID: UUID?
    var title: String
    var note: String
    var goal: String
    var expectedDate: Date?
    var durationMinutes: Int
    var isCompleted: Bool
    var completedAt: Date? = nil
    var order: Int
    /// 思维导图中的手动位置；nil 表示使用自动树布局。
    var mapX: Double? = nil
    var mapY: Double? = nil
}

enum TaskSource: String, Codable, CaseIterable {
    case project
    case routine
    case spontaneous

    var title: String {
        switch self {
        case .project: return "项目"
        case .routine: return "长期"
        case .spontaneous: return "随性"
        }
    }
}

struct TodayTask: Codable, Identifiable, Hashable {
    var quadrant: TaskQuadrant? = nil
    var id: UUID
    var sourceID: UUID?
    var source: TaskSource
    var title: String
    var note: String
    var time: String
    var durationMinutes: Int
    var isCompleted: Bool
    var completedAt: Date? = nil
    var order: Int
}

struct RoutineTask: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var detail: String
    var repeatRule: String
    var milestone: String
    var isEnabled: Bool
}

/// 思维导图中两个任务之间的自由连接线。
/// 它只表达“这两件事互相关联”，不参与父子层级，也不会改变任务树的结构。
struct MapLink: Codable, Identifiable, Hashable {
    var id: UUID
    var fromTaskID: UUID
    var toTaskID: UUID

    /// 连接线是无向的：端点顺序相反也算同一条。
    func connects(_ first: UUID, _ second: UUID) -> Bool {
        (fromTaskID == first && toTaskID == second) || (fromTaskID == second && toTaskID == first)
    }

    func touches(_ taskID: UUID) -> Bool {
        fromTaskID == taskID || toTaskID == taskID
    }

    var endpointIDs: Set<UUID> { [fromTaskID, toTaskID] }
}

enum TaskQuadrant: String, Codable, CaseIterable, Identifiable {
    case importantUrgent = "important_urgent"
    case importantNotUrgent = "important_not_urgent"
    case notImportantUrgent = "not_important_urgent"
    case notImportantNotUrgent = "not_important_not_urgent"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importantUrgent: return "重要且紧急"
        case .importantNotUrgent: return "重要不紧急"
        case .notImportantUrgent: return "不重要但紧急"
        case .notImportantNotUrgent: return "不重要不紧急"
        }
    }

    var actionTitle: String {
        switch self {
        case .importantUrgent: return "现在处理"
        case .importantNotUrgent: return "留出时间"
        case .notImportantUrgent: return "尽快简化"
        case .notImportantNotUrgent: return "稍后再看"
        }
    }

    var symbol: String {
        switch self {
        case .importantUrgent: return "exclamationmark.circle.fill"
        case .importantNotUrgent: return "calendar.circle.fill"
        case .notImportantUrgent: return "bolt.circle.fill"
        case .notImportantNotUrgent: return "tray.circle.fill"
        }
    }
}

/// 象限中保存的是项目任务引用，不复制任务本体。
struct QuadrantPlacement: Codable, Identifiable, Hashable {
    var taskID: UUID
    var quadrant: TaskQuadrant
    var order: Int

    var id: UUID { taskID }
}

enum OperationKind: String, Codable, CaseIterable {
    case createProject = "create_project"
    case updateProject = "update_project"
    case deleteProject = "delete_project"
    case createPlanTask = "create_plan_task"
    case updatePlanTask = "update_plan_task"
    case reparentPlanTask = "reparent_plan_task"
    case setTaskQuadrant = "set_task_quadrant"
    case deletePlanTask = "delete_plan_task"
    case scheduleToday = "schedule_today"
    case createTodayTask = "create_today_task"
    case updateTodayTask = "update_today_task"
    case completeTodayTask = "complete_today_task"
    case deleteTodayTask = "delete_today_task"
    case createRoutine = "create_routine"
    case updateRoutine = "update_routine"
}

/// AI 和应用之间唯一允许的写入协议。所有字段都可编码、可校验、可预览。
struct TaskOperation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: OperationKind
    var targetID: UUID?
    var projectID: UUID?
    var parentID: UUID?
    /// AI 在同一份建议里创建树时使用的临时引用，不会写入存档。
    var clientID: String? = nil
    var parentClientID: String? = nil
    /// 在同一份建议里引用刚创建的项目，不会写入存档。
    var projectClientID: String? = nil
    var title: String?
    var note: String?
    var goal: String?
    var time: String?
    var durationMinutes: Int?
    var repeatRule: String?
    var milestone: String?
    var reason: String
    var quadrant: TaskQuadrant? = nil

    enum CodingKeys: String, CodingKey {
        case kind, targetID, projectID, parentID, clientID, parentClientID, projectClientID
        case title, note, goal, time, durationMinutes, repeatRule, milestone, reason, quadrant
    }
}

struct AIProposal: Codable, Equatable {
    var summary: String
    var operations: [TaskOperation]
}
