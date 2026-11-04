import DailyCore
import DailyDesign

/// Builds the palette's standard entries with the labels of `components/shell/CommandPalette.tsx`.
public enum ShellCommands {
  public static func standard(
    sidebar: SidebarModel,
    navigate: @escaping (AppRoute) -> Void,
    setTheme: @escaping (ThemePreference) -> Void,
    setDensity: @escaping (Density) -> Void,
    setBackdrop: @escaping (Backdrop) -> Void,
    profile: @escaping () -> Void,
    changePassword: @escaping () -> Void,
    changePhoto: @escaping () -> Void,
    appearance: @escaping () -> Void,
    signOut: @escaping () -> Void
  ) -> [PaletteCommand] {
    // The web's "Ir para" lists its pages; here the sidebar rows are the pages.
    let navigation = sidebar.orderedEntries.map { entry in
      PaletteCommand(
        id: "navigate.\(routeKey(entry.route))",
        group: "Ir para",
        title: entry.title,
        systemImage: entry.systemImage
      ) { navigate(entry.route) }
    }
    let themes = ThemePreference.allCases.map { value in
      PaletteCommand(id: "theme.\(value.rawValue)", group: "Tema", title: themeLabel(value)) { setTheme(value) }
    }
    let densities = Density.allCases.map { value in
      PaletteCommand(id: "density.\(value.rawValue)", group: "Densidade", title: densityLabel(value)) {
        setDensity(value)
      }
    }
    let backdrops = Backdrop.allCases.map { value in
      PaletteCommand(id: "backdrop.\(value.rawValue)", group: "Fundo", title: backdropLabel(value)) {
        setBackdrop(value)
      }
    }
    let account = [
      PaletteCommand(id: "account.profile", group: "Conta", title: "Perfil", systemImage: "person", action: profile),
      PaletteCommand(
        id: "account.password", group: "Conta", title: "Trocar senha", systemImage: "key", action: changePassword),
      PaletteCommand(
        id: "account.photo", group: "Conta", title: "Alterar foto de perfil", systemImage: "person.crop.circle",
        action: changePhoto),
      PaletteCommand(
        id: "account.appearance", group: "Conta", title: "Aparência", systemImage: "gearshape",
        keywords: ["tema", "densidade", "fundo"], action: appearance),
      PaletteCommand(
        id: "account.signOut", group: "Conta", title: "Sair", systemImage: "rectangle.portrait.and.arrow.right",
        action: signOut),
    ]
    return navigation + themes + densities + backdrops + account
  }

  static func themeLabel(_ value: ThemePreference) -> String {
    switch value {
    case .system: "Tema do sistema"
    case .light: "Tema claro"
    case .dark: "Tema escuro"
    }
  }

  static func densityLabel(_ value: Density) -> String {
    switch value {
    case .comfortable: "Densidade confortável"
    case .compact: "Densidade compacta"
    }
  }

  static func backdropLabel(_ value: Backdrop) -> String {
    switch value {
    case .mesh: "Fundo gradiente"
    case .catppuccin: "Fundo Catppuccin"
    case .dracula: "Fundo Dracula"
    case .wezterm: "Fundo WezTerm"
    }
  }

  private static func routeKey(_ route: AppRoute) -> String {
    switch route {
    case .today: "today"
    case .module(let id): "module.\(id.rawValue)"
    case .agents: "agents"
    case .access: "access"
    }
  }
}
