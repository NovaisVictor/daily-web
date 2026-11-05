import DailyDesign
import DailyModels
import SwiftUI

/// One story of the bulk start-date review (`Row`, `components/jira/actions/BulkStartDate.tsx`).
struct BulkStartDateRow: Equatable, Identifiable {
  enum Kind: Equatable {
    case editable(date: String, basis: JiraStartDateBasis, included: Bool)
    case unavailable(error: String)
  }

  let key: String
  let summary: String
  var kind: Kind

  var id: String { key }
}

nonisolated enum BulkStartDates {
  static let missingStart: [JiraProblem] = [.storyInProgressWithoutStart, .storyDoneWithoutStart]

  /// The problems the button counts: stories missing their start date.
  static func missing(_ problems: [JiraProblemItem]) -> [JiraProblemItem] {
    problems.filter { issue in issue.problems.contains { missingStart.contains($0) } }
  }

  /// A suggestion with a basis the app does not know is no suggestion, as
  /// `isSuggestion` refuses it on the web.
  static func rows(_ suggestions: [JiraStartDateKeySuggestion], summaries: [String: String]) -> [BulkStartDateRow] {
    suggestions.map { suggestion in
      let summary = summaries[suggestion.key] ?? ""
      if suggestion.status == .suggested, let date = suggestion.date, let basis = suggestion.basis,
        JiraText.basisNote(basis) != nil
      {
        return BulkStartDateRow(
          key: suggestion.key, summary: summary, kind: .editable(date: date, basis: basis, included: true))
      }
      return BulkStartDateRow(
        key: suggestion.key, summary: summary,
        kind: .unavailable(error: suggestion.error ?? "resposta inesperada do servidor"))
    }
  }

  /// Included rows with a real calendar date no later than `limit` (today).
  static func writable(_ rows: [BulkStartDateRow], limit: String) -> [JiraEndpoints.StartDateItem] {
    rows.compactMap { row in
      guard case .editable(let date, _, true) = row.kind, isCalendarDate(date), date <= limit else { return nil }
      return JiraEndpoints.StartDateItem(key: row.key, date: date)
    }
  }

  /// `isCalendarDate`: `YYYY-MM-DD` naming a day that exists.
  static func isCalendarDate(_ value: String) -> Bool {
    guard let (year, month, day) = JiraDates.calendarParts(value) else { return false }
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    guard let date = utc.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
    let parts = utc.dateComponents([.year, .month, .day], from: date)
    return parts.year == year && parts.month == month && parts.day == day
  }
}

/// "Preencher início em todas": only on the user's own view, where a bulk
/// edit cannot land on a colleague's issues by accident.
struct BulkStartDateButton: View {
  let problems: [JiraProblemItem]
  let store: JiraStore

  enum Phase: Equatable {
    case closed
    case loading
    case failed(String)
    case review([BulkStartDateRow], error: String?)
    case writing([BulkStartDateRow])
    case written([BulkStartDateRow], results: [String: JiraStartDateResult], error: String?)
  }

  @State private var phase: Phase = .closed

  var body: some View {
    let missing = BulkStartDates.missing(problems)
    if store.activePerson == nil, !missing.isEmpty {
      HStack {
        Spacer()
        Button(phase == .loading ? "Buscando datas…" : "Preencher início em todas (\(missing.count))") {
          open(missing)
        }
        .pillButtonStyle(.outline, size: .small)
        .disabled(phase == .loading)
      }
      .sheet(isPresented: presented) {
        BulkStartDateSheet(phase: $phase, store: store)
      }
    }
  }

  private var presented: Binding<Bool> {
    Binding(
      get: { phase != .closed && phase != .loading },
      set: { if !$0 { phase = .closed } })
  }

  private func open(_ missing: [JiraProblemItem]) {
    phase = .loading
    Task {
      let result = await store.startDateSuggestions(missing.map(\.key))
      guard phase == .loading else { return }
      switch result {
      case .failure(let error): phase = .failed(error.userMessage)
      case .success(let suggestions):
        let summaries = Dictionary(missing.map { ($0.key, $0.summary) }, uniquingKeysWith: { first, _ in first })
        phase = .review(BulkStartDates.rows(suggestions, summaries: summaries), error: nil)
      }
    }
  }
}

