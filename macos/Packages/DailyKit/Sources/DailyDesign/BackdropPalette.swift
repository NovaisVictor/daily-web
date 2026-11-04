import SwiftUI

/// The page background for a scheme and backdrop: the `--mesh-*` tokens of
/// app/globals.css. It lives beside `Theme` rather than inside it because only the
/// window background reads it.
public struct BackdropPalette: Sendable, Equatable {
  /// One radial blob of the `bg-mesh` stack (globals.css:908): a color fading to
  /// transparent at `stop` of the gradient ray, centred at `center`.
  public struct Blob: Sendable, Equatable {
    public var color: Color
    public var center: UnitPoint
    public var stop: Double
  }

  /// `--mesh-base`.
  public var base: Color
  /// `--mesh-1` … `--mesh-5`; empty when the backdrop sets them `transparent`.
  public var blobs: [Blob]

  public var isFlat: Bool { blobs.isEmpty }

  public static func resolve(scheme: ColorScheme, backdrop: Backdrop) -> BackdropPalette {
    switch (scheme, backdrop) {
    case (.dark, .mesh): darkMesh
    case (.dark, .catppuccin):
      // --mesh-base: var(--ctp-base) (globals.css:471); the blobs are cleared at :375.
      BackdropPalette(base: Theme.Mocha.base, blobs: [])
    case (.dark, .dracula):
      // --mesh-base: var(--drc-background) (globals.css:610), blobs transparent :611-615.
      BackdropPalette(base: Theme.Dracula.background, blobs: [])
    case (.dark, .wezterm): weztermMesh
    case (_, .catppuccin):
      // Catppuccin Latte base (globals.css:374), blobs transparent :375-379.
      BackdropPalette(base: Color(oklch: 0.958, 0.006, 264.5), blobs: [])
    default:
      // Light keeps the mesh for Dracula and WezTerm (globals.css:527, :659).
      lightMesh
    }
  }

  /// Positions and stops of the five radial gradients in `bg-mesh` (globals.css:911-915).
  private static func blobs(_ colors: [Color]) -> [Blob] {
    let geometry: [(UnitPoint, Double)] = [
      (UnitPoint(x: 0.10, y: 0.04), 0.55),
      (UnitPoint(x: 0.82, y: 0.00), 0.50),
      (UnitPoint(x: 0.92, y: 0.58), 0.48),
      (UnitPoint(x: 0.16, y: 0.84), 0.52),
      (UnitPoint(x: 0.58, y: 0.38), 0.58),
    ]
    return zip(colors, geometry).map { Blob(color: $0, center: $1.0, stop: $1.1) }
  }

  static let lightMesh = BackdropPalette(
    base: Color(oklch: 0.986, 0.004, 265),  // --mesh-base :91
    blobs: blobs([
      Color(oklch: 0.957, 0.017, 255),  // --mesh-1 :92
      Color(oklch: 0.957, 0.019, 305),  // --mesh-2 :93
      Color(oklch: 0.97, 0.013, 25),  // --mesh-3 :94
      Color(oklch: 0.97, 0.013, 200),  // --mesh-4 :95
      Color(oklch: 0.992, 0.006, 95),  // --mesh-5 :96
    ])
  )

  static let darkMesh = BackdropPalette(
    base: Color(oklch: 0.134, 0.006, 285),  // --mesh-base :293
    blobs: blobs([
      Color(oklch: 0.188, 0.062, 265),  // --mesh-1 :294
      Color(oklch: 0.182, 0.066, 310),  // --mesh-2 :295
      Color(oklch: 0.174, 0.05, 20),  // --mesh-3 :296
      Color(oklch: 0.178, 0.047, 205),  // --mesh-4 :297
      Color(oklch: 0.156, 0.024, 280),  // --mesh-5 :298
    ])
  )

  static let weztermMesh = BackdropPalette(
    base: Color(oklch: 0.158, 0.047, 302.755),  // --mesh-base :687 (--wzt-background :662)
    blobs: blobs([
      Color(oklch: 0.22, 0.09, 302.755),  // --mesh-1 :688 (--wzt-glow-purple :664)
      Color(oklch: 0.21, 0.085, 339.288),  // --mesh-2 :689 (--wzt-glow-cursor :665)
      Color(oklch: 0.2, 0.07, 357.741),  // --mesh-3 :690 (--wzt-glow-magenta :666)
      Color(oklch: 0.2, 0.05, 194.87),  // --mesh-4 :691 (--wzt-glow-cyan :667)
      Color(oklch: 0.175, 0.04, 302.755),  // --mesh-5 :692 (--wzt-glow-haze :668)
    ])
  )
}
