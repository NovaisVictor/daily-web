import DailyModels
import Foundation

/// One number on a summary card, e.g. "3 atrasadas".
struct HomeMetric: Equatable, Sendable {
  var value: Int
  var label: String
  /// Drawn in the danger tone when non-zero (late tasks).
  var urgent = false
}

/// One module's compact card on the "Hoje" screen.
struct HomeCard: Identifiable, Equatable, Sendable {
  var module: ModuleID
  var title: String
  var systemImage: String
  /// The panel came back with neither data nor error.
  var isOff = false
  /// Every `PanelResult.error` the card depends on; shown next to the data that did come.
  var errors: [String] = []
  var metrics: [HomeMetric] = []
  /// Up to `HomeSummary.previewLimit` rows of what the numbers count.
  var lines: [String] = []
  /// The web's empty copy, when the data came and there is nothing to show.
  var emptyText: String?

  var id: String { module.rawValue }
}

/// The cards of the "Hoje" screen, one per module that is on, in the web's panel order.
struct HomeSummary: Equatable, Sendable {
  static let previewLimit = 3
  /// What a card says when its module is on but the panel came back empty-handed
  /// (both fields null). The web hides such a panel; a card cannot just vanish.
  static let offText = "Sem dados por enquanto."
  /// `components/AgendaPanel.tsx:149` with the one-day range of `lib/agendaWindow.ts:28`.
  static let agendaEmpty = "Nada agendado para hoje."
  /// `components/SlackPanel.tsx:93`.
  static let slackEmpty = "Nenhuma menção nos últimos 7 dias."

  var cards: [HomeCard]
  /// `nothingOn` in `components/dashboard/useDashboardPanels.tsx:48`.
  var nothingOn: Bool

  init(state: DashboardState, now: Date, calendar: Calendar = ClockText.calendar) {
    let today = ClockText.isoDay(now, calendar: calendar)
    let minute = ClockText.minuteOfDay(now, calendar: calendar)
    nothingOn = state.modules.isEmpty
    cards = ModuleID.known.filter(state.modules.contains).compactMap { module in
      switch module {
      case .email: Self.email(state.email)
      case .tasks: Self.tasks(state.tasks, today: today)
      case .notes: HomeCard(module: .notes, title: "Notas rápidas", systemImage: "note.text")
      case .agenda: Self.agenda(state.agenda, today: today, minute: minute)
      case .jira: Self.jira(state.jira, problems: state.jiraProblems)
      case .pulls: Self.pulls(review: state.reviewRequests, followed: state.pulls)
      case .slack: Self.slack(state.slack)
      default: nil
      }
    }
  }

  static func email(_ panel: PanelResult<[EmailEnvelope]>) -> HomeCard {
    var card = HomeCard(module: .email, title: "E-mail", systemImage: "envelope")
    guard let envelopes = card.receive(panel) else { return card }
    let unread = envelopes.filter(\.unread)
    card.metrics = [HomeMetric(value: unread.count, label: "não lidos")]
    card.lines = unread.prefix(previewLimit).map { $0.subject.isEmpty ? "—" : $0.subject }
    return card
  }

  /// Late and still open, then due today and still open; same day boundary as
  /// `isOverdue` and the "HOJE" group of `lib/taskGrouping.ts:29-33,77-79`.
  static func tasks(_ panel: PanelResult<[TodoTask]>, today: String) -> HomeCard {
    var card = HomeCard(module: .tasks, title: "Tarefas", systemImage: "checklist")
    guard let tasks = card.receive(panel) else { return card }
    let open = tasks.filter { !$0.completed && !$0.due.isEmpty }
    let overdue = open.filter { $0.due < today }.sorted(by: dueThenPriority)
    let dueToday = open.filter { $0.due == today }.sorted(by: dueThenPriority)
    card.metrics = [
      HomeMetric(value: overdue.count, label: "atrasadas", urgent: true),
      HomeMetric(value: dueToday.count, label: "para hoje"),
    ]
    card.lines = (overdue + dueToday).prefix(previewLimit).map(\.title)
    return card
  }

