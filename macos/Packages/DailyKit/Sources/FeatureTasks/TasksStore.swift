import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import SwiftUI

/// A filter shown as a removable badge (`ActiveFilters`).
struct ActiveFilter: Identifiable, Equatable {
  enum Kind: Equatable { case query, priority, window }
  let id: Kind
  let label: String
}

/// How the task form's save ended.
enum TaskSaveOutcome: Equatable {
  case saved
  /// The task was saved; only its note colour was not.
  case savedWithoutStyle(String)
  case failed(String)
}

/// State and actions of the tasks screen (`components/TasksPanel.tsx`). The
/// tasks live in the shared dashboard state; every write goes through
/// `DashboardStore.mutate`, then the state is read again so the server's own
/// result (a recurring task's next date, a parsed due date) shows at once
/// instead of on the next poll.
@Observable
final class TasksStore {
  // MARK: Filters (`TasksPanel.tsx:146-153`)

  var query = ""
  var priorityFilter: TaskPriority?
  var window: TaskGroupKey?
  /// Done tasks are noise day to day; the list hides them unless asked.
  var showCompleted = false

  /// The one message the panel shows inline: the form saved the task but not its colour.
  var actionError: String?

  @ObservationIgnored let client: any APIClient
  @ObservationIgnored let dashboard: DashboardStore
  @ObservationIgnored let preferences: PreferencesStore?
  @ObservationIgnored let focus: FocusScheduler?
  @ObservationIgnored let now: Now
  @ObservationIgnored private let announce: (String) -> Void

  init(
    client: any APIClient,
    dashboard: DashboardStore,
    preferences: PreferencesStore? = nil,
    focus: FocusScheduler? = nil,
    now: @escaping Now = LiveTime.now,
    announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
  ) {
    self.client = client
    self.dashboard = dashboard
    self.preferences = preferences
    self.focus = focus
    self.now = now
    self.announce = announce
  }

  /// `FeatureStores` key: the screen and the Início panel share one store.
  static let storeKey = "tasks"

  /// The session's store, made on first use.
  static func shared(in environment: AppEnvironment) -> TasksStore {
    environment.featureStores.store(storeKey) { TasksStore(environment: environment) }
  }

  convenience init(environment: AppEnvironment) {
    self.init(
      client: environment.client,
      dashboard: environment.dashboard,
      preferences: environment.preferences,
      focus: environment.focus
    )
  }

  // MARK: - Reading

  var panel: PanelResult<[TodoTask]>? { dashboard.state?.tasks }
  var all: [TodoTask] { panel?.data ?? [] }

  /// The board is the default: it does everything the list does.
  var view: TasksView {
    dashboard.state?.tasksView == .list ? .list : .board
  }

  /// Calendars the agenda reads; with none, "agendar foco" is hidden as on the web.
  var calendars: [AgendaCalendarRef] { dashboard.state?.agendaCalendars ?? [] }
  var focusEnabled: Bool { !calendars.isEmpty }

  func task(id: String) -> TodoTask? { all.first { $0.id == id } }

  private func matchesBase(_ task: TodoTask) -> Bool {
    TaskText.matches(task.title, query: query) && (priorityFilter == nil || task.priority == priorityFilter)
  }

  func listGroups(today: Date) -> [TaskGroup] {
    let filtered = all.filter { matchesBase($0) && (showCompleted || !$0.completed) }
    let grouped = TaskGrouping.group(filtered, today: today)
    guard let window else { return grouped }
    return grouped.filter { $0.key == window }
  }

  /// The board always shows "Feito"; the window order carries into each column.
  func boardTasks(today: Date) -> [TodoTask] {
    TaskGrouping.group(all.filter(matchesBase), today: today)
      .filter { window == nil || $0.key == window }
      .flatMap(\.tasks)
  }

  /// The window chips: every window that has a task, before any filter.
  func availableWindows(today: Date) -> [TaskGroupKey] {
    TaskGrouping.group(all, today: today).map(\.key)
  }

  func visibleCount(today: Date) -> Int {
    view == .board
      ? boardTasks(today: today).count
      : listGroups(today: today).reduce(0) { $0 + $1.tasks.count }
  }

  var activeFilters: [ActiveFilter] {
    var filters: [ActiveFilter] = []
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !term.isEmpty { filters.append(ActiveFilter(id: .query, label: "Busca: \(term)")) }
    if let priorityFilter {
      filters.append(ActiveFilter(id: .priority, label: TaskText.priorityLabel(priorityFilter)))
    }
    if let window { filters.append(ActiveFilter(id: .window, label: window.label)) }
    return filters
  }

  func clear(_ filter: ActiveFilter.Kind) {
    switch filter {
    case .query: query = ""
    case .priority: priorityFilter = nil
    case .window: window = nil
    }
  }

