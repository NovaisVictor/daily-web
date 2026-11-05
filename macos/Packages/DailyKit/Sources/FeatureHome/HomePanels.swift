import DailyCore
import DailyDesign
import DailyModels
import Foundation

/// A state label on a row, drawn as a `StatusPill`.
struct HomePill: Equatable, Sendable {
  var label: String
  var glyph: StatusGlyph
  var tone: StatusTone
}

/// One read-only line of a panel.
struct HomeRow: Identifiable, Equatable, Sendable {
  var id: String
  /// The short column on the left: "#380", "TT-882", "10:00", "hoje".
  var lead: String
  /// Late things say so in the warning tone as well as in words.
  var leadIsLate = false
  var title: String
  /// Unread mail.
  var emphasized = false
  var pills: [HomePill] = []
  /// Joined with " · " under the title.
  var meta: [String] = []
  /// What `AppNavigator.open(_:itemID:)` should reveal; nil when the module cannot reveal one item.
  var itemID: String?

  var metaText: String { meta.joined(separator: " · ") }
}

/// One tab of a panel, or the whole body of a panel without tabs.
struct HomeTab: Identifiable, Equatable, Sendable {
  var id: String
  /// Empty for a panel without tabs.
  var label: String
  /// The number beside the tab label; hidden when zero, as `components/ui/legacy-tabs.tsx:78`.
  var count: Int
  /// What the panel header says next to the title while this tab is selected.
  var countText: String?
  /// The server answered with neither data nor error.
  var isOff = false
  var errors: [String] = []
  /// Up to `HomePanels.rowLimit` rows.
  var rows: [HomeRow] = []
  /// The web's empty copy, when the data came and there is nothing to list.
  var emptyText: String?
}

/// One module's panel on Início.
struct HomePanel: Identifiable, Equatable, Sendable {
  var module: ModuleID
  var title: String
  var tabs: [HomeTab]

  var id: String { module.rawValue }
  var hasTabs: Bool { tabs.count > 1 }
  var route: AppRoute { .module(module) }
}

/// The panels of Início: one per module that is on, in the web's panel
/// order (`components/dashboard/useDashboardPanels.tsx:50-141`), each with the rows
/// its web panel would show first. Notes are left out: their list is not in
/// `DashboardState` and the sidebar already opens them.
struct HomePanels: Equatable, Sendable {
  static let rowLimit = 5
  /// What a panel says when its module is on but the server sent neither data
  /// nor error. The web hides such a panel; here it would just vanish.
  static let offText = "Sem dados por enquanto."
  static let emDash = "—"

  var panels: [HomePanel]
  /// `nothingOn` in `components/dashboard/useDashboardPanels.tsx:48`.
  var nothingOn: Bool

  init(state: DashboardState, now: Date, calendar: Calendar = ClockText.calendar) {
    let clock = HomeClock(now: now, calendar: calendar)
    nothingOn = state.modules.isEmpty
    panels = ModuleID.known.filter(state.modules.contains).compactMap { module in
      switch module {
      case .email: Self.email(state.email, clock: clock)
      case .tasks: Self.tasks(state.tasks, clock: clock)
      case .agenda: Self.agenda(state.agenda, days: state.agendaDays, clock: clock)
      case .jira: Self.jira(state, clock: clock)
      case .pulls: Self.pulls(state, clock: clock)
      case .slack: Self.slack(state.slack, clock: clock)
      default: nil
      }
    }
  }

  // MARK: - E-mail

