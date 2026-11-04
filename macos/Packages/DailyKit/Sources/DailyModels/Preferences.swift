/// The theme choice (`lib/theme.ts:1`). Named apart from `DailyDesign`'s
/// `ThemePreference` so a feature importing both is not ambiguous.
public struct AppearanceTheme: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let system = AppearanceTheme(rawValue: "system")
  public static let light = AppearanceTheme(rawValue: "light")
  public static let dark = AppearanceTheme(rawValue: "dark")
  public static let known: [AppearanceTheme] = [.system, .light, .dark]
}

/// `lib/theme.ts:2`.
public struct AppearanceDensity: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let comfortable = AppearanceDensity(rawValue: "comfortable")
  public static let compact = AppearanceDensity(rawValue: "compact")
  public static let known: [AppearanceDensity] = [.comfortable, .compact]
}

/// `lib/theme.ts:4`.
public struct AppearanceBackdrop: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let mesh = AppearanceBackdrop(rawValue: "mesh")
  public static let catppuccin = AppearanceBackdrop(rawValue: "catppuccin")
  public static let dracula = AppearanceBackdrop(rawValue: "dracula")
  public static let wezterm = AppearanceBackdrop(rawValue: "wezterm")
  public static let known: [AppearanceBackdrop] = [.mesh, .catppuccin, .dracula, .wezterm]
}

/// The content width (`lib/theme.ts:6`).
public struct AppearanceWidth: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let full = AppearanceWidth(rawValue: "full")
  public static let limited = AppearanceWidth(rawValue: "limited")
  public static let known: [AppearanceWidth] = [.full, .limited]
}

/// What the user saved in the appearance settings (`AppearancePatch`,
/// `lib/theme.ts:56-64`): a value never chosen is absent
/// (`lib/preferences.ts:225-240`).
public struct Appearance: Codable, Sendable, Equatable, Hashable {
  public var theme: AppearanceTheme?
  public var density: AppearanceDensity?
  public var backdrop: AppearanceBackdrop?
  public var width: AppearanceWidth?

  public init(
    theme: AppearanceTheme? = nil,
    density: AppearanceDensity? = nil,
    backdrop: AppearanceBackdrop? = nil,
    width: AppearanceWidth? = nil
  ) {
    self.theme = theme
    self.density = density
    self.backdrop = backdrop
    self.width = width
  }
}

/// `PATCH /api/preferences` with `appearance` (`app/api/preferences/route.ts:137`).
public struct AppearanceResponse: Codable, Sendable, Equatable, Hashable {
  public var appearance: Appearance

  public init(appearance: Appearance) {
    self.appearance = appearance
  }
}

/// `PATCH /api/preferences` with `tasksView` (`app/api/preferences/route.ts:118`).
public struct TasksViewResponse: Codable, Sendable, Equatable, Hashable {
  public var tasksView: TasksView

  public init(tasksView: TasksView) {
    self.tasksView = tasksView
  }
}

/// `PATCH /api/preferences` with `homeView` (`app/api/preferences/route.ts:129`).
public struct HomeViewResponse: Codable, Sendable, Equatable, Hashable {
  public var homeView: HomeView

  public init(homeView: HomeView) {
    self.homeView = homeView
  }
}

/// `PATCH /api/preferences` with `layout` (`app/api/preferences/route.ts:97`).
public struct LayoutResponse: Codable, Sendable, Equatable, Hashable {
  public var layout: [LayoutItem]
  public var layouts: [SavedLayout]

  public init(layout: [LayoutItem], layouts: [SavedLayout]) {
    self.layout = layout
    self.layouts = layouts
  }
}
