/// The three normalized Jira situations (`lib/types.ts:215`).
public struct JiraStatusCategory: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let new = JiraStatusCategory(rawValue: "new")
  public static let indeterminate = JiraStatusCategory(rawValue: "indeterminate")
  public static let done = JiraStatusCategory(rawValue: "done")
  public static let known: [JiraStatusCategory] = [.new, .indeterminate, .done]
}

/// `lib/types.ts:206`.
public struct JiraRole: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let assignee = JiraRole(rawValue: "assignee")
  public static let reporter = JiraRole(rawValue: "reporter")
  public static let both = JiraRole(rawValue: "both")
  public static let known: [JiraRole] = [.assignee, .reporter, .both]
}

/// Jira's "Flagged" field (`lib/types.ts:218`).
public struct JiraFlag: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let impediment = JiraFlag(rawValue: "impediment")
  public static let none = JiraFlag(rawValue: "none")
  public static let known: [JiraFlag] = [.impediment, .none]
}

/// `lib/types.ts:208-211`.
public struct JiraParent: Codable, Sendable, Equatable, Hashable {
  public var key: String
  public var summary: String

  public init(key: String, summary: String) {
    self.key = key
    self.summary = summary
  }
}

/// `lib/types.ts:220-225`. `rank` 0 is the highest; null when Jira gives no order.
public struct JiraPriority: Codable, Sendable, Equatable, Hashable {
  public var name: String
  public var rank: Int?

  public init(name: String, rank: Int?) {
    self.name = name
    self.rank = rank
  }
}

/// An issue (`lib/types.ts:227-252`).
public struct JiraItem: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var key: String
  public var summary: String
  public var status: String
  public var statusCategory: JiraStatusCategory
  public var project: String
  public var url: String
  public var parent: JiraParent?
  public var role: JiraRole
  public var awaitingApproval: Bool
  public var kind: String
  public var subtask: Bool
  /// -1 subtask, 0 story, 1 epic, 2 initiative, 3 objective; null when unknown.
  public var hierarchyLevel: Int?
  public var updatedAt: String
  /// `YYYY-MM-DD`, or empty when there is no due date.
  public var dueDate: String
  public var priority: JiraPriority?
  public var flag: JiraFlag

  public var id: String { key }

  public init(
    key: String,
    summary: String,
    status: String,
    statusCategory: JiraStatusCategory,
    project: String,
    url: String,
    parent: JiraParent?,
    role: JiraRole,
    awaitingApproval: Bool,
    kind: String,
    subtask: Bool,
    hierarchyLevel: Int?,
    updatedAt: String,
    dueDate: String,
    priority: JiraPriority?,
    flag: JiraFlag
  ) {
    self.key = key
    self.summary = summary
    self.status = status
    self.statusCategory = statusCategory
    self.project = project
    self.url = url
    self.parent = parent
    self.role = role
    self.awaitingApproval = awaitingApproval
    self.kind = kind
    self.subtask = subtask
    self.hierarchyLevel = hierarchyLevel
    self.updatedAt = updatedAt
    self.dueDate = dueDate
    self.priority = priority
    self.flag = flag
  }
}

/// `JiraItem` plus whether it falls on today (`lib/types.ts:258-260`). The TS
/// type extends `JiraItem`, so the JSON is flat; the item fields are reachable
/// directly through dynamic member lookup.
@dynamicMemberLookup
public struct JiraDatedItem: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var item: JiraItem
  public var today: Bool

  public var id: String { item.key }

  public init(item: JiraItem, today: Bool) {
    self.item = item
    self.today = today
  }

  public subscript<Value>(dynamicMember keyPath: WritableKeyPath<JiraItem, Value>) -> Value {
    get { item[keyPath: keyPath] }
    set { item[keyPath: keyPath] = newValue }
  }

  private enum CodingKeys: String, CodingKey { case today }

  public init(from decoder: any Decoder) throws {
    item = try JiraItem(from: decoder)
    today = try decoder.container(keyedBy: CodingKeys.self).decode(Bool.self, forKey: .today)
  }

  public func encode(to encoder: any Encoder) throws {
    try item.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(today, forKey: .today)
  }
}

/// A filling defect the problems tab points at (`lib/types.ts:264-269`).
public struct JiraProblem: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let storyInProgressWithoutStart = JiraProblem(rawValue: "story-in-progress-without-start")
  public static let storyDoneWithoutStart = JiraProblem(rawValue: "story-done-without-start")
  public static let storyWithoutEpic = JiraProblem(rawValue: "story-without-epic")
  public static let epicWithoutStories = JiraProblem(rawValue: "epic-without-stories")
  public static let epicInProgressWithoutActiveStory = JiraProblem(rawValue: "epic-in-progress-without-active-story")
  public static let known: [JiraProblem] = [
    .storyInProgressWithoutStart, .storyDoneWithoutStart, .storyWithoutEpic, .epicWithoutStories,
    .epicInProgressWithoutActiveStory,
  ]
}

