import CoreText
import Foundation
import SwiftUI
import os

/// Why the bundled Geist files could not be registered.
public enum FontRegistrationError: Error, Sendable, Equatable {
  /// `Bundle.module` has no `Fonts` folder: the package resource rule is missing.
  case resourcesMissing
  /// Core Text rejected a file for a reason other than "already registered".
  case registrationFailed(file: String, code: Int, description: String)
}

/// The web's two faces, Geist Sans and Geist Mono, bundled as variable fonts.
///
/// Source: app/layout.tsx:3-4 imports `geist/font/sans` and `geist/font/mono`;
/// app/globals.css:29-30 bridges them to `--font-body` and `--font-code`, which
/// `--font-sans`, `--font-display` (:696, :700) and `--font-mono` (:697) read.
public enum DailyFonts {
  /// The two families, named as Core Text reports them.
  public enum Family: String, Sendable, CaseIterable {
    case sans = "Geist"
    case mono = "Geist Mono"

    /// PostScript name of the default (400) instance, the base the `wght` axis varies.
    public var regularPostScriptName: String {
      switch self {
      case .sans: "Geist-Regular"
      case .mono: "GeistMono-Regular"
      }
    }

    var fileName: String {
      switch self {
      case .sans: "Geist-Variable.ttf"
      case .mono: "GeistMono-Variable.ttf"
      }
    }
  }

  /// The OpenType `wght` axis tag.
  static let weightAxis = 0x7767_6874

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "DailyDesign")

  // A static let runs its initializer exactly once, which is what makes `register()`
  // idempotent and cheap to call from every font helper.
  private static let registration: Result<Void, FontRegistrationError> = performRegistration()

  /// Registers Geist and Geist Mono for this process. Safe to call any number of
  /// times; only the first call touches Core Text. The font helpers call it lazily,
  /// so previews and tests need no setup.
  public static func register() throws(FontRegistrationError) {
    try registration.get()
  }

  /// The Core Text font for a family at a size and CSS weight (100-900).
  public static func ctFont(_ family: Family, size: CGFloat, weight: Font.Weight) -> CTFont {
    ensureRegistered()
    let attributes: [CFString: Any] = [
      kCTFontNameAttribute: family.regularPostScriptName,
      kCTFontVariationAttribute: [weightAxis: cssWeight(weight)],
    ]
    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
  }

  /// The CSS `font-weight` number of a SwiftUI weight, the value of the `wght` axis.
  public static func cssWeight(_ weight: Font.Weight) -> Int {
    let table: [(Font.Weight, Int)] = [
      (.ultraLight, 200), (.thin, 100), (.light, 300), (.regular, 400), (.medium, 500),
      (.semibold, 600), (.bold, 700), (.heavy, 800), (.black, 900),
    ]
    guard let match = table.first(where: { $0.0 == weight }) else {
      // Font.Weight has no public initializer, so every value is one of the nine above.
      preconditionFailure("Unknown Font.Weight \(weight)")
    }
    return match.1
  }

  private static func ensureRegistered() {
    // Reading the static runs the one-time registration. A failure is logged there and
    // returned by `register()`; a view body cannot throw, so Core Text then substitutes
    // the system face.
    _ = registration
  }

  private static func performRegistration() -> Result<Void, FontRegistrationError> {
    guard let folder = Bundle.module.url(forResource: "Fonts", withExtension: nil) else {
      logger.fault("Geist fonts folder missing from the DailyDesign bundle")
      return .failure(.resourcesMissing)
    }
    for family in Family.allCases {
      let url = folder.appending(path: family.fileName)
      var unmanagedError: Unmanaged<CFError>?
      guard !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &unmanagedError) else { continue }
      guard let cfError = unmanagedError?.takeRetainedValue() else {
        logger.fault("Registering \(family.fileName, privacy: .public) failed without an error")
        return .failure(.registrationFailed(file: family.fileName, code: 0, description: "unknown"))
      }
      let code = CFErrorGetCode(cfError)
      // Already registered (a second process-scope call, or the app registering the
      // same faces) still leaves the font available, so it is success.
      if code == CTFontManagerError.alreadyRegistered.rawValue || code == CTFontManagerError.duplicatedName.rawValue {
        continue
      }
      let description = CFErrorCopyDescription(cfError) as String
      logger.fault(
        "Registering \(family.fileName, privacy: .public) failed (\(code)): \(description, privacy: .public)"
      )
      return .failure(.registrationFailed(file: family.fileName, code: code, description: description))
    }
    return .success(())
  }
}

extension Font {
  /// Geist at a type role's size and weight. Prefer `View.typeRole(_:)`, which also
  /// sets tracking and leading.
  public static func daily(_ role: TypeRole) -> Font { role.font }

  /// Geist Sans at a size the type scale does not name (the web's `text-xs`, `text-sm`
  /// and bracketed sizes such as `text-[11px]`). Unlike a `TypeRole`, it sets no
  /// tracking, leading or tabular digits.
  public static func daily(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    Font(DailyFonts.ctFont(.sans, size: size, weight: weight))
  }

  /// Geist Mono, the web's `--font-mono` (globals.css:697), for code and identifiers.
  public static func dailyMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    Font(DailyFonts.ctFont(.mono, size: size, weight: weight))
  }
}
