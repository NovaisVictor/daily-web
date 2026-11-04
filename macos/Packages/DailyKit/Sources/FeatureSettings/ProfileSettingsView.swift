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
      Form {
        Section("Perfil") {
          if let error = store.avatarError { PanelError(error) }
          photo(me)
          if let error = store.profileError { PanelError(error) }
          TextField("Nome completo", text: $store.fullName, prompt: Text("Seu nome completo"))
          TextField("E-mail", text: $store.email, prompt: Text("voce@exemplo.com"))
            .textContentType(.emailAddress)
          LabeledContent("Usuário", value: me.username)
          Button(store.isSavingProfile ? "Salvando…" : "Salvar") { Task { await store.saveProfile() } }
            .disabled(store.isSavingProfile)
        }
        Section("Senha") {
          if let error = store.passwordError {
            PanelError(error)
          } else if store.passwordSaved {
            Text("Senha alterada.")
              .foregroundStyle(theme.inkMid)
          }
          SecureField("Senha atual", text: $store.currentPassword)
          SecureField("Nova senha", text: $store.newPassword, prompt: Text("mín. 8 caracteres"))
          SecureField("Confirmar nova senha", text: $store.confirmPassword)
          Button(store.isChangingPassword ? "Trocando…" : "Trocar senha") {
            Task { await store.changePassword() }
          }
          .disabled(!store.canChangePassword)
        }
      }
      .formStyle(.grouped)
    } else if let error = store.loadError {
      VStack {
        PanelError(error)
        Spacer()
      }
      .padding(20)
    } else {
      LoadingState()
    }
  }

  private func photo(_ me: CurrentUser) -> some View {
    let displayName = (me.fullName?.isEmpty == false ? me.fullName : nil) ?? me.username
    return HStack(spacing: 16) {
      Avatar(name: displayName, imageData: AvatarEncoder.imageData(fromDataURL: me.avatarUrl), size: 80)
        .accessibilityLabel(displayName)
      Button(store.isUploadingAvatar ? "Enviando…" : "Colocar foto") { pickingPhoto = true }
        .disabled(store.isUploadingAvatar)
      if me.avatarUrl != nil {
        Button("Remover") { Task { await store.removeAvatar() } }
          .disabled(store.isUploadingAvatar)
      }
    }
  }
}

#Preview {
  ProfileSettingsView(store: ProfileStore(client: PreviewAPIClient(responses: [:]), user: PreviewFixtures.user))
}
