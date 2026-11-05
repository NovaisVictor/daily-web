import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureHome

@Suite struct HomePanelsTests {
  let clock = HomeClock(now: Fixtures.now, calendar: Fixtures.calendar)

  func panels(_ state: DashboardState) -> HomePanels {
    HomePanels(state: state, now: Fixtures.now, calendar: Fixtures.calendar)
  }

  func panel(_ module: ModuleID, in state: DashboardState = Fixtures.full) throws -> HomePanel {
    try #require(panels(state).panels.first { $0.module == module })
  }

  func tab(_ id: String, of module: ModuleID, in state: DashboardState = Fixtures.full) throws -> HomeTab {
    try #require(panel(module, in: state).tabs.first { $0.id == id })
  }

  // MARK: - Which panels

  @Test func listsEnabledModulesInTheWebPanelOrderWithoutNotes() {
    let home = panels(Fixtures.full)
    #expect(home.panels.map(\.module) == [.email, .tasks, .agenda, .jira, .pulls, .slack])
    #expect(!home.nothingOn)
  }

  @Test func skipsModulesThatAreNotOnAndUnknownOnes() {
    var state = Fixtures.full
    state.modules = [.tasks, ModuleID(rawValue: "future"), .slack]
    #expect(panels(state).panels.map(\.module) == [.tasks, .slack])
  }

  @Test func nothingOnWhenNoModuleIsListed() {
    let empty = panels(DashboardState(updatedAt: "", modules: []))
    #expect(empty.nothingOn)
    #expect(empty.panels.isEmpty)
  }

  @Test func tabsFollowTheWebPanels() throws {
    #expect(try panel(.pulls).tabs.map(\.label) == ["Acompanhados", "Revisões", "Meus PRs"])
    #expect(try panel(.jira).tabs.map(\.label) == ["Em aberto", "Entregues", "Aprovados", "Problemas"])
    #expect(try panel(.slack).tabs.map(\.label) == ["Menções", "Mensagens diretas"])
    for module: ModuleID in [.email, .tasks, .agenda] {
      #expect(try !panel(module).hasTabs)
    }
  }

  // MARK: - E-mail

  @Test func emailListsUnreadFirstWithSenderAndTime() throws {
    let inbox = try #require(panel(.email).tabs.first)
    #expect(inbox.countText == "2 não lidos")
    #expect(inbox.rows.map(\.title) == ["Assunto 1", "Assunto 3", "Assunto 2"])
    #expect(inbox.rows.map(\.emphasized) == [true, true, false])
    let first = try #require(inbox.rows.first)
    #expect(first.lead == "4h")
    #expect(first.meta == ["Exemplo"])
    #expect(first.itemID == "conn-1:1")
  }

  @Test func emailOrdersByDateWithinTheSameReadState() throws {
    var state = Fixtures.full
    var old = Fixtures.email("old", unread: false)
    old.date = "2026-11-01T12:00:00.000Z"
    var new = Fixtures.email("new", unread: false)
    new.date = "2026-11-04T16:00:00.000Z"
    state.email = PanelResult(data: [old, new], error: nil)
    let inbox = try #require(panel(.email, in: state).tabs.first)
    #expect(inbox.rows.map(\.title) == ["Assunto new", "Assunto old"])
    #expect(inbox.countText == "0 não lidos")
  }

  @Test func emptyInboxUsesTheWebCopy() throws {
    var state = Fixtures.full
    state.email = PanelResult(data: [], error: nil)
    #expect(try panel(.email, in: state).tabs.first?.emptyText == "Caixa de entrada limpa.")
  }

  @Test func senderNameDropsTheAddress() {
    #expect(HomePanels.senderName("Ana Souza <ana@example.com>") == "Ana Souza")
    #expect(HomePanels.senderName("\"Ana\" <ana@example.com>") == "Ana")
    #expect(HomePanels.senderName("ana@example.com") == "ana@example.com")
  }

