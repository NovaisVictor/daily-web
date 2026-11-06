import SwiftUI

// MARK: - Motion tokens

/// `--dur-fast`, `--dur`, `--dur-slow` and `--ease` (globals.css:124-128), plus the
/// Tailwind durations the web's controls spell inline.
public enum Motion {
  /// 110ms.
  nonisolated public static let fast: TimeInterval = 0.110
  /// 160ms.
  nonisolated public static let standard: TimeInterval = 0.160
  /// 240ms.
  nonisolated public static let slow: TimeInterval = 0.240
  /// Tailwind `duration-100`: the web's hover colour changes.
  nonisolated public static let hover: TimeInterval = 0.100
  /// Tailwind `duration-150`: `button.tsx`'s `transition-all duration-150`.
  nonisolated public static let control: TimeInterval = 0.150
  /// `panel-press 0.5s linear` (globals.css:1050-1063): the long-press ring of a
  /// dashboard panel. Linear, so it reads as a progress, not as an ease.
  nonisolated public static let press: TimeInterval = 0.5

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

  /// Runs a state change inside the brand ease, or plainly when Reduce Motion is on,
  /// for changes made from an action rather than tracked by `.animation(_:value:)`.
  public static func animate(reduceMotion: Bool, _ duration: TimeInterval = standard, _ body: () -> Void) {
    if reduceMotion {
      body()
    } else {
      withAnimation(ease(duration), body)
    }
  }

  /// How a revealed block (an expanded section, an inline form) comes in: sliding
  /// down from its header, or only fading when Reduce Motion is on, since a fade
  /// carries no movement.
  public static func reveal(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
  }
}

// MARK: - Text normalization

/// Pure text rules shared by the input controls, kept apart so they are testable.
nonisolated public enum TextNormalization {
  /// The text with every line break (`\r\n`, `\r` or `\n`) replaced by one space,
  /// or the same text untouched when it has none.
  public static func singleLine(_ text: String) -> String {
    // Unicode scalars, not Characters: "\r\n" is one grapheme and would match
    // neither "\r" nor "\n" as a Character.
    guard text.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) else { return text }
    return
      text
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
  }
}

// MARK: - View modifiers

extension View {
  /// `.animation(_:value:)` with the brand ease, switched off by Reduce Motion.
  public func dailyAnimation<V: Equatable>(_ duration: TimeInterval = Motion.standard, value: V) -> some View {
    modifier(DailyAnimationModifier(duration: duration, value: value))
  }

  /// The chevron of a disclosure: pointing right when closed, down when open,
  /// turning with the hover duration as the web's `transition-transform`.
  public func disclosureRotation(open: Bool) -> some View {
    modifier(DisclosureRotationModifier(open: open))
  }

  /// Tailwind's `animate-pulse` (opacity 1 → 0.5 → 1 over 2s) for something that is
  /// still working, such as a loading placeholder or a live indicator. Off with
  /// Reduce Motion, as the web's `motion-safe:` prefix.
  public func ambientPulse(active: Bool) -> some View {
    modifier(AmbientPulseModifier(active: active))
  }

  /// Keeps a one-line field on one line: pasted text with line breaks gets spaces
  /// in their place. A `TextField` without `axis: .vertical` still accepts a pasted
  /// newline, which then breaks the layout and the server value.
  public func singleLine(_ text: Binding<String>) -> some View {
    modifier(SingleLineModifier(text: text))
  }
}

private struct DailyAnimationModifier<V: Equatable>: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let duration: TimeInterval
  let value: V

  func body(content: Content) -> some View {
    content.animation(Motion.ease(duration, reduceMotion: reduceMotion), value: value)
  }
}

private struct DisclosureRotationModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let open: Bool

  func body(content: Content) -> some View {
    content
      .rotationEffect(.degrees(open ? 90 : 0))
      .animation(Motion.ease(Motion.hover, reduceMotion: reduceMotion), value: open)
  }
}

private struct AmbientPulseModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let active: Bool

  // Reading the setting here, not once at creation, stops the pulse as soon as
  // Reduce Motion is turned on: the branch change drops the running animator.
  func body(content: Content) -> some View {
    if active && !reduceMotion {
      content.phaseAnimator([1.0, 0.5]) { view, opacity in
        view.opacity(opacity)
      } animation: { _ in
        // `cubic-bezier(0.4, 0, 0.6, 1)`, one second each way.
        Animation.timingCurve(0.4, 0, 0.6, 1, duration: 1)
      }
    } else {
      content
    }
  }
}

private struct SingleLineModifier: ViewModifier {
  @Binding var text: String

  func body(content: Content) -> some View {
    content.onChange(of: text) { _, newValue in
      let normalized = TextNormalization.singleLine(newValue)
      // Writing back only when something changed keeps the cursor where it is
      // while the person types.
      if normalized != newValue { text = normalized }
    }
  }
}

// MARK: - Ping dot

/// The web's `motion-safe:animate-ping` dot (`components/agents/TaskCard.tsx:14`,
/// `AgentBoard.tsx:60`): something waits on the person. The dot stays solid and a
/// halo of the same colour grows and fades around it; with Reduce Motion, or when
/// not `active`, only the dot shows. Decorative: the words beside it carry the meaning.
public struct PingDot: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let color: Color
  private let active: Bool
  private let size: CGFloat

  /// `size` defaults to the web's `size-1.5`.
  public init(color: Color, active: Bool = true, size: CGFloat = 6) {
    self.color = color
    self.active = active
    self.size = size
  }

  public var body: some View {
    let animating = active && !reduceMotion
    TimelineView(.animation(paused: !animating)) { timeline in
      let halo = Self.halo(at: timeline.date.timeIntervalSinceReferenceDate)
      Circle()
        .fill(color)
        .frame(width: size, height: size)
        .background {
          if animating {
            Circle()
              .fill(color)
              .scaleEffect(halo.scale)
              .opacity(halo.opacity)
          }
        }
    }
    .accessibilityHidden(true)
  }

  /// Tailwind's `ping` keyframes (`1s cubic-bezier(0, 0, 0.2, 1) infinite`, with
  /// `75%, 100% { transform: scale(2); opacity: 0 }`) at a point in time.
  static func halo(at time: TimeInterval) -> (scale: CGFloat, opacity: Double) {
    let cycle = time.truncatingRemainder(dividingBy: 1)
    let progress = min(max(cycle, 0) / 0.75, 1)
    let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))
    let eased = curve.value(at: progress)
    return (scale: CGFloat(1 + eased), opacity: 1 - eased)
  }
}
