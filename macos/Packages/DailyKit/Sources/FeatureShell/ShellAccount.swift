import AppKit
import DailyDesign
import SwiftUI

/// Who is signed in, as the toolbar shows it.
public struct ShellAccount: Equatable, Sendable {
  public let displayName: String
  public let username: String
  /// Image bytes as the server sent them; nil when the person has no photo.
  public let avatar: Data?

  public init(displayName: String, username: String, avatar: Data?) {
    self.displayName = displayName
    self.username = username
    self.avatar = avatar
  }

  /// The letter shown when there is no photo (`components/shell/Header.tsx`).
  var initial: String { String(displayName.prefix(1)).uppercased() }
}

/// The account menu's actions (`components/shell/Header.tsx`).
public struct ShellAccountActions {
  public let profile: () -> Void
  public let connectAgent: () -> Void
  public let settings: () -> Void
  /// Awaited so the item can read "Saindo…" until it finishes, as on the web.
  public let signOut: () async -> Void

  public init(
    profile: @escaping () -> Void,
    connectAgent: @escaping () -> Void,
    settings: @escaping () -> Void,
    signOut: @escaping () async -> Void
  ) {
    self.profile = profile
    self.connectAgent = connectAgent
    self.settings = settings
    self.signOut = signOut
  }
}

struct AccountMenu: View {
  let account: ShellAccount
  let actions: ShellAccountActions

  @State private var isLeaving = false

  var body: some View {
    Menu {
      Section(account.displayName) {
        Button("Perfil", systemImage: "person", action: actions.profile)
        Button("Conectar agente", systemImage: "cpu", action: actions.connectAgent)
        Button("Configurações", systemImage: "gearshape", action: actions.settings)
      }
      Divider()
      Button(isLeaving ? "Saindo…" : "Sair", systemImage: "rectangle.portrait.and.arrow.right") {
        isLeaving = true
        Task {
          await actions.signOut()
          isLeaving = false
        }
      }
      .disabled(isLeaving)
    } label: {
      AccountAvatar(account: account)
    }
    .menuIndicator(.hidden)
    .accessibilityLabel(account.displayName)
  }
}

struct AccountAvatar: View {
  let account: ShellAccount
  @Environment(\.theme) private var theme

  var body: some View {
    Group {
      // An undecodable photo shows the initial, like the web's AvatarFallback.
      if let data = account.avatar, let image = NSImage(data: data) {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Text(account.initial)
          .font(.caption.weight(.semibold))
          .foregroundStyle(theme.ink)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(theme.surface2)
      }
    }
    .frame(width: 24, height: 24)
    .clipShape(.circle)
    .accessibilityHidden(true)
  }
}

#Preview("Menu da conta") {
  AccountMenu(account: PreviewData.account, actions: PreviewData.accountActions)
    .padding()
}