  @Test func rowsStopAtTheLimit() throws {
    var state = Fixtures.full
    state.email = PanelResult(data: (1...7).map { Fixtures.email("\($0)", unread: true) }, error: nil)
    let inbox = try #require(panel(.email, in: state).tabs.first)
    #expect(inbox.count == 7)
    #expect(inbox.rows.count == HomePanels.rowLimit)
  }

  // MARK: - Tarefas

  /// Late first, then today by priority, then later, then undated; completed never shows.
  @Test func tasksPutLateAndTodayFirst() throws {
    let tasks = try #require(panel(.tasks).tabs.first)
    #expect(tasks.count == 5)
    #expect(tasks.rows.map(\.id) == ["late", "today-high", "today-low", "tomorrow", "no-date"])
    #expect(tasks.rows.map(\.lead) == ["01/11", "hoje", "hoje", "amanhã", "—"])
    let late = try #require(tasks.rows.first)
    #expect(late.leadIsLate)
    #expect(late.pills == [HomePill(label: "atrasada", glyph: .alert, tone: .warning)])
    #expect(tasks.rows[1].meta == ["Alta"])
    #expect(tasks.rows[1].itemID == "today-high")
  }

  @Test func taskTimeJoinsThePriority() throws {
    var state = Fixtures.full
    var task = Fixtures.task("t", due: "2026-11-04", priority: .low)
    task.time = "14:30"
    state.tasks = PanelResult(data: [task], error: nil)
    #expect(try panel(.tasks, in: state).tabs.first?.rows.first?.metaText == "Baixa · 14:30")
  }

  @Test func noOpenTaskUsesTheWebCopy() throws {
    var state = Fixtures.full
    state.tasks = PanelResult(data: [Fixtures.task("done", due: "2026-11-01", completed: true)], error: nil)
    let tasks = try #require(panel(.tasks, in: state).tabs.first)
    #expect(tasks.rows.isEmpty)
    #expect(tasks.emptyText == "Nenhuma tarefa por aqui. Crie a primeira.")
  }

  // MARK: - Agenda

  @Test func agendaListsWhatIsAhead() throws {
    let agenda = try #require(panel(.agenda).tabs.first)
    #expect(agenda.countText == "3 hoje")
    // 09:00 already passed at 13:15; all-day stays first.
    #expect(agenda.rows.map(\.title) == ["Aniversário", "Planejamento", "Amanhã"])
    #expect(agenda.rows.map(\.lead) == ["dia", "15:00", "amanhã"])
    #expect(agenda.rows[2].meta == ["Pessoal", "10:00"])
    #expect(agenda.rows.allSatisfy { $0.itemID == nil })
  }

  @Test func agendaWithEverythingPastKeepsTheEvents() throws {
    var state = Fixtures.full
    state.agenda = PanelResult(data: [Fixtures.event("2026-11-04", "09:00", "Daily")], error: nil)
    let agenda = try #require(panel(.agenda, in: state).tabs.first)
    #expect(agenda.rows.map(\.title) == ["Daily"])
    #expect(agenda.emptyText == nil)
  }

  @Test func emptyAgendaUsesTheRangeCopy() throws {
    var state = Fixtures.full
    state.agenda = PanelResult(data: [], error: nil)
    #expect(try panel(.agenda, in: state).tabs.first?.emptyText == "Nada agendado para hoje e amanhã.")
    state.agendaDays = 7
    #expect(try panel(.agenda, in: state).tabs.first?.emptyText == "Nada agendado nos próximos 7 dias.")
    state.agendaDays = 1
    #expect(try panel(.agenda, in: state).tabs.first?.emptyText == "Nada agendado para hoje.")
  }

  // MARK: - Jira

