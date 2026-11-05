import DailyModels
import Testing

@testable import FeatureNotifications

func notice(_ id: String, _ source: NotificationSource, read: Bool = false, url: String = "https://x/1")
  -> NotificationItem
{
  NotificationItem(id: id, source: source, title: "título \(id)", url: url, read: read, date: "2026-11-04T10:00:00Z")
}

@Suite struct NotificationsLogicTests {
  let items = [
    notice("jira_mention:ABC-1", .jiraMention),
    notice("pull_request:o/r#2", .pullRequest, read: true),
    notice("email:<m@x>", .email, url: ""),
    notice("slack:C1-1", .slack),
  ]

  @Test func labelsEachSource() {
    #expect(NotificationsLogic.filterSources.map(NotificationsLogic.label) == ["JIRA", "PR", "E-MAIL", "SLACK"])
    #expect(NotificationsLogic.label(NotificationSource(rawValue: "calendar")) == "CALENDAR")
  }

  @Test func popoverIsWebSizedAndCapsAtSeventyPercentOfTheScreen() {
    #expect(NotificationsLogic.popoverWidth == 460)
    #expect(NotificationsLogic.popoverMaxHeight(screenHeight: 1000) == 700)
    #expect(NotificationsLogic.popoverMaxHeight(screenHeight: 875) == 612)
    #expect(NotificationsLogic.popoverMaxHeight(screenHeight: nil) == nil)
  }

  @Test func countsUnread() {
    #expect(NotificationsLogic.unread(items).count == 3)
    #expect(NotificationsLogic.bellLabel(unread: 3) == "notificações (3 não lidas)")
    #expect(NotificationsLogic.unreadCaption(1) == "1 não lida")
    #expect(NotificationsLogic.unreadCaption(3) == "3 não lidas")
  }

  @Test func emptyFilterShowsEverySource() {
    #expect(NotificationsLogic.visible(items, sources: []).count == 4)
  }

  @Test func filtersBySource() {
    let visible = NotificationsLogic.visible(items, sources: [.pullRequest, .slack])
    #expect(visible.map(\.id) == ["pull_request:o/r#2", "slack:C1-1"])
  }

  @Test func recognisesJiraKeys() {
    #expect(NotificationsLogic.isJiraKey("ABC-12"))
    #expect(NotificationsLogic.isJiraKey("A_B2-1"))
    // `isJiraKey` upper-cases before testing.
    #expect(NotificationsLogic.isJiraKey("abc-12"))
    #expect(!NotificationsLogic.isJiraKey("ABC"))
    #expect(!NotificationsLogic.isJiraKey("1AB-2"))
    #expect(!NotificationsLogic.isJiraKey("ABC-12 OR 1=1"))
  }

  @Test func extractsTheIssueKeyOfAMention() {
    #expect(NotificationsLogic.mentionKey(notice("jira_mention:ABC-1", .jiraMention)) == "ABC-1")
    #expect(NotificationsLogic.mentionKey(notice("jira_mention:abc-7", .jiraMention)) == "abc-7")
    #expect(NotificationsLogic.mentionKey(notice("jira_mention:not a key", .jiraMention)) == nil)
    #expect(NotificationsLogic.mentionKey(notice("ABC-1", .jiraMention)) == nil)
    #expect(NotificationsLogic.mentionKey(notice("jira_mention:ABC-1", .pullRequest)) == nil)
  }

  @Test func chunksAtTheServerLimit() {
    let ids = (0..<450).map { "email:\($0)" }
    let chunks = NotificationsLogic.chunks(ids)
    #expect(chunks.map(\.count) == [200, 200, 50])
    #expect(chunks.flatMap { $0 } == ids)
    #expect(NotificationsLogic.chunks(Array(ids.prefix(200))).count == 1)
    #expect(NotificationsLogic.chunks([]).isEmpty)
  }

  @Test func marksReadInTheState() {
    var state = DashboardState(updatedAt: "x", modules: [], notifications: PanelResult(data: items, error: nil))
    NotificationsLogic.markRead(["jira_mention:ABC-1", "slack:C1-1"], in: &state)
    #expect(state.notifications.data?.filter { !$0.read }.map(\.id) == ["email:<m@x>"])
  }

  @Test func splitsTheExternalIDAtTheFirstColon() {
    #expect(NotificationsLogic.externalID("email:mail-1:42") == "mail-1:42")
    #expect(NotificationsLogic.externalID(":x") == nil)
    #expect(NotificationsLogic.externalID("email:") == nil)
  }

  @Test func findsTheMessageOfAnEmailNotice() {
    let inbox = [
      EmailEnvelope(
        id: "42", account: "mail-1", accountLabel: "T", from: "a", subject: "s", unread: true, date: "",
        messageId: "<m@x>", references: [], labels: [], mailbox: .inbox, folder: "INBOX", actionError: nil),
      EmailEnvelope(
        id: "7", account: "mail-2", accountLabel: "P", from: "a", subject: "s", unread: true, date: "",
        messageId: "", references: [], labels: [], mailbox: .inbox, folder: "INBOX", actionError: nil),
    ]
    #expect(NotificationsLogic.emailItemID(notice("email:<m@x>", .email), inbox: inbox) == "mail-1:42")
    #expect(NotificationsLogic.emailItemID(notice("email:mail-2:7", .email), inbox: inbox) == "mail-2:7")
    #expect(NotificationsLogic.emailItemID(notice("email:<gone@x>", .email), inbox: inbox) == nil)
  }
}
