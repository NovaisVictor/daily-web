import DailyCore
import DailyModels
import Foundation

/// The two lists of the panel (`ABAS` in `components/SlackPanel.tsx`).
nonisolated enum SlackTab: String, CaseIterable, Identifiable, Sendable {
  case mentions
  case directs

  var id: String { rawValue }

  var label: String {
    switch self {
    case .mentions: "Menções"
    case .directs: "Mensagens diretas"
    }
  }

  var emptyText: String {
    switch self {
    case .mentions: "Nenhuma menção nos últimos 7 dias."
    case .directs: "Nenhuma mensagem direta não lida."
    }
  }

  func items(in digest: SlackDigest?) -> [SlackMessage] {
    switch self {
    case .mentions: digest?.mentions ?? []
    case .directs: digest?.directs ?? []
    }
  }

  /// The tab that lists `id`; nil when neither does (the message left the digest).
  static func containing(_ id: String, in digest: SlackDigest?) -> SlackTab? {
    allCases.first { tab in tab.items(in: digest).contains { $0.id == id } }
  }
}

/// `formatRelative` (`lib/format.ts:39-49`): the same unit steps and rounding,
/// so the app and the web say "há 5 minutos" for the same message.
nonisolated enum SlackDates {
  static let emDash = "—"

  /// `relativeTime` in `lib/format.ts`; "—" for a date the web cannot read.
  static func relative(_ value: String, now: Date) -> String {
    guard let date = RelativeTime.parseISO(value) else { return emDash }
    return RelativeTime.named(date, now: now)
  }
}