  @Test func jiraOpenTabShowsKeyStatusAndDue() throws {
    var state = Fixtures.full
    state.jira = PanelResult(
      data: [
        Fixtures.issue(
          "DW-9", awaitingApproval: false, status: "EM ANDAMENTO", updatedAt: "2026-10-20T10:00:00.000Z",
          dueDate: "2026-11-03", priority: "Alta")
      ],
      error: nil)
    let open = try tab("abertas", of: .jira, in: state)
    let row = try #require(open.rows.first)
    #expect(row.lead == "DW-9")
    #expect(row.pills == [HomePill(label: "Em andamento", glyph: .moving, tone: .info)])
    #expect(row.meta == ["Alta", "parado há 15d", "venceu há 1d"])
    #expect(row.itemID == "DW-9")
  }

  @Test func jiraDueLabelsFollowTheWeb() {
    #expect(clock.jiraDue("2026-11-04") == "vence hoje")
    #expect(clock.jiraDue("2026-11-05") == "vence amanhã")
    #expect(clock.jiraDue("2026-11-10") == "vence em 6d")
    #expect(clock.jiraDue("2026-11-20") == "vence 20/11")
    #expect(clock.jiraDue("") == nil)
  }

  @Test func jiraTabsCountTheirLists() throws {
    var state = Fixtures.full
    state.jiraDelivered = PanelResult(
      data: [
        JiraDatedItem(item: Fixtures.issue("DW-5", awaitingApproval: false), today: true),
        JiraDatedItem(item: Fixtures.issue("DW-6", awaitingApproval: false), today: false),
      ],
      error: nil)
    state.jiraApproved = PanelResult(
      data: [JiraDatedItem(item: Fixtures.issue("DW-7", awaitingApproval: false), today: false)], error: nil)
    let jira = try panel(.jira, in: state)
    #expect(jira.tabs.map(\.count) == [2, 1, 0, 2])
    // Closed lists keep the web's default "hoje" period.
    #expect(jira.tabs[1].rows.map(\.id) == ["DW-5"])
    #expect(jira.tabs[2].emptyText == "Nenhuma issue aprovada hoje.")
    #expect(jira.tabs[3].rows.first?.meta == ["sem épico"])
    #expect(jira.tabs[0].countText == "2")
    #expect(jira.tabs[2].countText == nil)
  }

  @Test func jiraTabErrorsStayOnTheirTab() throws {
    var state = Fixtures.full
    state.jira = PanelResult(data: nil, error: "Jira fora do ar")
    state.jiraProblems = PanelResult(data: [], error: "Falha nos problemas")
    let jira = try panel(.jira, in: state)
    #expect(jira.tabs[0].errors == ["Jira fora do ar"])
    #expect(jira.tabs[0].rows.isEmpty && jira.tabs[0].emptyText == nil)
    #expect(jira.tabs[3].errors == ["Falha nos problemas"])
    #expect(jira.tabs[3].emptyText == "Nenhuma história ou épico com problema.")
    // Delivered never came: the tab is off, not empty.
    #expect(jira.tabs[1].isOff)
  }

  @Test func statusIsNormalized() {
    #expect(HomePanels.normalizeStatus(" EM ANDAMENTO ") == "Em andamento")
    #expect(HomePanels.normalizeStatus("") == "")
  }

  // MARK: - Pull requests

