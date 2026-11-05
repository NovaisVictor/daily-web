import DailyDesign
import DailyModels
import SwiftUI

/// The inline fixes of a problem row (`components/JiraProblemFix.tsx`): fill
/// the start date, choose the epic. Each one fetches a suggestion, shows it
/// for review and writes only on "Salvar".
struct ProblemFixView: View {
  let issue: JiraProblemItem
  let store: JiraStore

  private static let startProblems: [JiraProblem] = [.storyInProgressWithoutStart, .storyDoneWithoutStart]

  var body: some View {
    let needsStart = issue.problems.contains { Self.startProblems.contains($0) }
    let needsEpic = issue.problems.contains(.storyWithoutEpic)
    if needsStart || needsEpic {
      FlowLayout(spacing: 8) {
        if needsStart { StartDateFix(key: issue.key, store: store) }
        if needsEpic { EpicFix(key: issue.key, project: issue.project, store: store) }
      }
      .padding(.top, 4)
    }
  }
}

/// `Step<T>`: idle, loading, editing, saving, saved.
private enum FixStep: Equatable {
  case idle
  case loading
  case editing(String)
  case saving(String)
  case saved

  var value: String? {
    switch self {
    case .editing(let value), .saving(let value): value
    default: nil
    }
  }
}

private struct StartDateFix: View {
  @Environment(\.theme) private var theme
  let key: String
  let store: JiraStore

  @State private var step: FixStep = .idle
  @State private var note: String?
  @State private var error: String?

  var body: some View {
    HStack(spacing: 8) {
      switch step {
      case .saved:
        Text("início gravado no Jira").foregroundStyle(theme.success)
      case .editing(let value), .saving(let value):
        if value.isEmpty {
          Button("Escolher data") { step = .editing(JiraDates.dayString(store.now())) }
            .pillButtonStyle(.outline, size: .small)
            .disabled(step == .saving(value))
        } else {
          DatePicker(
            "data de início de \(key)",
            selection: Binding(
              get: { JiraDates.localDate(value) ?? store.now() },
              set: { step = .editing(JiraDates.dayString($0)) }),
            displayedComponents: .date
          )
          .labelsHidden()
          .accessibilityLabel("data de início de \(key)")
          .disabled(step == .saving(value))
        }
        Button(step == .saving(value) ? "Salvando…" : "Salvar") { save(value) }
          .pillButtonStyle(.primary, size: .small)
          .disabled(value.isEmpty || step == .saving(value))
        Button("Cancelar") { step = .idle }.pillButtonStyle(.ghost, size: .small)
        if let note { Text(note).foregroundStyle(theme.inkDim) }
        if let error { Text(error).foregroundStyle(theme.danger) }
      case .idle, .loading:
        Button(step == .loading ? "Lendo o histórico…" : "Preencher início", action: suggest)
          .pillButtonStyle(.outline, size: .small)
          .disabled(step == .loading)
        if let error { Text(error).foregroundStyle(theme.danger) }
      }
    }
    .font(.geist(12))
    .controlSize(.small)
  }

  private func suggest() {
    error = nil
    step = .loading
    Task {
      switch await store.startDateSuggestion(key) {
      case .success(let suggestion):
        let date = suggestion.date ?? ""
        note =
          (!date.isEmpty ? suggestion.basis.flatMap(JiraText.basisNote) : nil)
          ?? "o histórico não diz quando começou"
        step = .editing(date)
      case .failure(let failure):
        error = failure.userMessage
        step = .idle
      }
    }
  }

  private func save(_ date: String) {
    error = nil
    step = .saving(date)
    Task {
      if let failure = await store.setStartDate(key, date: date) {
        error = failure.userMessage
        step = .editing(date)
      } else {
        step = .saved
      }
    }
  }
}

private struct EpicFix: View {
  @Environment(\.theme) private var theme
  let key: String
  let project: String
  let store: JiraStore

  @State private var step: FixStep = .idle
  @State private var epics: [JiraParent] = []
  @State private var error: String?

  var body: some View {
    HStack(spacing: 8) {
      switch step {
      case .saved:
        Text("épico gravado no Jira").foregroundStyle(theme.success)
      case .editing(let value), .saving(let value):
        Picker("épico de \(key)", selection: Binding(get: { value }, set: { step = .editing($0) })) {
          Text("Escolha o épico").tag("")
          ForEach(epics, id: \.key) { epic in Text("\(epic.key) — \(epic.summary)").tag(epic.key) }
        }
        .labelsHidden()
        .frame(maxWidth: 288)
        .accessibilityLabel("épico de \(key)")
        .disabled(step == .saving(value))
        Button(step == .saving(value) ? "Salvando…" : "Salvar") { save(value) }
          .pillButtonStyle(.primary, size: .small)
          .disabled(value.isEmpty || step == .saving(value))
        Button("Cancelar") { step = .idle }.pillButtonStyle(.ghost, size: .small)
        if let error { Text(error).foregroundStyle(theme.danger) }
      case .idle, .loading:
        Button(step == .loading ? "Buscando épicos…" : "Escolher épico", action: fetch)
          .pillButtonStyle(.outline, size: .small)
          .disabled(step == .loading)
        if let error { Text(error).foregroundStyle(theme.danger) }
      }
    }
    .font(.geist(12))
    .controlSize(.small)
  }

  private func fetch() {
    error = nil
    step = .loading
    Task {
      switch await store.epics(project: project) {
      case .success(let list):
        epics = list
        if list.isEmpty {
          error = "nenhum épico aberto em \(project)"
          step = .idle
        } else {
          step = .editing("")
        }
      case .failure(let failure):
        error = failure.userMessage
        step = .idle
      }
    }
  }

  private func save(_ epic: String) {
    error = nil
    step = .saving(epic)
    Task {
      if let failure = await store.setParent(key, epic: epic) {
        error = failure.userMessage
        step = .editing(epic)
      } else {
        step = .saved
      }
    }
  }
}
