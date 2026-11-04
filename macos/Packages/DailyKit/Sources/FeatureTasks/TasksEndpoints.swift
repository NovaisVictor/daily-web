import DailyAPI
import DailyModels
import Foundation

/// `app/api/tasks/**`. The server parses `due` itself (`lib/dateParsing.ts`)
/// and answers a ready-to-show message when it cannot.
nonisolated enum TasksEndpoints {
  /// `POST /api/tasks`. Absent keys are left out of the JSON, as the web does.
  struct CreateBody: Encodable, Sendable, Equatable {
    var title: String
    var due: String?
    var priority: TaskPriority?
    var recur: String?
    var status: String?
  }

  struct CompletedBody: Encodable, Sendable, Equatable {
    var completed: Bool
  }

  /// `PATCH /api/tasks/{id}` from the form: every field, as `TaskFormModal` sends it.
  struct EditBody: Encodable, Sendable, Equatable {
    var title: String
    var due: String
    var priority: TaskPriority
    var recur: String
  }

  struct StatusBody: Encodable, Sendable, Equatable {
    var status: String
  }

  /// Writes only the keys the patch carries, with an explicit `null` for
  /// "automatic": the route tells "absent" from "null" (`board/route.ts:24-41`).
  struct StyleBody: Encodable, Sendable, Equatable {
    var patch: NoteStylePatch

    private enum Keys: String, CodingKey { case paper, pin, pinShape }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      if case .some(let value) = patch.paper { try container.encode(value, forKey: .paper) }
      if case .some(let value) = patch.pin { try container.encode(value, forKey: .pin) }
      if case .some(let value) = patch.pinShape { try container.encode(value, forKey: .pinShape) }
    }
  }

  struct TitleBody: Encodable, Sendable, Equatable {
    var title: String
  }

  struct SubtaskBody: Encodable, Sendable, Equatable {
    var completed: Bool?
    var title: String?
  }

  static func create(_ body: CreateBody) -> Endpoint<CreatedTaskResponse> {
    Endpoint(.post, "/api/tasks", body: body)
  }

  static func setCompleted(id: String, _ completed: Bool) -> Endpoint<EmptyResponse> {
    Endpoint(.patch, taskPath(id), body: CompletedBody(completed: completed))
  }

  static func edit(id: String, _ body: EditBody) -> Endpoint<EmptyResponse> {
    Endpoint(.patch, taskPath(id), body: body)
  }

  static func delete(id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, taskPath(id))
  }

  /// Only "todo" and "doing": completing goes through `setCompleted`.
  static func setStatus(id: String, _ column: BoardColumn) -> Endpoint<EmptyResponse> {
    Endpoint(.patch, taskPath(id) + "/board", body: StatusBody(status: column.rawValue))
  }

  static func setStyle(id: String, _ patch: NoteStylePatch) -> Endpoint<TaskBoardResponse> {
    Endpoint(.patch, taskPath(id) + "/board", body: StyleBody(patch: patch))
  }

  static func addSubtask(taskID: String, title: String) -> Endpoint<EmptyResponse> {
    Endpoint(.post, taskPath(taskID) + "/subtasks", body: TitleBody(title: title))
  }

  static func updateSubtask(taskID: String, itemID: String, _ body: SubtaskBody) -> Endpoint<EmptyResponse> {
    Endpoint(.patch, subtaskPath(taskID, itemID), body: body)
  }

  static func deleteSubtask(taskID: String, itemID: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, subtaskPath(taskID, itemID))
  }

  private static func taskPath(_ id: String) -> String {
    "/api/tasks/\(Endpoint<EmptyResponse>.segment(id))"
  }

  private static func subtaskPath(_ taskID: String, _ itemID: String) -> String {
    taskPath(taskID) + "/subtasks/\(Endpoint<EmptyResponse>.segment(itemID))"
  }
}
