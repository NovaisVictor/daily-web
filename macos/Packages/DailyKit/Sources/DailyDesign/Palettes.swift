import SwiftUI

// Every literal below is copied from app/globals.css; the comment names the CSS
// custom property and the line it is declared on. Dark values cite the explicit
// `:root.dark` leg (from line 285), which the file keeps byte-identical to the
// `prefers-color-scheme` leg (from line 195).

/// The post-it paper names the server stores for a note (`.postit[data-paper]`).
public enum PostitPaper: String, Sendable, CaseIterable {
  case yellow, pink, blue, green, white, grey
}

extension Theme {
  /// `--radius` (globals.css:132), 0.75rem.
  static let baseRadius: CGFloat = 12

  /// Light theme, `:root` (globals.css:25). Also the light Catppuccin, Dracula and
  /// WezTerm pages: those backdrops change only the page background in light
  /// (Catppuccin) or nothing at all (Dracula, WezTerm), see `BackdropPalette`.
  static let lightDefault: Theme = {
    let ink = Color(oklch: 0.145, 0.01, 285)  // --ink :59
    let inkDim = Color(oklch: 0.145, 0.01, 285, alpha: 0.52)  // --ink-dim :61
    return Theme(
      surface0: Color(oklch: 0.976, 0.003, 250),  // --surface-0 :36
      surface1: Color(oklch: 0.992, 0.002, 250),  // --surface-1 :37
      surface2: Color(oklch: 1, 0, 0),  // --surface-2 :38
      surface3: Color(oklch: 1, 0, 0),  // --surface-3 :39
      ink: ink,
      inkMid: Color(oklch: 0.145, 0.01, 285, alpha: 0.72),  // --ink-mid :60
      inkDim: inkDim,
      line: Color(oklch: 0.885, 0.006, 250),  // --line :63
      lineSoft: Color(oklch: 0.935, 0.005, 250),  // --line-soft :64
      lineStrong: Color(oklch: 0.78, 0.009, 250),  // --line-strong :65
      brand: Color(oklch: 0.5, 0.128, 155),  // --brand :69
      brandInk: Color(oklch: 0.985, 0, 0),  // --brand-ink :70
      brandTint: Color(oklch: 0.5, 0.128, 155, alpha: 0.10),  // --brand-tint :71 (brand / 10%)
      success: Color(oklch: 0.48, 0.125, 152),  // --signal-success :76
      warning: Color(oklch: 0.5, 0.105, 88),  // --signal-warning :77
      danger: Color(oklch: 0.52, 0.19, 26),  // --signal-danger :78
      info: Color(oklch: 0.5, 0.13, 248),  // --signal-info :79
      neutral: inkDim,  // --signal-neutral :80 (var(--ink-dim))
      successTint: Color(oklch: 0.48, 0.125, 152, alpha: 0.11),  // --signal-success-tint :81
      warningTint: Color(oklch: 0.5, 0.105, 88, alpha: 0.13),  // --signal-warning-tint :82
      dangerTint: Color(oklch: 0.52, 0.19, 26, alpha: 0.10),  // --signal-danger-tint :83
      infoTint: Color(oklch: 0.5, 0.13, 248, alpha: 0.10),  // --signal-info-tint :84
      neutralTint: Color(oklch: 0.53, 0.013, 250, alpha: 0.10),  // --signal-neutral-tint :85
      postit: [
        PostitPaper.yellow.rawValue: Color(oklch: 0.95, 0.11, 98),  // --postit-yellow :112
        PostitPaper.pink.rawValue: Color(oklch: 0.925, 0.055, 355),  // --postit-pink :113
        PostitPaper.blue.rawValue: Color(oklch: 0.93, 0.045, 235),  // --postit-blue :114
        PostitPaper.green.rawValue: Color(oklch: 0.935, 0.065, 150),  // --postit-green :115
        PostitPaper.white.rawValue: Color(oklch: 0.985, 0.004, 95),  // --postit-white :116
        PostitPaper.grey.rawValue: Color(oklch: 0.9, 0.008, 260),  // --postit-grey :117
      ],
      postitInk: Color(oklch: 0.27, 0.03, 70),  // --postit-ink :118
      radius: baseRadius,
      density: .comfortable
    )
  }()

