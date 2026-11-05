import DailyDesign
import DailyModels
import SwiftUI

/// One option of a multi-value selector (`JiraMultiFilterOption`).
struct JiraFilterOption: Identifiable, Equatable {
  let value: String
  let label: String
  var secondary: String?

  var id: String { value }
}

/// The popover behind "filtros do Jira" (`FilterPopover` in `JiraPanel.tsx`).
struct JiraFilterPopover: View {
  @Environment(\.theme) private var theme
  @Bindable var store: JiraStore
  let known: [String: JiraItem]

  var body: some View {
    let options = store.filterOptions(known: known)
    let person = store.activePerson != nil
    VStack(alignment: .leading, spacing: 14) {
      // Role and display only apply to "Em aberto".
      if store.tab == .open {
        section("Papel") {
          HStack(spacing: 6) {
            ForEach(JiraRoleFilter.allCases) { role in
              Chip(role.label(person: person), isOn: store.role == role) { store.role = role }
            }
          }
        }
        section("Exibição") {
          Chip(store.grouped ? "Lista simples" : "Hierarquia", isOn: !store.grouped) { store.grouped.toggle() }
        }
      }
      section("Status") {
        JiraMultiFilter(
          label: "filtrar por status", title: "Filtrar por Status", placeholder: "Status", name: "Status",
          group: store.filters.status, options: options.statuses.map { JiraFilterOption(value: $0, label: $0) },
          formatLabel: { $0 }
        ) { store.filters.status = $0 }
      }
      section("Tipo") {
        JiraMultiFilter(
          label: "filtrar por tipo", title: "Filtrar por Tipo", placeholder: "Tipo", name: "Tipo",
          group: store.filters.tier,
          options: JiraTier.allCases.map { JiraFilterOption(value: $0.rawValue, label: $0.label) },
          formatLabel: { JiraTier(rawValue: $0)?.label ?? $0 }
        ) { store.filters.tier = $0 }
      }
      section("Hierarquia") {
        // The three tiers cascade, and the chevron says so.
        HStack(spacing: 2) {
          hierarchy(.initiative, "iniciativa", "Iniciativa", options.initiatives)
          chevron
          hierarchy(.epic, "épico", "Épico", options.epics)
          chevron
          hierarchy(.story, "história", "História", options.stories)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("hierarquia do Jira")
      }
    }
    .padding(16)
    .frame(width: 420, alignment: .leading)
  }

  private var chevron: some View {
    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(theme.inkDim)
      .accessibilityHidden(true)
  }

  private func hierarchy(_ field: JiraFilterField, _ lower: String, _ name: String, _ items: [JiraItem])
    -> some View
  {
    JiraMultiFilter(
      label: "filtrar por \(lower)", title: "Filtrar por \(name)", placeholder: name, name: name,
      group: store.filters[field],
      options: items.map {
        JiraFilterOption(value: $0.key, label: store.label(for: $0.key, known: known), secondary: $0.key)
      },
      formatLabel: { store.label(for: $0, known: known) }
    ) { next in
      // The story tier has nothing below it, so `change` equals a plain set there.
      store.filters.change(field, to: next)
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).typeRole(.caption).foregroundStyle(theme.inkDim).accessibilityAddTraits(.isHeader)
      content()
    }
  }
}

/// A multi-value selector with include/exclude (`components/JiraMultiFilterDropdown.tsx`).
struct JiraMultiFilter: View {
  @Environment(\.theme) private var theme
  let label: String
  let title: String
  let placeholder: String
  let name: String
  let group: JiraFilterGroup
  let options: [JiraFilterOption]
  let formatLabel: (String) -> String
  let onChange: (JiraFilterGroup) -> Void

  @State private var open = false
  @State private var search = ""

  /// Chosen values stay listed even when the tab's options no longer hold them.
  private var allOptions: [JiraFilterOption] {
    var list = options
    for value in group.values where !list.contains(where: { $0.value == value }) {
      list.insert(JiraFilterOption(value: value, label: formatLabel(value)), at: 0)
    }
    return list
  }

