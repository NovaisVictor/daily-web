import CoreText
import SwiftUI
import Testing

@testable import DailyDesign

@Suite("Geist fonts")
struct FontsTests {
  @Test("registration succeeds and is idempotent")
  func registers() throws {
    try DailyFonts.register()
    try DailyFonts.register()
  }

  @Test("PostScript and family names resolve to the bundled faces", arguments: DailyFonts.Family.allCases)
  func resolves(family: DailyFonts.Family) throws {
    try DailyFonts.register()
    let byName = CTFontCreateWithName(family.regularPostScriptName as CFString, 16, nil)
    #expect(CTFontCopyPostScriptName(byName) as String == family.regularPostScriptName)
    #expect(CTFontCopyFamilyName(byName) as String == family.rawValue)

    let font = DailyFonts.ctFont(family, size: 16, weight: .regular)
    #expect(CTFontCopyFamilyName(font) as String == family.rawValue)
    #expect(CTFontGetSize(font) == 16)
  }

  @Test("SwiftUI weights map to CSS weights")
  func weightTable() {
    #expect(DailyFonts.cssWeight(.regular) == 400)
    #expect(DailyFonts.cssWeight(.medium) == 500)
    #expect(DailyFonts.cssWeight(.semibold) == 600)
    #expect(DailyFonts.cssWeight(.bold) == 700)
  }

  @Test("CSS weights rise with SwiftUI's weight order")
  func weightsAreMonotonic() {
    // SwiftUI's own order, lightest first: ultraLight is lighter than thin.
    let ordered: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
    let css = ordered.map(DailyFonts.cssWeight)
    #expect(css == [100, 200, 300, 400, 500, 600, 700, 800, 900])
    #expect(zip(css, css.dropFirst()).allSatisfy { $0 < $1 })
  }

  @Test("the same family, size and weight return the cached font")
  func cacheHit() {
    let first = DailyFonts.ctFont(.mono, size: 17, weight: .semibold)
    let second = DailyFonts.ctFont(.mono, size: 17, weight: .semibold)
    #expect(first === second)
    #expect(DailyFonts.font(.mono, size: 17, weight: .semibold) == DailyFonts.font(.mono, size: 17, weight: .semibold))
    #expect(DailyFonts.ctFont(.mono, size: 17, weight: .bold) !== first)
    #expect(DailyFonts.ctFont(.sans, size: 17, weight: .semibold) !== first)
  }

  @Test(
    "the wght axis carries the CSS weight",
    arguments: DailyFonts.Family.allCases, [Font.Weight.regular, .medium, .semibold, .bold]
  )
  func variation(family: DailyFonts.Family, weight: Font.Weight) throws {
    try DailyFonts.register()
    let font = DailyFonts.ctFont(family, size: 14, weight: weight)
    #expect(try effectiveWeight(font) == Double(DailyFonts.cssWeight(weight)))
  }

  @Test("type roles keep the web scale and use Geist at their weight")
  func roles() throws {
    try DailyFonts.register()
    let sizes: [TypeRole: CGFloat] = [
      .display: 44, .title: 34, .heading: 30, .subhead: 20, .body: 16, .data: 14, .caption: 13,
    ]
    let weights: [TypeRole: Int] = [
      .display: 600, .title: 600, .heading: 600, .subhead: 600, .body: 400, .data: 500, .caption: 500,
    ]
    for role in TypeRole.allCases {
      #expect(role.size == sizes[role])
      #expect(DailyFonts.cssWeight(role.weight) == weights[role])
      let font = DailyFonts.ctFont(.sans, size: role.size, weight: role.weight)
      #expect(CTFontCopyFamilyName(font) as String == "Geist")
    }
  }

  @Test("the natural line height constant matches Geist's metrics")
  func naturalLine() throws {
    try DailyFonts.register()
    let font = DailyFonts.ctFont(.sans, size: 100, weight: .regular)
    let line = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) / 100
    #expect(abs(line - TypeRole.naturalLineHeight) < 0.01)
    #expect(abs(TypeRole.body.lineSpacing - 3.2) < 0.0001)
    #expect(TypeRole.display.lineSpacing == 0)
  }
}

/// The `wght` value a font renders at. Core Text omits an axis left at its default
/// from `CTFontCopyVariation`, so that case reads the axis default instead.
private func effectiveWeight(_ font: CTFont) throws -> Double {
  if let value = (CTFontCopyVariation(font) as? [Int: Double])?[DailyFonts.weightAxis] { return value }
  let axes = try #require(CTFontCopyVariationAxes(font) as? [[CFString: Any]])
  let axis = try #require(axes.first { ($0[kCTFontVariationAxisIdentifierKey] as? Int) == DailyFonts.weightAxis })
  return try #require(axis[kCTFontVariationAxisDefaultValueKey] as? Double)
}

@Suite struct HandFontTests {
  @Test func patrickHandRegistersAndResolves() throws {
    try DailyFonts.register()
    let font = CTFontCreateWithName(DailyFonts.handPostScriptName as CFString, 17, nil)
    #expect(CTFontCopyPostScriptName(font) as String == DailyFonts.handPostScriptName)
  }
}
