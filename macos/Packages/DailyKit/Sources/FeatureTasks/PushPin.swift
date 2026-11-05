import DailyDesign
import DailyModels
import SwiftUI

/// The pin as a drawing, not a photo (`components/tasks/PushPin.tsx`): one flat
/// colour per shape and an ink outline, with no light, gloss or shadow. Each
/// shape is drawn upright in the SVG's 40×48 box and tilted onto its needle
/// tip, so every shape pierces the paper at the same point.
nonisolated enum PinGeometry {
  /// The SVG `viewBox`.
  static let box = CGSize(width: 40, height: 48)
  /// The needle tip, the point each shape rotates around (`rotate(… 20 41)`).
  static let tip = CGPoint(x: 20, y: 41)

  static func tilt(_ shape: PinShape) -> Double {
    switch shape {
    case .ball: 18
    case .heart: 16
    default: 22
    }
  }

  /// The needle, stroked only.
  static func needle(_ shape: PinShape) -> Path {
    let top: CGFloat =
      switch shape {
      case .ball: 20
      case .heart: 21
      default: 27
      }
    var path = Path()
    path.move(to: CGPoint(x: 20, y: top))
    path.addLine(to: tip)
    return path
  }

  /// The filled parts in the SVG's paint order: each one covers the outline
  /// of the part before it.
  static func parts(_ shape: PinShape) -> [Path] {
    switch shape {
    case .ball:
      [Path(ellipseIn: CGRect(x: 10.5, y: 3, width: 19, height: 19))]
    case .heart:
      [heart]
    default:
      [
        Path(roundedRect: CGRect(x: 11.5, y: 22, width: 17, height: 5), cornerRadius: 2.5),
        polygon([(15, 12.5), (25, 12.5), (23.5, 22), (16.5, 22)]),
        Path(roundedRect: CGRect(x: 10, y: 4, width: 20, height: 9), cornerRadius: 4.5),
      ]
    }
  }

  private static var heart: Path {
    var path = Path()
    path.move(to: CGPoint(x: 20, y: 23))
    path.addCurve(to: CGPoint(x: 14.3, y: 4.8), control1: CGPoint(x: 8.5, y: 15.5), control2: CGPoint(x: 8, y: 5.5))
    path.addCurve(to: CGPoint(x: 20, y: 9), control1: CGPoint(x: 17.5, y: 4.4), control2: CGPoint(x: 19.4, y: 6.8))
    path.addCurve(to: CGPoint(x: 25.7, y: 4.8), control1: CGPoint(x: 20.6, y: 6.8), control2: CGPoint(x: 22.5, y: 4.4))
    path.addCurve(to: CGPoint(x: 20, y: 23), control1: CGPoint(x: 32, y: 5.5), control2: CGPoint(x: 31.5, y: 15.5))
    path.closeSubpath()
    return path
  }

  private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
    var path = Path()
    path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
  }

  /// The tilt around the tip, then the box scaled into `rect`.
  static func transform(_ shape: PinShape, into rect: CGRect) -> CGAffineTransform {
    let scale = min(rect.width / box.width, rect.height / box.height)
    let radians = tilt(shape) * .pi / 180
    return CGAffineTransform(translationX: -tip.x, y: -tip.y)
      .concatenating(CGAffineTransform(rotationAngle: radians))
      .concatenating(CGAffineTransform(translationX: tip.x, y: tip.y))
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
  }
}

/// One part of a pin, placed in the view's frame.
struct PinPartShape: Shape {
  let path: Path
  let shape: PinShape

  func path(in rect: CGRect) -> Path {
    path.applying(PinGeometry.transform(shape, into: rect))
  }
}

/// A pin as `.postit-pin` draws it: 36×44 on the board, the colour from the
/// fixed `--pin` map and the outline in the paper's ink, dark in every theme
/// (`globals.css:1462-1504`).
struct PushPinView: View {
  @Environment(\.theme) private var theme
  let color: PinColor
  let shape: PinShape
  var size = CGSize(width: 36, height: 44)

  var body: some View {
    let scale = min(size.width / PinGeometry.box.width, size.height / PinGeometry.box.height)
    ZStack {
      PinPartShape(path: PinGeometry.needle(shape), shape: shape)
        .stroke(theme.postitInk, style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
      ForEach(Array(PinGeometry.parts(shape).enumerated()), id: \.offset) { _, part in
        let piece = PinPartShape(path: part, shape: shape)
        piece.fill(PinPalette.color(color))
          .overlay { piece.stroke(theme.postitInk, style: StrokeStyle(lineWidth: 2 * scale, lineJoin: .round)) }
      }
    }
    .frame(width: size.width, height: size.height)
    .accessibilityHidden(true)
  }
}
