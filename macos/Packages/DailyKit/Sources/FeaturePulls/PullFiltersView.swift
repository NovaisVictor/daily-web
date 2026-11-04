import DailyDesign
import SwiftUI

/// Search, the secondary filters behind one button, and the active filters
/// below (`components/pulls/PullFilters.tsx`).
struct PullFiltersView: View {
  @Bindable var store: PullsStore
  @State private var showingPopover = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      FilterBar("filtrar pull requests") {
        SearchField(
          text: $store.filters.query, label: "buscar pull requests", placeholder: "título, repo#número, autor, card")
        Button {
          showingPopover = true
        } label: {
          Label(
            store.hiddenFilterCount > 0 ? "Filtros (\(store.hiddenFilterCount))" : "Filtros",
            systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtros, \(countLabel(store.hiddenFilterCount))")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
          PullFilterPopover(store: store)
        }
      }
      PullActiveFiltersRow(filters: store.activeFilters, remove: store.clear, clearAll: store.clearFilters)
    }
  }

  /// `countLabel` in `components/ui/FilterPopover.tsx`.
  private func countLabel(_ count: Int) -> String {
    if count == 0 { return "nenhum ativo" }
    return count == 1 ? "1 ativo" : "\(count) ativos"
  }
}

/// The popover's sections: repository, author, then the states grouped by question.
private struct PullFilterPopover: View {
  @Environment(\.theme) private var theme
  @Bindable var store: PullsStore

  var body: some View {
    let options = store.filterOptions
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        section("Repositório") {
          MultiValueFilter(
            label: "filtrar por repositório", placeholder: "Todos os repositórios", group: $store.filters.repo,
            options: options.repos)
        }
        section("Autor") {
          MultiValueFilter(
            label: "filtrar por autor", placeholder: "Todos os autores", group: $store.filters.author,
            options: options.authors)
        }
        ForEach(PullState.groups, id: \.title) { group in
          section(group.title) {
            ForEach(group.states, id: \.self) { state in
              Toggle(
                state.label,
                isOn: Binding(get: { store.filters.state.contains(state) }, set: { _ in store.toggle(state) })
              )
              .toggleStyle(.checkbox)
            }
          }
        }
      }
      .padding(16)
    }
    .frame(width: 320)
    .frame(maxHeight: 520)
    .accessibilityLabel("filtros de pull requests")
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).typeRole(.caption).foregroundStyle(theme.inkDim).accessibilityAddTraits(.isHeader)
      content()
    }
  }
}

/// Include/exclude mode and the options with their counts
/// (`components/JiraMultiFilterDropdown.tsx`), laid out inline in the popover.
private struct MultiValueFilter: View {
  @Environment(\.theme) private var theme
  let label: String
  let placeholder: String
  @Binding var group: PullFilterGroup
  let options: [PullFilterOption]
  @State private var search = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Picker(label, selection: $group.mode) {
          Text("É igual a (=)").tag(PullFilterMode.include)
          Text("Não é igual a (≠)").tag(PullFilterMode.exclude)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("modo de \(label)")
        if !group.values.isEmpty {
          Button("Limpar") { group.values = [] }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("limpar opções de \(label)")
        }
      }
      if options.count > 5 {
        TextField("Buscar opção...", text: $search)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
      }
      if options.isEmpty {
        Text(placeholder).typeRole(.caption).foregroundStyle(theme.inkDim)
      }
      ForEach(visible) { option in
        Toggle(
          "\(option.value) (\(option.count))",
          isOn: Binding(get: { group.values.contains(option.value) }, set: { _ in group.toggle(option.value) })
        )
        .toggleStyle(.checkbox)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private var visible: [PullFilterOption] {
    let term = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !term.isEmpty else { return options }
    return options.filter { $0.value.lowercased().contains(term) }
  }
}

/// The active filters as removable badges, and "Limpar tudo" from two on
/// (`components/ui/ActiveFilters.tsx`).
struct PullActiveFiltersRow: View {
  @Environment(\.theme) private var theme
  let filters: [PullActiveFilter]
  let remove: (PullActiveFilter.Kind) -> Void
  let clearAll: () -> Void

  var body: some View {
    if !filters.isEmpty {
      FlowLayout(spacing: 8) {
        ForEach(filters) { filter in
          HStack(spacing: 4) {
            Text(filter.label).typeRole(.caption)
            Button {
              remove(filter.id)
            } label: {
              Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkDim)
            .accessibilityLabel("remover filtro \(filter.label)")
          }
          .padding(.leading, 8)
          .padding(.trailing, 4)
          .padding(.vertical, 3)
          .background(theme.neutralTint, in: .capsule)
        }
        if filters.count > 1 {
          Button("Limpar tudo", systemImage: "xmark", action: clearAll)
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
      }
    }
  }
}
