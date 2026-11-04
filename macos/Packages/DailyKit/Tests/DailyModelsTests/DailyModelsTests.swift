import Foundation
import Testing

@testable import DailyModels

/// One fixture and the type it is a response of.
struct FixtureCase: Sendable, CustomTestStringConvertible {
  let name: String
  let check: @Sendable () throws -> Void

  var testDescription: String { name }

  /// Decodes, re-encodes and decodes again: the values must match, and the
  /// re-encoded JSON must carry every non-null key of the fixture, so a key the
  /// server sends and the model drops fails here.
  static func of<T: Codable & Equatable & Sendable>(_ type: T.Type, _ name: String) -> FixtureCase {
    FixtureCase(name: name) {
      let original = try Fixture.data(name)
      let decoded = try JSONDecoder().decode(type, from: original)
      let encoded = try JSONEncoder().encode(decoded)
      #expect(try JSONDecoder().decode(type, from: encoded) == decoded)
      #expect(try Fixture.normalized(encoded) == Fixture.normalized(original))
    }
  }
}

let fixtureCases: [FixtureCase] = [
  .of(DashboardState.self, "dashboard-state-full.json"),
  .of(DashboardState.self, "dashboard-state-off.json"),
  .of(CurrentUser.self, "me.json"),
  .of(CurrentUser.self, "me-minimal.json"),
  .of(ProfileResponse.self, "profile.json"),
  .of(AvatarResponse.self, "avatar-removed.json"),
  .of(UsersResponse.self, "users.json"),
  .of(CreatedUserResponse.self, "user-created.json"),
  .of(OKResponse.self, "ok.json"),
  .of(AppearanceResponse.self, "preferences-appearance.json"),
  .of(AppearanceResponse.self, "preferences-appearance-partial.json"),
  .of(TasksViewResponse.self, "preferences-tasks-view.json"),
  .of(HomeViewResponse.self, "preferences-home-view.json"),
  .of(LayoutResponse.self, "preferences-layout.json"),
  .of(PomodoroState.self, "pomodoro.json"),
  .of(FocusBlockResponse.self, "focus-block.json"),
  .of(NotificationsReadResult.self, "notifications-read.json"),
  .of(NotesResponse.self, "notes.json"),
  .of(NoteResponse.self, "note.json"),
  .of(NoteListResponse.self, "notes-reordered.json"),
  .of(NotesSyncResponse.self, "notes-sync.json"),
  .of(NoteFoldersResponse.self, "note-folders.json"),
  .of(NoteFolderResponse.self, "note-folder.json"),
  .of(CreatedTaskResponse.self, "task-created.json"),
  .of(TaskBoardResponse.self, "task-board.json"),
  .of(MailboxesResponse.self, "email-mailboxes-cached.json"),
  .of(MailboxesResponse.self, "email-mailboxes-synced.json"),
  .of(EmailFoldersResponse.self, "email-folders.json"),
  .of(EmailMessagesResponse.self, "email-messages.json"),
  .of(EmailBody.self, "email-body.json"),
  .of(EmailBatchResponse.self, "email-batch.json"),
  .of(EmailToNoteResponse.self, "email-to-note.json"),
  .of(EmailToNoteResponse.self, "email-to-note-repeated.json"),
  .of(EmailToTaskResponse.self, "email-to-task.json"),
  .of(EmailDraftResponse.self, "email-draft.json"),
  .of(JiraEpicsResponse.self, "jira-epics.json"),
  .of(JiraApprovalsResponse.self, "jira-approvals.json"),
  .of(JiraCommentResponse.self, "jira-comment.json"),
  .of(JiraPriorityOptions.self, "jira-priorities.json"),
  .of(JiraFlagResponse.self, "jira-flag-warning.json"),
  .of(JiraStartDateSuggestion.self, "jira-start-date.json"),
  .of(JiraStartDateSuggestion.self, "jira-start-date-none.json"),
  .of(JiraCreatedStory.self, "jira-story.json"),
  .of(JiraTransitionsResponse.self, "jira-transitions.json"),
  .of(JiraPeopleResponse.self, "jira-people.json"),
  .of(JiraPersonView.self, "jira-person-view.json"),
  .of(JiraStartDateSuggestionsResponse.self, "jira-start-date-suggestions.json"),
  .of(JiraStartDateResultsResponse.self, "jira-start-date-results.json"),
  .of(JiraStartDateResultsResponse.self, "jira-start-date-results-none-written.json"),
  .of(PullReposResponse.self, "pulls-repos.json"),
  .of(PullJiraSyncResponse.self, "pulls-jira-sync.json"),
  .of(PullCommentResponse.self, "pull-comment.json"),
  .of(PullMergeResponse.self, "pull-merge.json"),
  .of(PullRerunResponse.self, "pull-rerun.json"),
  .of(PullReviewersResponse.self, "pull-reviewers.json"),
  .of(PullReviewResponse.self, "pull-review.json"),
  .of(AgentsBoard.self, "agents-board.json"),
  .of(AgentTaskDetail.self, "agent-task-detail.json"),
  .of(AgentTask.self, "agent-task.json"),
  .of(AgentTerminal.self, "agent-terminal-available.json"),
  .of(AgentTerminal.self, "agent-terminal-unavailable.json"),
  .of(AgentMessageReceipt.self, "agent-message.json"),
  .of(APICredentialsResponse.self, "agent-access-tokens.json"),
  .of(CreatedAPICredential.self, "agent-access-token-created.json"),
  .of(AgentAccessPrompt.self, "agent-access-prompt.json"),
  .of(AgentAccessConfig.self, "agent-access-config.json"),
  .of(OAuthGrantsResponse.self, "agent-access-grants.json"),
  .of(IntegrationsPayload.self, "integrations.json"),
  .of(ModulesResponse.self, "integrations-modules.json"),
  .of(ConnectionRemovedResponse.self, "integrations-connection-removed.json"),
  .of(ConnectionTestResult.self, "integrations-test.json"),
  .of(GoogleCalendarsResponse.self, "google-calendars.json"),
]

@Suite struct FixtureDecodingTests {
  @Test(arguments: fixtureCases)
  func fixtureDecodesAndRoundTrips(_ fixture: FixtureCase) throws {
    try fixture.check()
  }

  @Test func everyFixtureHasACase() throws {
    let covered = Set(fixtureCases.map(\.name))
    let files = Set(try Fixture.allNames())
    #expect(files.subtracting(covered).isEmpty, "fixtures without a decoding case")
    #expect(covered.subtracting(files).isEmpty, "cases without a fixture file")
  }
}
