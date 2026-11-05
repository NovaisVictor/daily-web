import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

extension AgendaStore {
  /// `FeatureStores` key shared by the screen and the Início panel.
  static let storeKey = "agenda"

  /// The session's one agenda store (spec 011 FR-011-10). It has no lifecycle
  /// of its own (no polling, no load on appear), so any number of views can share it.
  static func shared(in environment: AppEnvironment) -> AgendaStore {
    environment.featureStores.store(storeKey) {
      AgendaStore(
        dashboard: environment.dashboard,
        preferences: environment.preferences,
        focus: environment.focus
      )
    }
  }
}

/// The body of `components/AgendaPanel.tsx` under its header: drop zone,
/// period chips, errors, loading, empty text and the days, plus the focus sheet.
struct AgendaContent: View {
  let store: AgendaStore
  let server: URL?
  /// Tells this view's drops apart from those of another view on the same store.
  @State private var presenter = UUID()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if store.acceptsDrops {
        FocusDropTarget("Solte aqui para agendar um bloco de foco", for: FocusSource.self) { items in
          store.receiveDrop(items, presenter: presenter)
        }
        .padding(.bottom, 12)
      }
      FilterBar("Período da agenda") {
        ForEach(AgendaRange.all) { range in
          Chip(range.label, isOn: range.days == store.days, isDisabled: store.isChangingRange) {
            Task { await store.chooseRange(range.days) }
          }
        }
      }
      VStack(alignment: .leading, spacing: 20) {
        if let error = store.agenda?.error {
          PanelError(error)
        }
        if let error = store.rangeError {
          PanelError(error)
        }
        if store.isLoading, store.items.isEmpty {
          AgendaSkeletonRows(count: 3)
        }
        if !store.isLoading, store.items.isEmpty, store.agenda?.error == nil {
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
    .frame(maxWidth: .infinity, alignment: .leading)
    .sheet(item: draftBinding) { draft in
      FocusBlockSheet(store: store, draft: draft, server: server)
    }
  }

  private var draftBinding: Binding<FocusDraft?> {
    Binding(
      get: { store.draft(for: presenter) },
      set: { newValue in
        if newValue == nil { store.draft = nil }
      }
    )
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
          // `px-2 py-2` in both densities, with the shared zebra and hover (AG-5).
          ListRow(index: index, isLast: index == items.count - 1, verticalPadding: 8) {
            AgendaRow(item: item, showsAccountLabel: showsAccountLabels)
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

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      // An all-day event has no time (`AgendaPanel.tsx:161`).
      Text(item.time.isEmpty ? "dia" : item.time)
        .font(.daily(size: 14).monospacedDigit())
        .foregroundStyle(theme.ink)
        .frame(width: 44, alignment: .leading)
      Text(item.title.isEmpty ? "—" : item.title)
        .font(.daily(size: 14))
        .foregroundStyle(theme.inkMid)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      if showsAccountLabel, !item.accountLabel.isEmpty {
        // `shrink-0`: on a narrow panel the title truncates, not the account.
        Text(item.accountLabel)
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          .lineLimit(1)
          .fixedSize()
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(theme.neutralTint, in: .capsule)
          .overlay { Capsule().strokeBorder(theme.lineStrong) }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// `SkeletonRows` (`components/ui/legacy-skeleton.tsx`): bars as tall as a row's
/// text, at the web's staggered widths, pulsing like `animate-pulse`.
struct AgendaSkeletonRows: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dimmed = false
  let count: Int

  /// `55 + ((i * 13) % 35)` percent.
  static func widthFraction(_ index: Int) -> CGFloat {
    CGFloat(55 + (index * 13) % 35) / 100
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(0..<count, id: \.self) { index in
        GeometryReader { proxy in
          RoundedRectangle(cornerRadius: Radius.small / 2)
            .fill(theme.neutralTint)
            .frame(width: proxy.size.width * Self.widthFraction(index))
        }
        .frame(height: 12)
      }
    }
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .opacity(dimmed ? 0.5 : 1)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dimmed = true }
    }
    .accessibilityHidden(true)
  }
}
