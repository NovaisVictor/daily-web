import DailyModels
import DailyStorage
import Foundation
import Testing

@testable import DailyCore

@Suite struct AlertEngineTests {
  let poster = FakeNotificationPoster()
  let directory = Fixtures.temporaryDirectory()
  let defaults = Fixtures.defaults()
  let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()
  let clock = MutableNow()

  final class MutableNow {
    var date = VirtualClock.origin
  }

  init() {
    defaults.set("1", forKey: AlertEngine.enabledKey)
  }

  func makeEngine() -> AlertEngine {
    let clock = self.clock
    return AlertEngine(
      poster: poster,
      cache: DiskCache(fileName: "alerts.json", directory: directory),
      defaults: defaults,
      now: { clock.date },
      calendar: calendar
    )
  }

  func date(_ text: String) throws -> Date {
    try #require(AlertRules.localDate(String(text.prefix(10)), String(text.suffix(8)), calendar: calendar))
      .addingTimeInterval(TimeInterval(Int(text.suffix(2)) ?? 0))
  }

  /// Baseline with the fixture, then the changed state; returns what was posted.
  func alerts(after change: (inout DashboardState) -> Void) async throws -> [DesktopAlert] {
    let engine = makeEngine()
    var state = try Fixtures.dashboard()
    await engine.process(state)
    #expect(poster.posted.isEmpty)
    change(&state)
    state.updatedAt = "2026-11-04T12:41:00.000Z"
    await engine.process(state)
    return poster.posted
  }

  @Test func firstLoadOnlyRecordsTheBaseline() async throws {
    let engine = makeEngine()
    await engine.process(try Fixtures.dashboard())
    #expect(poster.posted.isEmpty)
  }

  @Test func newUnreadInboxEmail() async throws {
    let posted = try await alerts { state in
      var mail = state.email.data?[0]
      mail?.id = "5000"
      mail?.messageId = ""
      mail?.subject = ""
      var sent = mail
      sent?.id = "5001"
      sent?.mailbox = .sent
      state.email.data?.append(contentsOf: [mail, sent].compactMap { $0 })
    }
    #expect(posted.map(\.title) == ["Novo e-mail"])
    #expect(posted.first?.body == "Ana Exemplo <ana@example.com> — (sem assunto)")
    #expect(posted.first?.tag == "email:conn-mail-1:5000")
    #expect(posted.first?.target == AlertTarget(route: .module(.email), itemID: "conn-mail-1:5000"))
  }

  @Test func jiraAssignedApprovalAndReporterSkipped() async throws {
    let posted = try await alerts { state in
      guard var issue = state.jira.data?[0] else { return }
      issue.key = "DEMO-200"
      issue.summary = "Nova tela"
      var approval = issue
      approval.key = "DEMO-201"
      approval.awaitingApproval = true
      var reported = issue
      reported.key = "DEMO-202"
      reported.role = .reporter
      state.jira.data?.append(contentsOf: [issue, approval, reported])
    }
    #expect(posted.map(\.title) == ["Nova issue no seu nome", "Aprovação pendente"])
    #expect(posted.map(\.body) == ["DEMO-200 — Nova tela", "DEMO-201 — Nova tela"])
    #expect(posted.first?.target.route == .module(.jira))
  }

  @Test func jiraProblem() async throws {
    let posted = try await alerts { state in
      state.jiraProblems.data?[0].problems.append(.storyDoneWithoutStart)
    }
    #expect(posted.map(\.title) == ["Issue com problema"])
    #expect(posted.first?.body == "DEMO-145 — concluída sem data de início")
    #expect(posted.first?.tag == "jira-problem:DEMO-145:story-done-without-start")
  }

  @Test func pullsAndReviews() async throws {
    let posted = try await alerts { state in
      guard var pull = state.pulls.data?.items[0], var review = state.reviewRequests.data?.items[0] else { return }
      pull.number = 400
      pull.title = "Novo filtro"
      var mine = pull
      mine.number = 401
      mine.mine = true
      var issue = pull
      issue.number = 402
      issue.isPullRequest = false
      state.pulls.data?.items.append(contentsOf: [pull, mine, issue])
      review.number = 78
      review.title = "Índices"
      state.reviewRequests.data?.items.append(review)
    }
    #expect(posted.map(\.title) == ["Novo PR", "Revisão pedida"])
    #expect(posted.map(\.body) == ["acme/painel#400 — Novo filtro", "acme/api#78 — Índices"])
    #expect(posted.first?.target.itemID == "acme/painel#400")
  }

  @Test func agendaEvent() async throws {
    let posted = try await alerts { state in
      state.agenda.data?.append(
        AgendaItem(account: "conn-cal-1", accountLabel: "A", date: "2026-11-06", time: "", title: "Retro"))
    }
    #expect(posted.map(\.title) == ["Novo evento na agenda"])
    #expect(posted.first?.body == "06/11 dia inteiro — Retro")
  }

