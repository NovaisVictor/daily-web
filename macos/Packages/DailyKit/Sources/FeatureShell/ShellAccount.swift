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

/// The appearance the avatar menu shows as checked (`AccountMenu.tsx:138-170`).
public struct ShellAppearance: Equatable, Sendable {
  public let theme: ThemePreference
  public let density: Density
  public let backdrop: Backdrop

  public init(theme: ThemePreference, density: Density, backdrop: Backdrop) {
    self.theme = theme
    self.density = density
    self.backdrop = backdrop
  }
}

/// The account menu's actions (spec 012 FR-012-06).
public struct ShellAccountActions {
  public let profile: () -> Void
  public let connectAgent: () -> Void
  /// "Agentes e atividades", the agents workspace that lost its sidebar row (FR-012-02).
  public let agentsWorkspace: () -> Void
  public let settings: () -> Void
  // Main-actor closures, so the menu's radio bindings can call them.
  public let setTheme: @MainActor (ThemePreference) -> Void
  public let setDensity: @MainActor (Density) -> Void
  public let setBackdrop: @MainActor (Backdrop) -> Void
  /// Awaited so the item can read "Saindo…" until it finishes, as on the web.
  public let signOut: () async -> Void

  public init(
    profile: @escaping () -> Void,
    connectAgent: @escaping () -> Void,
    agentsWorkspace: @escaping () -> Void,
    settings: @escaping () -> Void,
    setTheme: @escaping @MainActor (ThemePreference) -> Void,
    setDensity: @escaping @MainActor (Density) -> Void,
    setBackdrop: @escaping @MainActor (Backdrop) -> Void,
    signOut: @escaping () async -> Void
  ) {
    self.profile = profile
    self.connectAgent = connectAgent
    self.agentsWorkspace = agentsWorkspace
    self.settings = settings
    self.setTheme = setTheme
    self.setDensity = setDensity
    self.setBackdrop = setBackdrop
    self.signOut = signOut
  }
}

/// The radio items' labels, copied from `components/shell/AccountMenu.tsx:30-47`.
enum AccountMenuLabels {
  static func theme(_ value: ThemePreference) -> String {
    switch value {
    case .system: "Sistema"
    case .light: "Claro"
    case .dark: "Escuro"
    }
  }

  static func density(_ value: Density) -> String {
    switch value {
    case .comfortable: "Confortável"
    case .compact: "Compacto"
    }
  }

  /// Dracula and WezTerm only remap the dark theme; the hint keeps a light-theme pick
  /// from looking broken.
  static func backdrop(_ value: Backdrop) -> String {
    switch value {
    case .mesh: "Gradiente"
    case .catppuccin: "Catppuccin"
    case .dracula: "Dracula (só no tema escuro)"
    case .wezterm: "WezTerm (só no tema escuro)"
    }
  }
}

struct AccountMenu: View {
  let account: ShellAccount
  let appearance: ShellAppearance
  let actions: ShellAccountActions

  @State private var isLeaving = false

  var body: some View {
    Menu {
      Section(account.displayName) {
        Button("Perfil", systemImage: "person", action: actions.profile)
        Button("Conectar agente", systemImage: "cpu", action: actions.connectAgent)
        Button("Agentes e atividades", systemImage: "rectangle.3.group", action: actions.agentsWorkspace)
        Button("Configurações", systemImage: "gearshape", action: actions.settings)
      }
      Section("Tema") {
        radioGroup("Tema", ThemePreference.allCases, appearance.theme, AccountMenuLabels.theme, actions.setTheme)
      }
      Section("Densidade") {
        radioGroup("Densidade", Density.allCases, appearance.density, AccountMenuLabels.density, actions.setDensity)
      }
      Section("Fundo") {
        radioGroup("Fundo", Backdrop.allCases, appearance.backdrop, AccountMenuLabels.backdrop, actions.setBackdrop)
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
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .iconButtonStyle()
    .help(account.displayName)
    .accessibilityLabel(account.displayName)
  }

  /// An inline picker renders as checkable items, the web's `DropdownMenuRadioGroup`.
  private func radioGroup<Value: Hashable & Sendable>(
    _ title: String,
    _ values: [Value],
    _ current: Value,
    _ label: @escaping (Value) -> String,
    _ choose: @escaping @MainActor (Value) -> Void
  ) -> some View {
    Picker(title, selection: Binding(get: { current }, set: choose)) {
      ForEach(values, id: \.self) { value in
        Text(label(value)).tag(value)
      }
    }
    .pickerStyle(.inline)
    .labelsHidden()
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
          .font(.daily(.caption))
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
  AccountMenu(account: PreviewData.account, appearance: PreviewData.appearance, actions: PreviewData.accountActions)
    .padding()
}