  /// Dark theme, `:root.dark` (globals.css:285).
  static let darkDefault: Theme = {
    let inkDim = Color(oklch: 1, 0, 0, alpha: 0.52)  // --ink-dim :320
    return Theme(
      surface0: Color(oklch: 0.134, 0.005, 285),  // --surface-0 :286
      surface1: Color(oklch: 0.112, 0.004, 285),  // --surface-1 :287 (darker than 0 on purpose)
      surface2: Color(oklch: 0.185, 0.007, 285),  // --surface-2 :288
      surface3: Color(oklch: 0.205, 0.008, 285),  // --surface-3 :289
      ink: Color(oklch: 1, 0, 0),  // --ink :318
      inkMid: Color(oklch: 1, 0, 0, alpha: 0.72),  // --ink-mid :319
      inkDim: inkDim,
      line: Color(oklch: 0.305, 0.01, 285),  // --line :322
      lineSoft: Color(oklch: 0.205, 0.006, 285),  // --line-soft :323
      lineStrong: Color(oklch: 0.4, 0.013, 285),  // --line-strong :324
      brand: Color(oklch: 0.72, 0.155, 158),  // --brand :326
      brandInk: Color(oklch: 0.17, 0.02, 158),  // --brand-ink :327
      brandTint: Color(oklch: 0.72, 0.155, 158, alpha: 0.14),  // --brand-tint :328
      success: Color(oklch: 0.75, 0.15, 155),  // --signal-success :331
      warning: Color(oklch: 0.8, 0.13, 90),  // --signal-warning :332
      danger: Color(oklch: 0.7, 0.17, 24),  // --signal-danger :333
      info: Color(oklch: 0.73, 0.11, 245),  // --signal-info :334
      neutral: inkDim,  // --signal-neutral :80 (var(--ink-dim), dark value)
      successTint: Color(oklch: 0.75, 0.15, 155, alpha: 0.16),  // --signal-success-tint :335
      warningTint: Color(oklch: 0.8, 0.13, 90, alpha: 0.16),  // --signal-warning-tint :336
      dangerTint: Color(oklch: 0.7, 0.17, 24, alpha: 0.16),  // --signal-danger-tint :337
      infoTint: Color(oklch: 0.73, 0.11, 245, alpha: 0.16),  // --signal-info-tint :338
      neutralTint: Color(oklch: 0.655, 0.015, 250, alpha: 0.16),  // --signal-neutral-tint :339
      postit: [
        PostitPaper.yellow.rawValue: Color(oklch: 0.82, 0.1, 95),  // --postit-yellow :355
        PostitPaper.pink.rawValue: Color(oklch: 0.8, 0.065, 355),  // --postit-pink :356
        PostitPaper.blue.rawValue: Color(oklch: 0.8, 0.055, 235),  // --postit-blue :357
        PostitPaper.green.rawValue: Color(oklch: 0.81, 0.075, 150),  // --postit-green :358
        PostitPaper.white.rawValue: Color(oklch: 0.86, 0.004, 95),  // --postit-white :359
        PostitPaper.grey.rawValue: Color(oklch: 0.76, 0.008, 260),  // --postit-grey :362
      ],
      postitInk: Color(oklch: 0.2, 0.02, 70),  // --postit-ink :363
      radius: baseRadius,
      density: .comfortable
    )
  }()

  /// Catppuccin Mocha primitives, `:root[data-backdrop='catppuccin']` (globals.css:387).
  enum Mocha {
    static let crust = Color(oklch: 0.183, 0.02, 284.204)  // --ctp-crust :388 #11111b
    static let mantle = Color(oklch: 0.216, 0.025, 284.065)  // --ctp-mantle :389 #181825
    static let base = Color(oklch: 0.243, 0.03, 283.911)  // --ctp-base :390 #1e1e2e
    static let surface0 = Color(oklch: 0.324, 0.032, 281.978)  // --ctp-surface0 :391 #313244
    static let surface1 = Color(oklch: 0.404, 0.032, 280.152)  // --ctp-surface1 :392 #45475a
    static let overlay0 = Color(oklch: 0.55, 0.034, 277.095)  // --ctp-overlay0 :394 #6c7086
    static let subtext0 = Color(oklch: 0.751, 0.04, 273.932)  // --ctp-subtext0 :395 #a6adc8
    static let subtext1 = Color(oklch: 0.817, 0.04, 272.862)  // --ctp-subtext1 :396 #bac2de
    static let text = Color(oklch: 0.879, 0.043, 272.277)  // --ctp-text :397 #cdd6f4
    static let mauve = Color(oklch: 0.787, 0.119, 304.769)  // --ctp-mauve :398 #cba6f7
    static let pink = Color(oklch: 0.87, 0.075, 336.304)  // --ctp-pink :399 #f5c2e7
    static let red = Color(oklch: 0.756, 0.13, 2.764)  // --ctp-red :400 #f38ba8
    static let yellow = Color(oklch: 0.919, 0.07, 86.528)  // --ctp-yellow :401 #f9e2af
    static let green = Color(oklch: 0.858, 0.109, 142.715)  // --ctp-green :402 #a6e3a1
    static let blue = Color(oklch: 0.766, 0.111, 259.885)  // --ctp-blue :404 #89b4fa
  }

