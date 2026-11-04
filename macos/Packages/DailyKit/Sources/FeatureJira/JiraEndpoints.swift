import DailyAPI
import DailyModels
import Foundation

/// `app/api/jira/**` (contract in `macos/docs/contracts/api.md`, "Jira").
nonisolated enum JiraEndpoints {
  struct KeyBody: Encodable, Sendable, Equatable {
    var key: String
  }

  struct AccountBody: Encodable, Sendable, Equatable {
    var accountId: String
  }

  struct TransitionBody: Encodable, Sendable, Equatable {
    var transitionId: String
  }

  struct CommentBody: Encodable, Sendable, Equatable {
    var body: String
  }

  enum Decision: String, Encodable, Sendable {
    case approve
    case decline
  }

  struct ApprovalBody: Encodable, Sendable, Equatable {
    var approvalId: String
    var decision: Decision
  }

  /// `{action:"flag", reason}` or `{action:"unflag", note?}`; an empty note is
  /// left out, as `FlagAction.tsx:104-106` does.
  enum FlagBody: Encodable, Sendable, Equatable {
    case flag(reason: String)
    case unflag(note: String?)

    private enum Keys: String, CodingKey { case action, reason, note }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      switch self {
      case .flag(let reason):
        try container.encode("flag", forKey: .action)
        try container.encode(reason, forKey: .reason)
      case .unflag(let note):
        try container.encode("unflag", forKey: .action)
        try container.encodeIfPresent(note, forKey: .note)
      }
    }
  }

  /// `PUT /fields`. Removing the due date sends an explicit `null`
  /// (`parseEditChange`, `lib/integrations/jira/edits.ts:48`).
  enum FieldChange: Encodable, Sendable, Equatable {
    case due(String?)
    case priority(String)
    case assignSelf

    private enum Keys: String, CodingKey { case change, dueDate, priorityId }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      switch self {
      case .due(let date):
        try container.encode("due", forKey: .change)
        try container.encode(date, forKey: .dueDate)
      case .priority(let id):
        try container.encode("priority", forKey: .change)
        try container.encode(id, forKey: .priorityId)
      case .assignSelf:
        try container.encode("assign-self", forKey: .change)
      }
    }
  }

  struct StoryBody: Encodable, Sendable, Equatable {
    var summary: String
    var description: String?
  }

  struct ParentBody: Encodable, Sendable, Equatable {
    var epic: String
  }

  struct DateBody: Encodable, Sendable, Equatable {
    var date: String
  }

  struct StartDateItem: Encodable, Sendable, Equatable {
    var key: String
    var date: String
  }

  struct StartDatesBody: Encodable, Sendable, Equatable {
    var items: [StartDateItem]
  }

  /// `START_DATE_BATCH`, `lib/jiraLimits.ts`: the server takes at most this many keys.
  static let startDateBatch = 50

  // MARK: Watch and people

  static func watch(_ key: String) -> Endpoint<DashboardState> {
    Endpoint(.post, "/api/jira/watch", body: KeyBody(key: key))
  }

  static func unwatch(_ key: String) -> Endpoint<DashboardState> {
    Endpoint(.delete, "/api/jira/watch", body: KeyBody(key: key))
  }

  static func searchPeople(_ query: String) -> Endpoint<JiraPeopleResponse> {
    Endpoint(.get, "/api/jira/people/search", query: [URLQueryItem(name: "q", value: query)])
  }

  static func follow(_ accountId: String) -> Endpoint<JiraPeopleResponse> {
    Endpoint(.post, "/api/jira/people", body: AccountBody(accountId: accountId))
  }

  static func unfollow(_ accountId: String) -> Endpoint<JiraPeopleResponse> {
    Endpoint(.delete, "/api/jira/people", body: AccountBody(accountId: accountId))
  }

  static func personView(_ accountId: String) -> Endpoint<JiraPersonView> {
    Endpoint(.get, "/api/jira/people/\(Endpoint<JiraPersonView>.segment(accountId))")
  }

  // MARK: Issue writes

  static func transitions(_ key: String) -> Endpoint<JiraTransitionsResponse> {
    Endpoint(.get, issuePath(key, "transitions"))
  }

  static func transition(_ key: String, id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.post, issuePath(key, "transitions"), body: TransitionBody(transitionId: id))
  }

  static func comment(_ key: String, body: String) -> Endpoint<JiraCommentResponse> {
    Endpoint(.post, issuePath(key, "comments"), body: CommentBody(body: body))
  }

  static func approvals(_ key: String) -> Endpoint<JiraApprovalsResponse> {
    Endpoint(.get, issuePath(key, "approvals"))
  }

  static func decide(_ key: String, approvalId: String, decision: Decision) -> Endpoint<EmptyResponse> {
    Endpoint(.post, issuePath(key, "approvals"), body: ApprovalBody(approvalId: approvalId, decision: decision))
  }

  static func flag(_ key: String, _ body: FlagBody) -> Endpoint<JiraFlagResponse> {
    Endpoint(.post, issuePath(key, "flag"), body: body)
  }

  static func priorities(_ key: String) -> Endpoint<JiraPriorityOptions> {
    Endpoint(.get, issuePath(key, "fields"), query: [URLQueryItem(name: "options", value: "priority")])
  }

  static func edit(_ key: String, _ change: FieldChange) -> Endpoint<EmptyResponse> {
    Endpoint(.put, issuePath(key, "fields"), body: change)
  }

  static func createStory(_ key: String, _ body: StoryBody) -> Endpoint<JiraCreatedStory> {
    Endpoint(.post, issuePath(key, "stories"), body: body)
  }

  static func epics(project: String) -> Endpoint<JiraEpicsResponse> {
    Endpoint(.get, "/api/jira/epics", query: [URLQueryItem(name: "project", value: project)])
  }

  static func setParent(_ key: String, epic: String) -> Endpoint<EmptyResponse> {
    Endpoint(.put, issuePath(key, "parent"), body: ParentBody(epic: epic))
  }

  static func startDate(_ key: String) -> Endpoint<JiraStartDateSuggestion> {
    Endpoint(.get, issuePath(key, "start-date"))
  }

  static func setStartDate(_ key: String, date: String) -> Endpoint<EmptyResponse> {
    Endpoint(.put, issuePath(key, "start-date"), body: DateBody(date: date))
  }

  static func startDateSuggestions(_ keys: [String]) -> Endpoint<JiraStartDateSuggestionsResponse> {
    Endpoint(
      .get, "/api/jira/problems/start-dates", query: [URLQueryItem(name: "keys", value: keys.joined(separator: ","))])
  }

  static func writeStartDates(_ items: [StartDateItem]) -> Endpoint<JiraStartDateResultsResponse> {
    Endpoint(.post, "/api/jira/problems/start-dates", body: StartDatesBody(items: items))
  }

  private static func issuePath(_ key: String, _ action: String) -> String {
    "/api/jira/issues/\(Endpoint<EmptyResponse>.segment(key))/\(action)"
  }
}
