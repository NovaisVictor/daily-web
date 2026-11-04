import DailyModels
import Foundation

/// Where clicking an alert takes the user.
public struct AlertTarget: Equatable, Sendable {
  public var route: AppRoute
  /// The item inside the route: email `account:id`, Jira key, pull `repo#number`,
  /// Slack message id, agent task id. nil when the route is enough.
  public var itemID: String?
  /// The item's web address, when the server gave one.
  public var url: String?

  public init(route: AppRoute, itemID: String? = nil, url: String? = nil) {
    self.route = route
    self.itemID = itemID
    self.url = url
  }

  private enum Key {
    static let route = "route"
    static let itemID = "itemID"
    static let url = "url"
  }

  /// For `UNNotificationContent.userInfo`.
  public var userInfo: [String: String] {
    var info = [Key.route: Self.encode(route)]
    if let itemID { info[Key.itemID] = itemID }
    if let url, !url.isEmpty { info[Key.url] = url }
    return info
  }

  /// Reads back what `userInfo` wrote, from a clicked notification.
  public init?(userInfo: [AnyHashable: Any]) {
    guard let text = userInfo[Key.route] as? String, let route = Self.decode(text) else { return nil }
    self.init(route: route, itemID: userInfo[Key.itemID] as? String, url: userInfo[Key.url] as? String)
  }

  static func encode(_ route: AppRoute) -> String {
    switch route {
    case .today: "today"
    case .agents: "agents"
    case .access: "access"
    case .module(let module): "module:\(module.rawValue)"
    }
  }

  static func decode(_ text: String) -> AppRoute? {
    switch text {
    case "today": return .today
    case "agents": return .agents
    case "access": return .access
    default:
      guard text.hasPrefix("module:") else { return nil }
      return .module(ModuleID(rawValue: String(text.dropFirst("module:".count))))
    }
  }
}

/// One system notification (`DesktopAlert`, `lib/desktopAlerts.ts:4-9`).
public struct DesktopAlert: Equatable, Sendable {
  /// Dedupe key; a notification with the same tag replaces the previous one.
  public var tag: String
  public var title: String
  public var body: String
  public var target: AlertTarget
  /// The bell's notice for the same item (`NotificationItem.id`), when there is
  /// one: the system notification then offers "Marcar como lida".
  public var notificationID: String?

  /// `UNNotificationCategory` id of alerts that carry a `notificationID`.
  public static let dashboardCategory = "dashboard-notification"
  /// `userInfo` key of the `notificationID`.
  public static let notificationIDKey = "notificationID"

  public init(tag: String, title: String, body: String, target: AlertTarget, notificationID: String? = nil) {
    self.tag = tag
    self.title = title
    self.body = body
    self.target = target
    self.notificationID = notificationID
  }

  /// `target.userInfo` plus the notice id.
  public var userInfo: [String: String] {
    var info = target.userInfo
    if let notificationID { info[Self.notificationIDKey] = notificationID }
    return info
  }
}

/// `AlertSource` (`lib/desktopAlerts.ts:11`) plus the app's agent source.
public nonisolated enum AlertSource: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
  case email
  case jira
  case jiraProblem
  case pull
  case review
  case agenda
  case slack
  /// Not in the web, which only flashes the tab title (`AgentBoard.tsx:36-44`).
  case agent
}

/// What was already announced (`SeenState`, `lib/desktopAlerts.ts:13-17`),
/// persisted so a relaunch does not repeat alerts.
public nonisolated struct SeenState: Codable, Sendable, Equatable {
  public var v: Int
  /// A source without an entry has never been seen: its first list is the baseline.
  public var sources: [AlertSource: [String]]
  public var reminders: [String]

  public init(sources: [AlertSource: [String]] = [:], reminders: [String] = []) {
    v = 1
    self.sources = sources
    self.reminders = reminders
  }
}

/// An agent task waiting on the user, as `needsYou` in
/// `components/agents/contracts.ts:34` decides (`AgentAttentionRules.waiting`).
public nonisolated struct AgentAttention: Equatable, Sendable {
  public var taskID: String
  public var title: String
  /// When it started waiting; a new wait on the same task alerts again.
  public var since: String
  /// `AgentNeedsYou.kind`: `permission` picks the permission wording.
  public var kind: String
  /// The assigned agent's display name; empty when the task has none.
  public var agent: String

  public init(taskID: String, title: String, since: String, kind: String, agent: String) {
    self.taskID = taskID
    self.title = title
    self.since = since
    self.kind = kind
    self.agent = agent
  }
}

/// The pure rules of `lib/desktopAlerts.ts`, line by line.
public enum AlertRules {
  /// `PROBLEM_LABEL`, `lib/parsers/jiraProblems.ts:68-74`.
  static func problemLabel(_ problem: JiraProblem) -> String {
    switch problem {
    case .storyInProgressWithoutStart: "em andamento sem data de início"
    case .storyDoneWithoutStart: "concluída sem data de início"
    case .storyWithoutEpic: "sem épico"
    case .epicWithoutStories: "sem histórias"
    case .epicInProgressWithoutActiveStory: "em andamento sem história em andamento"
    default: problem.rawValue
    }
  }

