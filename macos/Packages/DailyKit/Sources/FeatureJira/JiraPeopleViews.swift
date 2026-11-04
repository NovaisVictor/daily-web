import DailyDesign
import DailyModels
import SwiftUI

/// Whose Jira is on screen, as the screen title itself (`components/jira/PersonSwitcher.tsx`).
struct PersonSwitcher: View {
  @Environment(\.theme) private var theme
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
      Text("Jira · \(active?.displayName ?? "Eu")")
        .typeRole(.subhead)
        .foregroundStyle(theme.ink)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
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
          .textFieldStyle(.roundedBorder)
          .focused($focused)
          .accessibilityLabel("buscar pessoa no Jira")
          .onKeyPress(.escape) {
            store.closePeopleSearch()
            return .handled
          }
        Button {
          store.closePeopleSearch()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("fechar busca de pessoa")
        .accessibilityLabel("fechar busca de pessoa")
      }
      if let error = store.peopleError { PanelError(error) }
      if store.peopleSearching {
        Text("Buscando…").font(.system(size: 13)).foregroundStyle(theme.inkDim)
      } else if !store.peopleCandidates.isEmpty {
        FlowLayout(spacing: 8) {
          ForEach(store.peopleCandidates) { person in
            Button(person.displayName) { Task { await store.follow(person.accountId) } }
              .controlSize(.small)
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
