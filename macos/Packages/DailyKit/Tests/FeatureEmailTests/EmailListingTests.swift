import DailyModels
import Foundation
import Testing

@testable import FeatureEmail

let saoPaulo = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt

func localDate(_ text: String) -> Date {
  guard let date = EmailDates.parse(text, timeZone: saoPaulo) else {
    preconditionFailure("Unreadable test date \(text)")
  }
  return date
}

/// The cases of `tests/lib/emailGroups.test.ts`.
@Suite struct EmailGroupingTests {
  let now = localDate("2026-10-04T15:00:00")

  func threads(_ list: [EmailEnvelope]) -> [EmailThread] {
    EmailThreading.threads(list).stableSorted { $0.lastDate > $1.lastDate }
  }

  func keys(_ groups: [EmailThreadGroup]) -> [String] {
    groups.map { "\($0.label): \($0.threads.map(\.subject).joined(separator: ","))" }
  }

  func group(_ list: [EmailEnvelope], _ by: EmailGroupBy) -> [EmailThreadGroup] {
    EmailGrouping.group(threads(list), by: by, now: now, timeZone: saoPaulo)
  }

  @Test func noneIsOneGroupInTheGivenOrder() {
    let list = threads([
      envelope("1", subject: "A", date: "2026-10-04T10:00:00"),
      envelope("2", subject: "B", date: "2026-10-03T10:00:00"),
    ])
    let groups = EmailGrouping.group(list, by: .none, now: now, timeZone: saoPaulo)
    #expect(groups.count == 1)
    #expect(groups[0].threads == list)
  }

  @Test func byAccountUsesTheBoxName() {
    let groups = group(
      [
        envelope("1", account: "mail-1", accountLabel: "Trabalho", subject: "A"),
        envelope("2", account: "mail-2", accountLabel: "Pessoal", subject: "B", date: "2026-10-04T09:00:00"),
        envelope("3", account: "mail-1", accountLabel: "Trabalho", subject: "C", date: "2026-10-04T08:00:00"),
      ], .account)
    #expect(keys(groups) == ["Trabalho: A,C", "Pessoal: B"])
  }

  @Test func bySenderIgnoresCase() {
    let groups = group(
      [
        envelope("1", from: "GitHub", subject: "A"),
        envelope("2", from: "github", subject: "B", date: "2026-10-04T09:00:00"),
        envelope("3", from: "Luan", subject: "C", date: "2026-10-04T08:00:00"),
      ], .sender)
    #expect(keys(groups) == ["GitHub: A,B", "Luan: C"])
  }

  @Test func bySenderUsesWhoWroteLastIgnoringSent() {
    let groups = group(
      [
        envelope("1", from: "Luan", subject: "Proposta", messageId: "<raiz@x>"),
        envelope(
          "2", from: "Milton", subject: "Re: Proposta", date: "2026-10-04T11:00:00", messageId: "<r1@x>",
          references: ["<raiz@x>"]),
        envelope(
          "3", from: "Eu", subject: "Re: Proposta", date: "2026-10-04T12:00:00", messageId: "<r2@x>",
          references: ["<raiz@x>", "<r1@x>"], mailbox: .sent, folder: "Sent"),
      ], .sender)
    #expect(groups.map(\.label) == ["Milton"])
  }

  @Test func byDateInRelativeBuckets() {
    let groups = group(
      [
        envelope("1", subject: "hoje", date: "2026-10-04T08:00:00"),
        envelope("2", subject: "ontem", date: "2026-10-03T23:00:00"),
        envelope("3", subject: "semana", date: "2026-09-29T10:00:00"),
        envelope("4", subject: "mês", date: "2026-09-10T10:00:00"),
        envelope("5", subject: "antigo", date: "2026-07-01T10:00:00"),
      ], .date)
    #expect(
      keys(groups) == [
        "Hoje: hoje", "Ontem: ontem", "Últimos 7 dias: semana", "Últimos 30 dias: mês", "Mais antigos: antigo",
      ])
  }

  @Test func followsTheChosenSort() {
    let list = Array(
      threads([
        envelope("1", subject: "hoje", date: "2026-10-04T08:00:00"),
        envelope("2", subject: "antigo", date: "2026-07-01T10:00:00"),
      ]).reversed())
    #expect(
      EmailGrouping.group(list, by: .date, now: now, timeZone: saoPaulo).map(\.label) == ["Mais antigos", "Hoje"])
  }

  @Test func unreadableDateIsOlder() {
    #expect(group([envelope("1", subject: "sem data", date: "lixo")], .date).map(\.label) == ["Mais antigos"])
  }

  @Test func noConversationNoGroup() {
    #expect(EmailGrouping.group([], by: .account, now: now, timeZone: saoPaulo).isEmpty)
  }

  @Test func optionLabels() {
    #expect(EmailGroupBy.allCases.map(\.optionLabel) == ["Sem agrupar", "Por conta", "Por remetente", "Por data"])
  }
}

@Suite struct EmailListingTests {
  let now = localDate("2026-10-04T15:00:00")

