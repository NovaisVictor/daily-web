import SwiftUI

// MARK: - Type scale

/// The seven type roles of app/globals.css (`@utility type-*`, lines 851-903), with
/// 1rem = 16pt. Each role carries size, line height, weight and tracking together so
/// a call site never picks them one by one.
///
/// The web sets Geist; the native app uses the system face (SF Pro), a deliberate
/// divergence: Geist would have to be bundled, and SF is what a Mac reader expects.
public enum TypeRole: String, Sendable, CaseIterable {
  case display, title, heading, subhead, body, data, caption

  /// Font size in points.
  public var size: CGFloat {
    switch self {
    case .display: 44  // 2.75rem :853
    case .title: 34  // 2.125rem :861
    case .heading: 30  // 1.875rem :869
    case .subhead: 20  // 1.25rem :877
    case .body: 16  // 1rem :885
    case .data: 14  // 0.875rem :892
    case .caption: 13  // 0.8125rem :899
    }
  }

  /// CSS `line-height`, as a multiple of the size.
  public var lineHeight: CGFloat {
    switch self {
    case .display: 1.05
    case .title: 1.1
    case .heading: 1.2
    case .subhead: 1.3
    case .body: 1.5
    case .data: 1.45
    case .caption: 1.4
    }
  }

  public var weight: Font.Weight {
    switch self {
    case .display, .title, .heading, .subhead: .semibold  // 600
    case .body: .regular  // 400
    case .data, .caption: .medium  // 500
    }
  }

  /// CSS `letter-spacing` in em.
  public var trackingEm: CGFloat {
    switch self {
    case .display, .title, .heading: -0.04
    case .subhead: -0.02
    case .body, .data, .caption: 0
    }
  }

  /// Tracking in points for `View.tracking(_:)`.
  public var tracking: CGFloat { size * trackingEm }

  /// Extra leading to reach the CSS line height. SF's natural line is about 1.2× the
  /// size, so a role tighter than that gets none rather than a negative spacing.
  public var lineSpacing: CGFloat { max(0, size * (lineHeight - 1.2)) }

  public var font: Font {
    let font = Font.system(size: size, weight: weight)
    // `type-data` sets tabular-nums (:894); numbers use the body face, never mono.
    return self == .data ? font.monospacedDigit() : font
  }
}

extension Font {
  /// The font of a type role. Prefer `View.typeRole(_:)`, which also sets tracking and leading.
  public static func daily(_ role: TypeRole) -> Font { role.font }
}

extension View {
  /// Applies a whole type role: font, tracking and line spacing.
  public func typeRole(_ role: TypeRole) -> some View {
    font(role.font)
      .tracking(role.tracking)
      .lineSpacing(role.lineSpacing)
  }
}

// MARK: - Radius

/// The radius scale derived from `--radius` (globals.css:132 and :771-774).
/// Buttons, chips and status pills do not use it: they are capsules.
public enum Radius {
  /// `--radius-sm`, radius − 2px.
  public static let small: CGFloat = 10
  /// `--radius-md`, the base `--radius`.
  public static let medium: CGFloat = 12
  /// `--radius-lg`, radius + 2px.
  public static let large: CGFloat = 14
  /// `--radius-xl`, radius + 5px.
  public static let extraLarge: CGFloat = 17
}

// MARK: - Motion

/// `--dur-fast`, `--dur`, `--dur-slow` and `--ease` (globals.css:124-128).
public enum Motion {
  /// 110ms.
  public static let fast: TimeInterval = 0.110
  /// 160ms.
  public static let standard: TimeInterval = 0.160
  /// 240ms.
  public static let slow: TimeInterval = 0.240

  /// `--ease: cubic-bezier(0.2, 0, 0, 1)`.
  public static func ease(_ duration: TimeInterval = standard) -> Animation {
    .timingCurve(0.2, 0, 0, 1, duration: duration)
  }

  /// `--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)`.
  public static func easeInOut(_ duration: TimeInterval = standard) -> Animation {
    .timingCurve(0.4, 0, 0.2, 1, duration: duration)
  }

  /// The brand ease, or no animation when Reduce Motion is on (the web's
  /// `motion-reduce:transition-none`).
  public static func ease(_ duration: TimeInterval = standard, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : ease(duration)
  }
}

// MARK: - Density

/// The metrics that change with the density preference. The web's compact rules
/// sit at globals.css:1850-1865; where the web has no comfortable counterpart for a
/// native list row, the value is the native choice and says so.
public struct DensityMetrics: Sendable, Equatable {
  /// Vertical padding of a list or table row (compact: `padding-block: 0.5rem`, :1854).
  public var rowVerticalPadding: CGFloat
  /// Height of a table header row (compact: `height: 2.5rem`, :1857; comfortable 48pt is native).
  public var headerRowHeight: CGFloat
  /// Space between the parts of a post-it (`.postit` gap 0.5rem :1406, compact 0.375rem :1860).
  public var noteSpacing: CGFloat
  /// Post-it padding (`1.1rem 0.9rem 0.6rem` :1407, compact `0.85rem 0.75rem 0.45rem` :1861).
  public var notePadding: EdgeInsets
  /// Space between notes in a board lane (`.board-notes` gap 2.25rem :1375, compact 1rem :1864).
  public var boardNoteSpacing: CGFloat
  /// Height of a chip, select or search field: `h-8` in both densities.
  public var controlHeight: CGFloat

  public static let comfortable = DensityMetrics(
    // No table component on the web sets a comfortable padding; 12pt is the native
    // choice that keeps the compact step visible.
    rowVerticalPadding: 12,
    headerRowHeight: 48,
    noteSpacing: 8,
    notePadding: EdgeInsets(top: 17.6, leading: 14.4, bottom: 9.6, trailing: 14.4),
    boardNoteSpacing: 36,
    controlHeight: 32
  )

  public static let compact = DensityMetrics(
    rowVerticalPadding: 8,
    headerRowHeight: 40,
    noteSpacing: 6,
    notePadding: EdgeInsets(top: 13.6, leading: 12, bottom: 7.2, trailing: 12),
    boardNoteSpacing: 16,
    controlHeight: 32
  )
}

extension Density {
  public var metrics: DensityMetrics {
    switch self {
    case .comfortable: .comfortable
    case .compact: .compact
    }
  }
}

extension Theme {
  public var metrics: DensityMetrics { density.metrics }

  /// `--brand-edge`: the brand at 45% in every palette (globals.css:72, :329, :485, :629).
  public var brandEdge: Color { brand.opacity(0.45) }

  /// The paper color for a server `NotePaper` value; unknown values get yellow, the
  /// web's default paper (`.postit { --postit-paper: var(--postit-yellow) }`, :1397).
  public func postitPaper(_ paper: String) -> Color? {
    postit[paper] ?? postit[PostitPaper.yellow.rawValue]
  }
}
