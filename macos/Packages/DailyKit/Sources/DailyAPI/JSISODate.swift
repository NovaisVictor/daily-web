import Foundation

/// `Date.prototype.toISOString()`: UTC with exactly three fraction digits,
/// e.g. `2026-11-04T12:30:45.123Z`. The server parses these with `Date.parse`
/// and compares them with values it printed itself, so the client prints them
/// the same way.
public enum JSISODate {
  public static func string(from date: Date) -> String {
    // `Date` is a `Double`, so x.123 may be stored as x.12299…; the formatter
    // truncates, which would print .122. Milliseconds are rounded first and
    // written by hand, as JavaScript's integer milliseconds would print them.
    let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
    let (seconds, fraction) = milliseconds.quotientAndRemainder(dividingBy: 1000)
    let (wholeSeconds, positiveFraction) = fraction < 0 ? (seconds - 1, fraction + 1000) : (seconds, fraction)
    let base = Date(timeIntervalSince1970: TimeInterval(wholeSeconds)).formatted(Date.ISO8601FormatStyle())
    let fractionText = String(positiveFraction + 1000).dropFirst()
    return "\(base.dropLast()).\(fractionText)Z"
  }
}
