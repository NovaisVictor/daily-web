import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureTasks

@MainActor
@Suite struct TasksStoreTests {
  // MARK: Completing

  @Test func completingIsOptimisticSendsTheBodyAndReloads() async {
    let harness = Harness([makeTask("t1", doing: true)])
    let gate = Gate()
    harness.serve(state: makeState([makeTask("t1", completed: true)])) { _ in
      await gate.wait()
      return FakeAPIClient.ok
    }
    let task = harness.tasks[0]
    let running = Task { await harness.store.toggleComplete(task) }
    await settle()
    // Ahead of the server, and "doing" ends with it (`setTaskCompleted`).
    #expect(harness.tasks[0].completed)
    #expect(!harness.tasks[0].doing)
    gate.open()
    #expect(await running.value == nil)
    #expect(harness.client.writes.map(\.description) == [#"PATCH /api/tasks/t1 {"completed":true}"#])
    #expect(harness.client.calls.last?.path == "/api/state")
  }

  @Test func aRecurringTaskIsNotMarkedAheadOfTheServer() async {
    let harness = Harness([makeTask("t1", due: "2026-09-21", recur: "daily")])
    let gate = Gate()
    harness.serve(state: makeState([makeTask("t1", due: "2026-09-22", recur: "daily")])) { _ in
      await gate.wait()
      return FakeAPIClient.ok
    }
    let running = Task { await harness.store.toggleComplete(harness.tasks[0]) }
    await settle()
    #expect(!harness.tasks[0].completed)
    gate.open()
    _ = await running.value
    // The server's answer, read right after, carries the next date.
    #expect(harness.tasks[0].due == "2026-09-22")
  }

  @Test func aFailedCompletionRollsBackAndToasts() async {
    let harness = Harness([makeTask("t1")])
    harness.failWrites("tarefa não encontrada")
    let error = await harness.store.toggleComplete(harness.tasks[0])
    #expect(error == .server(status: 400, message: "tarefa não encontrada", code: nil, retry: nil))
    #expect(!harness.tasks[0].completed)
    #expect(harness.toasts.toasts.map(\.text) == ["tarefa não encontrada"])
  }

  // MARK: Board

  @Test func movingToDoneCompletesInsteadOfWritingAStatus() async {
    let harness = Harness([makeTask("t1", doing: true)])
    #expect(await harness.store.move(harness.tasks[0], to: .done))
    #expect(harness.client.writes.map(\.description) == [#"PATCH /api/tasks/t1 {"completed":true}"#])
    #expect(harness.announcements.items == ["t movida para Feito."])
  }

