import DailyDesign
import SwiftUI

extension Font {
  /// Geist at a size the web sets outside the type scale (`text-[11px]`, `text-xs`,
  /// `text-sm`); the type roles cover only the scale's steps.
  static func geist(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    Font(DailyFonts.ctFont(.sans, size: size, weight: weight))
  }
}