  private var filtered: [JiraFilterOption] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return allOptions }
    return allOptions.filter {
      $0.label.lowercased().contains(query) || ($0.secondary?.lowercased().contains(query) ?? false)
    }
  }

  private var exclude: Bool { group.mode == .exclude }

  private var triggerText: String {
    switch group.values.count {
    case 0: placeholder
    case 1: allOptions.first { $0.value == group.values[0] }?.label ?? formatLabel(group.values[0])
    default: "\(name) (\(group.values.count))"
    }
  }

  var body: some View {
    let state = group.values.isEmpty ? "" : ", \(exclude ? "excluindo" : "incluindo") \(triggerText)"
    Button {
      open.toggle()
    } label: {
      HStack(spacing: 6) {
        if !group.values.isEmpty {
          Text(exclude ? "≠" : "=")
            .font(.geist(11, weight: .bold))
            .foregroundStyle(exclude ? Color.white : theme.brandInk)
            .padding(.horizontal, 4)
            .background(exclude ? theme.danger : theme.brand, in: .rect(cornerRadius: 3))
            .help(exclude ? "Modo: não é igual a (exclusão)" : "Modo: é igual a (inclusão)")
        }
        Text(triggerText)
          .font(.geist(12))
          .foregroundStyle(group.values.isEmpty ? theme.inkDim : theme.ink)
          .lineLimit(1)
          .frame(maxWidth: 176, alignment: .leading)
        Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(theme.inkDim)
      }
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(
        group.values.isEmpty ? theme.surface2 : (exclude ? theme.dangerTint : theme.brandTint),
        in: .rect(cornerRadius: 6)
      )
      .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.lineStrong) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("abrir menu \(label)\(state)")
    .popover(isPresented: $open, arrowEdge: .bottom) { panel }
  }

  private func modeButton(_ mode: JiraFilterMode) -> some View {
    let current = group.mode == mode
    let tint = mode == .exclude ? theme.danger : theme.surface2
    return Button {
      onChange(JiraFilterGroup(group.values, mode: mode))
    } label: {
      Text(mode.title)
        .font(.geist(11, weight: .medium))
        .foregroundStyle(current ? (mode == .exclude ? Color.white : theme.ink) : theme.inkDim)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(current ? tint : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(mode.accessibilityLabel(for: label))
    .accessibilityAddTraits(current ? .isSelected : [])
  }

  private var panel: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title).fontWeight(.semibold).foregroundStyle(theme.ink)
        Spacer()
        if !group.values.isEmpty {
          Button("Limpar") { onChange(JiraFilterGroup([], mode: group.mode)) }
            .pillButtonStyle(.ghost, size: .small)
            .accessibilityLabel("limpar opções de \(label)")
        }
      }
      // Two buttons, as the web: each one names its mode aloud (`JiraMultiFilterDropdown.tsx:172-195`).
      HStack(spacing: 4) {
        ForEach([JiraFilterMode.include, .exclude], id: \.self) { mode in
          modeButton(mode)
        }
      }
      .padding(3)
      .background(theme.surface1, in: .rect(cornerRadius: 8))
      if allOptions.count > 5 {
        TextField("Buscar opção...", text: $search).textFieldStyle(.roundedBorder)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          if filtered.isEmpty {
            Text("Nenhuma opção encontrada").foregroundStyle(theme.inkDim).frame(maxWidth: .infinity)
              .padding(.vertical, 10)
          }
          ForEach(filtered) { option in
            Toggle(isOn: Binding(get: { group.values.contains(option.value) }, set: { _ in toggle(option.value) })) {
              HStack {
                Text(option.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let secondary = option.secondary {
                  Text(secondary).font(.dailyMono(size: 10)).foregroundStyle(theme.inkDim)
                }
              }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(option.label)
          }
        }
      }
      .frame(maxHeight: 208)
      Divider()
      HStack {
        Text("\(group.values.count) de \(allOptions.count) selecionados")
        Spacer()
        if exclude { Text("Excluindo selecionados").foregroundStyle(theme.danger) }
      }
      .font(.geist(11))
      .foregroundStyle(theme.inkDim)
    }
    .font(.geist(12))
    .padding(12)
    .frame(width: 288)
  }

  private func toggle(_ value: String) {
    let values =
      group.values.contains(value) ? group.values.filter { $0 != value } : group.values + [value]
    onChange(JiraFilterGroup(values, mode: group.mode))
  }
}