  @Test func reviewsTabShowsRepoAgeAndBadges() throws {
    let reviews = try tab("revisoes", of: .pulls)
    #expect(reviews.count == 2)
    let row = try #require(reviews.rows.first)
    #expect(row.lead == "#7")
    #expect(row.title == "PR 7")
    #expect(row.meta == ["acme/web", "aberto há 1 dia", "bruno"])
    #expect(
      row.pills == [
        HomePill(label: "CI ok", glyph: .live, tone: .success),
        HomePill(label: "aguardando revisão", glyph: .idle, tone: .neutral),
      ])
    #expect(row.itemID == "acme/web#7")
  }

  @Test func myPullsShowFailuresStalenessAndNoAuthor() throws {
    var state = Fixtures.full
    let pull = Fixtures.pull(
      3, mine: true, ci: .failing, review: .changesRequested, merge: .conflict, createdAt: "2026-10-01T10:00:00.000Z",
      updatedAt: "2026-10-30T10:00:00.000Z")
    state.myPulls = PanelResult(data: MyPullsDigest(items: [pull], truncated: false, total: 1), error: nil)
    let row = try #require(tab("meus", of: .pulls, in: state).rows.first)
    #expect(row.pills.map(\.label) == ["CI falhou", "pediram mudanças", "conflito"])
    #expect(row.meta == ["aberto há 34 dias", "parado há 5 dias"])
  }

  @Test func pullOpenedTodaySaysSo() throws {
    let age = try #require(clock.pullAge(createdAt: "2026-11-04T15:00:00.000Z", updatedAt: "2026-11-04T15:00:00Z"))
    #expect(age.opened == "aberto hoje")
    #expect(age.stalled == nil)
    #expect(clock.pullAge(createdAt: "", updatedAt: "") == nil)
  }

  @Test func pullTabsUseTheWebEmptyCopyAndErrors() throws {
    var state = Fixtures.full
    state.pulls = PanelResult(
      data: PullsDigest(items: [], errors: ["acme/old: not found", "acme/x: 403"], defaultBranches: [], truncated: []),
      error: nil)
    state.myPulls = PanelResult(data: MyPullsDigest(items: [], truncated: false, total: 0), error: "Token sem acesso")
    let pulls = try panel(.pulls, in: state)
    #expect(pulls.tabs[0].errors == ["acme/old: not found; acme/x: 403"])
    #expect(pulls.tabs[0].emptyText == "Nada aberto nos repositórios acompanhados.")
    #expect(pulls.tabs[2].errors == ["Token sem acesso"])
    #expect(pulls.tabs[2].emptyText == "Nenhum PR seu aberto.")
  }

  @Test func panelThatCameBackEmptyHandedIsOff() throws {
    var state = Fixtures.full
    state.tasks = PanelResult(data: nil, error: nil)
    let tasks = try #require(panel(.tasks, in: state).tabs.first)
    #expect(tasks.isOff)
    #expect(tasks.rows.isEmpty && tasks.errors.isEmpty && tasks.emptyText == nil)
    #expect(try tab("acompanhados", of: .pulls).isOff)
  }

  @Test func partialErrorKeepsTheData() throws {
    var state = Fixtures.full
    state.agenda.error = "Uma agenda falhou"
    let agenda = try #require(panel(.agenda, in: state).tabs.first)
    #expect(agenda.errors == ["Uma agenda falhou"])
    #expect(agenda.rows.count == 3)
  }

  // MARK: - Slack

  @Test func slackTabsListMessages() throws {
    let slack = try panel(.slack)
    #expect(slack.tabs.map(\.count) == [1, 2])
    let row = try #require(slack.tabs[0].rows.first)
    #expect(row.lead == "5h")
    #expect(row.meta == ["carla", "geral"])
    #expect(row.itemID == "m1")
  }

  @Test func slackEmptyTabsUseTheWebCopy() throws {
    var state = Fixtures.full
    state.slack = PanelResult(data: SlackDigest(mentions: [], directs: [], team: "Acme"), error: nil)
    let slack = try panel(.slack, in: state)
    #expect(slack.tabs.map(\.emptyText) == ["Nenhuma menção nos últimos 7 dias.", "Nenhuma mensagem direta não lida."])
  }

  // MARK: - Clock

  @Test func relativeTimeMatchesTheWeb() {
    #expect(clock.relative("2026-11-04T16:15:00Z") == "agora")
    #expect(clock.relative("2026-11-04T16:03:00Z") == "12min")
    #expect(clock.relative("2026-11-03T15:00:00Z") == "ontem")
    #expect(clock.relative("2026-11-01T15:00:00Z") == "3d")
    #expect(clock.relative("2026-10-02T15:00:00Z") == "02/10")
    #expect(clock.relative("") == "—")
  }
}