  /// Unread first, then the newest; "Caixa de entrada limpa." is `components/EmailPanel.tsx:1253`.
  static func email(_ panel: PanelResult<[EmailEnvelope]>, clock: HomeClock) -> HomePanel {
    var tab = HomeTab(panel, id: "inbox", label: "")
    if let envelopes = panel.data {
      let inbox = envelopes.filter { $0.mailbox == .inbox }
      let unread = inbox.filter(\.unread).count
      tab.count = unread
      tab.countText = unread == 1 ? "1 não lido" : "\(unread) não lidos"
      let ordered = inbox.enumerated().sorted { a, b in
        if a.element.unread != b.element.unread { return a.element.unread }
        let (da, db) = (clock.date(a.element.date), clock.date(b.element.date))
        if da != db { return (da ?? .distantPast) > (db ?? .distantPast) }
        return a.offset < b.offset
      }
      tab.rows = ordered.prefix(rowLimit).map { _, envelope in
        HomeRow(
          id: "\(envelope.account):\(envelope.id)",
          lead: clock.relative(envelope.date),
          title: envelope.subject.isEmpty ? emDash : envelope.subject,
          emphasized: envelope.unread,
          meta: [senderName(envelope.from)].filter { !$0.isEmpty },
          itemID: "\(envelope.account):\(envelope.id)")
      }
      if inbox.isEmpty { tab.emptyText = "Caixa de entrada limpa." }
    }
    return HomePanel(module: .email, title: "E-mail", tabs: [tab])
  }

