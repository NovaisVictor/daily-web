import DailyDesign
import SwiftUI

/// The web's native `<select>` dressed as a pill (`selectClass`, lib/theme.ts:143:
/// `h-8 rounded-full border bg-glass px-3 text-sm shadow-e1`): the chosen option and
/// a chevron, opening a menu that checks the current one.
struct PillSelect<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let options: [Value]
  let title: (Value) -> String

  var body: some View {
    Menu {
      Picker(label, selection: $selection) {
        ForEach(options, id: \.self) { Text(title($0)).tag($0) }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack(spacing: 6) {
        Text(title(selection))
        // SF Symbol sizing only: the chevron of the browser select.
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .accessibilityHidden(true)
      }
    }
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .pillButtonStyle(.outline, size: .small)
    .fixedSize()
    .accessibilityLabel(label)
    .accessibilityValue(title(selection))
  }
}
