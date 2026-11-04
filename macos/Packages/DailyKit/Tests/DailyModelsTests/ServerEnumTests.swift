import Foundation
import Testing

@testable import DailyModels

@Suite struct ServerEnumTests {
  @Test func encodesAsABareString() throws {
    let data = try JSONEncoder().encode([PullReview.changesRequested])
    #expect(String(decoding: data, as: UTF8.self) == #"["changes-requested"]"#)
  }

  @Test func knownValueDecodesToItsConstant() throws {
    #expect(try Fixture.decode(AgentTaskStatus.self, json: #""blocked""#) == .blocked)
    #expect(AgentTaskStatus.blocked.isKnown)
  }

  @Test(arguments: [
    #"{"id":"n1","source":"teams","title":"t","url":"","read":false,"date":""}"#
  ])
  func unknownNotificationSourceDecodes(_ json: String) throws {
    let item = try Fixture.decode(NotificationItem.self, json: json)
    #expect(item.source.rawValue == "teams")
    #expect(!item.source.isKnown)
  }

  @Test func unknownValuesInsideAStateDecodeAndRoundTrip() throws {
    var object = try #require(
      try JSONSerialization.jsonObject(with: Fixture.data("dashboard-state-full.json")) as? [String: Any]
    )
    object["modules"] = ["email", "calendar-v2"]
    object["tasksView"] = "timeline"
    var pomodoro = try #require(object["pomodoro"] as? [String: Any])
    pomodoro["phase"] = "long-rest"
    object["pomodoro"] = pomodoro

    let data = try JSONSerialization.data(withJSONObject: object)
    let state = try JSONDecoder().decode(DashboardState.self, from: data)

    #expect(state.modules == [.email, ModuleID(rawValue: "calendar-v2")])
    #expect(state.tasksView.rawValue == "timeline" && !state.tasksView.isKnown)
    #expect(state.pomodoro.phase.rawValue == "long-rest" && !state.pomodoro.phase.isKnown)
    #expect(try JSONDecoder().decode(DashboardState.self, from: JSONEncoder().encode(state)) == state)
  }

  @Test func unknownAgentValuesDecode() throws {
    let json = #"""
      {"id":"t","parentTaskId":null,"externalId":"e","title":"x","description":"","status":"paused",
       "hold":{"reason":"vacation","note":null},"assignment":null,
       "source":{"provider":"gitlab","resource":"g/r#1"},"version":1,"createdAt":"","lastActivityAt":""}
      """#
    let task = try Fixture.decode(AgentTask.self, json: json)
    #expect(task.status.rawValue == "paused" && !task.status.isKnown)
    #expect(task.hold?.reason.rawValue == "vacation")
    #expect(task.source?.provider.rawValue == "gitlab")
  }

  @Test func unknownTerminalReasonDecodes() throws {
    let terminal = try Fixture.decode(AgentTerminal.self, json: #"{"available":false,"reason":"sleeping"}"#)
    #expect(terminal == .unavailable(AgentTerminalUnavailableReason(rawValue: "sleeping")))
  }

  @Test func unknownJiraValuesDecode() throws {
    var object = try #require(
      try JSONSerialization.jsonObject(with: Fixture.data("jira-person-view.json")) as? [String: Any]
    )
    var problems = try #require(object["problems"] as? [String: Any])
    var items = try #require(problems["data"] as? [[String: Any]])
    items[0]["problems"] = ["story-without-owner"]
    items[0]["statusCategory"] = "undefined"
    items[0]["flag"] = "blocker"
    problems["data"] = items
    object["problems"] = problems

    let view = try JSONDecoder().decode(JiraPersonView.self, from: JSONSerialization.data(withJSONObject: object))
    let item = try #require(view.problems.data?.first)
    #expect(item.problems.map(\.rawValue) == ["story-without-owner"])
    #expect(!item.statusCategory.isKnown)
    #expect(item.flag.rawValue == "blocker")
  }
}