  @Test func slackMentionAndDirect() async throws {
    let posted = try await alerts { state in
      let mention = SlackMessage(
        id: "C9-1", channel: "#geral", author: "Bia", text: "olha isso", date: "", url: "https://x.slack.com/1")
      var direct = mention
      direct.id = "D9-2"
      direct.text = "oi"
      state.slack.data?.mentions.append(mention)
      state.slack.data?.directs.append(direct)
    }
    #expect(posted.map(\.title) == ["Menção no Slack", "Mensagem no Slack"])
    #expect(posted.map(\.body) == ["Bia — olha isso", "Bia — oi"])
    #expect(
      posted.first?.target.userInfo == ["route": "module:slack", "itemID": "C9-1", "url": "https://x.slack.com/1"])
  }

  @Test func moreThanFiveBecomeOneSummary() async throws {
    let posted = try await alerts { state in
      for index in 0..<6 {
        state.agenda.data?.append(
          AgendaItem(account: "c", accountLabel: "A", date: "2026-11-06", time: "1\(index):00", title: "E\(index)"))
      }
    }
    #expect(posted.count == 1)
    #expect(posted.first?.title == "daily-web")
    #expect(posted.first?.body == "6 novidades no painel")
    #expect(posted.first?.tag == "resumo")
  }

  @Test func sameUpdatedAtIsNotProcessedTwice() async throws {
    let engine = makeEngine()
    var state = try Fixtures.dashboard()
    await engine.process(state)
    state.slack.data?.directs.removeAll()
    await engine.process(state)
    state.slack.data?.directs.append(
      SlackMessage(id: "D-new", channel: "", author: "Bia", text: "oi", date: "", url: ""))
    await engine.process(state)
    #expect(poster.posted.isEmpty)
  }

  @Test func announcedKeysSurviveARelaunch() async throws {
    var state = try Fixtures.dashboard()
    await makeEngine().process(state)
    state.updatedAt = "second"
    state.agenda.data?.append(AgendaItem(account: "c", accountLabel: "A", date: "2026-11-06", time: "", title: "Retro"))
    await makeEngine().process(state)
    #expect(poster.posted.count == 1)

    poster.clear()
    state.updatedAt = "third"
    await makeEngine().process(state)
    #expect(poster.posted.isEmpty)
  }

  @Test func resetMakesTheNextLoadABaseline() async throws {
    let engine = makeEngine()
    var state = try Fixtures.dashboard()
    await engine.process(state)
    engine.reset()
    state.updatedAt = "after sign-in"
    state.agenda.data?.append(AgendaItem(account: "c", accountLabel: "A", date: "2026-11-06", time: "", title: "Retro"))
    await engine.process(state)
    #expect(poster.posted.isEmpty)
    #expect(
      try DiskCache<SeenState>(fileName: "alerts.json", directory: directory).load()?.sources[.agenda]?.count == 3)
  }

  @Test func disabledRecordsButDoesNotPost() async throws {
    defaults.set("0", forKey: AlertEngine.enabledKey)
    let posted = try await alerts { state in
      state.agenda.data?.append(
        AgendaItem(account: "c", accountLabel: "A", date: "2026-11-06", time: "", title: "Retro"))
    }
    #expect(posted.isEmpty)
  }

  @Test func enableAsksPermissionAndStoresTheFlag() async {
    defaults.removeObject(forKey: AlertEngine.enabledKey)
    let engine = makeEngine()
    #expect(!engine.isEnabled)
    poster.granted = false
    await engine.enable()
    #expect(!engine.isEnabled)
    poster.granted = true
    await engine.enable()
    #expect(engine.isEnabled)
    #expect(defaults.string(forKey: AlertEngine.enabledKey) == "1")
    engine.disable()
    #expect(defaults.string(forKey: AlertEngine.enabledKey) == "0")
  }

  @Test func remindersFireOnceWithinTenMinutes() async throws {
    let engine = makeEngine()
    // The fixture has "Reunião de planejamento" on 2026-11-04 at 14:30.
    clock.date = try date("2026-11-04 14:19:00")
    await engine.process(try Fixtures.dashboard())
    #expect(poster.posted.isEmpty)

    clock.date = try date("2026-11-04 14:22:30")
    await engine.checkReminders()
    #expect(poster.posted.map(\.title) == ["Em 8 min"])
    #expect(poster.posted.first?.body == "14:30 — Reunião de planejamento")
    #expect(poster.posted.first?.target.route == .module(.agenda))

    clock.date = try date("2026-11-04 14:23:00")
    await engine.checkReminders()
    await makeEngine().checkReminders()
    #expect(poster.posted.count == 1)

    clock.date = try date("2026-11-04 14:30:00")
    await engine.checkReminders()
    #expect(poster.posted.count == 1)
  }

  @Test func agentsAlertWhenANewWaitStarts() async {
    let engine = makeEngine()
    await engine.updateAgents([AgentAttention(taskID: "t1", title: "Migrar banco", since: "a")])
    #expect(poster.posted.isEmpty)
    await engine.updateAgents([
      AgentAttention(taskID: "t1", title: "Migrar banco", since: "a"),
      AgentAttention(taskID: "t2", title: "Revisar PR", since: "b"),
    ])
    #expect(poster.posted.map(\.title) == ["Aguardando você"])
    #expect(poster.posted.first?.body == "Revisar PR")
    #expect(poster.posted.first?.target == AlertTarget(route: .agents, itemID: "t2"))
  }

  @Test func pomodoroPhaseTextsFollowTheWeb() async {
    defaults.set("0", forKey: AlertEngine.enabledKey)
    let engine = makeEngine()
    await engine.pomodoroPhaseChanged(.rest)
    await engine.pomodoroPhaseChanged(.focus)
    #expect(poster.posted.map(\.body) == ["Hora de descansar", "Hora de focar"])
    #expect(poster.posted.map(\.title) == ["daily-web", "daily-web"])

    poster.authorized = false
    await engine.pomodoroPhaseChanged(.rest)
    #expect(poster.posted.count == 2)
  }

  @Test func targetRoundTripsThroughUserInfo() {
    let targets = [
      AlertTarget(route: .today),
      AlertTarget(route: .agents, itemID: "t1"),
      AlertTarget(route: .module(.pulls), itemID: "acme/api#7", url: "https://github.com/acme/api/pull/7"),
    ]
    for target in targets {
      let info: [AnyHashable: Any] = target.userInfo.reduce(into: [:]) { $0[$1.key] = $1.value }
      #expect(AlertTarget(userInfo: info) == target)
    }
  }
}
