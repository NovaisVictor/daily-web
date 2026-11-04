import DailyModels
import Testing

@testable import FeatureEmail

/// The cases of `tests/lib/parsers/threads.test.ts`.
@Suite struct EmailThreadingTests {
  func mail(
    _ id: String, account: String = "work", from: String = "Alguém", subject: String = "assunto",
    unread: Bool = false, date: String = "2026-08-27T12:00:00Z", messageId: String = "<1@x>",
    references: [String] = []
  ) -> EmailEnvelope {
    envelope(
      id, account: account, from: from, subject: subject, unread: unread, date: date, messageId: messageId,
      references: references)
  }

  @Test(arguments: [
    "Re: teste assunto", "RE: teste assunto", "Res: teste assunto", "Fwd: teste assunto", "ENC: teste assunto",
    "Re: Re: Re: teste assunto", "Re: Fwd: teste assunto", "RE[2]: teste assunto", "  re:   teste assunto  ",
  ])
  func stripsReplyPrefixes(raw: String) {
    #expect(EmailThreading.normalizeSubject(raw) == "teste assunto")
  }

  @Test func keepsWordsThatOnlyLookLikePrefixes() {
    #expect(EmailThreading.normalizeSubject("Refatoração do build") == "Refatoração do build")
    #expect(EmailThreading.normalizeSubject("Resultado da apuração") == "Resultado da apuração")
    #expect(EmailThreading.normalizeSubject("Review: contrato") == "Review: contrato")
    #expect(EmailThreading.normalizeSubject("") == "")
    #expect(EmailThreading.normalizeSubject("Re:") == "")
  }

  @Test func joinsTheReplyByReference() {
    let threads = EmailThreading.threads([
      mail("1", from: "você", subject: "teste assunto", messageId: "<a@x>"),
      mail("2", from: "Luan", subject: "Re: teste assunto", messageId: "<b@x>", references: ["<a@x>"]),
    ])
    #expect(threads.count == 1)
    #expect(threads[0].messages.map(\.id) == ["1", "2"])
    #expect(threads[0].subject == "teste assunto")
    #expect(threads[0].participants == ["você", "Luan"])
  }

  @Test func joinsTheWholeConversationAndAnyOrder() {
    let chain = EmailThreading.threads([
      mail("1", messageId: "<a@x>"),
      mail("2", messageId: "<b@x>", references: ["<a@x>"]),
      mail("3", messageId: "<c@x>", references: ["<a@x>", "<b@x>"]),
    ])
    #expect(chain.count == 1)
    #expect(chain[0].messages.count == 3)
    let reversed = EmailThreading.threads([
      mail("2", date: "2026-08-27T13:00:00Z", messageId: "<b@x>", references: ["<a@x>"]),
      mail("1", date: "2026-08-27T12:00:00Z", messageId: "<a@x>"),
    ])
    #expect(reversed.count == 1)
    #expect(reversed[0].messages.map(\.id) == ["1", "2"])
  }

  @Test func subjectJoinsOnlyInsideOneAccount() {
    #expect(
      EmailThreading.threads([
        mail("1", subject: "teste assunto", messageId: "<a@x>"),
        mail("2", subject: "Re: teste assunto", messageId: "<b@x>"),
      ]).count == 1)
    #expect(
      EmailThreading.threads([
        mail("1", account: "work", subject: "Reunião", messageId: "<a@x>"),
        mail("2", account: "pessoal", subject: "Re: Reunião", messageId: "<b@x>"),
      ]).count == 2)
    #expect(
      EmailThreading.threads([
        mail("1", account: "work", messageId: "<a@x>"),
        mail("2", account: "pessoal", messageId: "<b@x>", references: ["<a@x>"]),
      ]).count == 1)
  }

  @Test func separatesDifferentAndEmptySubjects() {
    #expect(
      EmailThreading.threads([
        mail("1", subject: "Nota fiscal", messageId: "<a@x>"), mail("2", subject: "Reunião", messageId: "<b@x>"),
      ]).count == 2)
    #expect(
      EmailThreading.threads([mail("1", subject: "", messageId: "<a@x>"), mail("2", subject: "", messageId: "<b@x>")])
        .count == 2)
  }

  @Test func comparesMessageIdsWithoutBracketsOrCase() {
    let threads = EmailThreading.threads([
      mail("1", subject: "um", messageId: "<A@X>"),
      mail("2", subject: "outro", messageId: "<b@x>", references: ["a@x"]),
    ])
    #expect(threads.count == 1)
  }

  @Test func countsUnreadAndKeepsTheLatestDate() {
    let threads = EmailThreading.threads([
      mail("1", unread: false, date: "2026-08-27T12:00:00Z", messageId: "<a@x>"),
      mail("2", unread: true, date: "2026-08-27T15:00:00Z", messageId: "<b@x>", references: ["<a@x>"]),
      mail("3", unread: true, date: "2026-08-27T14:00:00Z", messageId: "<c@x>", references: ["<a@x>"]),
    ])
    #expect(threads[0].unreadCount == 2)
    #expect(threads[0].lastDate == "2026-08-27T15:00:00Z")
  }

  @Test func doesNotRepeatParticipants() {
    let threads = EmailThreading.threads([
      mail("1", from: "Luan", messageId: "<a@x>"),
      mail("2", from: "Luan", messageId: "<b@x>", references: ["<a@x>"]),
      mail("3", from: "você", messageId: "<c@x>", references: ["<a@x>"]),
    ])
    #expect(threads[0].participants == ["Luan", "você"])
  }

  @Test func emptyAndSingle() {
    #expect(EmailThreading.threads([]).isEmpty)
    let single = EmailThreading.threads([mail("1")])
    #expect(single.count == 1)
    #expect(single[0].messages.count == 1)
  }
}
