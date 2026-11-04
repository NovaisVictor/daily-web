import Foundation
import Testing

@testable import DailyModels

@Suite struct DashboardStateTests {
  @Test func fullStateHasEveryModuleOnWithData() throws {
    let state = try Fixture.decode(DashboardState.self, "dashboard-state-full.json")

    #expect(Set(state.modules) == Set(ModuleID.known))
    #expect(state.agendaDays == 7)
    #expect(state.tasksView == .board)
    #expect(state.homeView == .workspace)
    #expect(state.nextRefreshAt == "2026-11-04T12:45:00.000Z")
    #expect(state.pomodoro.running)

    #expect(state.email.data?.count == 3)
    #expect(state.email.data?[1].actionError == "a pasta de destino não existe mais")
    #expect(state.email.data?[2].mailbox == .sent)
    #expect(state.agenda.data?.count == 2)
    #expect(state.pulls.data?.items.count == 2)
    #expect(state.pulls.data?.items[1].size == nil)
    #expect(state.pulls.data?.items[1].jira == nil)
    #expect(state.reviewRequests.data?.items.first?.reviewRequestedAt == "2026-11-04T08:00:00Z")
    #expect(state.myPulls.data?.errors == nil)
    #expect(state.jira.data?.count == 2)
    #expect(state.jiraWatched.data?.count == 1)
    #expect(state.jiraDelivered.data?.first?.today == true)
    #expect(state.jiraDelivered.data?.first?.key == "DEMO-139")
    #expect(state.jiraApproved.data?.count == 1)
    #expect(state.jiraProblems.data?.first?.problems == [.storyInProgressWithoutStart, .storyWithoutEpic])
    #expect(state.jiraAncestors.map(\.key) == ["DEMO-100", "DEMO-1"])
    #expect(state.jiraAncestors[1].priority?.rank == nil)
    #expect(state.tasks.data?.first?.paper == .pink)
    #expect(state.tasks.data?[1].paper == nil)
    #expect(state.slack.data?.team == "Acme")
    #expect(state.notifications.data?.map(\.source) == [.jiraMention, .pullRequest, .email, .slack])
  }

  @Test func offStateHasModulesOffAndOneError() throws {
    let state = try Fixture.decode(DashboardState.self, "dashboard-state-off.json")

    #expect(state.modules == [.tasks, .notes])
    #expect(state.email.isOff)
    #expect(state.agenda.isOff)
    #expect(state.pulls.isOff)
    #expect(state.reviewRequests.isOff)
    #expect(state.myPulls.isOff)
    #expect(state.jira.isOff)
    #expect(state.jiraWatched.isOff)
    #expect(state.jiraDelivered.isOff)
    #expect(state.jiraApproved.isOff)
    #expect(state.jiraProblems.isOff)
    #expect(state.slack.isOff)
    #expect(state.nextRefreshAt == nil)

    #expect(!state.tasks.isOff)
    #expect(state.tasks.data == nil)
    #expect(state.tasks.error == "mstodo: comando não encontrado")

    // An empty list is a module that is on with nothing in it, not an off one.
    #expect(!state.notifications.isOff)
    #expect(state.notifications.data == [])
  }

  @Test func twoArgumentInitKeepsEveryPanelOff() {
    let state = DashboardState(updatedAt: "2026-11-04T12:00:00.000Z", modules: [.tasks])

    #expect(state.email.isOff && state.tasks.isOff && state.notifications.isOff)
    #expect(state.agendaDays == 2)
    #expect(state.tasksView == .list)
    #expect(state.pomodoro == .disabled)
    #expect(state.nextRefreshAt == nil)
  }

  @Test func encodedStateKeepsOffPanelsAsExplicitNulls() throws {
    let state = DashboardState(updatedAt: "2026-11-04T12:00:00.000Z", modules: [])
    let object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
    )
    let email = try #require(object["email"] as? [String: Any])

    #expect(email["data"] is NSNull)
    #expect(email["error"] is NSNull)
  }
}