  /// "Ana Souza <ana@example.com>" → "Ana Souza"; a bare address stays as it is.
  static func senderName(_ from: String) -> String {
    let trimmed = from.trimmingCharacters(in: .whitespaces)
    guard let open = trimmed.firstIndex(of: "<"), open > trimmed.startIndex else { return trimmed }
    let name = trimmed[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    return name.isEmpty ? trimmed : name
  }

  // MARK: - Tarefas

  /// `PRIORITY_LABEL` in `components/TasksPanel.tsx:84-88`.
  static func priorityLabel(_ priority: TaskPriority) -> String {
    switch priority {
    case .high: "Alta"
    case .low: "Baixa"
    default: "Normal"
    }
  }

  /// Open tasks: late, then today, then the rest by due date and priority, the
  /// undated last (`lib/taskGrouping.ts`). Empty copy: `components/TasksPanel.tsx:475`.
  static func tasks(_ panel: PanelResult<[TodoTask]>, clock: HomeClock) -> HomePanel {
    var tab = HomeTab(panel, id: "tasks", label: "")
    if let tasks = panel.data {
      let today = clock.today
      let (overdue, dueToday) = TaskDay.dueByToday(tasks, today: today)
      let open = tasks.filter { !$0.completed }
      let later = open.filter { !$0.due.isEmpty && $0.due > today }.sorted(by: TaskDay.dueThenPriority)
      let undated = open.filter(\.due.isEmpty).sorted {
        TaskDay.priorityRank($0.priority) < TaskDay.priorityRank($1.priority)
      }
      tab.count = open.count
      tab.countText = open.isEmpty ? nil : String(open.count)
      tab.rows = (overdue + dueToday + later + undated).prefix(rowLimit).map { task in
        let late = TaskDay.isOverdue(task, today: today)
        return HomeRow(
          id: task.id,
          lead: clock.dayLabel(task.due),
          leadIsLate: late,
          title: task.title.isEmpty ? emDash : task.title,
          pills: late ? [HomePill(label: "atrasada", glyph: .alert, tone: .warning)] : [],
          meta: [priorityLabel(task.priority), task.time].filter { !$0.isEmpty },
          itemID: task.id)
      }
      if open.isEmpty { tab.emptyText = "Nenhuma tarefa por aqui. Crie a primeira." }
    }
    return HomePanel(module: .tasks, title: "Tarefas", tabs: [tab])
  }

  // MARK: - Agenda

  /// `AGENDA_RANGES[].emptyLabel` in `lib/agendaWindow.ts:27-33`; unknown ranges fall back to two days.
  static func agendaEmpty(days: Int) -> String {
    let label =
      switch days {
      case 1: "para hoje"
      case 3, 7, 14: "nos próximos \(days) dias"
      default: "para hoje e amanhã"
      }
    return "Nada agendado \(label)."
  }

  /// What is still ahead in the window, all-day events first within a day
  /// (`components/AgendaPanel.tsx:34-37`). When everything already passed, the
  /// window's events stay listed rather than leaving a blank panel.
  static func agenda(_ panel: PanelResult<[AgendaItem]>, days: Int, clock: HomeClock) -> HomePanel {
    var tab = HomeTab(panel, id: "agenda", label: "")
    if let items = panel.data {
      let sorted = items.enumerated().sorted { a, b in
        (a.element.date, a.element.time, a.offset) < (b.element.date, b.element.time, b.offset)
      }.map(\.element)
      let ahead = sorted.filter { item in
        item.date > clock.today || (item.date == clock.today && (item.time.isEmpty || item.time >= clock.minute))
      }
      let todays = items.filter { $0.date == clock.today }.count
      tab.count = todays
      tab.countText = "\(todays) hoje"
      tab.rows = (ahead.isEmpty ? sorted : ahead).prefix(rowLimit).enumerated().map { index, item in
        let isToday = item.date == clock.today
        // `components/AgendaPanel.tsx:166-168`: "dia" for all-day, an em dash for no title.
        let lead = isToday ? (item.time.isEmpty ? "dia" : item.time) : clock.dayLabel(item.date)
        return HomeRow(
          id: "\(index)-\(item.account)-\(item.date)-\(item.time)-\(item.title)",
          lead: lead,
          title: item.title.isEmpty ? emDash : item.title,
          meta: [item.accountLabel, isToday ? "" : item.time].filter { !$0.isEmpty })
      }
      if items.isEmpty { tab.emptyText = agendaEmpty(days: days) }
    }
    return HomePanel(module: .agenda, title: "Agenda", tabs: [tab])
  }

  // MARK: - Jira

  /// The four tabs of `components/JiraPanel.tsx:709-724`, with the closed lists on
  /// the web's default "hoje" period (`JiraPanel.tsx:303,534`).
  static func jira(_ state: DashboardState, clock: HomeClock) -> HomePanel {
    var open = HomeTab(state.jira, id: "abertas", label: "Em aberto")
    if let items = state.jira.data {
      open.fill(items.map { jiraRow($0, clock: clock) }, empty: "Nenhuma issue atribuída.")
    }
    var delivered = HomeTab(state.jiraDelivered, id: "entregues", label: "Entregues")
    if let items = state.jiraDelivered.data {
      let todays = items.filter(\.today).map { jiraRow($0.item, clock: clock) }
      delivered.fill(todays, empty: "Nenhuma issue entregue hoje.")
    }
    var approved = HomeTab(state.jiraApproved, id: "aprovados", label: "Aprovados")
    if let items = state.jiraApproved.data {
      let todays = items.filter(\.today).map { jiraRow($0.item, clock: clock) }
      approved.fill(todays, empty: "Nenhuma issue aprovada hoje.")
    }
    var problems = HomeTab(state.jiraProblems, id: "problemas", label: "Problemas")
    if let items = state.jiraProblems.data {
      let rows = items.map { problem in
        var row = jiraRow(problem.item, clock: clock)
        row.meta = [problem.problems.map(JiraFormat.problemLabel).joined(separator: ", ")]
        return row
      }
      problems.fill(rows, empty: "Nenhuma história ou épico com problema.")
    }
    return HomePanel(module: .jira, title: "Jira", tabs: [open, delivered, approved, problems])
  }

  /// The row of `components/JiraPanel.tsx:1420-1440`: status, priority, stalled, due.
  static func jiraRow(_ issue: JiraItem, clock: HomeClock) -> HomeRow {
    let status = JiraFormat.normalizeStatus(issue.status)
    var pills: [HomePill] = []
    if !status.isEmpty {
      let (glyph, tone): (StatusGlyph, StatusTone) =
        switch issue.statusCategory {
        case .done: (.live, .success)
        case .indeterminate: (.moving, .info)
        default: (.idle, .neutral)
        }
      pills.append(HomePill(label: status, glyph: glyph, tone: tone))
    }
    let meta = [issue.priority?.name, clock.jiraStaleness(issue.updatedAt), clock.jiraDue(issue.dueDate)]
    return HomeRow(
      id: issue.key,
      lead: issue.key,
      title: issue.summary.isEmpty ? emDash : issue.summary,
      pills: pills,
      meta: meta.compactMap(\.self).filter { !$0.isEmpty },
      itemID: issue.key)
  }

  // MARK: - Pull requests

  /// The three tabs of `components/PullsPanel.tsx:310-312`; Acompanhados is the web's default.
  static func pulls(_ state: DashboardState, clock: HomeClock) -> HomePanel {
    var tracked = HomeTab(state.pulls, id: "acompanhados", label: "Acompanhados")
    if let digest = state.pulls.data {
      tracked.errors += digest.errors.isEmpty ? [] : [digest.errors.joined(separator: "; ")]
      tracked.fill(
        digest.items.map { pullRow($0, withRepo: false, clock: clock) },
        empty: "Nada aberto nos repositórios acompanhados.")
    }
    var reviews = HomeTab(state.reviewRequests, id: "revisoes", label: "Revisões")
    if let digest = state.reviewRequests.data {
      let errors = digest.errors ?? []
      reviews.errors += errors.isEmpty ? [] : [errors.joined(separator: "; ")]
      reviews.fill(
        digest.items.map { pullRow($0, withRepo: true, clock: clock) }, empty: "Nenhuma revisão pedida a você.")
    }
    var mine = HomeTab(state.myPulls, id: "meus", label: "Meus PRs")
    if let digest = state.myPulls.data {
      let errors = digest.errors ?? []
      mine.errors += errors.isEmpty ? [] : [errors.joined(separator: "; ")]
      mine.fill(digest.items.map { pullRow($0, withRepo: false, clock: clock) }, empty: "Nenhum PR seu aberto.")
    }
    return HomePanel(module: .pulls, title: "GitHub", tabs: [tracked, reviews, mine])
  }

  /// `components/pulls/PullRow.tsx` and `PullBadges.tsx`: CI, review, conflict,
  /// draft, then the age and the author when it is not you.
  static func pullRow(_ item: PullRequestItem, withRepo: Bool, clock: HomeClock) -> HomeRow {
    var pills: [HomePill] = []
    if item.isPullRequest {
      switch item.ci {
      case .failing: pills.append(HomePill(label: "CI falhou", glyph: .alert, tone: .destructive))
      case .running: pills.append(HomePill(label: "CI rodando", glyph: .moving, tone: .info))
      case .passing: pills.append(HomePill(label: "CI ok", glyph: .live, tone: .success))
      default: break
      }
      switch item.review {
      case .changesRequested: pills.append(HomePill(label: "pediram mudanças", glyph: .alert, tone: .warning))
      case .approved: pills.append(HomePill(label: "aprovado", glyph: .live, tone: .success))
      case .pending: pills.append(HomePill(label: "aguardando revisão", glyph: .idle, tone: .neutral))
      default: break
      }
      if item.merge == .conflict {
        pills.append(HomePill(label: "conflito", glyph: .alert, tone: .destructive))
      }
    }
    if item.draft { pills.append(HomePill(label: "rascunho", glyph: .idle, tone: .neutral)) }
    var meta = withRepo ? [item.repo] : []
    if let age = clock.pullAge(createdAt: item.createdAt, updatedAt: item.updatedAt) {
      meta.append(age.opened)
      if let stalled = age.stalled { meta.append(stalled) }
    }
    if !item.mine && !item.author.isEmpty { meta.append(item.author) }
    let ref = "\(item.repo)#\(item.number)"
    return HomeRow(
      id: ref, lead: "#\(item.number)", title: item.title.isEmpty ? emDash : item.title, pills: pills, meta: meta,
      itemID: ref)
  }

  // MARK: - Slack

  /// The two tabs of `components/SlackPanel.tsx:80-81`, empty copy at `:91-92`.
  static func slack(_ panel: PanelResult<SlackDigest>, clock: HomeClock) -> HomePanel {
    var mentions = HomeTab(panel, id: "mencoes", label: "Menções")
    var directs = HomeTab(panel, id: "diretas", label: "Mensagens diretas")
    if let digest = panel.data {
      mentions.fill(digest.mentions.map { slackRow($0, clock: clock) }, empty: "Nenhuma menção nos últimos 7 dias.")
      directs.fill(digest.directs.map { slackRow($0, clock: clock) }, empty: "Nenhuma mensagem direta não lida.")
    }
    return HomePanel(module: .slack, title: "Slack", tabs: [mentions, directs])
  }

  static func slackRow(_ message: SlackMessage, clock: HomeClock) -> HomeRow {
    HomeRow(
      id: message.id,
      lead: clock.relative(message.date),
      title: message.text.isEmpty ? emDash : message.text,
      meta: [message.author, message.channel].filter { !$0.isEmpty },
      itemID: message.id)
  }
}

extension HomeTab {
  /// Takes the panel's off flag and error; data and error can come together.
  fileprivate init<Value>(_ panel: PanelResult<Value>, id: String, label: String) {
    self.init(id: id, label: label, count: 0, isOff: panel.isOff, errors: panel.error.map { [$0] } ?? [])
  }

