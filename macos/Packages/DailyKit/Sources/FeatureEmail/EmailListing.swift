import DailyModels
import Foundation

nonisolated enum EmailSort: String, CaseIterable, Sendable, Identifiable {
  case recent
  case oldest

  var id: String { rawValue }

  var label: String {
    switch self {
    case .recent: "Mais recentes"
    case .oldest: "Mais antigos"
    }
  }
}

/// The search, chips and selects above the list (`EmailPanel.tsx`).
nonisolated struct EmailFilters: Equatable, Sendable {
  var query = ""
  var onlyUnread = false
  /// nil is "all accounts".
  var account: String?
  var sort: EmailSort = .recent
  var groupBy: EmailGroupBy = .none

  /// Accent- and case-insensitive on both sides, so "revisao" finds "Revisão"
  /// (`matchesQuery` in `lib/filters.ts`).
  static func matches(_ fields: [String], query: String) -> Bool {
    let term = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    if term.isEmpty { return true }
    return fields.contains { normalize($0).contains(term) }
  }

  private static func normalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
  }

  struct Active: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case query, unread, account }
    var kind: Kind
    var label: String
    var id: String { "\(kind)" }
  }

  /// The removable badges under the bar (`activeFilters`).
  func active(mailboxes: [MailboxRef]) -> [Active] {
    var list: [Active] = []
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { list.append(Active(kind: .query, label: "Busca: \(trimmed)")) }
    if onlyUnread { list.append(Active(kind: .unread, label: "Não lidos")) }
    if let account {
      list.append(Active(kind: .account, label: mailboxes.first { $0.id == account }?.label ?? account))
    }
    return list
  }
}

/// Everything the list draws, derived from the messages and the filters.
nonisolated struct EmailListing: Equatable, Sendable {
  var all: [EmailEnvelope]
  var visible: [EmailEnvelope]
  var threads: [EmailThread]
  var groups: [EmailThreadGroup]
  /// The screen order of the conversations, which is what a range means.
  var order: [String]

  static func build(all: [EmailEnvelope], filters: EmailFilters, now: Date, timeZone: TimeZone) -> EmailListing {
    let filtered = all.filter { message in
      EmailFilters.matches([message.subject, message.from], query: filters.query)
        && (!filters.onlyUnread || message.unread)
        && (filters.account == nil || message.account == filters.account)
    }
    let recent = filters.sort == .recent
    let visible = filtered.stableSorted { recent ? $0.date > $1.date : $0.date < $1.date }
    // Threads are built after the filters, and sent messages only join a
    // conversation: one nobody answered is not part of the inbox.
    let threads = EmailThreading.threads(visible)
      .filter { thread in thread.messages.contains { $0.mailbox == .inbox } }
      .stableSorted { recent ? $0.lastDate > $1.lastDate : $0.lastDate < $1.lastDate }
    let groups = EmailGrouping.group(threads, by: filters.groupBy, now: now, timeZone: timeZone)
    return EmailListing(
      all: all, visible: visible, threads: threads, groups: groups,
      order: groups.flatMap { $0.threads.map(\.id) })
  }
}

/// Turns the addresses of a plain-text body into links (`linkify` in
/// `EmailPanel.tsx`); trailing punctuation stays with the sentence.
nonisolated enum EmailLinks {
  struct Segment: Equatable, Sendable {
    var text: String
    var url: URL?
  }

  static func segments(_ text: String) -> [Segment] {
    var segments: [Segment] = []
    var rest = text[...]
    while let match = rest.firstMatch(of: #/https?://[^\s<>()]+/#) {
      if match.range.lowerBound > rest.startIndex {
        segments.append(Segment(text: String(rest[rest.startIndex..<match.range.lowerBound])))
      }
      var address = String(match.output)
      while let last = address.last, ".,;:!?)'\"".contains(last) { address.removeLast() }
      segments.append(Segment(text: address, url: URL(string: address)))
      rest = rest[rest.index(match.range.lowerBound, offsetBy: address.count)...]
    }
    if !rest.isEmpty { segments.append(Segment(text: String(rest))) }
    return segments
  }

  static func attributed(_ text: String) -> AttributedString {
    var result = AttributedString()
    for segment in segments(text) {
      var piece = AttributedString(segment.text)
      if let url = segment.url {
        piece.link = url
        piece.underlineStyle = .single
      }
      result += piece
    }
    return result
  }
}
