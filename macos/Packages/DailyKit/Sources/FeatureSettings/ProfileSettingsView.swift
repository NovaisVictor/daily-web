import DailyCore
import DailyDesign
import DailyModels
import SwiftUI
import UniformTypeIdentifiers
import os

/// Name, e-mail, photo and password (`components/ProfilePanel.tsx`).
struct ProfileSettingsView: View {
  @Environment(\.theme) private var theme
  @State private var store: ProfileStore
  @State private var pickingPhoto = false

  init(environment: AppEnvironment) {
    let session = environment.session
    _store = State(
      initialValue: ProfileStore(client: environment.client, user: session.user) { session.updateUser($0) })
  }

  init(store: ProfileStore) {
    _store = State(initialValue: store)
  }

  var body: some View {
    content
      .task { await store.load() }
      .fileImporter(isPresented: $pickingPhoto, allowedContentTypes: AvatarEncoder.allowedTypes) { result in
        switch result {
        case .success(let url):
          Task { await store.uploadAvatar(from: url) }
        case .failure(let error):
          Logger.settings.error("Photo picker failed: \(String(describing: error), privacy: .public)")
        }
      }
  }

  @ViewBuilder private var content: some View {
    if let me = store.me {
      VStack(alignment: .leading, spacing: 16) {
        SettingsSection("Perfil") {
          if let error = store.avatarError { PanelError(error) }
          photo(me)
          if let error = store.profileError { PanelError(error) }
          field("Nome completo") {
            TextField("Nome completo", text: $store.fullName, prompt: Text("Seu nome completo"))
              .singleLine($store.fullName)
          }
          field("E-mail") {
            TextField("E-mail", text: $store.email, prompt: Text("voce@exemplo.com"))
              .singleLine($store.email)
              .textContentType(.emailAddress)
          }
          field("Usuário") {
            Text(me.username)
              .typeRole(.data)
              .foregroundStyle(theme.inkMid)
              .textSelection(.enabled)
          }
          Button(store.isSavingProfile ? "Salvando…" : "Salvar") { Task { await store.saveProfile() } }
            .pillButtonStyle(.primary, size: .small)
            .disabled(store.isSavingProfile)
        }
        SettingsSection("Senha") {
          if let error = store.passwordError {
            PanelError(error)
          } else if store.passwordSaved {
            Text("Senha alterada.")
              .typeRole(.data)
              .foregroundStyle(theme.inkMid)
          }
          field("Senha atual") {
            SecureField("Senha atual", text: $store.currentPassword)
          }
          field("Nova senha") {
            SecureField("Nova senha", text: $store.newPassword, prompt: Text("mín. 8 caracteres"))
          }
          field("Confirmar nova senha") {
            SecureField("Confirmar nova senha", text: $store.confirmPassword)
          }
          Button(store.isChangingPassword ? "Trocando…" : "Trocar senha") {
            Task { await store.changePassword() }
          }
          .pillButtonStyle(.outline, size: .small)
          .disabled(!store.canChangePassword)
        }
      }
      .textFieldStyle(.roundedBorder)
    } else if let error = store.loadError {
      PanelError(error)
    } else {
      LoadingState()
    }
  }

  /// A visible label over its input; the input keeps the same name for VoiceOver.
  private func field<Input: View>(_ label: String, @ViewBuilder input: () -> Input) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .typeRole(.caption)
        .foregroundStyle(theme.inkMid)
        .accessibilityHidden(true)
      input()
        .labelsHidden()
        .accessibilityLabel(label)
    }
  }

  private func photo(_ me: CurrentUser) -> some View {
    let displayName = (me.fullName?.isEmpty == false ? me.fullName : nil) ?? me.username
    return HStack(spacing: 16) {
      Avatar(name: displayName, imageData: AvatarEncoder.imageData(fromDataURL: me.avatarUrl), size: 80)
        .accessibilityLabel(displayName)
      Button(store.isUploadingAvatar ? "Enviando…" : "Colocar foto") { pickingPhoto = true }
        .pillButtonStyle(.outline, size: .small)
        .disabled(store.isUploadingAvatar)
      if me.avatarUrl != nil {
        Button("Remover") { Task { await store.removeAvatar() } }
          .pillButtonStyle(.ghost, size: .small)
          .disabled(store.isUploadingAvatar)
      }
    }
  }
}

#Preview {
  ProfileSettingsView(store: ProfileStore(client: PreviewAPIClient(responses: [:]), user: PreviewFixtures.user))
    .padding(24)
}