  /// A tab whose header count is the size of its list (`PullsPanel.tsx:283-296`).
  fileprivate mutating func fill(_ all: [HomeRow], empty: String) {
    count = all.count
    countText = all.isEmpty ? nil : String(all.count)
    rows = Array(all.prefix(HomePanels.rowLimit))
    if all.isEmpty { emptyText = empty }
  }
}

/// The dates and labels the rows need, against one fixed "now".
struct HomeClock: Sendable {
  let now: Date
  let calendar: Calendar
  let today: String
  let minute: String

  private static let dayMS = 86_400.0
  /// `STALE_UPDATE_MS` in `lib/pullAge.ts:5`.
  private static let pullStaleSeconds = 3 * dayMS

  init(now: Date, calendar: Calendar) {
    self.now = now
    self.calendar = calendar
    today = TaskDay.isoDay(now, calendar: calendar)
    minute = TaskDay.minuteOfDay(now, calendar: calendar)
  }

  /// The server's ISO timestamps, with or without milliseconds.
  func date(_ value: String) -> Date? { RelativeTime.parseISO(value) }

  /// `relativeTime` in `lib/filters.ts:23-43`: "agora", "12min", "3h", "ontem", "4d", "02/10".
  func relative(_ iso: String) -> String {
    guard let then = date(iso) else { return HomePanels.emDash }
    return RelativeTime.short(then, now: now, calendar: calendar)
  }

