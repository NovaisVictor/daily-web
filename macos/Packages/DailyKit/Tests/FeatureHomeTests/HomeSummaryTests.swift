import DailyModels
import Foundation
import Testing

@testable import FeatureHome

@Suite struct HomeSummaryTests {
  func summary(_ state: DashboardState) -> HomeSummary {
    HomeSummary(state: state, now: Fixtures.now, calendar: Fixtures.calendar)
  }

  func card(_ module: ModuleID, in state: DashboardState) throws -> HomeCard {
    try #require(summary(state).cards.first { $0.module == module })
  }

  @Test func listsEnabledModulesInTheWebPanelOrder() {
    let cards = summary(Fixtures.full).cards
    #expect(cards.map(\.module) == [.email, .tasks, .notes, .agenda, .jira, .pulls, .slack])
    #expect(!summary(Fixtures.full).nothingOn)
  }

  @Test func skipsModulesThatAreNotOnAndUnknownOnes() {
    var state = Fixtures.full
    state.modules = [.tasks, ModuleID(rawValue: "future"), .slack]
    #expect(summary(state).cards.map(\.module) == [.tasks, .slack])
  }

  @Test func nothingOnWhenNoModuleIsListed() {
    let empty = summary(DashboardState(updatedAt: "", modules: []))
    #expect(empty.nothingOn)
    #expect(empty.cards.isEmpty)
  }

  @Test func countsUnreadEmail() throws {
    let email = try card(.email, in: Fixtures.full)
    #expect(email.metrics == [HomeMetric(value: 2, label: "não lidos")])
    #expect(email.lines == ["Assunto 1", "Assunto 3"])
  }

  /// Completed and undated tasks never count; late ones come first, then today by priority.
  @Test func countsOverdueAndDueTodayOpenTasks() throws {
    let tasks = try card(.tasks, in: Fixtures.full)
    #expect(
      tasks.metrics == [
        HomeMetric(value: 1, label: "atrasadas", urgent: true),
        HomeMetric(value: 2, label: "para hoje"),
      ])
    #expect(tasks.lines == ["Tarefa late", "Tarefa today-high", "Tarefa today-low"])
  }

  @Test func countsTodaysEventsAndPreviewsWhatIsAhead() throws {
    let agenda = try card(.agenda, in: Fixtures.full)
    #expect(agenda.metrics == [HomeMetric(value: 3, label: "eventos hoje")])
    // 09:00 already passed at 13:15; all-day stays; tomorrow is not today.
    #expect(agenda.lines == ["dia  Aniversário", "15:00  Planejamento"])
    #expect(agenda.emptyText == nil)
  }

  @Test func agendaWithNothingTodayUsesTheWebCopy() throws {
    var state = Fixtures.full
    state.agenda = PanelResult(data: [Fixtures.event("2026-11-05", "10:00", "Amanhã")], error: nil)
    let agenda = try card(.agenda, in: state)
    #expect(agenda.metrics == [HomeMetric(value: 0, label: "eventos hoje")])
    #expect(agenda.emptyText == "Nada agendado para hoje.")
  }

  @Test func countsJiraApprovalsAndProblems() throws {
    let jira = try card(.jira, in: Fixtures.full)
    #expect(
      jira.metrics == [
        HomeMetric(value: 1, label: "aguardando aprovação"),
        HomeMetric(value: 2, label: "problemas"),
      ])
    #expect(jira.lines == ["DW-1  Resumo DW-1"])
  }

  @Test func countsReviewRequests() throws {
    let pulls = try card(.pulls, in: Fixtures.full)
    #expect(pulls.metrics == [HomeMetric(value: 2, label: "aguardando sua revisão")])
    #expect(pulls.lines == ["acme/web#7  PR 7", "acme/web#9  PR 9"])
  }

  @Test func countsSlackMentionsAndDirects() throws {
    let slack = try card(.slack, in: Fixtures.full)
    #expect(
      slack.metrics == [
        HomeMetric(value: 1, label: "menções"),
        HomeMetric(value: 2, label: "mensagens diretas"),
      ])
    #expect(slack.emptyText == nil)
  }

  @Test func slackWithoutMentionsUsesTheWebCopy() throws {
    var state = Fixtures.full
    state.slack = PanelResult(data: SlackDigest(mentions: [], directs: [], team: "Acme"), error: nil)
    #expect(try card(.slack, in: state).emptyText == "Nenhuma menção nos últimos 7 dias.")
  }

  @Test func previewStopsAtThree() throws {
    var state = Fixtures.full
    state.email = PanelResult(data: (1...5).map { Fixtures.email("\($0)", unread: true) }, error: nil)
    let email = try card(.email, in: state)
    #expect(email.metrics.first?.value == 5)
    #expect(email.lines.count == HomeSummary.previewLimit)
  }

  @Test func panelThatCameBackEmptyHandedIsOff() throws {
    var state = Fixtures.full
    state.tasks = PanelResult(data: nil, error: nil)
    state.reviewRequests = PanelResult(data: nil, error: nil)
    let tasks = try card(.tasks, in: state)
    #expect(tasks.isOff)
    #expect(tasks.metrics.isEmpty)
    #expect(tasks.errors.isEmpty)
    // Pulls is off only when both of its panels are.
    state.pulls = PanelResult(data: PullsDigest(items: [], errors: [], defaultBranches: [], truncated: []), error: nil)
    #expect(try card(.pulls, in: state).isOff == false)
    state.pulls = PanelResult(data: nil, error: nil)
    #expect(try card(.pulls, in: state).isOff)
  }

  @Test func errorWithoutDataShowsOnlyTheError() throws {
    var state = Fixtures.full
    state.email = PanelResult(data: nil, error: "IMAP recusou o login")
    let email = try card(.email, in: state)
    #expect(!email.isOff)
    #expect(email.errors == ["IMAP recusou o login"])
    #expect(email.metrics.isEmpty)
    #expect(email.lines.isEmpty)
  }

  @Test func partialErrorKeepsTheData() throws {
    var state = Fixtures.full
    state.agenda.error = "Uma agenda falhou"
    let agenda = try card(.agenda, in: state)
    #expect(agenda.errors == ["Uma agenda falhou"])
    #expect(agenda.metrics.first?.value == 3)
  }

  @Test func jiraCollectsBothErrorsAndKeepsWhatCame() throws {
    var state = Fixtures.full
    state.jira = PanelResult(data: nil, error: "Jira fora do ar")
    state.jiraProblems = PanelResult(data: [], error: "Falha nos problemas")
    let jira = try card(.jira, in: state)
    #expect(jira.errors == ["Jira fora do ar", "Falha nos problemas"])
    #expect(jira.metrics == [HomeMetric(value: 0, label: "problemas")])
  }

  @Test func pullsShowsTheFollowedReposErrorToo() throws {
    var state = Fixtures.full
    state.pulls = PanelResult(data: nil, error: "Token sem acesso")
    #expect(try card(.pulls, in: state).errors == ["Token sem acesso"])
  }

  @Test func notesCardOnlyOpensTheModule() throws {
    let notes = try card(.notes, in: Fixtures.full)
    #expect(notes.title == "Notas rápidas")
    #expect(notes.metrics.isEmpty && notes.errors.isEmpty && !notes.isOff)
  }
}
