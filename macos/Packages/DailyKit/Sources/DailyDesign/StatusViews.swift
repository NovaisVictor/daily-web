import SwiftUI

/// The tones of `components/data/Status.tsx`.
public enum StatusTone: String, Sendable, CaseIterable {
  case neutral, success, warning, destructive, info
}

/// The literal glyphs of `Status.tsx` (`GLYPH`): the shape carries the state with the
/// color, so the reading survives color blindness.
public enum StatusGlyph: String, Sendable, CaseIterable {
  /// Active, sent, live.
  case live = "●"
  /// Inactive, pending, ended.
  case idle = "○"
  /// In flight.
  case moving = "◐"
  /// Error.
  case alert = "▲"
}

extension Theme {
  /// The foreground of a tone (`TONE` and `DOT` in Status.tsx).
  public func color(for tone: StatusTone) -> Color {
    switch tone {
    case .neutral: inkDim
    case .success: success
    case .warning: warning
    case .destructive: danger
    case .info: info
    }
  }

  public func tint(for tone: StatusTone) -> Color {
    switch tone {
    case .neutral: neutralTint
    case .success: successTint
    case .warning: warningTint
    case .destructive: dangerTint
    case .info: infoTint
    }
  }

  public func border(for tone: StatusTone) -> Color {
    switch tone {
    case .neutral: lineStrong
    // `border-warning/45` vs `/40` for the others, as in Status.tsx.
    case .warning: warning.opacity(0.45)
    default: color(for: tone).opacity(0.4)
    }
  }
}

/// A state label in a capsule (`StatusPill` in Status.tsx).
public struct StatusPill: View {
  @Environment(\.theme) private var theme
  private let label: String
  private let glyph: StatusGlyph
  private let tone: StatusTone
  private let note: String?

  public init(_ label: String, glyph: StatusGlyph, tone: StatusTone, note: String? = nil) {
    self.label = label
    self.glyph = glyph
    self.tone = tone
    self.note = note
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      HStack(spacing: 6) {
        Text(glyph.rawValue).accessibilityHidden(true)
        Text(label)
      }
      .typeRole(.caption)
      .foregroundStyle(theme.color(for: tone))
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(theme.tint(for: tone), in: .capsule)
      .overlay { Capsule().strokeBorder(theme.border(for: tone)) }
      if let note {
        Text(note)
          .font(.geist(size: TextSize.extraSmall))
          .foregroundStyle(theme.inkDim)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// A decorative dot for dense lists; the word beside it carries the meaning.
public struct StatusDot: View {
  @Environment(\.theme) private var theme
  private let tone: StatusTone

  public init(_ tone: StatusTone) {
    self.tone = tone
  }

  public var body: some View {
    Circle()
      .fill(theme.color(for: tone))
      .frame(width: 8, height: 8)
      .accessibilityHidden(true)
  }
}

/// The variants of `components/ui/badge.tsx` that carry meaning.
public enum BadgeStyle: String, Sendable, CaseIterable {
  case brand, secondary, success, warning, danger, info
}

/// A small count or label (`components/ui/badge.tsx`).
public struct Badge: View {
  @Environment(\.theme) private var theme
  private let text: String
  private let style: BadgeStyle

  public init(_ text: String, style: BadgeStyle = .brand) {
    self.text = text
    self.style = style
  }

  public var body: some View {
    Text(text)
      .font(.geist(size: TextSize.extraSmall, weight: .medium).monospacedDigit())
      .lineLimit(1)
      .foregroundStyle(colors.foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(colors.background, in: .capsule)
      .overlay { Capsule().strokeBorder(colors.border) }
  }

  private var colors: (foreground: Color, background: Color, border: Color) {
    switch style {
    case .brand: (theme.brandInk, theme.brand, .clear)
    case .secondary: (theme.inkMid, theme.neutralTint, theme.lineStrong)
    case .success: signal(.success)
    case .warning: signal(.warning)
    case .danger: signal(.destructive)
    case .info: signal(.info)
    }
  }

  private func signal(_ tone: StatusTone) -> (foreground: Color, background: Color, border: Color) {
    (theme.color(for: tone), theme.tint(for: tone), theme.border(for: tone))
  }
}