  /// A `YYYY-MM-DD` day as the lead of a row: "hoje", "amanhã", or "DD/MM"
  /// (`formatDue` in `components/TasksPanel.tsx:98-102`); "—" without a date.
  func dayLabel(_ iso: String) -> String {
    if iso.isEmpty { return HomePanels.emDash }
    if iso == today { return "hoje" }
    if iso == TaskDay.addDays(today, 1) { return "amanhã" }
    let parts = iso.split(separator: "-")
    guard parts.count == 3 else { return iso }
    return "\(parts[2])/\(parts[1])"
  }

  /// `pullAge` in `lib/pullAge.ts:31-43`.
  func pullAge(createdAt: String, updatedAt: String) -> (opened: String, stalled: String?)? {
    guard let created = date(createdAt) else { return nil }
    let open = max(0, now.timeIntervalSince(created))
    let idle = date(updatedAt).map { max(0, now.timeIntervalSince($0)) }
    let opened = open < Self.dayMS ? "aberto hoje" : "aberto há \(Self.days(open))"
    let stalled = idle.flatMap { $0 > Self.pullStaleSeconds ? "parado há \(Self.days($0))" : nil }
    return (opened, stalled)
  }

  /// `formatDays` in `lib/pullAge.ts:23-25`.
  private static func days(_ seconds: TimeInterval) -> String {
    let count = Int((seconds / dayMS).rounded(.down))
    return count == 1 ? "1 dia" : "\(count) dias"
  }

  /// `stalenessLabel` in `lib/parsers/jira.ts:171-175`.
  func jiraStaleness(_ updatedAt: String) -> String? {
    JiraFormat.stalenessLabel(updatedAt: updatedAt, now: now)
  }

  /// `dueLabel` in `lib/parsers/jira.ts:184-196`, counted in local days.
  func jiraDue(_ dueDate: String) -> String? {
    JiraFormat.dueLabel(dueDate, now: now, calendar: calendar)
  }
}