  @Test func leavingDoneReopensThenWritesTheColumn() async {
    let harness = Harness([makeTask("t1", completed: true)])
    let gate = Gate()
    harness.serve(state: makeState([makeTask("t1", doing: true)])) { _ in
      await gate.wait()
      return FakeAPIClient.ok
    }
    let running = Task { await harness.store.move(harness.tasks[0], to: .doing) }
    await settle()
    #expect(!harness.tasks[0].completed)
    #expect(harness.tasks[0].doing)
    gate.open()
    #expect(await running.value)
    #expect(
      harness.client.writes.map(\.description) == [
        #"PATCH /api/tasks/t1 {"completed":false}"#,
        #"PATCH /api/tasks/t1/board {"status":"doing"}"#,
      ])
  }

  @Test func aRecurringTaskMovedToDoneSaysItComesBack() async {
    let harness = Harness([makeTask("t1", title: "Regar", due: "2026-09-21", recur: "weekly")])
    #expect(await harness.store.move(harness.tasks[0], to: .done))
    #expect(
      harness.announcements.items == ["Regar concluída. Ela repete, então volta para A fazer com a próxima data."])
  }

  @Test func aFailedMoveRollsBack() async {
    let harness = Harness([makeTask("t1")])
    harness.failWrites("coluna inválida")
    #expect(!(await harness.store.move(harness.tasks[0], to: .doing)))
    #expect(!harness.tasks[0].doing)
    #expect(harness.announcements.items == ["Não foi possível mover t: coluna inválida"])
  }

  @Test func movingToTheSameColumnSendsNothing() async {
    let harness = Harness([makeTask("t1", doing: true)])
    #expect(await harness.store.move(harness.tasks[0], to: .doing))
    #expect(harness.client.calls.isEmpty)
  }

  @Test func quickCreateSendsTheColumnInOneRequest() async {
    let harness = Harness([])
    harness.serve(state: makeState([makeTask("new", title: "Nota", doing: true)])) { _ in
      FakeAPIClient.json(CreatedTaskResponse(id: "new"))
    }
    #expect(await harness.store.quickCreate(title: "  Nota ", in: .doing))
    #expect(harness.client.writes.map(\.description) == [#"POST /api/tasks {"status":"doing","title":"Nota"}"#])
    #expect(harness.tasks.map(\.id) == ["new"])
    #expect(!(await harness.store.quickCreate(title: "   ", in: .todo)))
  }

  // MARK: Style

  @Test func styleIsOptimisticAndNeedsNoReload() async {
    let harness = Harness([makeTask("t1")])
    harness.serve(state: makeState([makeTask("t1")])) { _ in Data(#"{"ok":true,"paper":"pink"}"#.utf8) }
    await harness.store.changeStyle(harness.tasks[0], NoteStylePatch(paper: .some(.pink)))
    #expect(harness.tasks[0].paper == .pink)
    #expect(harness.client.calls.map(\.description) == [#"PATCH /api/tasks/t1/board {"paper":"pink"}"#])
    #expect(harness.announcements.items == ["Papel rosa em t."])
  }

  @Test func aFailedStyleGoesBackToTheOldColours() async {
    let harness = Harness([makeTask("t1", paper: .blue, pin: .red)])
    harness.failWrites("cor de papel inválida")
    await harness.store.changeStyle(harness.tasks[0], NoteStylePatch(paper: .some(nil)))
    #expect(harness.tasks[0].paper == .blue)
    #expect(harness.tasks[0].pin == .red)
  }

  // MARK: Delete

  @Test func deleteIsOptimisticAndRollsBack() async {
    let harness = Harness([makeTask("t1"), makeTask("t2")])
    harness.serve(state: makeState([makeTask("t2")]))
    #expect(await harness.store.delete(harness.tasks[0]) == nil)
    #expect(harness.tasks.map(\.id) == ["t2"])
    #expect(harness.client.writes.map(\.description) == ["DELETE /api/tasks/t1 -"])

    let failing = Harness([makeTask("t1")])
    failing.failWrites()
    #expect(await failing.store.delete(failing.tasks[0]) != nil)
    #expect(failing.tasks.map(\.id) == ["t1"])
  }

  // MARK: Form

  @Test func editingSavesTheTaskThenItsColour() async {
    let task = makeTask("t1", title: "Antigo", due: "2026-09-21")
    let harness = Harness([task])
    let initial = TaskDraft(task: task)
    var draft = initial
    draft.title = "Novo"
    draft.paper = .grey
    let outcome = await harness.store.save(draft, initial: initial, editing: task)
    #expect(outcome == .saved)
    #expect(
      harness.client.writes.map(\.description) == [
        #"PATCH /api/tasks/t1 {"due":"2026-09-21","priority":"normal","recur":"none","title":"Novo"}"#,
        #"PATCH /api/tasks/t1/board {"paper":"grey","pin":null,"pinShape":null}"#,
      ])
  }

  @Test func creatingUsesTheReturnedIdForTheColour() async {
    let harness = Harness([])
    harness.serve(state: makeState([makeTask("new-id")])) { call in
      call.method == "POST" ? FakeAPIClient.json(CreatedTaskResponse(id: "new-id")) : FakeAPIClient.ok
    }
    let initial = TaskDraft(task: nil)
    var draft = initial
    draft.title = "Nova"
    draft.setDay("2026-09-22")
    draft.setTime("14:30")
    draft.pinShape = .heart
    #expect(await harness.store.save(draft, initial: initial, editing: nil) == .saved)
    #expect(
      harness.client.writes.map(\.description) == [
        #"POST /api/tasks {"due":"2026-09-22 14:30","priority":"normal","title":"Nova"}"#,
        #"PATCH /api/tasks/new-id/board {"paper":null,"pin":null,"pinShape":"heart"}"#,
      ])
  }

  @Test func theServersMessageIsShownAsReturned() async {
    let harness = Harness([])
    harness.failWrites("data inválida: 2026-02-30")
    var draft = TaskDraft(task: nil)
    draft.title = "X"
    draft.setDay("2026-02-30")
    #expect(
      await harness.store.save(draft, initial: TaskDraft(task: nil), editing: nil)
        == .failed("data inválida: 2026-02-30"))
    #expect(harness.client.writes.count == 1)
  }

  @Test func aColourFailureAfterSavingIsReportedApart() async {
    let task = makeTask("t1")
    let harness = Harness([task])
    harness.serve(state: makeState([task])) { call throws(APIError) in
      if call.path.hasSuffix("/board") {
        throw .server(status: 502, message: "banco indisponível", code: nil, retry: nil)
      }
      return FakeAPIClient.ok
    }
    let initial = TaskDraft(task: task)
    var draft = initial
    draft.pin = .blue
    #expect(
      await harness.store.save(draft, initial: initial, editing: task) == .savedWithoutStyle("banco indisponível"))
    #expect(harness.store.actionError == "A tarefa foi salva, mas a cor não: banco indisponível")
  }

  @Test func aFailedEditRollsBackTheTitle() async {
    let task = makeTask("t1", title: "Antigo")
    let harness = Harness([task])
    harness.failWrites("título inválido")
    var draft = TaskDraft(task: task)
    draft.title = "Novo"
    #expect(
      await harness.store.save(draft, initial: TaskDraft(task: task), editing: task) == .failed("título inválido"))
    #expect(harness.tasks[0].title == "Antigo")
  }

  // MARK: Subtasks

  @Test func subtaskActions() async {
    let subtask = SubTask(id: "s1", title: "Passo", completed: false)
    let harness = Harness([makeTask("t1", subtasks: [subtask])])
    let task = harness.tasks[0]
    await harness.store.toggleSubtask(subtask, of: task)
    await harness.store.renameSubtask(subtask, of: task, to: " Outro ")
    await harness.store.renameSubtask(subtask, of: task, to: "  ")
    #expect(await harness.store.addSubtask(to: task, title: " Novo "))
    await harness.store.deleteSubtask(subtask, of: task)
    #expect(
      harness.client.writes.map(\.description) == [
        #"PATCH /api/tasks/t1/subtasks/s1 {"completed":true}"#,
        #"PATCH /api/tasks/t1/subtasks/s1 {"title":"Outro"}"#,
        #"POST /api/tasks/t1/subtasks {"title":"Novo"}"#,
        "DELETE /api/tasks/t1/subtasks/s1 -",
      ])
  }

  @Test func subtaskToggleIsOptimisticAndRollsBack() async {
    let subtask = SubTask(id: "s1", title: "Passo", completed: false)
    let harness = Harness([makeTask("t1", subtasks: [subtask])])
    let gate = Gate()
    harness.serve(state: makeState([makeTask("t1", subtasks: [subtask])])) { _ throws(APIError) in
      await gate.wait()
      throw .server(status: 502, message: "falhou", code: nil, retry: nil)
    }
    let running = Task { await harness.store.toggleSubtask(subtask, of: harness.tasks[0]) }
    await settle()
    #expect(harness.tasks[0].subtasks[0].completed)
    gate.open()
    await running.value
    #expect(!harness.tasks[0].subtasks[0].completed)
  }

  // MARK: Filters

  @Test func filtersMirrorThePanel() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let today = TaskGrouping.localISO(now)
    let harness = Harness(
      [
        makeTask("a", title: "Revisão", due: today, priority: .high),
        makeTask("b", title: "Daily", completed: true, due: today),
        makeTask("c", title: "Sem data", priority: .low),
      ], view: .list, now: now)
    let store = harness.store
    #expect(store.listGroups(today: now).flatMap(\.tasks).map(\.id) == ["a", "c"])
    // The board always shows "Feito".
    #expect(store.boardTasks(today: now).map(\.id) == ["a", "b", "c"])
    store.showCompleted = true
    #expect(store.listGroups(today: now).flatMap(\.tasks).map(\.id) == ["a", "b", "c"])
    store.query = "revisao"
    #expect(store.visibleCount(today: now) == 1)
    store.togglePriority(.low)
    #expect(store.visibleCount(today: now) == 0)
    store.query = ""
    store.toggleWindow(.noDate)
    #expect(store.listGroups(today: now).flatMap(\.tasks).map(\.id) == ["c"])
    #expect(store.activeFilters.map(\.label) == ["Baixa", "SEM DATA"])
    #expect(store.availableWindows(today: now) == [.today, .noDate])
    store.clearFilters()
    #expect(store.activeFilters.isEmpty)
  }

  @Test func theViewDefaultsToTheBoard() {
    let harness = Harness([], view: TasksView(rawValue: "grid"))
    #expect(harness.store.view == .board)
  }

  // MARK: View

  @Test func choosingTheViewIsSavedAndRolledBackOnFailure() async throws {
    let harness = Harness([], view: .board)
    let defaults = try #require(UserDefaults(suiteName: "FeatureTasksTests.view"))
    let preferences = PreferencesStore(
      client: harness.client, dashboard: harness.dashboard, toasts: harness.toasts, defaults: defaults)
    let store = TasksStore(client: harness.client, dashboard: harness.dashboard, preferences: preferences)
    harness.serve(state: makeState([], view: .list)) { _ in Data(#"{"tasksView":"list"}"#.utf8) }
    await store.choose(.list)
    #expect(store.view == .list)
    #expect(harness.client.writes.map(\.description) == [#"PATCH /api/preferences {"tasksView":"list"}"#])

    harness.failWrites("erro ao guardar")
    await store.choose(.board)
    #expect(store.view == .list)
  }
}
