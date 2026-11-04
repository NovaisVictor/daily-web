import DailyModels
import Foundation

/// What the daily summary reads (`StandupSource`, `lib/standup.ts`).
nonisolated struct StandupSource: Equatable, Sendable {
  var open: [JiraItem] = []
  var delivered: [JiraDatedItem] = []
  var approved: [JiraDatedItem] = []
  var myPulls: [PullRequestItem] = []
}

nonisolated struct Standup: Equatable, Sendable {
  var yesterday: [String]
  var today: [String]
  var blockers: [String]
}

nonisolated struct WeeklySummary: Equatable, Sendable {
  var delivered: [String]
  var pulls: [String]
  var blockers: [String]
}

/// The summary's period (`Range` in `components/jira/StandupDialog.tsx`).
nonisolated enum StandupRange: String, CaseIterable, Sendable {
  case daily
  case weekly

  var label: String {
    switch self {
    case .daily: "Diário"
    case .weekly: "Semanal"
    }
  }

  var description: String {
    switch self {
    case .daily: "O que você entregou desde o último dia útil, o que está em andamento e o que está travado."
    case .weekly: "O que você entregou e os PRs que abriu desde segunda-feira, e o que está travado agora."
    }
  }
}

/// `lib/standup.ts`, with the local calendar standing in for JavaScript's
/// local-time `Date`.
nonisolated enum StandupBuilder {
  static func previousWorkingDay(_ now: Date, calendar: Calendar = .current) -> Date {
    // Sunday 1, Monday 2, Saturday 7 in `Calendar`'s numbering.
    let back: Int
    switch calendar.component(.weekday, from: now) {
    case 1: back = 2
    case 2: back = 3
    case 7: back = 1
    default: back = 1
    }
    return daysBefore(now, back, calendar: calendar)
  }

  /// Monday of the current week; on the weekend, the Monday just past.
  static func startOfWeek(_ now: Date, calendar: Calendar = .current) -> Date {
    let jsDay = calendar.component(.weekday, from: now) - 1
    return daysBefore(now, (jsDay + 6) % 7, calendar: calendar)
  }

  private static func daysBefore(_ date: Date, _ days: Int, calendar: Calendar) -> Date {
    let start = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: -days, to: start) ?? start
  }

  private static func issueLine(_ item: JiraItem) -> String { "\(item.key) — \(item.summary)" }

  private static func pullLine(_ item: PullRequestItem) -> String { "\(item.repo)#\(item.number) — \(item.title)" }

  private static func within(_ iso: String, from: Date, until: Date) -> Bool {
    guard let time = JiraDates.parse(iso) else { return false }
    return time >= from && time < until
  }

  // The delivered and approved lists only say whether an issue fell on today;
  // `updatedAt` is the closest proxy for "since the last working day".
  private static func closedSince(_ items: [JiraDatedItem], from: Date, includeToday: Bool) -> [JiraDatedItem] {
    var seen: Set<String> = []
    var result: [JiraDatedItem] = []
    for item in items where includeToday || !item.today {
      guard let updated = JiraDates.parse(item.updatedAt), updated >= from, !seen.contains(item.key) else {
        continue
      }
      seen.insert(item.key)
      result.append(item)
    }
    return result
  }

  // An issue that only reached the list through a pending approval carries a
  // neutral `assignee` role, so approval rows are left out of the user's own work.
  private static func isOwnWork(_ item: JiraItem) -> Bool {
    item.role != .reporter && !item.awaitingApproval
  }

  /// `myPullBlockers` and `MY_PULL_BLOCKER_LABEL`, `lib/myPulls.ts:7-28`.
  static func pullBlockers(_ item: PullRequestItem) -> [String] {
    var blockers: [String] = []
    if item.ci == .failing { blockers.append("CI falhou") }
    if item.review == .changesRequested { blockers.append("pediram mudanças") }
    if item.merge == .conflict { blockers.append("conflito") }
    return blockers
  }

  /// `myPullGroup(item) === 'needs-you'`: a draft is its own group first.
  private static func needsYou(_ item: PullRequestItem) -> Bool {
    !item.draft && !pullBlockers(item).isEmpty
  }

  private static func blockerLines(_ own: [JiraItem], _ pulls: [PullRequestItem]) -> [String] {
    own.filter { $0.flag == .impediment }.map(issueLine)
      + pulls.filter(needsYou).map { "\(pullLine($0)) (\(pullBlockers($0).joined(separator: ", ")))" }
  }

  static func standup(_ source: StandupSource, now: Date, calendar: Calendar = .current) -> Standup {
    let today = calendar.startOfDay(for: now)
    let from = previousWorkingDay(now, calendar: calendar)
    let own = source.open.filter(isOwnWork)
    let pulls = source.myPulls.filter(\.isPullRequest)
    return Standup(
      yesterday: closedSince(source.delivered + source.approved, from: from, includeToday: false).map {
        issueLine($0.item)
      } + pulls.filter { within($0.createdAt, from: from, until: today) }.map(pullLine),
      today: own.filter { $0.statusCategory == .indeterminate && $0.flag == .none }.map(issueLine),
      blockers: blockerLines(own, pulls)
    )
  }

  // Only open pull requests are loaded, so a PR opened this week and already
  // merged is not here; the section says "abertos" and means exactly that.
  static func weekly(_ source: StandupSource, now: Date, calendar: Calendar = .current) -> WeeklySummary {
    let from = startOfWeek(now, calendar: calendar)
    let own = source.open.filter(isOwnWork)
    let pulls = source.myPulls.filter(\.isPullRequest)
    return WeeklySummary(
      delivered: closedSince(source.delivered + source.approved, from: from, includeToday: true).map {
        issueLine($0.item)
      },
      pulls: pulls.filter { within($0.createdAt, from: from, until: now) }.map(pullLine),
      blockers: blockerLines(own, pulls)
    )
  }

  private static func sections(_ sections: [(title: String, lines: [String], empty: String)]) -> String {
    sections.map { section in
      let items = section.lines.isEmpty ? [section.empty] : section.lines
      return ([section.title] + items.map { "- \($0)" }).joined(separator: "\n")
    }
    .joined(separator: "\n\n")
  }

  static func text(_ standup: Standup) -> String {
    sections([
      ("Ontem", standup.yesterday, "Nada entregue"),
      ("Hoje", standup.today, "Nada em andamento"),
      ("Bloqueios", standup.blockers, "Nenhum"),
    ])
  }

  static func text(_ weekly: WeeklySummary) -> String {
    sections([
      ("Entregue na semana", weekly.delivered, "Nada entregue"),
      ("PRs abertos na semana", weekly.pulls, "Nenhum"),
      ("Bloqueios", weekly.blockers, "Nenhum"),
    ])
  }

  /// `summaryText` in `StandupDialog.tsx`.
  static func summary(_ range: StandupRange, source: StandupSource, now: Date) -> String {
    switch range {
    case .daily: text(standup(source, now: now))
    case .weekly: text(weekly(source, now: now))
    }
  }
}
