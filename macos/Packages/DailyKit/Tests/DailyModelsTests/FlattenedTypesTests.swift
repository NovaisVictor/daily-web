import Foundation
import Testing

@testable import DailyModels

/// Types the server builds by extending or unioning another, which the models
/// decode by hand.
@Suite struct FlattenedTypesTests {
  @Test func datedItemReadsTheItemAndTodayFromOneObject() throws {
    let view = try Fixture.decode(JiraPersonView.self, "jira-person-view.json")
    let delivered = try #require(view.delivered.data?.first)

    #expect(delivered.today)
    #expect(delivered.item.key == "DEMO-139")
    #expect(delivered.statusCategory == .done)
    #expect(delivered.id == "DEMO-139")
  }

  @Test func datedItemEncodesFlat() throws {
    let state = try Fixture.decode(DashboardState.self, "dashboard-state-full.json")
    let item = try #require(state.jiraDelivered.data?.first)
    let object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
    )

    #expect(object["today"] as? Bool == true)
    #expect(object["key"] as? String == "DEMO-139")
    #expect(object["item"] == nil)
  }

  @Test func availableTerminalCarriesTheSnapshot() throws {
    let terminal = try Fixture.decode(AgentTerminal.self, "agent-terminal-available.json")
    guard case .available(let snapshot) = terminal else {
      Issue.record("expected an available terminal")
      return
    }
    #expect(snapshot.live.state == .prompt)
    #expect(snapshot.live.since == nil)
    #expect(snapshot.response?.content == "Pronto: os testes passam.")
  }

  @Test func unavailableTerminalCarriesTheReason() throws {
    let terminal = try Fixture.decode(AgentTerminal.self, "agent-terminal-unavailable.json")
    #expect(terminal == .unavailable(.notLocal))
  }

  @Test func startDateSuggestionsKeepEachBranch() throws {
    let response = try Fixture.decode(JiraStartDateSuggestionsResponse.self, "jira-start-date-suggestions.json")

    #expect(response.suggestions[0].status == .suggested)
    #expect(response.suggestions[0].basis == .created)
    #expect(response.suggestions[1].status == .failed)
    #expect(response.suggestions[1].error == "issue não encontrada")
  }

  @Test func boardCountsAndCatalogLookups() throws {
    let board = try Fixture.decode(AgentsBoard.self, "agents-board.json")
    #expect(board.count(of: .completed) == 4)
    #expect(board.count(of: AgentTaskStatus(rawValue: "paused")) == 0)
    #expect(board.sessions.items[1].live == nil)

    let integrations = try Fixture.decode(IntegrationsPayload.self, "integrations.json")
    #expect(integrations.spec(for: .tasks)?.alwaysAvailable == true)
    #expect(integrations.spec(for: .email)?.fields.first?.options?.count == 2)
    #expect(integrations.spec(for: .slack) == nil)
  }
}