private struct BulkStartDateSheet: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  @Binding var phase: BulkStartDateButton.Phase
  let store: JiraStore

  private var rows: [BulkStartDateRow] {
    switch phase {
    case .review(let rows, _), .writing(let rows), .written(let rows, _, _): rows
    default: []
    }
  }

  private var locked: Bool {
    if case .review = phase { return false }
    return true
  }

  private var limit: String { JiraDates.dayString(store.now()) }

  var body: some View {
    let count = BulkStartDates.writable(rows, limit: limit).count
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Preencher data de início").typeRole(.subhead).foregroundStyle(theme.ink)
        Text("Confira a data sugerida de cada história. Nada é gravado no Jira até você confirmar.")
          .font(.geist(13)).foregroundStyle(theme.inkDim)
      }
      if case .failed(let error) = phase {
        Text("Não foi possível sugerir as datas: \(error)").foregroundStyle(theme.danger)
      }
      if !rows.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in rowView(row) }
          }
        }
        .frame(maxHeight: 420)
      }
      if let error = currentError {
        Text(error).foregroundStyle(theme.danger)
      }
      HStack {
        Spacer()
        switch phase {
        case .written, .failed:
          Button("Fechar") { phase = .closed }.pillButtonStyle(.outline).keyboardShortcut(.defaultAction)
        default:
          Button("Cancelar") { phase = .closed }.pillButtonStyle(.outline).keyboardShortcut(.cancelAction)
          Button(phase.isWriting ? "Gravando…" : "Gravar \(count) \(count == 1 ? "data" : "datas")") { write() }
            .pillButtonStyle()
            .disabled(locked || count == 0)
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .font(.geist(13))
    .padding(20)
    .frame(width: 640)
  }

  private var currentError: String? {
    switch phase {
    case .review(_, let error), .written(_, _, let error): error
    default: nil
    }
  }

  @ViewBuilder
  private func rowView(_ row: BulkStartDateRow) -> some View {
    let result: JiraStartDateResult? = if case .written(_, let results, _) = phase { results[row.key] } else { nil }
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        if case .editable(let date, _, let included) = row.kind {
          Toggle(
            "Incluir \(row.key)",
            isOn: Binding(get: { included }, set: { edit(row.key, date: date, included: $0) })
          )
          .toggleStyle(.checkbox)
          .labelsHidden()
          .accessibilityLabel("Incluir \(row.key)")
          .disabled(locked)
        }
        Text(row.key).font(.dailyMono(size: 13)).foregroundStyle(theme.brand)
        Text(row.summary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        if case .editable(let date, _, let included) = row.kind {
          DatePicker(
            "Data de início de \(row.key)",
            selection: Binding(
              get: { JiraDates.localDate(date) ?? store.now() },
              set: { edit(row.key, date: JiraDates.dayString($0), included: included) }),
            in: ...store.now(),
            displayedComponents: .date
          )
          .labelsHidden()
          .accessibilityLabel("Data de início de \(row.key)")
          .disabled(locked)
        }
      }
      switch row.kind {
      case .editable(_, let basis, _):
        if let note = JiraText.basisNote(basis) { Text(note).font(.geist(12)).foregroundStyle(theme.inkDim) }
      case .unavailable(let error):
        Text("Sem sugestão: \(error)").font(.geist(12)).foregroundStyle(theme.danger)
      }
      if result?.outcome == .written {
        Text("gravada ✓").font(.geist(12)).foregroundStyle(theme.success)
      } else if result?.outcome == .refused {
        Text("Jira recusou: \(result?.error ?? "sem detalhe")").font(.geist(12)).foregroundStyle(theme.danger)
      }
    }
  }

  private func edit(_ key: String, date: String, included: Bool) {
    guard case .review(let rows, let error) = phase else { return }
    let next = rows.map { row in
      guard row.key == key, case .editable(_, let basis, _) = row.kind else { return row }
      var copy = row
      copy.kind = .editable(date: date, basis: basis, included: included)
      return copy
    }
    phase = .review(next, error: error)
  }

  private func write() {
    guard case .review(let rows, _) = phase else { return }
    let items = BulkStartDates.writable(rows, limit: limit)
    guard !items.isEmpty else { return }
    phase = .writing(rows)
    Task {
      let (results, error) = await store.writeStartDates(items)
      guard case .writing = phase else { return }
      if results.isEmpty {
        phase = .review(rows, error: error?.userMessage)
      } else {
        phase = .written(
          rows, results: Dictionary(results.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last }),
          error: error?.userMessage)
      }
    }
  }
}

extension BulkStartDateButton.Phase {
  fileprivate var isWriting: Bool {
    if case .writing = self { return true }
    return false
  }
}
