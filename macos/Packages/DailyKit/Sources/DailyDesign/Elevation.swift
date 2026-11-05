import SwiftUI

/// One layer of a CSS `box-shadow` list. Every elevation colour is a neutral
/// `oklch(L 0 0 / alpha)`: black for the drop shadows, white for the inset "shiny"
/// glow, so a layer stores the lightness and the alpha instead of a `Color`, which
/// keeps the values comparable to the CSS literals.
public struct ShadowLayer: Sendable, Equatable {
  /// CSS `inset`: drawn inside the surface instead of below it.
  public var inset: Bool
  public var x: CGFloat
  public var y: CGFloat
  /// CSS blur radius, in points (1px = 1pt).
  public var blur: CGFloat
  /// OKLCH lightness of the colour: 0 is black, 1 is white.
  public var lightness: Double
  public var alpha: Double

  public init(inset: Bool = false, x: CGFloat = 0, y: CGFloat, blur: CGFloat, lightness: Double, alpha: Double) {
    self.inset = inset
    self.x = x
    self.y = y
    self.blur = blur
    self.lightness = lightness
    self.alpha = alpha
  }

  public var color: Color { Color(oklch: lightness, 0, 0, alpha: alpha) }

  /// A drop shadow in `oklch(0 0 0 / alpha)`.
  static func drop(y: CGFloat, blur: CGFloat, alpha: Double) -> ShadowLayer {
    ShadowLayer(y: y, blur: blur, lightness: 0, alpha: alpha)
  }

  // `--shiny-sm`, `--shiny`, `--shiny-lg` (globals.css:46-48, the same in dark at
  // :219-221): a white glow falling from the top inside the surface.
  static let shinySmall = ShadowLayer(inset: true, y: 20, blur: 50, lightness: 1, alpha: 0.05)
  static let shiny = ShadowLayer(inset: true, y: 30, blur: 60, lightness: 1, alpha: 0.06)
  static let shinyLarge = ShadowLayer(inset: true, y: 50, blur: 100, lightness: 1, alpha: 0.07)
}

/// The elevation scale `e1` … `e5` (`--elevation-*`, applied through the
/// `shadow-e*` utilities at globals.css:798-826). Light gets depth from faint
/// shadows; dark keeps the same offsets with much heavier alphas, because a shadow
/// barely reads on a dark floor. No backdrop overrides these.
public enum Elevation: Int, Sendable, CaseIterable {
  case e1 = 1, e2, e3, e4, e5

  /// The layers of the shadow list, in CSS order.
  public func layers(for scheme: ColorScheme) -> [ShadowLayer] {
    switch (self, scheme) {
    // globals.css:50
    case (.e1, .light): [.shinySmall, .drop(y: 1, blur: 0, alpha: 0.05)]
    // globals.css:51
    case (.e2, .light): [.shiny, .drop(y: 1, blur: 0, alpha: 0.05), .drop(y: 4, blur: 2, alpha: 0.05)]
    // globals.css:52-54
    case (.e3, .light):
      [
        .shiny, .drop(y: 1, blur: 0, alpha: 0.05), .drop(y: 4, blur: 2, alpha: 0.05),
        .drop(y: 10, blur: 5, alpha: 0.10),
      ]
    // globals.css:55
    case (.e4, .light): [.shinyLarge, .drop(y: 2, blur: 4, alpha: 0.06), .drop(y: 12, blur: 24, alpha: 0.12)]
    // globals.css:56
    case (.e5, .light): [.shinyLarge, .drop(y: 4, blur: 8, alpha: 0.08), .drop(y: 24, blur: 48, alpha: 0.18)]
    // globals.css:223 (and :310 for an explicit .dark)
    case (.e1, _): [.shinySmall, .drop(y: 1, blur: 0, alpha: 0.35)]
    // globals.css:224
    case (.e2, _): [.shiny, .drop(y: 1, blur: 0, alpha: 0.35), .drop(y: 4, blur: 2, alpha: 0.30)]
    // globals.css:225-227
    case (.e3, _):
      [
        .shiny, .drop(y: 1, blur: 0, alpha: 0.40), .drop(y: 4, blur: 2, alpha: 0.35),
        .drop(y: 10, blur: 5, alpha: 0.45),
      ]
    // globals.css:228
    case (.e4, _): [.shinyLarge, .drop(y: 2, blur: 4, alpha: 0.45), .drop(y: 12, blur: 24, alpha: 0.55)]
    // globals.css:229
    case (.e5, _): [.shinyLarge, .drop(y: 4, blur: 8, alpha: 0.50), .drop(y: 24, blur: 48, alpha: 0.65)]
    }
  }
}

extension View {
  /// Paints the web elevation around (and the inset glow inside) `shape`. Unlike
  /// `View.shadow`, it never shadows the text inside, and the drop shadows are cut
  /// out of the surface itself, as CSS does for an outer `box-shadow`, so they do
  /// not darken a translucent surface from behind.
  public func elevation(
    _ level: Elevation,
    in shape: some Shape = RoundedRectangle(cornerRadius: Radius.medium)
  ) -> some View {
    modifier(ElevationModifier(level: level, shape: shape))
  }
}

struct ElevationModifier<S: Shape>: ViewModifier {
  @Environment(\.colorScheme) private var scheme
  let level: Elevation
  let shape: S

  func body(content: Content) -> some View {
    let layers = level.layers(for: scheme)
    let reach = Self.reach(of: layers)
    content
      .background {
        // Inset layers sit on the surface, below its content.
        ZStack {
          ForEach(Array(layers.filter(\.inset).enumerated()), id: \.offset) { _, layer in
            OutsideShape(base: shape, reach: reach)
              .fill(layer.color, style: FillStyle(eoFill: true))
              .offset(x: layer.x, y: layer.y)
              .blur(radius: Self.sigma(layer.blur))
          }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
      }
      .background {
        ZStack {
          ForEach(Array(layers.filter { !$0.inset }.enumerated()), id: \.offset) { _, layer in
            shape
              .fill(layer.color)
              .offset(x: layer.x, y: layer.y)
              .blur(radius: Self.sigma(layer.blur))
          }
        }
        .mask { OutsideShape(base: shape, reach: reach).fill(style: FillStyle(eoFill: true)) }
        .allowsHitTesting(false)
      }
  }

  /// A CSS blur radius is twice the Gaussian standard deviation, which is what
  /// SwiftUI's `blur(radius:)` takes.
  static func sigma(_ cssBlur: CGFloat) -> CGFloat { cssBlur / 2 }

  /// How far past the surface a layer can paint: its offset plus its blur.
  static func reach(of layers: [ShadowLayer]) -> CGFloat {
    layers.map { max(abs($0.x), abs($0.y)) + $0.blur }.max() ?? 0
  }
}

/// Everything within `reach` of the rect except `base`, filled with the even-odd
/// rule: the region an outer shadow may paint, and the "outside" an inset shadow
/// is cast from.
struct OutsideShape<S: Shape>: Shape {
  var base: S
  var reach: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path(rect.insetBy(dx: -reach, dy: -reach))
    path.addPath(base.path(in: rect))
    return path
  }
}
