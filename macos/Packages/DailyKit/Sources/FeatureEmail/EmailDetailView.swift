import DailyDesign
import DailyModels
import SwiftUI

/// The open message, right under its row (`EmailDetail` in `EmailPanel.tsx`).
///
/// The server sends the body already flattened to plain text
/// (`readable()` in `lib/parsers/mail.ts`), so it is drawn as text with its
/// addresses turned into links that open in the default browser.
struct EmailDetailView: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  let message: EmailEnvelope
  let tags: [String]

  var body: some View {
    let detail = store.detail?.key == message.key ? store.detail : nil
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        bodyText(detail?.text)
      }
      .frame(maxHeight: 340)

      // The quoted history stays folded: in a reply to a reply it is most of
      // the text, and the part already read.
      if let quoted = detail?.quoted, !quoted.isEmpty {
        let shown = detail?.showQuoted ?? false
        Button("···") { store.toggleQuoted() }
          .pillButtonStyle(.outline, size: .small)
          .accessibilityLabel(shown ? "esconder histórico" : "mostrar histórico")
        if shown {
          ScrollView {
            Text(EmailLinks.attributed(quoted))
              .font(.daily(size: 14))
              .foregroundStyle(theme.inkDim)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.leading, 12)
              .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 2) }
          }
          .frame(maxHeight: 340)
        }
      }

      if !tags.isEmpty {
        FlowLayout(spacing: 8) {
          ForEach(tags, id: \.self) { Badge($0, style: .secondary) }
        }
      }

      if let error = detail?.error {
        PanelError(error)
      }

      // No reply to your own sent message; the reply routes look the uid up in the inbox.
      if message.mailbox == .inbox {
        replyBox(detail)
      }
    }
    .padding(.vertical, 16)
    .padding(.leading, 36)
    .padding(.trailing, 16)
    .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("corpo do e-mail")
  }

  @ViewBuilder
  private func bodyText(_ text: String?) -> some View {
    Group {
      if let text, !text.isEmpty {
        Text(EmailLinks.attributed(text))
          .textSelection(.enabled)
      } else if text == nil {
        Text("Carregando…")
      } else {
        Text("")
      }
    }
    // `text-sm leading-relaxed` (1.625) over Geist's natural 1.3 line.
    .font(.daily(size: 14))
    .lineSpacing(14 * (1.625 - 1.3))
    .foregroundStyle(theme.inkMid)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func replyBox(_ detail: EmailDetailState?) -> some View {
    let reply = detail?.reply ?? ""
    let drafting = detail?.drafting ?? false
    let sending = detail?.sending ?? false
    return VStack(alignment: .leading, spacing: 8) {
      TextEditor(text: Binding(get: { reply }, set: { store.setReply($0) }))
        .font(.daily(size: 14))
        .scrollContentBackground(.hidden)
        .padding(8)
        .frame(minHeight: 88)
        .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
        .overlay(alignment: .topLeading) {
          if reply.isEmpty {
            Text("Escreva sua resposta — ou descreva o que dizer e peça o rascunho para a IA.")
              .font(.daily(size: 14))
              .foregroundStyle(theme.inkDim)
              .padding(.horizontal, 13)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
          }
        }
        .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.lineStrong) }
        .accessibilityLabel("resposta")
      HStack(spacing: 8) {
        Button(drafting ? "Gerando…" : "Responder com IA") {
          Task { await store.draftReply(message) }
        }
        .pillButtonStyle(.outline, size: .small)
        .disabled(drafting)
        Button(sending ? "Enviando…" : "Enviar resposta") {
          Task { await store.sendReply(message) }
        }
        .pillButtonStyle(.primary, size: .small)
        .disabled(sending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if detail?.sent == true {
          Text("Resposta enviada.")
            .font(.daily(size: 14))
            .foregroundStyle(theme.inkMid)
        }
      }
    }
  }
}