  /// Dark + Catppuccin, `:root.dark[data-backdrop='catppuccin']` (globals.css:464).
  static let catppuccinMocha = Theme(
    surface0: Mocha.base,  // --surface-0 :465
    surface1: Mocha.mantle,  // --surface-1 :466
    surface2: Mocha.surface0,  // --surface-2 :467
    surface3: Mocha.surface1,  // --surface-3 :468
    ink: Mocha.text,  // --ink :473
    inkMid: Mocha.subtext1,  // --ink-mid :474
    inkDim: Mocha.subtext0,  // --ink-dim :475
    line: Mocha.surface1,  // --line :477
    lineSoft: Mocha.surface0,  // --line-soft :478
    lineStrong: Mocha.overlay0,  // --line-strong :479
    brand: Mocha.mauve,  // --brand :482
    brandInk: Mocha.crust,  // --brand-ink :483
    brandTint: Color(oklch: 0.787, 0.119, 304.769, alpha: 0.14),  // --brand-tint :484
    success: Mocha.green,  // --signal-success :487
    warning: Mocha.yellow,  // --signal-warning :488
    danger: Mocha.red,  // --signal-danger :489
    info: Mocha.blue,  // --signal-info :490
    neutral: Mocha.subtext0,  // --signal-neutral :80 (var(--ink-dim))
    successTint: Color(oklch: 0.858, 0.109, 142.715, alpha: 0.16),  // --signal-success-tint :491
    warningTint: Color(oklch: 0.919, 0.07, 86.528, alpha: 0.16),  // --signal-warning-tint :492
    dangerTint: Color(oklch: 0.756, 0.13, 2.764, alpha: 0.16),  // --signal-danger-tint :493
    infoTint: Color(oklch: 0.766, 0.111, 259.885, alpha: 0.16),  // --signal-info-tint :494
    neutralTint: Color(oklch: 0.687, 0.037, 274.725, alpha: 0.16),  // --signal-neutral-tint :495
    postit: [
      PostitPaper.yellow.rawValue: Mocha.yellow,  // --postit-yellow :509
      PostitPaper.pink.rawValue: Mocha.pink,  // --postit-pink :510
      PostitPaper.blue.rawValue: Mocha.blue,  // --postit-blue :511
      PostitPaper.green.rawValue: Mocha.green,  // --postit-green :512
      PostitPaper.white.rawValue: Mocha.text,  // --postit-white :513
      PostitPaper.grey.rawValue: Mocha.subtext0,  // --postit-grey :514
    ],
    postitInk: Mocha.crust,  // --postit-ink :515
    radius: baseRadius,
    density: .comfortable
  )

