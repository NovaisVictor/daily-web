import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Accounts of this server, admin only (`components/UsersPanel.tsx`).
struct UsersSettingsView: View {
  @Environment(\.theme) private var theme
  @State private var store: UsersStore
  @State private var confirm: ConfirmRequest?
  private let isAdmin: Bool

  init(environment: AppEnvironment) {
    isAdmin = environment.session.user?.isAdmin == true
    _store = State(initialValue: UsersStore(client: environment.client))
  }

  init(store: UsersStore, isAdmin: Bool) {
    _store = State(initialValue: store)
    self.isAdmin = isAdmin
  }

  var body: some View {
    Group {
      if !isAdmin || store.forbidden {
        EmptyState("Só admins gerenciam usuários.")
          .padding(20)
      } else {
        list
          .task { await store.load() }
      }
    }
    .confirmDialog($confirm)
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader("Usuários", count: store.users.isEmpty ? nil : String(store.users.count))
        if let error = store.error { PanelError(error) }
        createForm
        if store.isLoading {
          LoadingState()
        } else if store.users.isEmpty {
          EmptyState("Nenhum usuário.", description: "Crie o primeiro acesso acima.")
        } else {
          VStack(spacing: 0) {
            ForEach(store.users) { user in
              row(user)
              if user.id != store.users.last?.id { Divider().overlay(theme.lineSoft) }
            }
          }
        }
      }
      .padding(20)
    }
  }

  private var createForm: some View {
    HStack(spacing: 8) {
      TextField("novo usuário", text: $store.username, prompt: Text("usuário"))
      SecureField("senha do novo usuário", text: $store.password, prompt: Text("senha (mín. 8)"))
      Toggle("admin", isOn: $store.isAdmin)
        .toggleStyle(.checkbox)
      Button(store.isCreating ? "Criando…" : "Criar usuário") { Task { await store.create() } }
        .disabled(!store.canCreate)
    }
    .textFieldStyle(.roundedBorder)
  }

  private func row(_ user: UserSummary) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(user.username)
            .font(.system(size: 14))
            .foregroundStyle(theme.ink)
          Text(user.isAdmin ? "admin" : "usuário")
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
        }
        Spacer()
        Button("Trocar senha", systemImage: "key") { store.toggleReset(user.username) }
          .labelStyle(.iconOnly)
          .help("Trocar senha")
          .accessibilityValue(store.resetFor == user.username ? "aberto" : "fechado")
        Button("remover \(user.username)", systemImage: "trash", role: .destructive) {
          confirm = ConfirmRequest(
            title: "Remover o usuário?",
            message: "\(user.username) perde o acesso imediatamente.",
            confirmLabel: "Remover",
            destructive: true,
            onConfirm: { Task { await store.remove(user) } }
          )
        }
        .labelStyle(.iconOnly)
        .help("Remover")
      }
      if store.resetFor == user.username {
        HStack(spacing: 8) {
          SecureField("nova senha de \(user.username)", text: $store.resetPassword, prompt: Text("nova senha (mín. 8)"))
            .textFieldStyle(.roundedBorder)
          Button("Salvar") { Task { await store.changePassword(user.username) } }
            .disabled(store.resetPassword.isEmpty)
        }
        .padding(.leading, 24)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
  }
}

private let previewUsers = """
  {"users":[{"id":"1","username":"ana","isAdmin":true,"createdAt":"2026-10-01T10:00:00.000Z"},
  {"id":"2","username":"bruno","isAdmin":false,"createdAt":"2026-10-02T10:00:00.000Z"}]}
  """

#Preview {
  UsersSettingsView(
    store: UsersStore(client: PreviewAPIClient(responses: ["GET /api/users": Data(previewUsers.utf8)])),
    isAdmin: true)
}
