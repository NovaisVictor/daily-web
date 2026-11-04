import DailyAPI
import DailyCore
import DailyModels
import Foundation

@testable import FeatureTasks

func makeTask(
  _ id: String = "x",
  title: String = "t",
  completed: Bool = false,
  due: String = "",
  priority: TaskPriority = .normal,
  time: String = "",
  recur: String = "",
  subtasks: [SubTask] = [],
  doing: Bool = false,
  paper: NotePaper? = nil,
  pin: PinColor? = nil,
  pinShape: PinShape? = nil
) -> TodoTask {
  TodoTask(
    id: id, title: title, completed: completed, due: due, priority: priority, time: time, recur: recur, notes: "",
    subtasks: subtasks, doing: doing, paper: paper, pin: pin, pinShape: pinShape)
}

func makeState(_ tasks: [TodoTask], view: TasksView = .board) -> DashboardState {
  var state = PreviewFixtures.dashboard
  state.tasks = PanelResult(data: tasks, error: nil)
  state.tasksView = view
  return state
}

/// Lets every ready main-actor task run.
@MainActor
func settle() async {
  for _ in 0..<200 { await Task.yield() }
}

@MainActor
final class Announcements {
  var items: [String] = []
}

/// A store over a fake client whose `GET /api/state` answers `server`, the
/// state the server holds after the write.
@MainActor
final class Harness {
  let client: FakeAPIClient
  let dashboard: DashboardStore
  let toasts: ToastCenter
  let store: TasksStore
  let announcements = Announcements()

  init(_ tasks: [TodoTask], view: TasksView = .board, now: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
    let client = FakeAPIClient()
    self.client = client
    // Toasts stay up for the whole test so they can be read.
    let toasts = ToastCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    self.toasts = toasts
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    let announcements = self.announcements
    store = TasksStore(client: client, dashboard: dashboard, now: { now }, announce: { announcements.items.append($0) })
    dashboard.apply(makeState(tasks, view: view))
    serve(state: makeState(tasks, view: view))
  }

  var tasks: [TodoTask] { dashboard.state?.tasks.data ?? [] }

  /// Answers writes with `write` and the dashboard read with `state`.
  func serve(
    state: DashboardState,
    write: @escaping @Sendable (FakeAPIClient.Call) async throws(APIError) -> Data = { _ in FakeAPIClient.ok }
  ) {
    let stateData = FakeAPIClient.json(state)
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { return stateData }
      return try await write(call)
    }
  }

  /// The write fails with the server's message and the read fails too, so the
  /// state on screen is exactly what the rollback left.
  func failWrites(_ message: String = "falhou") {
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { throw .offline }
      throw .server(status: 400, message: message, code: nil, retry: nil)
    }
  }
}
