import DailyAPI
import DailyModels
import Foundation

/// The calls of the bell: `POST /api/notifications/read` and the Jira comment
/// that answers a mention.
nonisolated enum NotificationsEndpoints {
  struct ReadOneBody: Encodable, Sendable, Equatable {
    let id: String
  }

  struct ReadManyBody: Encodable, Sendable, Equatable {
    let ids: [String]
  }

  struct CommentBody: Encodable, Sendable, Equatable {
    let body: String
  }

  /// One notice (`markRead`, `NotificationsBell.tsx`). The id goes in the body:
  /// it carries `/`, `#` and `:` (`route.ts:24-27`).
  static func markRead(id: String) -> Endpoint<NotificationsReadResult> {
    Endpoint(.post, "/api/notifications/read", body: ReadOneBody(id: id))
  }

  /// Up to `NotificationsLogic.maxIDsPerRequest` notices at once.
  static func markRead(ids: [String]) -> Endpoint<NotificationsReadResult> {
    Endpoint(.post, "/api/notifications/read", body: ReadManyBody(ids: ids))
  }

  /// `commentsUrl` + `sendJiraWrite` (`components/jira/actions/CommentAction.tsx`).
  static func jiraComment(key: String, body: String) -> Endpoint<JiraCommentResponse> {
    Endpoint(
      .post, "/api/jira/issues/\(Endpoint<JiraCommentResponse>.segment(key))/comments", body: CommentBody(body: body))
  }
}
