// FROZEN NAME (T006): `DashboardState` and the properties declared here are used
// by the shell and core. T101 adds every remaining key of `lib/types.ts:418-472`
// to this type; it must not rename or remove these.

/// The whole dashboard, as `GET /api/state` returns it (`lib/types.ts:418-472`).
/// A module that is off comes as a `PanelResult` with both fields null.
public struct DashboardState: Codable, Sendable, Equatable {
  public var updatedAt: String
  public var modules: [ModuleID]
  public var mailboxes: [MailboxRef]
  /// How many days the agenda covers, today included.
  public var agendaDays: Int
  public var agendaCalendars: [AgendaCalendarRef]
  public var tasksView: TasksView
  /// Web only; the app ignores it.
  public var homeView: HomeView
  /// Web only; the app ignores it.
  public var layout: [LayoutItem]
  /// Web only; the app ignores it.
  public var layouts: [SavedLayout]
  public var email: PanelResult<[EmailEnvelope]>
  public var agenda: PanelResult<[AgendaItem]>
  public var pulls: PanelResult<PullsDigest>
  public var reviewRequests: PanelResult<ReviewRequestsDigest>
  public var myPulls: PanelResult<MyPullsDigest>
  public var jira: PanelResult<[JiraItem]>
  public var jiraWatched: PanelResult<[JiraItem]>
  public var jiraFollowedPeople: [JiraPerson]
  public var jiraDelivered: PanelResult<[JiraDatedItem]>
  public var jiraApproved: PanelResult<[JiraDatedItem]>
  public var jiraProblems: PanelResult<[JiraProblemItem]>
  /// Parents of the issues above, up to the objective. Empty when the climb fails.
  public var jiraAncestors: [JiraItem]
  public var tasks: PanelResult<[TodoTask]>
  public var slack: PanelResult<SlackDigest>
  public var notifications: PanelResult<[NotificationItem]>
  public var pomodoro: PomodoroState
  /// When the background cycle runs again; null when it is not scheduled.
  public var nextRefreshAt: String?

  /// Everything past `modules` defaults to the server's own defaults
  /// (`lib/agendaWindow.ts:37`, `lib/pomodoro.ts:3-4`) with every panel off, so
  /// the two-argument form from T006 keeps compiling.
  public init(
    updatedAt: String,
    modules: [ModuleID],
    mailboxes: [MailboxRef] = [],
    agendaDays: Int = 2,
    agendaCalendars: [AgendaCalendarRef] = [],
    tasksView: TasksView = .list,
    homeView: HomeView = .grid,
    layout: [LayoutItem] = [],
    layouts: [SavedLayout] = [],
    email: PanelResult<[EmailEnvelope]> = PanelResult(data: nil, error: nil),
    agenda: PanelResult<[AgendaItem]> = PanelResult(data: nil, error: nil),
    pulls: PanelResult<PullsDigest> = PanelResult(data: nil, error: nil),
    reviewRequests: PanelResult<ReviewRequestsDigest> = PanelResult(data: nil, error: nil),
    myPulls: PanelResult<MyPullsDigest> = PanelResult(data: nil, error: nil),
    jira: PanelResult<[JiraItem]> = PanelResult(data: nil, error: nil),
    jiraWatched: PanelResult<[JiraItem]> = PanelResult(data: nil, error: nil),
    jiraFollowedPeople: [JiraPerson] = [],
    jiraDelivered: PanelResult<[JiraDatedItem]> = PanelResult(data: nil, error: nil),
    jiraApproved: PanelResult<[JiraDatedItem]> = PanelResult(data: nil, error: nil),
    jiraProblems: PanelResult<[JiraProblemItem]> = PanelResult(data: nil, error: nil),
    jiraAncestors: [JiraItem] = [],
    tasks: PanelResult<[TodoTask]> = PanelResult(data: nil, error: nil),
    slack: PanelResult<SlackDigest> = PanelResult(data: nil, error: nil),
    notifications: PanelResult<[NotificationItem]> = PanelResult(data: nil, error: nil),
    pomodoro: PomodoroState = .disabled,
    nextRefreshAt: String? = nil
  ) {
    self.updatedAt = updatedAt
    self.modules = modules
    self.mailboxes = mailboxes
    self.agendaDays = agendaDays
    self.agendaCalendars = agendaCalendars
    self.tasksView = tasksView
    self.homeView = homeView
    self.layout = layout
    self.layouts = layouts
    self.email = email
    self.agenda = agenda
    self.pulls = pulls
    self.reviewRequests = reviewRequests
    self.myPulls = myPulls
    self.jira = jira
    self.jiraWatched = jiraWatched
    self.jiraFollowedPeople = jiraFollowedPeople
    self.jiraDelivered = jiraDelivered
    self.jiraApproved = jiraApproved
    self.jiraProblems = jiraProblems
    self.jiraAncestors = jiraAncestors
    self.tasks = tasks
    self.slack = slack
    self.notifications = notifications
    self.pomodoro = pomodoro
    self.nextRefreshAt = nextRefreshAt
  }
}
