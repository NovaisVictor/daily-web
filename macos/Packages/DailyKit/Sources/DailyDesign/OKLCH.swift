import SwiftUI

/// A gamma-encoded sRGB color in the *extended* range: components may fall
/// slightly outside 0…1.
///
/// The web writes every token as `oklch()`, and a few of them (the light brand,
/// the yellow post-it) sit just outside sRGB. Safari paints those in Display P3
/// on a Mac screen, so clamping here would make the native app duller than the
/// page. SwiftUI's `.sRGB` color space is extended, so the out-of-range values
/// survive and render the same way.
nonisolated public struct SRGB: Sendable, Equatable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var opacity: Double

  public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  /// Converts a CSS `oklch(l c h / alpha)` value, with `l` as a 0…1 number and
  /// `h` in degrees, following CSS Color 4 (OKLCH → OKLab → linear sRGB → sRGB).
  public init(oklch lightness: Double, _ chroma: Double, _ hue: Double, alpha: Double = 1) {
    let radians = hue * .pi / 180
    let labA = chroma * cos(radians)
    let labB = chroma * sin(radians)

    // Matrices from Björn Ottosson's reference implementation, the same ones
    // CSS Color 4 uses.
    let lPrime = lightness + 0.396_337_777_4 * labA + 0.215_803_757_3 * labB
    let mPrime = lightness - 0.105_561_345_8 * labA - 0.063_854_172_8 * labB
    let sPrime = lightness - 0.089_484_177_5 * labA - 1.291_485_548_0 * labB
    let long = lPrime * lPrime * lPrime
    let medium = mPrime * mPrime * mPrime
    let short = sPrime * sPrime * sPrime

    let linearRed = 4.076_741_662_1 * long - 3.307_711_591_3 * medium + 0.230_969_929_2 * short
    let linearGreen = -1.268_438_004_6 * long + 2.609_757_401_1 * medium - 0.341_319_396_5 * short
    let linearBlue = -0.004_196_086_3 * long - 0.703_418_614_7 * medium + 1.707_614_701_0 * short

    self.init(
      red: Self.encode(linearRed),
      green: Self.encode(linearGreen),
      blue: Self.encode(linearBlue),
      opacity: alpha
    )
  }

  /// A `#rrggbb` literal, written as `0xrrggbb`.
  public init(hex: UInt32, alpha: Double = 1) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }

  /// The sRGB transfer function, sign-preserving for extended values as CSS Color 4 does.
  public static func encode(_ linear: Double) -> Double {
    let magnitude = abs(linear)
    let encoded = magnitude <= 0.003_130_8 ? 12.92 * magnitude : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
    return linear < 0 ? -encoded : encoded
  }

  /// The inverse of `encode`.
  public static func decode(_ encoded: Double) -> Double {
    let magnitude = abs(encoded)
    let linear = magnitude <= 0.040_45 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
    return encoded < 0 ? -linear : linear
  }

  public var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
  }
}

extension Color {
  /// `oklch(l c h / alpha)` from `app/globals.css`, converted once at definition time.
  /// Write the same literal as the CSS so a token can be traced by search.
  nonisolated public init(oklch lightness: Double, _ chroma: Double, _ hue: Double, alpha: Double = 1) {
    self = SRGB(oklch: lightness, chroma, hue, alpha: alpha).color
  }

  /// `#rrggbb` written as `0xrrggbb`.
  nonisolated public init(hex: UInt32, alpha: Double = 1) {
    self = SRGB(hex: hex, alpha: alpha).color
  }
}