  func build(_ list: [EmailEnvelope], _ filters: EmailFilters = EmailFilters()) -> EmailListing {
    EmailListing.build(all: list, filters: filters, now: now, timeZone: saoPaulo)
  }

  @Test func searchIsAccentAndCaseInsensitiveOverSubjectAndSender() {
    let list = [
      envelope("1", from: "Ana", subject: "Revisão do relatório"),
      envelope("2", from: "Luan Ávila", subject: "Outro"),
      envelope("3", from: "Bruno", subject: "Nada"),
    ]
    #expect(build(list, EmailFilters(query: "revisao")).visible.map(\.id) == ["1"])
    #expect(build(list, EmailFilters(query: " avila ")).visible.map(\.id) == ["2"])
    #expect(build(list, EmailFilters(query: "   ")).visible.count == 3)
  }

  @Test func unreadAndAccountFilters() {
    let list = [
      envelope("1", account: "a", unread: true), envelope("2", account: "a"), envelope("3", account: "b", unread: true),
    ]
    #expect(Set(build(list, EmailFilters(onlyUnread: true)).visible.map(\.id)) == ["1", "3"])
    #expect(build(list, EmailFilters(onlyUnread: true, account: "b")).visible.map(\.id) == ["3"])
  }

  @Test func sortsRecentOrOldest() {
    let list = [
      envelope("1", subject: "um", date: "2026-10-02T10:00:00"),
      envelope("2", subject: "dois", date: "2026-10-04T10:00:00"),
      envelope("3", subject: "três", date: "2026-10-03T10:00:00"),
    ]
    #expect(build(list).order == ["mail-1:2", "mail-1:3", "mail-1:1"])
    #expect(build(list, EmailFilters(sort: .oldest)).order == ["mail-1:1", "mail-1:3", "mail-1:2"])
  }

  @Test func sentAloneIsNotARowButJoinsAConversation() {
    let list = [
      envelope("1", subject: "Só minha", mailbox: .sent, folder: "Sent"),
      envelope("2", subject: "Proposta", messageId: "<p@x>"),
      envelope(
        "9", subject: "Re: Proposta", date: "2026-10-04T11:00:00", messageId: "<q@x>", references: ["<p@x>"],
        mailbox: .sent, folder: "Sent"),
    ]
    let listing = build(list)
    #expect(listing.threads.map(\.subject) == ["Proposta"])
    #expect(listing.threads[0].messages.count == 2)
    #expect(listing.threads[0].received.map(\.id) == ["2"])
  }

  @Test func groupedOrderIsTheScreenOrder() {
    let list = [
      envelope("1", account: "a", accountLabel: "A", subject: "x", date: "2026-10-04T10:00:00"),
      envelope("2", account: "b", accountLabel: "B", subject: "y", date: "2026-10-04T09:00:00"),
      envelope("3", account: "a", accountLabel: "A", subject: "z", date: "2026-10-04T08:00:00"),
    ]
    #expect(build(list, EmailFilters(groupBy: .account)).order == ["a:1", "a:3", "b:2"])
  }

  @Test func activeFilterLabels() {
    let boxes = [MailboxRef(id: "b", label: "Pessoal")]
    let filters = EmailFilters(query: " luan ", onlyUnread: true, account: "b")
    #expect(filters.active(mailboxes: boxes).map(\.label) == ["Busca: luan", "Não lidos", "Pessoal"])
    #expect(EmailFilters(account: "x").active(mailboxes: boxes).map(\.label) == ["x"])
  }

  @Test(arguments: [
    ("2026-10-04T14:59:30", "agora"), ("2026-10-04T14:55:00", "5min"), ("2026-10-04T12:00:00", "3h"),
    ("2026-10-03T14:00:00", "ontem"), ("2026-09-30T15:00:00", "4d"), ("2026-09-01T10:00:00", "01/09"),
    ("lixo", ""),
  ])
  func relativeTime(iso: String, expected: String) {
    #expect(EmailDates.relativeTime(iso, now: now, timeZone: saoPaulo) == expected)
  }

  @Test func parsesTheServerShapes() {
    #expect(EmailDates.parse("2026-10-04T18:00:00.000Z", timeZone: saoPaulo) == now)
    #expect(EmailDates.parse("2026-10-04T15:00:00-03:00", timeZone: .gmt) == now)
    #expect(EmailDates.parse("2026-10-04", timeZone: saoPaulo) == Date(timeIntervalSince1970: 1_791_072_000))
    #expect(EmailDates.parse("2026-02-30T10:00:00", timeZone: saoPaulo) == nil)
  }

  @Test func linksKeepTrailingPunctuationOut() {
    let segments = EmailLinks.segments("veja https://x.com/y. e (http://a.b/c), fim")
    #expect(
      segments.map(\.text) == ["veja ", "https://x.com/y", ". e (", "http://a.b/c", "), fim"])
    #expect(segments.compactMap(\.url).map(\.absoluteString) == ["https://x.com/y", "http://a.b/c"])
    #expect(EmailLinks.segments("sem link") == [EmailLinks.Segment(text: "sem link")])
  }
}