  /// Today's events; the preview lists what is still ahead (all-day ones included).
  static func agenda(_ panel: PanelResult<[AgendaItem]>, today: String, minute: String) -> HomeCard {
    var card = HomeCard(module: .agenda, title: "Agenda", systemImage: "calendar")
    guard let items = card.receive(panel) else { return card }
    // The web's sort (`components/AgendaPanel.tsx:34-37`): all-day ("") first.
    let todays = items.filter { $0.date == today }.sorted { $0.time < $1.time }
    let ahead = todays.filter { $0.time.isEmpty || $0.time >= minute }
    card.metrics = [HomeMetric(value: todays.count, label: "eventos hoje")]
    card.lines = ahead.prefix(previewLimit).map { item in
      // `components/AgendaPanel.tsx:166-168`: "dia" for all-day, an em dash for no title.
      "\(item.time.isEmpty ? "dia" : item.time)  \(item.title.isEmpty ? "—" : item.title)"
    }
    if todays.isEmpty { card.emptyText = agendaEmpty }
    return card
  }

  /// "aguardando a sua aprovação" (`components/JiraPanel.tsx:1415`) and the "Problemas" tab.
  static func jira(_ panel: PanelResult<[JiraItem]>, problems: PanelResult<[JiraProblemItem]>) -> HomeCard {
    var card = HomeCard(module: .jira, title: "Jira", systemImage: "list.bullet.rectangle")
    card.isOff = panel.isOff && problems.isOff
    card.errors = [panel.error, problems.error].compactMap(\.self)
    let awaiting = panel.data?.filter(\.awaitingApproval) ?? []
    if panel.data != nil {
      card.metrics.append(HomeMetric(value: awaiting.count, label: "aguardando aprovação"))
    }
    if let problems = problems.data {
      card.metrics.append(HomeMetric(value: problems.count, label: "problemas"))
    }
    card.lines = awaiting.prefix(previewLimit).map { "\($0.key)  \($0.summary)" }
    return card
  }

  /// The "Revisões" tab of `components/PullsPanel.tsx:311`: pull requests waiting on your review.
  static func pulls(review: PanelResult<ReviewRequestsDigest>, followed: PanelResult<PullsDigest>) -> HomeCard {
    var card = HomeCard(module: .pulls, title: "Pull requests", systemImage: "arrow.triangle.pull")
    card.isOff = review.isOff && followed.isOff
    card.errors = [review.error, followed.error].compactMap(\.self)
    if let digest = review.data {
      card.metrics = [HomeMetric(value: digest.items.count, label: "aguardando sua revisão")]
      card.lines = digest.items.prefix(previewLimit).map { "\($0.repo)#\($0.number)  \($0.title)" }
    }
    return card
  }

  /// The two tabs of `components/SlackPanel.tsx:80-81`.
  static func slack(_ panel: PanelResult<SlackDigest>) -> HomeCard {
    var card = HomeCard(module: .slack, title: "Slack", systemImage: "bubble.left.and.bubble.right")
    guard let digest = card.receive(panel) else { return card }
    card.metrics = [
      HomeMetric(value: digest.mentions.count, label: "menções"),
      HomeMetric(value: digest.directs.count, label: "mensagens diretas"),
    ]
    card.lines = digest.mentions.prefix(previewLimit).map { "\($0.author)  \($0.text)" }
    if digest.mentions.isEmpty { card.emptyText = slackEmpty }
    return card
  }

  /// `lib/taskGrouping.ts:61-64` without the completed key: only open tasks get here.
  private static func dueThenPriority(_ a: TodoTask, _ b: TodoTask) -> Bool {
    if a.due != b.due { return a.due < b.due }
    return priorityRank(a.priority) < priorityRank(b.priority)
  }

  private static func priorityRank(_ priority: TaskPriority) -> Int {
    switch priority {
    case .high: 0
    case .low: 2
    default: 1
    }
  }
}

extension HomeCard {
  /// Off, error and data are not exclusive: the server can send data with a partial error.
  /// Takes the panel's off flag and error, and hands back its data when there is any.
  fileprivate mutating func receive<Value>(_ panel: PanelResult<Value>) -> Value? {
    isOff = panel.isOff
    errors = panel.error.map { [$0] } ?? []
    return panel.data
  }
}
