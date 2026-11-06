import DailyDesign
import DailyModels
import SwiftUI

/// Whose Jira is on screen, as the screen title itself (`components/jira/PersonSwitcher.tsx`).
struct PersonSwitcher: View {
  @Environment(\.theme) private var theme
  @State private var hovering = false
  let store: JiraStore

  var body: some View {
    let active = store.activePerson
    Menu {
      Picker(
        "Pessoa",
        selection: Binding(get: { active?.accountId ?? "eu" }, set: { store.selectPerson($0 == "eu" ? nil : $0) })
      ) {
        Text("Eu").tag("eu")
        ForEach(store.people) { person in Text(person.displayName).tag(person.accountId) }
      }
      .pickerStyle(.inline)
      .labelsHidden()
      Divider()
      Button("Acompanhar pessoa", systemImage: "person.badge.plus") { store.peopleSearchOpen = true }
      if let active {
        Button("Parar de acompanhar \(active.displayName)", systemImage: "xmark", role: .destructive) {
          Task { await store.unfollow(active.accountId) }
        }
      }
    } label: {
      // `PersonSwitcher.tsx:54-55`: the name truncates and a chevron says it opens a menu.
      HStack(spacing: 4) {
        Text("Jira · \(active?.displayName ?? "Eu")")
          .typeRole(.subhead)
          .foregroundStyle(hovering ? theme.inkMid : theme.ink)
          .lineLimit(1)
          .truncationMode(.tail)
        Image(systemName: "chevron.down")
          .font(.system(size: 14))
          .foregroundStyle(theme.inkDim)
          .accessibilityHidden(true)
      }
      .contentShape(.rect)
    }
    // The button menu style renders the whole label, so the chevron and the
    // truncation survive; the borderless one keeps only the text.
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .onHover { hovering = $0 }
    .accessibilityLabel("Jira · \(active?.displayName ?? "Eu")")
  }
}

/// The person search card that "Acompanhar pessoa" opens.
struct PeopleSearchCard: View {
  @Environment(\.theme) private var theme
  @Bindable var store: JiraStore
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        TextField("buscar pessoa no Jira", text: $store.peopleQuery, prompt: Text("nome da pessoa"))
          .singleLine($store.peopleQuery)
          .textFieldStyle(.roundedBorder)
          .focused($focused)
          .accessibilityLabel("buscar pessoa no Jira")
          .onKeyPress(.escape) {
            store.closePeopleSearch()
            return .handled
          }
        IconButton("fechar busca de pessoa", systemImage: "xmark") { store.closePeopleSearch() }
      }
      if let error = store.peopleError { PanelError(error) }
      if store.peopleSearching {
        Text("Buscando…").font(.daily(size: 13)).foregroundStyle(theme.inkDim)
      } else if !store.peopleCandidates.isEmpty {
        FlowLayout(spacing: 8) {
          ForEach(store.peopleCandidates) { person in
            Button(person.displayName) { Task { await store.follow(person.accountId) } }
              .pillButtonStyle(.outline, size: .small)
          }
        }
      }
    }
    .padding(16)
    .background(theme.lineSoft.opacity(0.3), in: .rect(cornerRadius: Radius.medium))
    .overlay { RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.lineSoft) }
    .onAppear { focused = true }
    .task(id: store.peopleQuery) {
      // The web waits 300 ms after the last key before asking.
      do {
        try await Task.sleep(for: .milliseconds(300))
      } catch {
        // A newer keystroke cancelled this wait; its own task asks instead.
        return
      }
      await store.searchPeople(store.peopleQuery)
    }
  }
}