/// `JiraItem` plus its defects, never empty (`lib/types.ts:271-274`). Flat JSON,
/// like `JiraDatedItem`.
@dynamicMemberLookup
public struct JiraProblemItem: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var item: JiraItem
  public var problems: [JiraProblem]

  public var id: String { item.key }

  public init(item: JiraItem, problems: [JiraProblem]) {
    self.item = item
    self.problems = problems
  }

  public subscript<Value>(dynamicMember keyPath: WritableKeyPath<JiraItem, Value>) -> Value {
    get { item[keyPath: keyPath] }
    set { item[keyPath: keyPath] = newValue }
  }

  private enum CodingKeys: String, CodingKey { case problems }

  public init(from decoder: any Decoder) throws {
    item = try JiraItem(from: decoder)
    problems = try decoder.container(keyedBy: CodingKeys.self).decode([JiraProblem].self, forKey: .problems)
  }

  public func encode(to encoder: any Encoder) throws {
    try item.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(problems, forKey: .problems)
  }
}

/// A Jira user (`lib/types.ts:403-406`).
public struct JiraPerson: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var accountId: String
  public var displayName: String

  public var id: String { accountId }

  public init(accountId: String, displayName: String) {
    self.accountId = accountId
    self.displayName = displayName
  }
}

/// `GET /api/jira/people/{accountId}` (`lib/types.ts:408-416`,
/// `app/api/jira/people/[accountId]/route.ts:29`).
public struct JiraPersonView: Codable, Sendable, Equatable, Hashable {
  public var jira: PanelResult<[JiraItem]>
  public var delivered: PanelResult<[JiraDatedItem]>
  public var approved: PanelResult<[JiraDatedItem]>
  public var problems: PanelResult<[JiraProblemItem]>
  public var ancestors: [JiraItem]

  public init(
    jira: PanelResult<[JiraItem]>,
    delivered: PanelResult<[JiraDatedItem]>,
    approved: PanelResult<[JiraDatedItem]>,
    problems: PanelResult<[JiraProblemItem]>,
    ancestors: [JiraItem]
  ) {
    self.jira = jira
    self.delivered = delivered
    self.approved = approved
    self.problems = problems
    self.ancestors = ancestors
  }
}

/// `GET /api/jira/people/search`, `POST` and `DELETE /api/jira/people`
/// (`app/api/jira/people/search/route.ts:15,27`, `app/api/jira/people/route.ts:25,41`).
public struct JiraPeopleResponse: Codable, Sendable, Equatable, Hashable {
  public var people: [JiraPerson]

  public init(people: [JiraPerson]) {
    self.people = people
  }
}

/// `GET /api/jira/epics` (`app/api/jira/epics/route.ts:22`).
public struct JiraEpicsResponse: Codable, Sendable, Equatable, Hashable {
  public var epics: [JiraParent]

  public init(epics: [JiraParent]) {
    self.epics = epics
  }
}

/// An approval waiting for the user (`lib/integrations/jira/approvals.ts:15-18`).
public struct JiraPendingApproval: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// `GET /api/jira/issues/{key}/approvals` (`app/api/jira/issues/[key]/approvals/route.ts:24`).
public struct JiraApprovalsResponse: Codable, Sendable, Equatable, Hashable {
  public var approvals: [JiraPendingApproval]

  public init(approvals: [JiraPendingApproval]) {
    self.approvals = approvals
  }
}

/// `POST /api/jira/issues/{key}/comments` (`app/api/jira/issues/[key]/comments/route.ts:31`,
/// `lib/integrations/jira/comments.ts:6-8`).
public struct JiraCommentResponse: Codable, Sendable, Equatable, Hashable {
  public struct Comment: Codable, Sendable, Equatable, Hashable {
    public var id: String

    public init(id: String) {
      self.id = id
    }
  }

  public var ok: Bool
  public var comment: Comment

  public init(ok: Bool, comment: Comment) {
    self.ok = ok
    self.comment = comment
  }
}

/// A priority the issue can take (`lib/integrations/jira/edits.ts:9-12`).
public struct JiraPriorityOption: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// `GET /api/jira/issues/{key}/fields?options=priority`. The route returns
/// `fetchPriorityOptions` as is, so the body is flat
/// (`app/api/jira/issues/[key]/fields/route.ts:19`, `lib/integrations/jira/edits.ts:145-148`).
public struct JiraPriorityOptions: Codable, Sendable, Equatable, Hashable {
  public var priorities: [JiraPriorityOption]
  public var current: JiraPriorityOption?

  public init(priorities: [JiraPriorityOption], current: JiraPriorityOption?) {
    self.priorities = priorities
    self.current = current
  }
}

/// `POST /api/jira/issues/{key}/flag` (`app/api/jira/issues/[key]/flag/route.ts:49,52`):
/// `warning` when the flag changed but its comment failed.
public struct JiraFlagResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var warning: String?

  public init(ok: Bool, warning: String? = nil) {
    self.ok = ok
    self.warning = warning
  }
}