  func clearFilters() {
    query = ""
    priorityFilter = nil
    window = nil
  }

  func togglePriority(_ priority: TaskPriority) {
    priorityFilter = priorityFilter == priority ? nil : priority
  }

  func toggleWindow(_ key: TaskGroupKey) {
    window = window == key ? nil : key
  }

  // MARK: - View

  /// Saved through `PATCH /api/preferences`, optimistic like every write.
  func choose(_ next: TasksView) async {
    guard next != view, let preferences else { return }
    actionError = nil
    await preferences.setTasksView(next)
  }

  // MARK: - Tasks

  /// The checkbox. A recurring task is not marked ahead of the server: it rolls
  /// over to its next date instead, and a "done" flash would be a lie.
  @discardableResult
  func toggleComplete(_ task: TodoTask) async -> APIError? {
    let completed = !task.completed
    let recurring = !task.recur.isEmpty
    let id = task.id
    let client = self.client
    actionError = nil
    let error = await dashboard.mutate { state in
      if !recurring { Self.setCompleted(&state, id: id, completed) }
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.setCompleted(id: id, completed))
    }
    await dashboard.reload()
    return error
  }

  /// Moves a card between columns; true when every request went through.
  @discardableResult
  func move(_ task: TodoTask, to column: BoardColumn) async -> Bool {
    let steps = TaskBoard.planMove(task, to: column)
    guard !steps.isEmpty else { return true }
    let recurring = !task.recur.isEmpty
    let id = task.id
    let client = self.client
    actionError = nil
    let error = await dashboard.mutate { state in
      for step in steps {
        switch step {
        case .status(let to): Self.setDoing(&state, id: id, to == .doing)
        case .complete(let completed):
          if !(completed && recurring) { Self.setCompleted(&state, id: id, completed) }
        }
      }
    } commit: { () async throws(APIError) in
      for step in steps {
        switch step {
        case .complete(let completed): _ = try await client.send(TasksEndpoints.setCompleted(id: id, completed))
        case .status(let to): _ = try await client.send(TasksEndpoints.setStatus(id: id, to))
        }
      }
    }
    if let error {
      announce("Não foi possível mover \(task.title): \(error.userMessage)")
    } else if column == .done, recurring, !task.due.isEmpty {
      announce("\(task.title) concluída. Ela repete, então volta para A fazer com a próxima data.")
    } else {
      announce("\(task.title) movida para \(column.label).")
    }
    await dashboard.reload()
    return error == nil
  }

  /// One pick of paper, pin or shape, saved at once. The route corrects the
  /// server's cache itself, so success needs no reload.
  func changeStyle(_ task: TodoTask, _ patch: NoteStylePatch) async {
    let id = task.id
    let client = self.client
    actionError = nil
    let error = await dashboard.mutate { state in
      Self.mapTask(&state, id: id) { patch.applied(to: $0) }
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.setStyle(id: id, patch))
    }
    if let error {
      announce("Não foi possível mudar a cor de \(task.title): \(error.userMessage)")
      await dashboard.reload()
    } else {
      announce("\(patch.description) em \(task.title).")
    }
  }

  /// "+ Adicionar" at the foot of a column: one request even for "Fazendo",
  /// so a failure never leaves the task in the wrong column.
  @discardableResult
  func quickCreate(title: String, in column: BoardColumn) async -> Bool {
    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, column != .done else { return false }
    let client = self.client
    actionError = nil
    let error = await dashboard.mutate { _ in
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.create(.init(title: value, status: column.rawValue)))
    }
    if let error {
      announce("Não foi possível adicionar \(value): \(error.userMessage)")
      return false
    }
    announce("\(value) adicionada em \(column.label).")
    await dashboard.reload()
    return true
  }

  /// Deletes after the caller confirmed. Optimistic: the task leaves at once
  /// and comes back if the server refuses.
  @discardableResult
  func delete(_ task: TodoTask) async -> APIError? {
    let id = task.id
    let client = self.client
    actionError = nil
    let error = await dashboard.mutate { state in
      Self.mapTasks(&state) { $0.filter { $0.id != id } }
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.delete(id: id))
    }
    await dashboard.reload()
    return error
  }

  /// The form's "Salvar" (`TaskFormModal.tsx:200-260`). The colour is a
  /// second request after the task is saved: it lives in this app's database
  /// while the task may live in Microsoft To Do.
  func save(_ draft: TaskDraft, initial: TaskDraft, editing task: TodoTask?) async -> TaskSaveOutcome {
    let client = self.client
    actionError = nil
    var savedID = task?.id
    let error: APIError?
    if let task {
      let body = draft.editBody
      let id = task.id
      error = await dashboard.mutate { state in
        Self.mapTask(&state, id: id) { current in
          var next = current
          next.title = body.title
          next.priority = body.priority
          next.recur = body.recur == TaskRecur.none.rawValue ? "" : body.recur
          return next
        }
      } commit: { () async throws(APIError) in
        _ = try await client.send(TasksEndpoints.edit(id: id, body))
      }
    } else {
      let body = draft.createBody
      error = await dashboard.mutate { _ in
      } commit: { () async throws(APIError) in
        savedID = try await client.send(TasksEndpoints.create(body)).id
      }
    }
    if let error { return .failed(error.userMessage) }

    var outcome = TaskSaveOutcome.saved
    if draft.styleChanged(from: initial), let id = savedID {
      let patch = draft.style
      let styleError = await dashboard.mutate { state in
        Self.mapTask(&state, id: id) { patch.applied(to: $0) }
      } commit: { () async throws(APIError) in
        _ = try await client.send(TasksEndpoints.setStyle(id: id, patch))
      }
      if let styleError {
        outcome = .savedWithoutStyle(styleError.userMessage)
        actionError = "A tarefa foi salva, mas a cor não: \(styleError.userMessage)"
      }
    }
    await dashboard.reload()
    return outcome
  }

  // MARK: - Subtasks (`components/tasks/SubtaskList.tsx`)

  func toggleSubtask(_ subtask: SubTask, of task: TodoTask) async {
    let completed = !subtask.completed
    await writeSubtask(task, subtask, body: .init(completed: completed)) { $0.completed = completed }
  }

  /// Renaming has no button on the web, but the route takes a title; an empty
  /// one is ignored by the server, so it is not sent.
  func renameSubtask(_ subtask: SubTask, of task: TodoTask, to title: String) async {
    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value != subtask.title else { return }
    await writeSubtask(task, subtask, body: .init(title: value)) { $0.title = value }
  }

  @discardableResult
  func addSubtask(to task: TodoTask, title: String) async -> Bool {
    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return false }
    let id = task.id
    let client = self.client
    actionError = nil
    let error = await dashboard.mutate { _ in
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.addSubtask(taskID: id, title: value))
    }
    guard error == nil else { return false }
    await dashboard.reload()
    return true
  }

  func deleteSubtask(_ subtask: SubTask, of task: TodoTask) async {
    let taskID = task.id
    let itemID = subtask.id
    let client = self.client
    actionError = nil
    await dashboard.mutate { state in
      Self.mapTask(&state, id: taskID) { current in
        var next = current
        next.subtasks.removeAll { $0.id == itemID }
        return next
      }
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.deleteSubtask(taskID: taskID, itemID: itemID))
    }
    await dashboard.reload()
  }

  private func writeSubtask(
    _ task: TodoTask,
    _ subtask: SubTask,
    body: TasksEndpoints.SubtaskBody,
    change: @escaping (inout SubTask) -> Void
  ) async {
    let taskID = task.id
    let itemID = subtask.id
    let client = self.client
    actionError = nil
    await dashboard.mutate { state in
      Self.mapTask(&state, id: taskID) { current in
        var next = current
        if let index = next.subtasks.firstIndex(where: { $0.id == itemID }) { change(&next.subtasks[index]) }
        return next
      }
    } commit: { () async throws(APIError) in
      _ = try await client.send(TasksEndpoints.updateSubtask(taskID: taskID, itemID: itemID, body))
    }
    await dashboard.reload()
  }

  // MARK: - Focus

  func scheduleFocus(_ source: FocusSource, connectionId: String, start: Date, minutes: Int) async
    -> FocusScheduleResult
  {
    guard let focus else {
      return .invalid("Não foi possível criar o bloco de foco.")
    }
    return await focus.schedule(source, connectionId: connectionId, start: start, minutes: minutes)
  }

  // MARK: - State patches (`lib/statePatches.ts`)

  static func mapTasks(_ state: inout DashboardState, _ transform: ([TodoTask]) -> [TodoTask]) {
    guard let list = state.tasks.data else { return }
    state.tasks.data = transform(list)
  }

  static func mapTask(_ state: inout DashboardState, id: String, _ transform: (TodoTask) -> TodoTask) {
    mapTasks(&state) { list in list.map { $0.id == id ? transform($0) : $0 } }
  }

  /// Completing ends "Fazendo" on the server too (`setTaskCompleted`).
  static func setCompleted(_ state: inout DashboardState, id: String, _ completed: Bool) {
    mapTask(&state, id: id) { task in
      var next = task
      next.completed = completed
      if completed { next.doing = false }
      return next
    }
  }

  static func setDoing(_ state: inout DashboardState, id: String, _ doing: Bool) {
    mapTask(&state, id: id) { task in
      var next = task
      next.doing = doing
      return next
    }
  }
}