  static func agendaKey(_ prefix: String, _ item: AgendaItem) -> String {
    "\(prefix):\(item.account)|\(item.date)|\(item.time)|\(item.title)"
  }

  static func agendaBody(_ item: AgendaItem) -> String {
    let parts = item.date.split(separator: "-", omittingEmptySubsequences: false)
    let month = parts.count > 1 ? String(parts[1]) : "undefined"
    let day = parts.count > 2 ? String(parts[2]) : "undefined"
    let time = item.time.isEmpty ? "dia inteiro" : item.time
    return "\(day)/\(month) \(time) — \(item.title)"
  }

  /// Ordered alerts per source; nil when the panel has no data (off or failed).
  typealias Current = [AlertSource: [(key: String, alert: DesktopAlert)]?]

  /// `currentAlerts`, `lib/desktopAlerts.ts:32-131`.
  static func currentAlerts(_ state: DashboardState) -> Current {
    var result: Current = [:]

    result[.email] = state.email.data.map { items in
      items.compactMap { item in
        guard item.mailbox == .inbox, item.unread else { return nil }
        let key = "email:\(item.messageId.isEmpty ? "\(item.account):\(item.id)" : item.messageId)"
        let subject = item.subject.isEmpty ? "(sem assunto)" : item.subject
        let target = AlertTarget(route: .module(.email), itemID: "\(item.account):\(item.id)")
        return (key, DesktopAlert(tag: key, title: "Novo e-mail", body: "\(item.from) — \(subject)", target: target))
      }
    }

    result[.jira] = state.jira.data.map { items in
      items.compactMap { item in
        guard item.role != .reporter else { return nil }
        let key = "jira:\(item.key)"
        let title = item.awaitingApproval ? "Aprovação pendente" : "Nova issue no seu nome"
        let target = AlertTarget(route: .module(.jira), itemID: item.key, url: item.url)
        return (key, DesktopAlert(tag: key, title: title, body: "\(item.key) — \(item.summary)", target: target))
      }
    }

    result[.jiraProblem] = state.jiraProblems.data.map { items in
      items.flatMap { item in
        item.problems.map { problem in
          let key = "jira-problem:\(item.item.key):\(problem.rawValue)"
          let target = AlertTarget(route: .module(.jira), itemID: item.item.key, url: item.item.url)
          let body = "\(item.item.key) — \(problemLabel(problem))"
          return (key, DesktopAlert(tag: key, title: "Issue com problema", body: body, target: target))
        }
      }
    }

    result[.pull] = state.pulls.data.map { digest in
      digest.items.compactMap { item in
        guard item.isPullRequest, !item.mine else { return nil }
        let key = "pr:\(item.repo)#\(item.number)"
        let target = AlertTarget(route: .module(.pulls), itemID: "\(item.repo)#\(item.number)", url: item.url)
        let body = "\(item.repo)#\(item.number) — \(item.title)"
        return (key, DesktopAlert(tag: key, title: "Novo PR", body: body, target: target))
      }
    }

    result[.review] = state.reviewRequests.data.map { digest in
      digest.items.map { item in
        let key = "review:\(item.repo)#\(item.number)"
        let target = AlertTarget(route: .module(.pulls), itemID: "\(item.repo)#\(item.number)", url: item.url)
        let body = "\(item.repo)#\(item.number) — \(item.title)"
        return (key, DesktopAlert(tag: key, title: "Revisão pedida", body: body, target: target))
      }
    }

    result[.agenda] = state.agenda.data.map { items in
      items.map { item in
        let key = agendaKey("agenda", item)
        let target = AlertTarget(route: .module(.agenda))
        return (key, DesktopAlert(tag: key, title: "Novo evento na agenda", body: agendaBody(item), target: target))
      }
    }

    result[.slack] = state.slack.data.map { digest in
      let mentions = digest.mentions.map { item in
        slackAlert(item, title: "Menção no Slack")
      }
      let directs = digest.directs.map { item in
        slackAlert(item, title: "Mensagem no Slack")
      }
      return mentions + directs
    }

    return linkNotifications(result, notifications: state.notifications.data ?? [])
  }

  /// Ties each alert to the bell's notice for the same item. The notice ids are
  /// `source:externalId` (`notificationId`, `lib/notifications.ts`), with the
  /// same external ids the alert keys use. Review requests have no plain
  /// notice (only the stale-review one, a different item), so they get none.
  static func linkNotifications(_ current: Current, notifications: [NotificationItem]) -> Current {
    let known = Set(notifications.map(\.id))
    guard !known.isEmpty else { return current }
    let prefixes: [AlertSource: (alert: String, notice: String)] = [
      .email: ("email:", "email:"),
      .jira: ("jira:", "jira_mention:"),
      .pull: ("pr:", "pull_request:"),
      .slack: ("slack:", "slack:"),
    ]
    var linked = current
    for (source, prefix) in prefixes {
      guard let entry = current[source], let items = entry else { continue }
      linked[source] = items.map { item in
        guard item.key.hasPrefix(prefix.alert) else { return item }
        let candidate = prefix.notice + item.key.dropFirst(prefix.alert.count)
        guard known.contains(candidate) else { return item }
        var alert = item.alert
        alert.notificationID = candidate
        return (item.key, alert)
      }
    }
    return linked
  }