/// What a suggested start date is based on (`lib/integrations/jiraApi.ts:687`).
public struct JiraStartDateBasis: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let started = JiraStartDateBasis(rawValue: "started")
  public static let finished = JiraStartDateBasis(rawValue: "finished")
  public static let created = JiraStartDateBasis(rawValue: "created")
  public static let known: [JiraStartDateBasis] = [.started, .finished, .created]
}

/// `GET /api/jira/issues/{key}/start-date`: both null when there is no
/// suggestion (`app/api/jira/issues/[key]/start-date/route.ts:24`,
/// `lib/integrations/jiraApi.ts:689-692`).
public struct JiraStartDateSuggestion: Codable, Sendable, Equatable, Hashable {
  public var date: String?
  public var basis: JiraStartDateBasis?

  public init(date: String?, basis: JiraStartDateBasis?) {
    self.date = date
    self.basis = basis
  }
}

/// `POST /api/jira/issues/{key}/stories` (`app/api/jira/issues/[key]/stories/route.ts:28`,
/// `lib/integrations/jira/edits.ts:188-192`).
public struct JiraCreatedStory: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var key: String
  public var url: String

  public init(ok: Bool, key: String, url: String) {
    self.ok = ok
    self.key = key
    self.url = url
  }
}

/// What a transition needs beyond the click (`lib/integrations/jira/transitions.ts:9`).
/// A screen means fields only Jira itself can fill in.
public struct JiraTransitionRequirement: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let nothing = JiraTransitionRequirement(rawValue: "nothing")
  public static let screen = JiraTransitionRequirement(rawValue: "screen")
  public static let known: [JiraTransitionRequirement] = [.nothing, .screen]
}

/// `lib/integrations/jira/transitions.ts:11-16`.
public struct JiraTransition: Codable, Sendable, Equatable, Hashable, Identifiable {
  public struct Target: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var category: JiraStatusCategory

    public init(name: String, category: JiraStatusCategory) {
      self.name = name
      self.category = category
    }
  }

  public var id: String
  public var name: String
  public var to: Target
  public var requires: JiraTransitionRequirement

  public init(id: String, name: String, to: Target, requires: JiraTransitionRequirement) {
    self.id = id
    self.name = name
    self.to = to
    self.requires = requires
  }
}

/// `GET /api/jira/issues/{key}/transitions` (`app/api/jira/issues/[key]/transitions/route.ts:16`).
public struct JiraTransitionsResponse: Codable, Sendable, Equatable, Hashable {
  public var transitions: [JiraTransition]

  public init(transitions: [JiraTransition]) {
    self.transitions = transitions
  }
}

/// `suggested` or `failed` (`lib/integrations/jira/startDates.ts:10-12`).
public struct JiraStartDateSuggestionStatus: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let suggested = JiraStartDateSuggestionStatus(rawValue: "suggested")
  public static let failed = JiraStartDateSuggestionStatus(rawValue: "failed")
  public static let known: [JiraStartDateSuggestionStatus] = [.suggested, .failed]
}

/// One key of `GET /api/jira/problems/start-dates`. The TS type is a union on
/// `status`: `date` and `basis` come with `suggested`, `error` with `failed`
/// (`lib/integrations/jira/startDates.ts:10-12`).
public struct JiraStartDateKeySuggestion: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var key: String
  public var status: JiraStartDateSuggestionStatus
  public var date: String?
  public var basis: JiraStartDateBasis?
  public var error: String?

  public var id: String { key }

  public init(
    key: String,
    status: JiraStartDateSuggestionStatus,
    date: String? = nil,
    basis: JiraStartDateBasis? = nil,
    error: String? = nil
  ) {
    self.key = key
    self.status = status
    self.date = date
    self.basis = basis
    self.error = error
  }
}

/// `GET /api/jira/problems/start-dates` (`app/api/jira/problems/start-dates/route.ts:29`).
public struct JiraStartDateSuggestionsResponse: Codable, Sendable, Equatable, Hashable {
  public var suggestions: [JiraStartDateKeySuggestion]

  public init(suggestions: [JiraStartDateKeySuggestion]) {
    self.suggestions = suggestions
  }
}

/// `written` or `refused` (`lib/integrations/jira/startDates.ts:14`).
public struct JiraStartDateOutcome: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let written = JiraStartDateOutcome(rawValue: "written")
  public static let refused = JiraStartDateOutcome(rawValue: "refused")
  public static let known: [JiraStartDateOutcome] = [.written, .refused]
}

/// `lib/integrations/jira/startDates.ts:16-20`.
public struct JiraStartDateResult: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var key: String
  public var outcome: JiraStartDateOutcome
  public var error: String?

  public var id: String { key }

  public init(key: String, outcome: JiraStartDateOutcome, error: String? = nil) {
    self.key = key
    self.outcome = outcome
    self.error = error
  }
}

/// `POST /api/jira/problems/start-dates` (`app/api/jira/problems/start-dates/route.ts:75-76`).
/// `ok` only comes when at least one date was written (through `writeDone`).
public struct JiraStartDateResultsResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool?
  public var results: [JiraStartDateResult]

  public init(ok: Bool? = nil, results: [JiraStartDateResult]) {
    self.ok = ok
    self.results = results
  }
}
