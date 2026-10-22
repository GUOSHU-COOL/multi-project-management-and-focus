import Foundation
import Testing
@testable import CloudPlan

@Suite("任务仓库")
@MainActor
struct TaskStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudPlanTests-\(UUID().uuidString)")
            .appendingPathComponent("workspace.json")
    }

    @Test("无归属快记与每日任务共享状态并持久化")
    func quadrantQuickNoteSharesTodayState() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        let planCount = store.data.planTasks.count
        let count = store.data.todayTasks.count
        store.addQuadrantQuickNote("  买花\n路过花店时看看  ", quadrant: .importantNotUrgent)
        let task = try #require(store.data.todayTasks.last)
        #expect(store.data.todayTasks.count == count + 1)
        #expect(store.data.planTasks.count == planCount)
        #expect(task.sourceID == nil)
        #expect(task.source == .spontaneous)
        #expect(task.title == "买花")
        #expect(task.note == "买花\n路过花店时看看")
        #expect(task.quadrant == .importantNotUrgent)
        store.toggleToday(task.id)
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.todayTasks.last?.isCompleted == true)
        #expect(reloaded.data.todayTasks.last?.quadrant == .importantNotUrgent)
        store.toggleToday(task.id)
        #expect(store.data.todayTasks.last?.isCompleted == false)
        store.deleteToday(task.id)
        #expect(!store.data.todayTasks.contains { $0.id == task.id })
        store.addQuadrantQuickNote("  \n ", quadrant: .importantUrgent)
        #expect(store.data.todayTasks.count == count)
    }

    @Test("第四版存档迁移后每日任务保留且不自动归入象限")
    func versionFourTodayTasksMigrate() throws {
        let url = temporaryURL()
        var legacy = WorkspaceData.sample
        legacy.schemaVersion = 4
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: url)
        let store = TaskStore(fileURL: url)
        #expect(store.data.schemaVersion == 6)
        #expect(store.data.todayTasks == legacy.todayTasks)
        #expect(store.data.todayTasks.allSatisfy { $0.quadrant == nil })
        #expect(TaskStore(fileURL: url).data.schemaVersion == 6)
    }

    @Test("重新开始恢复今日状态并重置专注计时")
    func restartCompletedQuadrantTask() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "测试项目")
        let projectID = try #require(store.selectedProjectID)
        _ = try #require(store.addPlanTask(title: "测试任务", projectID: projectID))
        let task = try #require(store.data.planTasks.first)
        store.placeInQuadrant(taskID: task.id, quadrant: .importantUrgent)
        store.scheduleToday(planTaskID: task.id)
        store.setPlanTaskCompleted(task.id, isCompleted: true)
        let focus = FocusSessionController()
        focus.start(task: task, durationMinutes: 15)
        focus.pauseOrResume(taskID: task.id)
        store.setPlanTaskCompleted(task.id, isCompleted: false)
        focus.start(task: task, durationMinutes: 15)
        #expect(store.data.planTasks.first?.isCompleted == false)
        #expect(store.data.todayTasks.first { $0.sourceID == task.id }?.isCompleted == false)
        #expect(store.placement(for: task.id)?.quadrant == .importantUrgent)
        #expect(focus.sessions.count == 1)
        #expect(focus.state(for: task.id) == .running)
        #expect(focus.remainingSeconds(for: task.id) == 900)
        focus.stop(taskID: task.id)
    }

    @Test("项目任务可以安排到今天并持久化")
    func projectTaskCanBeScheduledAndPersists() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "旅行")
        store.addPlanTask(title: "订车票")
        let task = try #require(store.selectedPlanTasks.last)

        store.scheduleToday(planTaskID: task.id)

        #expect(store.data.todayTasks.contains { $0.sourceID == task.id })
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.todayTasks.contains { $0.sourceID == task.id })
    }

    @Test("项目任务可以添加到明确指定的项目")
    func planTaskCanTargetAnExplicitProject() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "项目甲")
        let firstProjectID = try #require(store.selectedProjectID)
        store.addProject(title: "项目乙")
        let selectedProjectID = try #require(store.selectedProjectID)

        let taskID = try #require(store.addPlanTask(title: "甲项目的新任务", projectID: firstProjectID))

        #expect(store.data.planTasks.first { $0.id == taskID }?.projectID == firstProjectID)
        #expect(store.selectedProjectID == selectedProjectID)
    }

    @Test("项目任务快记会清理首尾空白并持久化")
    func planTaskQuickNotePersists() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "发布新版本")
        let taskID = try #require(store.addPlanTask(title: "整理发布说明"))

        store.setPlanTaskQuickNote(taskID: taskID, note: "  先补上兼容性说明\n")

        #expect(store.data.planTasks.first { $0.id == taskID }?.note == "先补上兼容性说明")
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.planTasks.first { $0.id == taskID }?.note == "先补上兼容性说明")
    }

    @Test("项目任务快记会同步到今日副本")
    func planTaskQuickNoteSyncsToTodayCopy() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "发布新版本")
        let taskID = try #require(store.addPlanTask(title: "整理发布说明"))
        store.scheduleToday(planTaskID: taskID)

        store.setPlanTaskQuickNote(taskID: taskID, note: "确认下载地址")

        #expect(store.data.todayTasks.first { $0.sourceID == taskID }?.note == "确认下载地址")
    }

    @Test("今日项目任务快记会同步回计划任务")
    func todayQuickNoteSyncsBackToPlanTask() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "发布新版本")
        let taskID = try #require(store.addPlanTask(title: "整理发布说明"))
        store.scheduleToday(planTaskID: taskID)
        let todayID = try #require(store.data.todayTasks.first { $0.sourceID == taskID }?.id)

        store.setTodayTaskQuickNote(taskID: todayID, note: "等设计稿确认后发布")

        #expect(store.data.planTasks.first { $0.id == taskID }?.note == "等设计稿确认后发布")
    }

    @Test("空白快记会删除项目与今日副本中的内容")
    func blankQuickNoteRemovesContent() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "发布新版本")
        let taskID = try #require(store.addPlanTask(title: "整理发布说明", note: "旧快记"))
        store.scheduleToday(planTaskID: taskID)

        store.setPlanTaskQuickNote(taskID: taskID, note: " \n ")

        #expect(store.data.planTasks.first { $0.id == taskID }?.note.isEmpty == true)
        #expect(store.data.todayTasks.first { $0.sourceID == taskID }?.note.isEmpty == true)
    }

    @Test("创建项目后会立即进入新项目")
    func addingProjectSelectsAndShowsIt() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.selectedSection = .routines

        store.addProject(title: "自由潜水", detail: "去看看海面之下", symbol: "drop.fill")

        let project = try #require(store.selectedProject)
        #expect(project.title == "自由潜水")
        #expect(project.detail == "去看看海面之下")
        #expect(project.symbol == "drop.fill")
        #expect(store.selectedSection == .projects)
    }

    @Test("长期任务频率可以更新并持久化")
    func routineFrequencyCanBeUpdatedAndPersists() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addRoutine(title: "每周练习", repeatRule: "每周 3 次")
        let routine = try #require(store.data.routines.last)

        var updated = routine
        updated.repeatRule = "每周 5 次"
        store.updateRoutine(updated)

        #expect(store.data.routines.first { $0.id == routine.id }?.repeatRule == "每周 5 次")
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.routines.first { $0.id == routine.id }?.repeatRule == "每周 5 次")
    }

    @Test("删除项目会一并移除关联计划和今日副本")
    func deletingProjectCascadesSafely() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "短途旅行")
        let projectID = try #require(store.selectedProjectID)
        store.addPlanTask(title: "订车票")
        let taskID = try #require(store.selectedPlanTasks.last?.id)
        let otherTaskID = try #require(store.addPlanTask(title: "整理随身物品"))
        store.scheduleToday(planTaskID: taskID)
        store.placeInQuadrant(taskID: taskID, quadrant: .importantUrgent)
        store.placeInQuadrantOther(taskID: otherTaskID)

        store.deleteProject(projectID)

        #expect(!store.data.projects.contains { $0.id == projectID })
        #expect(!store.data.planTasks.contains { $0.projectID == projectID })
        #expect(!store.data.todayTasks.contains { $0.sourceID == taskID })
        #expect(!store.data.quadrantPlacements.contains { $0.taskID == taskID })
        #expect(!store.data.quadrantOtherTaskIDs.contains(otherTaskID))
    }

    @Test("AI 建议通过校验后可以执行")
    func aiProposalIsValidatedThenApplied() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        let proposal = AIProposal(
            summary: "安排一件轻量任务",
            operations: [TaskOperation(
                kind: .createTodayTask,
                targetID: nil,
                projectID: nil,
                parentID: nil,
                title: "看看晚霞",
                note: "",
                goal: nil,
                time: "18:30",
                durationMinutes: 15,
                repeatRule: nil,
                milestone: nil,
                reason: "给今天留一点呼吸"
            )]
        )

        try store.apply(proposal)

        #expect(store.data.todayTasks.contains { $0.title == "看看晚霞" && $0.time == "18:30" })
    }

    @Test("无效 AI 建议不会留下半成品")
    func invalidAIProposalCannotMutateStore() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        let before = store.data
        let proposal = AIProposal(
            summary: "无效删除",
            operations: [TaskOperation(
                kind: .deleteTodayTask,
                targetID: UUID(),
                projectID: nil,
                parentID: nil,
                title: nil,
                note: nil,
                goal: nil,
                time: nil,
                durationMinutes: nil,
                repeatRule: nil,
                milestone: nil,
                reason: "测试"
            )]
        )

        #expect(throws: StoreError.self) {
            try store.apply(proposal)
        }
        #expect(store.data == before)
    }

    @Test("AI 的结构化 JSON 可以解码为操作")
    func structuredAIResponseDecodes() throws {
        let json = """
        {
          "summary": "把散步放到傍晚",
          "operations": [{
            "kind": "create_today_task",
            "targetID": null,
            "projectID": null,
            "parentID": null,
            "clientID": null,
            "parentClientID": null,
            "title": "去海边散步",
            "note": "不带耳机",
            "goal": null,
            "time": "18:20",
            "durationMinutes": 30,
            "repeatRule": null,
            "milestone": null,
            "reason": "给今天留出呼吸"
          }]
        }
        """

        let decoded = try JSONDecoder().decode(AIProposal.self, from: Data(json.utf8))

        #expect(decoded.operations.first?.kind == .createTodayTask)
        #expect(decoded.operations.first?.title == "去海边散步")
    }

    @Test("任务可以无限嵌套且删除父任务会删除整棵子树")
    func nestedTreeCascadesAtEveryDepth() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "做一场展览")
        let rootID = try #require(store.addPlanTask(title: "策展"))
        let childID = try #require(store.addPlanTask(title: "确定主题", parentID: rootID))
        let grandchildID = try #require(store.addPlanTask(title: "采访创作者", parentID: childID))
        let greatGrandchildID = try #require(store.addPlanTask(title: "整理访谈", parentID: grandchildID))
        store.scheduleToday(planTaskID: greatGrandchildID)

        #expect(store.selectedPlanTasks.first(where: { $0.id == greatGrandchildID })?.parentID == grandchildID)
        store.deletePlanTask(rootID)

        let removed = Set([rootID, childID, grandchildID, greatGrandchildID])
        #expect(store.data.planTasks.allSatisfy { !removed.contains($0.id) })
        #expect(store.data.todayTasks.allSatisfy { item in
            guard let sourceID = item.sourceID else { return true }
            return !removed.contains(sourceID)
        })
    }

    @Test("任务可跨分支重挂但不能形成循环")
    func reparentingRejectsCycles() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "写小说")
        let charactersID = try #require(store.addPlanTask(title: "人物"))
        let plotID = try #require(store.addPlanTask(title: "情节"))
        let motivationID = try #require(store.addPlanTask(title: "主角动机", parentID: charactersID))

        try store.reparentPlanTask(motivationID, to: plotID)
        #expect(store.selectedPlanTasks.first(where: { $0.id == motivationID })?.parentID == plotID)

        #expect(throws: StoreError.self) {
            try store.reparentPlanTask(plotID, to: motivationID)
        }
        #expect(store.selectedPlanTasks.first(where: { $0.id == plotID })?.parentID == nil)
    }

    @Test("任务重挂支持撤销重做并持久化撤销结果")
    func reparentingSupportsUndoRedoAndPersists() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        let undoManager = UndoManager()
        store.addProject(title: "筹备播客")
        let researchID = try #require(store.addPlanTask(title: "资料研究"))
        let recordingID = try #require(store.addPlanTask(title: "录制"))
        let outlineID = try #require(store.addPlanTask(title: "整理提纲", parentID: researchID))

        try store.reparentPlanTask(outlineID, to: recordingID, undoManager: undoManager)
        #expect(store.data.planTasks.first(where: { $0.id == outlineID })?.parentID == recordingID)
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(store.data.planTasks.first(where: { $0.id == outlineID })?.parentID == researchID)
        #expect(TaskStore(fileURL: url).data.planTasks.first(where: { $0.id == outlineID })?.parentID == researchID)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(store.data.planTasks.first(where: { $0.id == outlineID })?.parentID == recordingID)
        #expect(TaskStore(fileURL: url).data.planTasks.first(where: { $0.id == outlineID })?.parentID == recordingID)
    }

    @Test("子任务可以移回项目顶层并撤销")
    func childCanMoveToRootAndUndo() throws {
        let store = TaskStore(fileURL: temporaryURL())
        let undoManager = UndoManager()
        store.addProject(title: "布置新家")
        let roomID = try #require(store.addPlanTask(title: "书房"))
        let deskID = try #require(store.addPlanTask(title: "挑选书桌", parentID: roomID))

        try store.reparentPlanTask(deskID, to: nil, undoManager: undoManager)
        #expect(store.data.planTasks.first(where: { $0.id == deskID })?.parentID == nil)

        undoManager.undo()
        #expect(store.data.planTasks.first(where: { $0.id == deskID })?.parentID == roomID)
    }

    @Test("完成子任务不会自动完成父任务")
    func completingChildDoesNotCompleteParent() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "发布新版本")
        let releaseID = try #require(store.addPlanTask(title: "发布准备"))
        let notesID = try #require(store.addPlanTask(title: "发布说明", parentID: releaseID))

        store.setPlanTaskCompleted(notesID, isCompleted: true)

        #expect(store.data.planTasks.first(where: { $0.id == notesID })?.isCompleted == true)
        #expect(store.data.planTasks.first(where: { $0.id == releaseID })?.isCompleted == false)
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.planTasks.first(where: { $0.id == notesID })?.isCompleted == true)
        #expect(reloaded.data.planTasks.first(where: { $0.id == releaseID })?.isCompleted == false)
    }

    @Test("跨分支拖动会原子更新层级和整棵子树坐标")
    func branchMoveCommitsHierarchyAndPositionsTogether() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "准备展览")
        let curationID = try #require(store.addPlanTask(title: "策展"))
        let interviewID = try #require(store.addPlanTask(title: "采访", parentID: curationID))
        let productionID = try #require(store.addPlanTask(title: "制作"))
        let positions = [
            curationID: CGPoint(x: 660, y: 280),
            interviewID: CGPoint(x: 900, y: 280),
            productionID: CGPoint(x: 120, y: 80)
        ]

        try store.movePlanTaskBranch(curationID, to: productionID, positions: positions)

        #expect(store.data.planTasks.first(where: { $0.id == curationID })?.parentID == productionID)
        #expect(store.data.planTasks.first(where: { $0.id == curationID })?.mapX == 660)
        #expect(store.data.planTasks.first(where: { $0.id == interviewID })?.mapX == 900)
        #expect(store.data.planTasks.first(where: { $0.id == productionID })?.mapX == nil)

        let beforeInvalidMove = store.data
        #expect(throws: StoreError.self) {
            try store.movePlanTaskBranch(productionID, to: interviewID, positions: [productionID: CGPoint(x: 400, y: 80)])
        }
        #expect(store.data == beforeInvalidMove)
    }

    @Test("AI 可在一次建议中构建多层任务树")
    func aiBuildsTreeWithTemporaryClientIDs() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "学习摄影")
        let projectID = try #require(store.selectedProjectID)
        let proposal = AIProposal(summary: "建立学习路径", operations: [
            TaskOperation(
                kind: .createPlanTask,
                targetID: nil,
                projectID: projectID,
                parentID: nil,
                clientID: "stage_1",
                parentClientID: nil,
                title: "理解曝光",
                note: "",
                goal: "掌握曝光三角",
                time: nil,
                durationMinutes: 60,
                repeatRule: nil,
                milestone: nil,
                reason: "先建立基础"
            ),
            TaskOperation(
                kind: .createPlanTask,
                targetID: nil,
                projectID: projectID,
                parentID: nil,
                clientID: "task_1",
                parentClientID: "stage_1",
                title: "练习快门速度",
                note: "拍流水",
                goal: "看懂动态模糊",
                time: nil,
                durationMinutes: 30,
                repeatRule: nil,
                milestone: nil,
                reason: "把概念变成动作"
            ),
            TaskOperation(
                kind: .createPlanTask,
                targetID: nil,
                projectID: projectID,
                parentID: nil,
                clientID: "task_2",
                parentClientID: "task_1",
                title: "比较三档快门",
                note: "",
                goal: "完成对比图",
                time: nil,
                durationMinutes: 20,
                repeatRule: nil,
                milestone: nil,
                reason: "形成三级练习"
            )
        ])

        try store.apply(proposal)

        let stage = try #require(store.data.planTasks.first { $0.title == "理解曝光" })
        let practice = try #require(store.data.planTasks.first { $0.title == "练习快门速度" })
        let comparison = try #require(store.data.planTasks.first { $0.title == "比较三档快门" })
        #expect(practice.parentID == stage.id)
        #expect(comparison.parentID == practice.id)
    }

    @Test("AI 可重组既有任务层级")
    func aiReparentsExistingTask() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "发布播客")
        let projectID = try #require(store.selectedProjectID)
        let preparationID = try #require(store.addPlanTask(title: "准备"))
        let productionID = try #require(store.addPlanTask(title: "制作"))
        let outlineID = try #require(store.addPlanTask(title: "写提纲", parentID: preparationID))
        let proposal = AIProposal(summary: "把提纲归到制作", operations: [
            TaskOperation(
                kind: .reparentPlanTask,
                targetID: outlineID,
                projectID: projectID,
                parentID: productionID,
                clientID: nil,
                parentClientID: nil,
                title: nil,
                note: nil,
                goal: nil,
                time: nil,
                durationMinutes: nil,
                repeatRule: nil,
                milestone: nil,
                reason: "提纲直接服务于本期制作"
            )
        ])

        try store.apply(proposal)

        #expect(store.data.planTasks.first(where: { $0.id == outlineID })?.parentID == productionID)
    }

    @Test("AI 可在同一份建议中创建项目和它的任务树")
    func aiCreatesProjectAndReferencesItWithClientID() throws {
        let store = TaskStore(fileURL: temporaryURL())
        let proposal = AIProposal(summary: "建立播客项目", operations: [
            TaskOperation(
                kind: .createProject,
                targetID: nil,
                projectID: nil,
                parentID: nil,
                clientID: "project_podcast",
                title: "发布播客",
                note: "从选题到上线",
                goal: nil,
                time: nil,
                durationMinutes: nil,
                repeatRule: nil,
                milestone: nil,
                reason: "Notion 内容属于独立项目"
            ),
            TaskOperation(
                kind: .createPlanTask,
                targetID: nil,
                projectID: nil,
                parentID: nil,
                clientID: "task_outline",
                parentClientID: nil,
                projectClientID: "project_podcast",
                title: "完成节目提纲",
                note: "",
                goal: "形成可录制提纲",
                time: nil,
                durationMinutes: 45,
                repeatRule: nil,
                milestone: nil,
                reason: "先把内容范围定清楚"
            )
        ])

        try store.apply(proposal)

        let project = try #require(store.data.projects.first { $0.title == "发布播客" })
        #expect(store.data.planTasks.contains { $0.projectID == project.id && $0.title == "完成节目提纲" })
    }

    @Test("AI 设置象限也必须经过结构化操作")
    func aiSetsExistingTaskQuadrant() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "产品发布")
        let taskID = try #require(store.addPlanTask(title: "修复发布阻塞"))
        let proposal = AIProposal(summary: "标出当前阻塞", operations: [
            TaskOperation(
                kind: .setTaskQuadrant,
                targetID: taskID,
                projectID: nil,
                parentID: nil,
                title: nil,
                note: nil,
                goal: nil,
                time: nil,
                durationMinutes: nil,
                repeatRule: nil,
                milestone: nil,
                reason: "直接影响发布且需要立即处理",
                quadrant: .importantUrgent
            )
        ])

        try store.apply(proposal)

        #expect(store.placement(for: taskID)?.quadrant == .importantUrgent)
    }

    @Test("预览前校验会拦截不存在的目标且不修改数据")
    func proposalValidationSimulatesWholeDraft() throws {
        let store = TaskStore(fileURL: temporaryURL())
        let before = store.data
        let proposal = AIProposal(summary: "无效象限", operations: [
            TaskOperation(
                kind: .setTaskQuadrant,
                targetID: UUID(),
                projectID: nil,
                parentID: nil,
                title: nil,
                note: nil,
                goal: nil,
                time: nil,
                durationMinutes: nil,
                repeatRule: nil,
                milestone: nil,
                reason: "测试",
                quadrant: .importantUrgent
            )
        ])

        #expect(throws: StoreError.self) {
            try store.validate(proposal)
        }
        #expect(store.data == before)
    }

    @Test("AI 请求使用自定义 Responses 地址并关闭响应存储")
    func aiRequestUsesConfiguredProviderWithoutStorage() throws {
        let service = OpenAIService()
        let configuration = AIConfiguration(
            apiKey: "test-key",
            model: "gpt-5.6-sol",
            baseURL: "https://example.ai/v1/",
            reasoningEffort: "xhigh",
            serviceTier: "default",
            disableResponseStorage: true
        )

        let request = try service.makeProposalRequest(
            instruction: "整理项目",
            workspaceJSON: "{}",
            sourceMaterial: "[{\"name\":\"Tasks.csv\",\"content\":\"Name\\n准备发布\"}]",
            configuration: configuration
        )
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])

        #expect(request.url?.absoluteString == "https://example.ai/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(body["model"] as? String == "gpt-5.6-sol")
        #expect(body["store"] as? Bool == false)
        #expect((body["reasoning"] as? [String: Any])?["effort"] as? String == "xhigh")
        #expect(body["service_tier"] as? String == "default")
        #expect((body["input"] as? String)?.contains("Tasks.csv") == true)
    }

    @Test("AI 自定义地址必须使用 HTTPS")
    func aiProviderRejectsInsecureEndpoint() {
        #expect(throws: AIServiceError.self) {
            _ = try OpenAIService.responsesURL(for: "http://example.ai/v1")
        }
    }

    @Test("Notion 导出的 CSV 和 Markdown 可一起读取")
    func notionExportFilesLoadLocally() throws {
        let directory = temporaryURL().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let csv = directory.appendingPathComponent("Tasks.csv")
        let markdown = directory.appendingPathComponent("Project.md")
        try Data("Name,Status\n准备发布,进行中\n".utf8).write(to: csv)
        try Data("# 发布项目\n- 完成检查\n".utf8).write(to: markdown)

        let payload = try NotionImportService.load(urls: [markdown, csv])
        let decoded = try JSONDecoder().decode([NotionImportFile].self, from: Data(payload.sourceMaterial.utf8))

        #expect(payload.files.count == 2)
        #expect(payload.characterCount > 0)
        #expect(decoded.contains { $0.name == "Tasks.csv" && $0.content.contains("准备发布") })
        #expect(decoded.contains { $0.name == "Project.md" && $0.content.contains("完成检查") })
    }

    @Test("发送当前项目时不会夹带其他项目内容")
    func aiContextCanBeScopedToCurrentProject() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "项目甲")
        let firstID = try #require(store.selectedProjectID)
        store.addPlanTask(title: "甲任务")
        store.addProject(title: "项目乙")
        store.addPlanTask(title: "乙任务")

        let context = store.exportAIContext(projectID: firstID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceData.self, from: Data(context.utf8))

        #expect(decoded.projects.map(\.title) == ["项目甲"])
        #expect(decoded.planTasks.map(\.title) == ["甲任务"])
        #expect(decoded.todayTasks.isEmpty)
        #expect(decoded.routines.isEmpty)
    }

    @Test("旧版存档会迁移到最新版并保留任务")
    func schemaOneWorkspaceMigratesToLatestSchema() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let projectID = UUID()
        let taskID = UUID()
        let legacy = """
        {
          "schemaVersion": 1,
          "projects": [{"id":"\(projectID.uuidString)","title":"旧项目","detail":"","symbol":"cloud.fill"}],
          "planTasks": [{
            "id":"\(taskID.uuidString)","projectID":"\(projectID.uuidString)","parentID":null,
            "title":"旧任务","note":"","goal":"","expectedDate":null,
            "durationMinutes":30,"isCompleted":false,"order":0
          }],
          "todayTasks": [],
          "routines": []
        }
        """
        try Data(legacy.utf8).write(to: url)

        let store = TaskStore(fileURL: url)

        #expect(store.data.schemaVersion == 6)
        #expect(store.data.planTasks.first?.title == "旧任务")
        #expect(store.data.planTasks.first?.mapX == nil)
        #expect(store.data.quadrantPlacements.isEmpty)
        #expect(store.data.quadrantOtherTaskIDs.isEmpty)
        #expect(store.data.mapLinks.isEmpty)
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(persisted?["schemaVersion"] as? Int == 6)
        #expect((persisted?["quadrantOtherTaskIDs"] as? [Any])?.isEmpty == true)
        #expect((persisted?["mapLinks"] as? [Any])?.isEmpty == true)
    }

    @Test("第二版存档迁移后得到空的四象限且会持久化")
    func schemaTwoWorkspaceMigratesToQuadrants() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let projectID = UUID()
        let taskID = UUID()
        let legacy = """
        {
          "schemaVersion": 2,
          "projects": [{"id":"\(projectID.uuidString)","title":"进行中的项目","detail":"","symbol":"cloud.fill"}],
          "planTasks": [{
            "id":"\(taskID.uuidString)","projectID":"\(projectID.uuidString)","parentID":null,
            "title":"保留下来的任务","note":"","goal":"","expectedDate":null,
            "durationMinutes":25,"isCompleted":false,"order":0,"mapX":320,"mapY":120
          }],
          "todayTasks": [],
          "routines": []
        }
        """
        try Data(legacy.utf8).write(to: url)

        let store = TaskStore(fileURL: url)

        #expect(store.data.schemaVersion == 6)
        #expect(store.data.planTasks.first?.id == taskID)
        #expect(store.data.planTasks.first?.mapX == 320)
        #expect(store.data.quadrantPlacements.isEmpty)
        #expect(store.data.quadrantOtherTaskIDs.isEmpty)
        #expect(store.data.mapLinks.isEmpty)
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect((persisted?["quadrantPlacements"] as? [Any])?.isEmpty == true)
        #expect((persisted?["quadrantOtherTaskIDs"] as? [Any])?.isEmpty == true)
        #expect((persisted?["mapLinks"] as? [Any])?.isEmpty == true)
    }

    @Test("第三版存档升级后保留象限并得到空的其他区域")
    func schemaThreeWorkspaceMigratesToManualOther() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let projectID = UUID()
        let taskID = UUID()
        let legacy = """
        {
          "schemaVersion": 3,
          "projects": [{"id":"\(projectID.uuidString)","title":"原有项目","detail":"","symbol":"cloud.fill"}],
          "planTasks": [{
            "id":"\(taskID.uuidString)","projectID":"\(projectID.uuidString)","parentID":null,
            "title":"原有象限任务","note":"","goal":"","expectedDate":null,
            "durationMinutes":30,"isCompleted":false,"order":0
          }],
          "todayTasks": [],
          "routines": [],
          "quadrantPlacements": [{"taskID":"\(taskID.uuidString)","quadrant":"important_urgent","order":0}]
        }
        """
        try Data(legacy.utf8).write(to: url)

        let store = TaskStore(fileURL: url)

        #expect(store.data.schemaVersion == 6)
        #expect(store.placement(for: taskID)?.quadrant == .importantUrgent)
        #expect(store.quadrantOtherTasks.isEmpty)
        #expect(store.data.mapLinks.isEmpty)
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect((persisted?["quadrantOtherTaskIDs"] as? [Any])?.isEmpty == true)
        #expect((persisted?["mapLinks"] as? [Any])?.isEmpty == true)
    }

    @Test("任务放入四象限后只保存引用并可持久化移动")
    func quadrantPlacementPersistsAndMovesWithoutDuplication() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "发布新产品")
        let firstID = try #require(store.addPlanTask(title: "修复发布阻塞"))
        let secondID = try #require(store.addPlanTask(title: "梳理季度路线"))

        store.placeInQuadrant(taskID: firstID, quadrant: .importantUrgent)
        store.placeInQuadrant(taskID: secondID, quadrant: .importantNotUrgent)
        store.placeInQuadrant(taskID: firstID, quadrant: .importantNotUrgent, before: secondID)

        #expect(store.data.planTasks.filter { $0.id == firstID }.count == 1)
        #expect(store.data.quadrantPlacements.filter { $0.taskID == firstID }.count == 1)
        #expect(!store.data.quadrantOtherTaskIDs.contains(firstID))
        #expect(store.tasks(in: .importantUrgent).isEmpty)
        #expect(store.tasks(in: .importantNotUrgent).map(\.id) == [firstID, secondID])

        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.placement(for: firstID)?.quadrant == .importantNotUrgent)
        #expect(reloaded.tasks(in: .importantNotUrgent).map(\.id) == [firstID, secondID])
    }

    @Test("从边界移出四象限会保留项目任务并持久化")
    func removingFromQuadrantKeepsOriginalTaskAndPersists() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "准备发布")
        let taskID = try #require(store.addPlanTask(title: "检查发布包"))
        store.placeInQuadrant(taskID: taskID, quadrant: .importantUrgent)

        store.removeFromQuadrant(taskID: taskID)

        #expect(store.data.planTasks.contains { $0.id == taskID })
        #expect(store.placement(for: taskID) == nil)
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.planTasks.contains { $0.id == taskID })
        #expect(reloaded.placement(for: taskID) == nil)
    }

    @Test("其他默认空白且只保存手动放入的任务")
    func quadrantOtherOnlyContainsManuallyPlacedTasks() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "准备分享")
        let firstID = try #require(store.addPlanTask(title: "整理演示文稿"))
        let secondID = try #require(store.addPlanTask(title: "准备讲稿"))

        #expect(store.quadrantOtherTasks.isEmpty)

        store.placeInQuadrantOther(taskID: firstID)
        store.placeInQuadrantOther(taskID: secondID, before: firstID)

        #expect(store.quadrantOtherTasks.map(\.id) == [secondID, firstID])
        #expect(store.placement(for: firstID) == nil)
        #expect(store.placement(for: secondID) == nil)
        #expect(TaskStore(fileURL: url).quadrantOtherTasks.map(\.id) == [secondID, firstID])
    }

    @Test("任务在象限和其他之间移动时只保留一个位置")
    func taskMovesExclusivelyBetweenQuadrantAndOther() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "准备分享")
        let taskID = try #require(store.addPlanTask(title: "整理演示文稿"))
        store.placeInQuadrant(taskID: taskID, quadrant: .importantUrgent)

        store.placeInQuadrantOther(taskID: taskID)

        #expect(store.placement(for: taskID) == nil)
        #expect(store.quadrantOtherTasks.map(\.id) == [taskID])

        store.placeInQuadrant(taskID: taskID, quadrant: .importantNotUrgent)

        #expect(store.placement(for: taskID)?.quadrant == .importantNotUrgent)
        #expect(store.quadrantOtherTasks.isEmpty)
    }

    @Test("删除任务树会同步清除象限引用")
    func deletingTaskTreeRemovesQuadrantPlacements() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "整理工作室")
        let rootID = try #require(store.addPlanTask(title: "清点"))
        let childID = try #require(store.addPlanTask(title: "清点器材", parentID: rootID))
        store.placeInQuadrantOther(taskID: rootID)
        store.placeInQuadrant(taskID: childID, quadrant: .importantUrgent)

        store.deletePlanTask(rootID)

        #expect(store.data.quadrantPlacements.allSatisfy { $0.taskID != rootID && $0.taskID != childID })
        #expect(!store.data.quadrantOtherTaskIDs.contains(rootID))
    }

    @Test("专注会按所选时长启动并可暂停结束")
    func focusSessionUsesChosenDuration() throws {
        let projectID = UUID()
        let task = PlanTask(id: UUID(), projectID: projectID, parentID: nil, title: "写发布说明", note: "", goal: "", expectedDate: nil, durationMinutes: 25, isCompleted: false, order: 0)
        let focus = FocusSessionController()

        focus.start(task: task, durationMinutes: 45)
        #expect(focus.session(for: task.id)?.taskID == task.id)
        #expect(focus.remainingSeconds(for: task.id) == 45 * 60)
        #expect(focus.state(for: task.id) == .running)

        focus.pauseOrResume(taskID: task.id)
        #expect(focus.state(for: task.id) == .paused)
        focus.stop(taskID: task.id)
        #expect(focus.session(for: task.id) == nil)
        #expect(focus.state(for: task.id) == .idle)
    }

    @Test("多个象限任务可以同时运行且控制互不影响")
    func focusSessionsRunConcurrently() throws {
        let projectID = UUID()
        let writing = PlanTask(id: UUID(), projectID: projectID, parentID: nil, title: "写发布说明", note: "", goal: "", expectedDate: nil, durationMinutes: 25, isCompleted: false, order: 0)
        let review = PlanTask(id: UUID(), projectID: projectID, parentID: nil, title: "检查发布包", note: "", goal: "", expectedDate: nil, durationMinutes: 30, isCompleted: false, order: 1)
        let focus = FocusSessionController()

        focus.start(task: writing, durationMinutes: 25)
        focus.start(task: review, durationMinutes: 45)

        #expect(focus.sessions.map(\.taskID) == [writing.id, review.id])
        #expect(focus.state(for: writing.id) == .running)
        #expect(focus.state(for: review.id) == .running)
        #expect(focus.remainingSeconds(for: writing.id) > 0)
        #expect(focus.remainingSeconds(for: review.id) > 0)

        focus.pauseOrResume(taskID: writing.id)
        #expect(focus.state(for: writing.id) == .paused)
        #expect(focus.state(for: review.id) == .running)

        focus.stop(taskID: review.id)
        #expect(focus.session(for: review.id) == nil)
        #expect(focus.state(for: writing.id) == .paused)
    }

    @Test("导图自动布局会按层级向右展开")
    func mindMapLayoutReflectsHierarchy() throws {
        let projectID = UUID()
        let root = PlanTask(id: UUID(), projectID: projectID, parentID: nil, title: "阶段", note: "", goal: "", expectedDate: nil, durationMinutes: 30, isCompleted: false, order: 0)
        let child = PlanTask(id: UUID(), projectID: projectID, parentID: root.id, title: "动作", note: "", goal: "", expectedDate: nil, durationMinutes: 20, isCompleted: false, order: 0)
        let grandchild = PlanTask(id: UUID(), projectID: projectID, parentID: child.id, title: "下一步", note: "", goal: "", expectedDate: nil, durationMinutes: 10, isCompleted: false, order: 0)

        let layout = MindMapLayout(tasks: [root, child, grandchild]).automaticPositions

        let rootPosition = try #require(layout[root.id])
        let childPosition = try #require(layout[child.id])
        let grandchildPosition = try #require(layout[grandchild.id])
        #expect(childPosition.x > rootPosition.x)
        #expect(grandchildPosition.x > childPosition.x)
        #expect(layout.values.map(\.y).min() == 105)
    }

    @Test("导图点击父节点会逐层显示后续子任务")
    func mindMapVisibilityExpandsOneLevelAtATime() throws {
        let projectID = UUID()
        let root = PlanTask(id: UUID(), projectID: projectID, parentID: nil, title: "阶段", note: "", goal: "", expectedDate: nil, durationMinutes: 30, isCompleted: false, order: 0)
        let child = PlanTask(id: UUID(), projectID: projectID, parentID: root.id, title: "动作", note: "", goal: "", expectedDate: nil, durationMinutes: 20, isCompleted: false, order: 0)
        let grandchild = PlanTask(id: UUID(), projectID: projectID, parentID: child.id, title: "下一步", note: "", goal: "", expectedDate: nil, durationMinutes: 10, isCompleted: false, order: 0)
        let otherRoot = PlanTask(id: UUID(), projectID: projectID, parentID: nil, title: "另一个阶段", note: "", goal: "", expectedDate: nil, durationMinutes: 15, isCompleted: false, order: 1)
        let tasks = [root, child, grandchild, otherRoot]

        #expect(MindMapVisibility.visibleTasks(in: tasks, expandedTaskIDs: []).map(\.id) == [root.id, otherRoot.id])
        #expect(MindMapVisibility.visibleTasks(in: tasks, expandedTaskIDs: [root.id]).map(\.id) == [root.id, child.id, otherRoot.id])
        #expect(MindMapVisibility.visibleTasks(in: tasks, expandedTaskIDs: [root.id, child.id]).map(\.id) == tasks.map(\.id))
        #expect(MindMapVisibility.visibleTasks(in: tasks, expandedTaskIDs: [child.id]).map(\.id) == [root.id, otherRoot.id])
    }

    @Test("第五版存档迁移后从空连接线开始并可持久化")
    func schemaFiveWorkspaceMigratesWithoutMapLinks() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let projectID = UUID()
        let taskID = UUID()
        let legacy = """
        {
          "schemaVersion": 5,
          "projects": [{"id":"\(projectID.uuidString)","title":"第五版项目","detail":"","symbol":"cloud.fill"}],
          "planTasks": [{
            "id":"\(taskID.uuidString)","projectID":"\(projectID.uuidString)","parentID":null,
            "title":"保留下来的任务","note":"","goal":"","expectedDate":null,
            "durationMinutes":30,"isCompleted":false,"order":0,"mapX":400,"mapY":200
          }],
          "todayTasks": [],
          "routines": [],
          "quadrantPlacements": [],
          "quadrantOtherTaskIDs": []
        }
        """
        try Data(legacy.utf8).write(to: url)

        let store = TaskStore(fileURL: url)

        #expect(store.data.schemaVersion == 6)
        #expect(store.data.planTasks.first?.id == taskID)
        #expect(store.data.planTasks.first?.mapX == 400)
        #expect(store.data.mapLinks.isEmpty)
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(persisted?["schemaVersion"] as? Int == 6)
        #expect((persisted?["mapLinks"] as? [Any])?.isEmpty == true)
    }

    @Test("导图连接线只连接同一项目的两个任务并可持久化")
    func mapLinksConnectTasksAndPersist() throws {
        let url = temporaryURL()
        let store = TaskStore(fileURL: url)
        store.addProject(title: "做一本小书")
        let writingID = try #require(store.addPlanTask(title: "写第一章"))
        let designID = try #require(store.addPlanTask(title: "挑字体"))

        try store.addMapLink(from: writingID, to: designID)

        let link = try #require(store.data.mapLinks.first)
        #expect(link.fromTaskID == writingID)
        #expect(link.toTaskID == designID)
        #expect(store.selectedMapLinks.map(\.id) == [link.id])
        #expect(store.linkedTasks(of: writingID).map(\.id) == [designID])
        #expect(store.linkCount(for: designID) == 1)
        #expect(store.selectedPlanTasks.allSatisfy { $0.parentID == nil })

        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.data.mapLinks == [link])

        #expect(throws: StoreError.self) { try store.addMapLink(from: designID, to: writingID) }
        #expect(throws: StoreError.self) { try store.addMapLink(from: writingID, to: writingID) }
        store.addProject(title: "另一个项目")
        let otherID = try #require(store.addPlanTask(title: "别处的任务"))
        #expect(throws: StoreError.self) { try store.addMapLink(from: writingID, to: otherID) }
        #expect(store.data.mapLinks.count == 1)

        store.removeMapLink(between: designID, and: writingID)
        #expect(store.data.mapLinks.isEmpty)
        #expect(TaskStore(fileURL: url).data.mapLinks.isEmpty)
    }

    @Test("连接线绘制在任务节点边缘")
    func mapLinkAnchorsFollowNodeEdges() throws {
        let horizontal = MapLinkGeometry.anchors(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 400, y: 120),
            nodeWidth: 200
        )
        #expect(horizontal.start == CGPoint(x: 200, y: 100))
        #expect(horizontal.end == CGPoint(x: 300, y: 120))

        let vertical = MapLinkGeometry.anchors(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 120, y: 400),
            nodeWidth: 200,
            nodeHeight: 80
        )
        #expect(vertical.start == CGPoint(x: 100, y: 140))
        #expect(vertical.end == CGPoint(x: 120, y: 360))
    }

    @Test("删除任务树或项目都会断开相关连接线")
    func deletingTasksAndProjectsRemovesMapLinks() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "整理房间")
        let rootID = try #require(store.addPlanTask(title: "收衣服"))
        let childID = try #require(store.addPlanTask(title: "叠好", parentID: rootID))
        let otherID = try #require(store.addPlanTask(title: "擦桌子"))
        try store.addMapLink(from: childID, to: otherID)

        store.deletePlanTask(rootID)

        #expect(store.data.mapLinks.isEmpty)
        #expect(store.linkedTasks(of: otherID).isEmpty)

        let projectID = try #require(store.selectedProjectID)
        let firstID = try #require(store.addPlanTask(title: "拖地"))
        let secondID = try #require(store.addPlanTask(title: "换床单"))
        try store.addMapLink(from: firstID, to: secondID)
        store.deleteProject(projectID)

        #expect(store.data.planTasks.allSatisfy { $0.projectID != projectID })
        #expect(store.data.mapLinks.isEmpty)
    }

    @Test("AI 删除任务时不会留下悬空连接线")
    func aiDeleteDropsDanglingMapLinks() throws {
        let store = TaskStore(fileURL: temporaryURL())
        store.addProject(title: "发布")
        let projectID = try #require(store.selectedProjectID)
        let firstID = try #require(store.addPlanTask(title: "写文案"))
        let secondID = try #require(store.addPlanTask(title: "配图"))
        try store.addMapLink(from: firstID, to: secondID)
        let proposal = AIProposal(summary: "删掉重复的任务", operations: [
            TaskOperation(
                kind: .deletePlanTask,
                targetID: secondID,
                projectID: projectID,
                parentID: nil,
                clientID: nil,
                parentClientID: nil,
                title: nil,
                note: nil,
                goal: nil,
                time: nil,
                durationMinutes: nil,
                repeatRule: nil,
                milestone: nil,
                reason: "与配图任务重复"
            )
        ])

        try store.apply(proposal)

        #expect(store.data.planTasks.filter { $0.projectID == projectID }.map(\.id) == [firstID])
        #expect(store.data.mapLinks.isEmpty)
    }
}
