import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// One task's page (`components/agents/TaskDetail.tsx`) and its actions
/// (`TaskActions.tsx`). The board store polls it while it is open.
@Observable
final class AgentTaskDetailStore {
  let taskID: String
  private(set) var detail: AgentTaskDetail?
  private(set) var error: String?
  /// Activity page (`cursor`); nil is the newest page.
  private(set) var activityCursor: String?
  private(set) var subtaskCursor: String?

  private(set) var isSaving = false
  /// The last failed action, shown under the buttons (`TaskActions.tsx:33`).
  private(set) var actionError: String?

  /// The terminal of the task's session, when it has one.
  private(set) var live: AgentLiveStore?

  /// Starts the live panel once a session is known; the board store mirrors
  /// the screen's visibility here.
  var isVisible = false {
    didSet {
      guard isVisible != oldValue else { return }
      if isVisible { live?.start() } else { live?.stop() }
    }
  }

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let poller: Poller
  @ObservationIgnored let now: Now
  @ObservationIgnored private let onDeleted: @MainActor () -> Void
  @ObservationIgnored private var generation = 0

  init(
    taskID: String,
    client: any APIClient,
    poller: Poller,
    now: @escaping Now,
    onDeleted: @escaping @MainActor () -> Void
  ) {
    self.taskID = taskID
    self.client = client
    self.poller = poller
    self.now = now
    self.onDeleted = onDeleted
  }

  var task: AgentTask? { detail?.task }

  // MARK: - Loading

  func load() async {
    generation += 1
    let current = generation
    let endpoint = AgentsEndpoints.task(id: taskID, activityCursor: activityCursor, subtaskCursor: subtaskCursor)
    do {
      let next = try await client.send(endpoint)
      guard current == generation else { return }
      detail = next
      error = nil
      updateLive(sessionID: next.task.assignment?.sessionId)
    } catch {
      guard current == generation else { return }
      Logger.agents.error("Task detail load failed: \(String(describing: error), privacy: .public)")
      if AgentsLogic.dropsData(error) {
        detail = nil
        updateLive(sessionID: nil)
      }
      self.error = AgentsLogic.pollMessage(error)
    }
  }

  func setActivityCursor(_ cursor: String?) {
    activityCursor = cursor
    Task { await load() }
  }

  func setSubtaskCursor(_ cursor: String?) {
    subtaskCursor = cursor
    Task { await load() }
  }

  private func updateLive(sessionID: String?) {
    guard live?.sessionID != sessionID else { return }
    live?.stop()
    guard let sessionID else {
      live = nil
      return
    }
    let store = AgentLiveStore(sessionID: sessionID, client: client, poller: poller)
    live = store
    if isVisible { store.start() }
  }

  /// Stops the live panel when the detail closes.
  func close() {
    live?.stop()
  }

  // MARK: - Actions

  /// The statuses the task can move to now (`transitions[task.status]`).
  var availableTransitions: [AgentTaskStatus] {
    task.map { AgentsLogic.transitions(from: $0.status) } ?? []
  }

  /// A transition without a hold, or with the hold from the reason dialog.
  /// Returns true when it went through.
  @discardableResult
  func transition(to status: AgentTaskStatus, hold: AgentTaskHold? = nil) async -> Bool {
    guard let task else { return false }
    let body = AgentsEndpoints.TransitionBody(status: status, hold: hold, expectedVersion: task.version)
    return await change { [client, taskID] () async throws(APIError) in
      _ = try await client.send(AgentsEndpoints.transition(id: taskID, body))
    }
  }

  /// `version` is the one the edit started from, so a poll that lands while
  /// the dialog is open does not hide a conflict (`TaskActions.tsx:21`, `:32`).
  @discardableResult
  func edit(title: String, description: String, version: Int) async -> Bool {
    let body = AgentsEndpoints.EditBody(
      title: String(title.prefix(AgentsLogic.titleMax)),
      description: String(description.prefix(AgentsLogic.descriptionMax)),
      expectedVersion: version)
    return await change { [client, taskID] () async throws(APIError) in
      _ = try await client.send(AgentsEndpoints.edit(id: taskID, body))
    }
  }

  @discardableResult
  func delete() async -> Bool {
    let deleted = await change(reload: false) { [client, taskID] () async throws(APIError) in
      _ = try await client.send(AgentsEndpoints.delete(id: taskID))
    }
    if deleted {
      close()
      onDeleted()
    }
    return deleted
  }

  func clearActionError() { actionError = nil }

  /// Runs one write. A 409 means the task moved on (another tab, the agent):
  /// the page reloads so the next try uses the new version.
  private func change(reload: Bool = true, _ send: () async throws(APIError) -> Void) async -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    actionError = nil
    defer { isSaving = false }
    do {
      try await send()
    } catch {
      Logger.agents.error("Task change failed: \(String(describing: error), privacy: .public)")
      actionError = AgentsLogic.changeMessage(error)
      if case .server(409, _, _, _) = error { await load() }
      return false
    }
    if reload { await load() }
    return true
  }
}
