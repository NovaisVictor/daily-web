import DailyModels
import Foundation
import Testing

@testable import FeatureJira

/// `tests/lib/standup.test.ts`, on a fixed local time zone.
@Suite struct StandupTests {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
    return calendar
  }()

  static func local(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
  }

  static let monday = local(19, 9, 30)
  static let wednesday = local(21, 9, 30)

  static func at(_ day: Int, _ hour: Int = 15) -> String { JiraText.isoForTest(local(day, hour)) }

  static func issue(
    _ key: String = "A-1", summary: String = "Resumo", category: JiraStatusCategory = .indeterminate,
    role: JiraRole = .assignee, approval: Bool = false, flag: JiraFlag = .none
  ) -> JiraItem {
    makeIssue(
      key, summary: summary, category: category, role: role, approval: approval, updatedAt: at(20), flag: flag)
  }

  static func dated(_ key: String = "A-1", summary: String = "Resumo", today: Bool = false, updatedAt: String? = nil)
    -> JiraDatedItem
  {
    var item = makeIssue(key, summary: summary, status: "Resolvido", category: .done, updatedAt: updatedAt ?? at(20))
    item.summary = summary
    return JiraDatedItem(item: item, today: today)
  }

  static func pull(
    number: Int = 7, title: String = "feat: add login", createdAt: String? = nil, draft: Bool = false,
    isPullRequest: Bool = true, ci: PullCI = .passing, review: PullReview = .pending, merge: PullMerge = .clean
  ) -> PullRequestItem {
    PullRequestItem(
      id: "PR_\(number)", repo: "acme/api", number: number, title: title,
      url: "https://github.com/acme/api/pull/\(number)", author: "viewer", draft: draft, awaitingYou: false,
      mine: true, isPullRequest: isPullRequest, updatedAt: at(20), createdAt: createdAt ?? at(10), ci: ci,
      failedChecks: [], review: review, pendingReviewers: [], reviewers: [], reviewRequestedAt: nil, merge: merge,
      size: nil, headRef: "feature/login", baseRef: "main", headSha: "abc")
  }

  func standup(_ source: StandupSource, _ now: Date = wednesday) -> Standup {
    StandupBuilder.standup(source, now: now, calendar: Self.calendar)
  }

  func weekly(_ source: StandupSource, _ now: Date = wednesday) -> WeeklySummary {
    StandupBuilder.weekly(source, now: now, calendar: Self.calendar)
  }

  // MARK: previousWorkingDay

  @Test func previousWorkingDayIsTheDayBefore() {
    #expect(StandupBuilder.previousWorkingDay(Self.wednesday, calendar: Self.calendar) == Self.local(20))
  }

  @Test func previousWorkingDayIsFridayOnMonday() {
    #expect(StandupBuilder.previousWorkingDay(Self.monday, calendar: Self.calendar) == Self.local(16))
  }

  @Test func previousWorkingDayIsFridayOverTheWeekend() {
    #expect(StandupBuilder.previousWorkingDay(Self.local(17, 10), calendar: Self.calendar) == Self.local(16))
    #expect(StandupBuilder.previousWorkingDay(Self.local(18, 10), calendar: Self.calendar) == Self.local(16))
  }

  // MARK: buildStandup

  @Test func emptySections() {
    #expect(standup(StandupSource()) == Standup(yesterday: [], today: [], blockers: []))
  }

  @Test func yesterdayListsDeliveredAndApproved() {
    let result = standup(
      StandupSource(
        delivered: [Self.dated("A-1", summary: "Entregue")],
        approved: [Self.dated("A-2", summary: "Aprovada", updatedAt: Self.at(20, 18))]))
    #expect(result.yesterday == ["A-1 — Entregue", "A-2 — Aprovada"])
  }

  @Test func yesterdayLeavesOutTodayAndBefore() {
    let result = standup(
      StandupSource(delivered: [
        Self.dated("A-1", today: true, updatedAt: Self.at(21, 8)), Self.dated("A-2", updatedAt: Self.at(19)),
      ]))
    #expect(result.yesterday.isEmpty)
  }

  @Test func yesterdayListsAnIssueOnce() {
    let result = standup(StandupSource(delivered: [Self.dated("A-1")], approved: [Self.dated("A-1")]))
    #expect(result.yesterday == ["A-1 — Resumo"])
  }

  @Test func mondayReachesBackToFriday() {
    let result = standup(
      StandupSource(
        delivered: [
          Self.dated("A-1", summary: "Sexta", updatedAt: Self.at(16)),
          Self.dated("A-2", summary: "Sábado", updatedAt: Self.at(17)),
          Self.dated("A-3", summary: "Quinta", updatedAt: Self.at(15)),
        ],
        myPulls: [Self.pull(number: 1, title: "Sexta", createdAt: Self.at(16))]),
      Self.monday)
    #expect(result.yesterday == ["A-1 — Sexta", "A-2 — Sábado", "acme/api#1 — Sexta"])
  }

  @Test func yesterdayListsPullsOpenedSinceThePreviousWorkingDay() {
    let result = standup(
      StandupSource(myPulls: [
        Self.pull(number: 1, title: "Ontem", createdAt: Self.at(20)),
        Self.pull(number: 2, title: "Hoje", createdAt: Self.at(21, 8)),
        Self.pull(number: 3, title: "Antes", createdAt: Self.at(19)),
        Self.pull(number: 4, title: "Issue", createdAt: Self.at(20), isPullRequest: false),
      ]))
    #expect(result.yesterday == ["acme/api#1 — Ontem"])
  }

  @Test func todayListsAssignedIssuesInProgress() {
    let result = standup(
      StandupSource(open: [
        Self.issue("A-1", summary: "Andando"), Self.issue("A-2", summary: "Ambos", role: .both),
        Self.issue("A-3", category: .new), Self.issue("A-4", role: .reporter), Self.issue("A-5", approval: true),
        Self.issue("A-6", flag: .impediment),
      ]))
    #expect(result.today == ["A-1 — Andando", "A-2 — Ambos"])
  }

  @Test func blockersListImpededIssues() {
    let result = standup(
      StandupSource(open: [
        Self.issue("A-1", summary: "Travada", flag: .impediment),
        Self.issue("A-2", summary: "A fazer", category: .new, flag: .impediment),
        Self.issue("A-3", role: .reporter, flag: .impediment), Self.issue("A-4"),
      ]))
    #expect(result.blockers == ["A-1 — Travada", "A-2 — A fazer"])
  }

  @Test func blockersListBlockedPullsWithTheirCause() {
    let result = standup(
      StandupSource(myPulls: [
        Self.pull(number: 1, title: "CI", ci: .failing),
        Self.pull(number: 2, title: "Revisão", review: .changesRequested),
        Self.pull(number: 3, title: "Conflito", merge: .conflict),
        Self.pull(number: 4, title: "Tudo", ci: .failing, review: .changesRequested, merge: .conflict),
      ]))
    #expect(
      result.blockers == [
        "acme/api#1 — CI (CI falhou)", "acme/api#2 — Revisão (pediram mudanças)", "acme/api#3 — Conflito (conflito)",
        "acme/api#4 — Tudo (CI falhou, pediram mudanças, conflito)",
      ])
  }

  @Test func blockersLeaveOutWaitingAndDrafts() {
    let result = standup(
      StandupSource(myPulls: [
        Self.pull(number: 1), Self.pull(number: 2, draft: true, ci: .failing),
        Self.pull(number: 3, review: .approved, merge: .clean), Self.pull(number: 4, ci: .running, merge: .unknown),
      ]))
    #expect(result.blockers.isEmpty)
  }

  // MARK: standupText

  @Test func textWithPlaceholders() {
    #expect(
      StandupBuilder.text(Standup(yesterday: [], today: [], blockers: []))
        == "Ontem\n- Nada entregue\n\nHoje\n- Nada em andamento\n\nBloqueios\n- Nenhum")
  }

  @Test func textOneLinePerItem() {
    let text = StandupBuilder.text(
      Standup(
        yesterday: ["A-1 — Entregue", "acme/api#7 — feat: add login"], today: ["A-2 — Andando"],
        blockers: ["A-3 — Travada"]))
    #expect(
      text
        == "Ontem\n- A-1 — Entregue\n- acme/api#7 — feat: add login\n\nHoje\n- A-2 — Andando\n\nBloqueios\n- A-3 — Travada"
    )
  }

  // MARK: startOfWeek and buildWeekly

  @Test func startOfWeek() {
    #expect(StandupBuilder.startOfWeek(Self.wednesday, calendar: Self.calendar) == Self.local(19))
    #expect(StandupBuilder.startOfWeek(Self.monday, calendar: Self.calendar) == Self.local(19))
    #expect(StandupBuilder.startOfWeek(Self.local(25, 10), calendar: Self.calendar) == Self.local(19))
  }

  @Test func weeklyEmpty() {
    #expect(weekly(StandupSource()) == WeeklySummary(delivered: [], pulls: [], blockers: []))
  }

  @Test func weeklyListsSinceMondayTodayIncluded() {
    let result = weekly(
      StandupSource(
        delivered: [
          Self.dated("A-1", summary: "Segunda", updatedAt: Self.at(19, 10)),
          Self.dated("A-2", summary: "Hoje", today: true, updatedAt: Self.at(21, 8)),
        ],
        approved: [Self.dated("A-3", summary: "Aprovada", updatedAt: Self.at(20))]))
    #expect(result.delivered == ["A-1 — Segunda", "A-2 — Hoje", "A-3 — Aprovada"])
  }

  @Test func weeklyLeavesOutBeforeMonday() {
    #expect(weekly(StandupSource(delivered: [Self.dated("A-1", updatedAt: Self.at(16))])).delivered.isEmpty)
  }

  @Test func weeklyListsAnIssueOnce() {
    #expect(
      weekly(StandupSource(delivered: [Self.dated("A-1")], approved: [Self.dated("A-1")])).delivered == [
        "A-1 — Resumo"
      ])
  }

  @Test func weeklyListsPullsOpenedSinceMonday() {
    let result = weekly(
      StandupSource(myPulls: [
        Self.pull(number: 1, title: "feat: segunda", createdAt: Self.at(19, 9)),
        Self.pull(number: 2, title: "feat: hoje", createdAt: Self.at(21, 8)),
        Self.pull(number: 3, title: "feat: antiga", createdAt: Self.at(15)),
        Self.pull(number: 4, title: "issue", createdAt: Self.at(20), isPullRequest: false),
      ]))
    #expect(result.pulls == ["acme/api#1 — feat: segunda", "acme/api#2 — feat: hoje"])
  }

  @Test func weeklyBlockersMatchTheDaily() {
    let blocked = StandupSource(
      open: [Self.issue("A-9", summary: "Travada", flag: .impediment)], myPulls: [Self.pull(ci: .failing)])
    #expect(weekly(blocked).blockers.count == 2)
    #expect(weekly(blocked).blockers == standup(blocked).blockers)
  }

  @Test func weeklyTextWithPlaceholders() {
    #expect(
      StandupBuilder.text(WeeklySummary(delivered: [], pulls: [], blockers: []))
        == "Entregue na semana\n- Nada entregue\n\nPRs abertos na semana\n- Nenhum\n\nBloqueios\n- Nenhum")
  }
}
