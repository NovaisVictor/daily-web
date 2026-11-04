import AppKit
import DailyDesign
import SwiftUI

/// "Resumo para a daily" (`components/jira/StandupDialog.tsx`): the daily or
/// weekly summary, ready to copy.
struct StandupSheet: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  let source: StandupSource
  let now: Date

  @State private var range: StandupRange = .daily
  @State private var copied: Bool?

  private var text: String { StandupBuilder.summary(range, source: source, now: now) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Resumo para a daily").typeRole(.subhead).foregroundStyle(theme.ink).accessibilityAddTraits(.isHeader)
        Text(range.description).font(.system(size: 13)).foregroundStyle(theme.inkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 8) {
        ForEach(StandupRange.allCases, id: \.self) { option in
          Chip(option.label, isOn: range == option) {
            range = option
            copied = nil
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Período do resumo")
      ScrollView {
        Text(text)
          .font(.system(size: 13, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
      }
      .frame(minHeight: 256)
      .background(theme.surface1, in: .rect(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.lineStrong) }
      .accessibilityLabel("texto do resumo")
      if copied == false {
        Text("Não deu para copiar. Selecione o texto acima e copie com ⌘C.")
          .font(.system(size: 13)).foregroundStyle(theme.danger)
      }
      HStack {
        Spacer()
        Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(copied == true ? "Copiado" : "Copiar", action: copy)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 520)
  }

  // The web says Ctrl+C; on a Mac the shortcut is ⌘C.
  private func copy() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    copied = pasteboard.setString(text, forType: .string)
    AccessibilityNotification.Announcement(copied == true ? "Copiado" : "Não deu para copiar").post()
  }
}
