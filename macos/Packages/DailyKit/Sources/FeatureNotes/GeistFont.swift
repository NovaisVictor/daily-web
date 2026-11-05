import DailyDesign
import SwiftUI

extension Font {
  /// Geist Sans at a size the type scale does not name (the web's `text-xs`, `text-sm`
  /// and bracketed sizes). A `TypeRole` would change the size or the weight.
  static func geist(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    Font(DailyFonts.ctFont(.sans, size: size, weight: weight))
  }
}
