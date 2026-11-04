import DailyAPI
import DailyModels
import Testing

@testable import FeatureTasks

@Suite struct TasksEndpointsTests {
  private func describe<T>(_ endpoint: Endpoint<T>) -> String {
    "\(endpoint.method.rawValue) \(endpoint.path) \(FakeAPIClient.encode(endpoint.body) ?? "-")"
  }

  @Test func everyEndpoint() {
    #expect(
      describe(TasksEndpoints.create(.init(title: "A", status: "doing")))
        == #"POST /api/tasks {"status":"doing","title":"A"}"#)
    #expect(describe(TasksEndpoints.setCompleted(id: "t1", true)) == #"PATCH /api/tasks/t1 {"completed":true}"#)
    #expect(
      describe(TasksEndpoints.edit(id: "t1", .init(title: "B", due: "hoje", priority: .low, recur: "none")))
        == #"PATCH /api/tasks/t1 {"due":"hoje","priority":"low","recur":"none","title":"B"}"#)
    #expect(describe(TasksEndpoints.delete(id: "t1")) == "DELETE /api/tasks/t1 -")
    #expect(describe(TasksEndpoints.setStatus(id: "t1", .doing)) == #"PATCH /api/tasks/t1/board {"status":"doing"}"#)
    #expect(
      describe(TasksEndpoints.addSubtask(taskID: "t1", title: "s"))
        == #"POST /api/tasks/t1/subtasks {"title":"s"}"#)
    #expect(
      describe(TasksEndpoints.updateSubtask(taskID: "t1", itemID: "s1", .init(completed: false)))
        == #"PATCH /api/tasks/t1/subtasks/s1 {"completed":false}"#)
    #expect(
      describe(TasksEndpoints.updateSubtask(taskID: "t1", itemID: "s1", .init(title: "novo")))
        == #"PATCH /api/tasks/t1/subtasks/s1 {"title":"novo"}"#)
    #expect(describe(TasksEndpoints.deleteSubtask(taskID: "t1", itemID: "s1")) == "DELETE /api/tasks/t1/subtasks/s1 -")
  }

  @Test func styleSendsOnlyTheKeysPickedWithExplicitNull() {
    #expect(
      describe(TasksEndpoints.setStyle(id: "t1", NoteStylePatch(paper: .some(nil))))
        == #"PATCH /api/tasks/t1/board {"paper":null}"#)
    #expect(
      describe(TasksEndpoints.setStyle(id: "t1", NoteStylePatch(pin: .some(.red))))
        == #"PATCH /api/tasks/t1/board {"pin":"red"}"#)
    #expect(
      describe(TasksEndpoints.setStyle(id: "t1", .full(paper: .blue, pin: nil, pinShape: .heart)))
        == #"PATCH /api/tasks/t1/board {"paper":"blue","pin":null,"pinShape":"heart"}"#)
  }

  @Test func idsArePercentEncoded() {
    #expect(TasksEndpoints.delete(id: "AQMk+ADAw/abc==").path == "/api/tasks/AQMk%2BADAw%2Fabc%3D%3D")
    #expect(
      TasksEndpoints.deleteSubtask(taskID: "a/b", itemID: "c=").path == "/api/tasks/a%2Fb/subtasks/c%3D")
  }
}
