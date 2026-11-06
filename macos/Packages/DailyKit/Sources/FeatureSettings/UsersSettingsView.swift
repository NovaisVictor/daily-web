import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Who sees the user management: the server answers 403 to anyone else
/// (`components/UsersPanel.tsx:42-46`), so a non-admin is not even asked.
enum UsersAccess {
  static func canManage(_ user: CurrentUser?) -> Bool { user?.isAdmin == true }

  static func showsList(isAdmin: Bool, forbidden: Bool) -> Bool { isAdmin && !forbidden }
}

/// Accounts of this server, admin only (`components/UsersPanel.tsx`).
struct UsersSettingsView: View {
  @Environment(\.theme) private var theme
  @State private var store: UsersStore
  @State private var confirm: ConfirmRequest?
  private let isAdmin: Bool

  init(environment: AppEnvironment) {
    isAdmin = UsersAccess.canManage(environment.session.user)
    _store = State(initialValue: UsersStore(client: environment.client))
  }

  init(store: UsersStore, isAdmin: Bool) {
    _store = State(initialValue: store)
    self.isAdmin = isAdmin
  }

  var body: some View {
    Group {
      if UsersAccess.showsList(isAdmin: isAdmin, forbidden: store.forbidden) {
        SettingsSection("Usuários", count: store.users.isEmpty ? nil : String(store.users.count)) {
          list
        }
        .task { await store.load() }
      } else {
        SettingsSection("Usuários") {
          EmptyState("Só admins gerenciam usuários.")
        }
      }
    }
    .confirmDialog($confirm)
  }

  @ViewBuilder private var list: some View {
    if let error = store.error { PanelError(error) }
    createForm
    if store.isLoading {
      LoadingState()
    } else if store.users.isEmpty {
      EmptyState("Nenhum usuário.", description: "Crie o primeiro acesso acima.")
    } else {
      VStack(spacing: 0) {
        ForEach(Array(store.users.enumerated()), id: \.element.id) { index, user in
          ListRow(index: index, isLast: index == store.users.count - 1) {
            row(user)
          }
        }
      }
    }
  }

  private var createForm: some View {
    FlowLayout(spacing: 8) {
      TextField("novo usuário", text: $store.username, prompt: Text("usuário"))
        .singleLine($store.username)
        .frame(minWidth: 140)
      SecureField("senha do novo usuário", text: $store.password, prompt: Text("senha (mín. 8)"))
        .frame(minWidth: 140)
      Toggle("admin", isOn: $store.isAdmin)
        .toggleStyle(.checkbox)
        .typeRole(.data)
        .foregroundStyle(theme.inkMid)
      Button(store.isCreating ? "Criando…" : "Criar usuário") { Task { await store.create() } }
        .pillButtonStyle(.primary, size: .small)
        .disabled(!store.canCreate)
    }
    .textFieldStyle(.roundedBorder)
  }

  private func row(_ user: UserSummary) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(user.username)
            .typeRole(.data)
            .foregroundStyle(theme.ink)
            .lineLimit(1)
          Text(user.isAdmin ? "admin" : "usuário")
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
        }
        Spacer()
        IconButton(
          "Trocar senha", systemImage: "key", variant: .outline, isActive: store.resetFor == user.username
        ) { store.toggleReset(user.username) }
        .accessibilityValue(store.resetFor == user.username ? "aberto" : "fechado")
        IconButton("remover \(user.username)", systemImage: "trash", size: .small) {
          confirm = ConfirmRequest(
            title: "Remover o usuário?",
            message: "\(user.username) perde o acesso imediatamente.",
            confirmLabel: "Remover",
            destructive: true,
            onConfirm: { Task { await store.remove(user) } }
          )
        }
      }
      if store.resetFor == user.username {
        HStack(spacing: 8) {
          SecureField("nova senha de \(user.username)", text: $store.resetPassword, prompt: Text("nova senha (mín. 8)"))
            .textFieldStyle(.roundedBorder)
          Button("Salvar") { Task { await store.changePassword(user.username) } }
            .pillButtonStyle(.outline, size: .small)
            .disabled(store.resetPassword.isEmpty)
        }
        .padding(.leading, 24)
      }
    }
  }
}

private let previewUsers = """
  {"users":[{"id":"1","username":"ana","isAdmin":true,"createdAt":"2026-10-01T10:00:00.000Z"},
  {"id":"2","username":"bruno","isAdmin":false,"createdAt":"2026-10-02T10:00:00.000Z"}]}
  """

#Preview {
  UsersSettingsView(
    store: UsersStore(client: PreviewAPIClient(responses: ["GET /api/users": Data(previewUsers.utf8)])),
    isAdmin: true
  )
  .padding(24)
}