  private static func slackAlert(_ item: SlackMessage, title: String) -> (key: String, alert: DesktopAlert) {
    let key = "slack:\(item.id)"
    let target = AlertTarget(route: .module(.slack), itemID: item.id, url: item.url)
    return (key, DesktopAlert(tag: key, title: title, body: "\(item.author) — \(item.text)", target: target))
  }

  /// Agent tasks waiting on the user, keyed like the dashboard sources. The
  /// words are the web push's (`attentionPayload`, `lib/push/dispatch.ts:53-54`),
  /// title cut at 120 characters like there.
  static func agentAlerts(_ waiting: [AgentAttention]) -> [(key: String, alert: DesktopAlert)] {
    waiting.map { item in
      let key = "agent:\(item.taskID):\(item.since)"
      let target = AlertTarget(route: .agents, itemID: item.taskID)
      // The push always names the session's agent; a task held for a decision
      // may have none assigned.
      let agent = item.agent.isEmpty ? "O agente" : item.agent
      let (title, body) =
        item.kind == "permission"
        ? ("Pedindo permissão: \(item.title)", "\(agent) está esperando você aprovar uma ação.")
        : ("Aguardando sua resposta: \(item.title)", "\(agent) parou e está esperando você.")
      return (key, DesktopAlert(tag: key, title: String(title.prefix(120)), body: body, target: target))
    }
  }

  /// `diffAlerts`, `lib/desktopAlerts.ts:133-155`. Later duplicates of a key win,
  /// like a JavaScript `Map`.
  static func diff(_ seen: SeenState, _ current: Current) -> (alerts: [DesktopAlert], seen: SeenState) {
    var alerts: [DesktopAlert] = []
    var sources = seen.sources
    for source in AlertSource.allCases {
      guard let entry = current[source], let items = entry else { continue }
      let unique = uniqued(items)
      if let previous = seen.sources[source] {
        let known = Set(previous)
        alerts += unique.filter { !known.contains($0.key) }.map(\.alert)
      }
      sources[source] = unique.map(\.key)
    }
    return (alerts, SeenState(sources: sources, reminders: seen.reminders))
  }

  private static func uniqued(_ items: [(key: String, alert: DesktopAlert)]) -> [(key: String, alert: DesktopAlert)] {
    var order: [String] = []
    var latest: [String: DesktopAlert] = [:]
    for item in items {
      if latest[item.key] == nil { order.append(item.key) }
      latest[item.key] = item.alert
    }
    return order.compactMap { key in latest[key].map { (key, $0) } }
  }

  /// `dueReminders`, `lib/desktopAlerts.ts:157-194`: events with a time that
  /// start within `leadMinutes`, once each.
  static func dueReminders(
    _ agenda: [AgendaItem],
    now: Date,
    seen: SeenState,
    calendar: Calendar,
    leadMinutes: Int = 10
  ) -> (alerts: [DesktopAlert], seen: SeenState) {
    var alerts: [DesktopAlert] = []
    let known = Set(seen.reminders)
    var retained: [String] = []
    let cutoff = now.addingTimeInterval(-24 * 60 * 60)

    func retain(_ key: String) {
      if !retained.contains(key) { retained.append(key) }
    }

    for item in agenda where !item.time.isEmpty {
      // Server and app share the time zone; the date and time are local.
      guard let start = localDate(item.date, item.time, calendar: calendar) else { continue }
      let key = agendaKey("reminder", item)
      if start >= cutoff, known.contains(key) { retain(key) }

      let remaining = start.timeIntervalSince(now)
      if remaining <= 0 || remaining > Double(leadMinutes * 60) || known.contains(key) { continue }
      retain(key)
      let minutes = Int((remaining / 60).rounded(.up))
      alerts.append(
        DesktopAlert(
          tag: key,
          title: "Em \(minutes) min",
          body: "\(item.time) — \(item.title)",
          target: AlertTarget(route: .module(.agenda))
        ))
    }
    var next = seen
    next.reminders = retained
    return (alerts, next)
  }

  /// `summarize`, `lib/desktopAlerts.ts:196-207`.
  static func summarize(_ alerts: [DesktopAlert], max: Int = 5) -> [DesktopAlert] {
    guard alerts.count > max else { return alerts }
    return [
      DesktopAlert(
        tag: "resumo",
        title: "daily-web",
        body: "\(alerts.count) novidades no painel",
        target: AlertTarget(route: .today)
      )
    ]
  }

  static func localDate(_ date: String, _ time: String, calendar: Calendar) -> Date? {
    let day = date.split(separator: "-").compactMap { Int($0) }
    let clock = time.split(separator: ":").compactMap { Int($0) }
    guard day.count == 3, clock.count >= 2 else { return nil }
    let components = DateComponents(year: day[0], month: day[1], day: day[2], hour: clock[0], minute: clock[1])
    return calendar.date(from: components)
  }
}
