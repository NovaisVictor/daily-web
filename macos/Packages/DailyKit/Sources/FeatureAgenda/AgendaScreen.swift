import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The agenda module (`components/AgendaPanel.tsx`): period, events grouped by
/// day and the drop zone that books a focus block.
public struct AgendaScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: AgendaStore
  private let session: SessionStore

  public init(environment: AppEnvironment) {
    session = environment.session
    _store = State(
      initialValue: AgendaStore(
        dashboard: environment.dashboard,
        preferences: environment.preferences,
        focus: environment.focus
      ))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SectionHeader("Agenda")
        if store.acceptsDrops {
          FocusDropTarget("Solte aqui para agendar um bloco de foco", for: FocusSource.self) { items in
            store.receiveDrop(items)
          }
        }
        FilterBar("Período da agenda") {
          ForEach(AgendaRange.all) { range in
            Chip(range.label, isOn: range.days == store.days, isDisabled: store.isChangingRange) {
              Task { await store.chooseRange(range.days) }
            }
          }
        }
        content
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .sheet(item: $store.draft) { draft in
      FocusBlockSheet(store: store, draft: draft, server: session.serverURL)
    }
  }

  @ViewBuilder private var content: some View {
    if store.state == nil {
      LoadingState()
    } else {
      if let error = store.agenda?.error {
        PanelError(error)
      }
      if store.items.isEmpty, store.agenda?.error == nil {
        EmptyState(AgendaRange.emptyText(days: store.days))
      }
      ForEach(store.groups) { group in
        AgendaDayView(
          label: store.dayLabel(group.date),
          items: group.items,
          showsAccountLabels: store.showsAccountLabels
        )
      }
    }
  }
}

private struct AgendaDayView: View {
  @Environment(\.theme) private var theme
  let label: String
  let items: [AgendaItem]
  let showsAccountLabels: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .accessibilityAddTraits(.isHeader)
      VStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          AgendaRow(item: item, showsAccountLabel: showsAccountLabels, striped: index % 2 == 1)
          if index < items.count - 1 {
            Divider().overlay(theme.lineSoft)
          }
        }
      }
    }
  }
}

private struct AgendaRow: View {
  @Environment(\.theme) private var theme
  let item: AgendaItem
  let showsAccountLabel: Bool
  let striped: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      // An all-day event has no time (`AgendaPanel.tsx:161`).
      Text(item.time.isEmpty ? "dia" : item.time)
        .font(.system(size: 14).monospacedDigit())
        .foregroundStyle(theme.ink)
        .frame(width: 44, alignment: .leading)
      Text(item.title.isEmpty ? "—" : item.title)
        .font(.system(size: 14))
        .foregroundStyle(theme.inkMid)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      if showsAccountLabel, !item.accountLabel.isEmpty {
        Text(item.accountLabel)
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(theme.neutralTint, in: .capsule)
          .overlay { Capsule().strokeBorder(theme.lineStrong) }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, theme.metrics.rowVerticalPadding)
    .background(striped ? theme.lineSoft.opacity(0.25) : .clear)
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  AgendaScreen(environment: .preview())
    .frame(width: 560, height: 520)
}