  /// Dracula ("Dark Dracula" cut) primitives, `:root[data-backdrop='dracula']` (globals.css:530).
  enum Dracula {
    static let darkest = Color(oklch: 0.2, 0, 0)  // --drc-darkest :531 #161616
    static let darker = Color(oklch: 0.218, 0, 0)  // --drc-darker :532 #1a1a1a
    static let background = Color(oklch: 0.244, 0, 0)  // --drc-background :533 #202020
    static let surface = Color(oklch: 0.285, 0, 0)  // --drc-surface :534 #2a2a2a
    static let currentLine = Color(oklch: 0.329, 0, 0)  // --drc-current-line :535 #353535
    static let comment = Color(oklch: 0.56, 0.08, 270.086)  // --drc-comment :537 #6272a4
    static let foregroundDim = Color(oklch: 0.752, 0.051, 273.789)  // --drc-foreground-dim :538 #a4add0
    static let foregroundMid = Color(oklch: 0.851, 0.018, 106.769)  // --drc-foreground-mid :539 #cfcfc2
    static let foreground = Color(oklch: 0.977, 0.008, 106.545)  // --drc-foreground :540 #f8f8f2
    static let purple = Color(oklch: 0.742, 0.149, 301.883)  // --drc-purple :541 #bd93f9
    static let red = Color(oklch: 0.682, 0.206, 24.431)  // --drc-red :543 #ff5555
    static let orange = Color(oklch: 0.834, 0.124, 66.558)  // --drc-orange :544 #ffb86c
    static let green = Color(oklch: 0.871, 0.22, 148.025)  // --drc-green :546 #50fa7b
    static let cyan = Color(oklch: 0.883, 0.093, 212.846)  // --drc-cyan :547 #8be9fd
  }

  /// Dark + Dracula, `:root.dark[data-backdrop='dracula']` (globals.css:603). The
  /// web does not override the post-its here, so they stay the dark default.
  static let draculaDark = Theme(
    surface0: Dracula.background,  // --surface-0 :604
    surface1: Dracula.darker,  // --surface-1 :605
    surface2: Dracula.surface,  // --surface-2 :606
    surface3: Dracula.currentLine,  // --surface-3 :607
    ink: Dracula.foreground,  // --ink :617
    inkMid: Dracula.foregroundMid,  // --ink-mid :618
    inkDim: Dracula.foregroundDim,  // --ink-dim :619
    line: Dracula.currentLine,  // --line :621
    lineSoft: Dracula.surface,  // --line-soft :622
    lineStrong: Dracula.comment,  // --line-strong :623
    brand: Dracula.purple,  // --brand :626
    brandInk: Dracula.darkest,  // --brand-ink :627
    brandTint: Color(oklch: 0.742, 0.149, 301.883, alpha: 0.14),  // --brand-tint :628
    success: Dracula.green,  // --signal-success :631
    warning: Dracula.orange,  // --signal-warning :632
    danger: Dracula.red,  // --signal-danger :633
    info: Dracula.cyan,  // --signal-info :634
    neutral: Dracula.foregroundDim,  // --signal-neutral :80 (var(--ink-dim))
    successTint: Color(oklch: 0.871, 0.22, 148.025, alpha: 0.16),  // --signal-success-tint :635
    warningTint: Color(oklch: 0.834, 0.124, 66.558, alpha: 0.16),  // --signal-warning-tint :636
    dangerTint: Color(oklch: 0.682, 0.206, 24.431, alpha: 0.16),  // --signal-danger-tint :637
    infoTint: Color(oklch: 0.883, 0.093, 212.846, alpha: 0.16),  // --signal-info-tint :638
    neutralTint: Color(oklch: 0.56, 0.08, 270.086, alpha: 0.16),  // --signal-neutral-tint :639
    postit: darkDefault.postit,
    postitInk: darkDefault.postitInk,
    radius: baseRadius,
    density: .comfortable
  )

  /// Dark + WezTerm, `:root.dark[data-backdrop='wezterm']` (globals.css:684). Only
  /// the page floor and the recessed plane change; everything else is the dark theme.
  static let weztermDark: Theme = {
    var theme = darkDefault
    theme.surface0 = Color(oklch: 0.158, 0.047, 302.755)  // --surface-0 :685 (--wzt-background :662, #11071d)
    theme.surface1 = Color(oklch: 0.13, 0.038, 302.755)  // --surface-1 :686 (--wzt-recessed :663)
    return theme
  }()

  /// The palette for a scheme and backdrop, before density is applied.
  static func palette(scheme: ColorScheme, backdrop: Backdrop) -> Theme {
    switch scheme {
    case .dark:
      switch backdrop {
      case .mesh: darkDefault
      case .catppuccin: catppuccinMocha
      case .dracula: draculaDark
      case .wezterm: weztermDark
      }
    case .light:
      // Catppuccin swaps only the page base in light; Dracula and WezTerm are
      // dark-only palettes and leave a light page untouched (globals.css:527, :659).
      lightDefault
    @unknown default:
      lightDefault
    }
  }
}
