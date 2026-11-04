import DailyModels
import Foundation

/// How the list is grouped (`lib/emailGroups.ts`).
nonisolated enum EmailGroupBy: String, CaseIterable, Sendable, Identifiable {
  case none
  case account
  case sender
  case date

  var id: String { rawValue }

  /// `EMAIL_GROUP_LABEL`.
  var label: String {
    switch self {
    case .none: "Sem agrupar"
    case .account: "Conta"
    case .sender: "Remetente"
    case .date: "Data"
    }
  }

  /// The option text of the toolbar select ("Por conta").
  var optionLabel: String {
    self == .none ? label : "Por \(label.lowercased())"
  }
}

nonisolated struct EmailThreadGroup: Identifiable, Equatable, Sendable {
  var key: String
  var label: String
  var threads: [EmailThread]

  var id: String { key }
}

nonisolated enum EmailGrouping {
  /// `senderLabel` in `lib/email/fromEmail.ts`.
  static func senderLabel(_ from: String) -> String {
    let collapsed = from.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return collapsed.isEmpty ? "remetente desconhecido" : collapsed
  }

  /// Groups appear in the order of their first conversation, so they follow
  /// the chosen sort.
  static func group(
    _ threads: [EmailThread], by: EmailGroupBy, now: Date, timeZone: TimeZone
  ) -> [EmailThreadGroup] {
    if by == .none { return [EmailThreadGroup(key: "all", label: "", threads: threads)] }
    var order: [String] = []
    var groups: [String: EmailThreadGroup] = [:]
    for thread in threads {
      let (key, label) = groupOf(thread, by: by, now: now, timeZone: timeZone)
      if groups[key] == nil {
        order.append(key)
        groups[key] = EmailThreadGroup(key: key, label: label, threads: [])
      }
      groups[key]?.threads.append(thread)
    }
    return order.compactMap { groups[$0] }
  }

  private static func groupOf(
    _ thread: EmailThread, by: EmailGroupBy, now: Date, timeZone: TimeZone
  ) -> (String, String) {
    if by == .date {
      let bucket = dateBucket(thread.lastDate, now: now, timeZone: timeZone)
      return (bucket.rawValue, bucket.label)
    }
    guard let message = latestReceived(thread) else { return ("", "") }
    if by == .account { return (message.account, message.accountLabel) }
    let label = senderLabel(message.from)
    return (label.lowercased(), label)
  }

  /// The conversation belongs to whoever wrote to you last, not to who began it.
  private static func latestReceived(_ thread: EmailThread) -> EmailEnvelope? {
    let received = thread.received
    let pool = received.isEmpty ? thread.messages : received
    guard var latest = pool.first else { return nil }
    for message in pool.dropFirst() where message.date > latest.date { latest = message }
    return latest
  }

  enum DateBucket: String {
    case today
    case yesterday
    case week
    case month
    case older

    var label: String {
      switch self {
      case .today: "Hoje"
      case .yesterday: "Ontem"
      case .week: "Últimos 7 dias"
      case .month: "Últimos 30 dias"
      case .older: "Mais antigos"
      }
    }
  }

  static func dateBucket(_ iso: String, now: Date, timeZone: TimeZone) -> DateBucket {
    guard let instant = EmailDates.parse(iso, timeZone: timeZone) else { return .older }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let from = calendar.startOfDay(for: instant)
    let to = calendar.startOfDay(for: now)
    let days = Int((to.timeIntervalSince(from) / 86_400).rounded())
    if days <= 0 { return .today }
    if days == 1 { return .yesterday }
    if days < 7 { return .week }
    if days < 30 { return .month }
    return .older
  }
}
