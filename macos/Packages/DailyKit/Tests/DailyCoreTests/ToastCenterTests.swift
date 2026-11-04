import Foundation
import Testing

@testable import DailyCore

@Suite struct ToastCenterTests {
  let clock = VirtualClock()

  @Test func toastsLeaveAfterTheDelay() async {
    let clock = self.clock
    let center = ToastCenter(dismissDelay: .seconds(4), sleep: { try await clock.sleep($0) })
    center.error("falhou")
    await clock.advance(by: .seconds(2))
    center.success("ok")
    #expect(center.toasts.map(\.text) == ["falhou", "ok"])
    await clock.advance(by: .seconds(2))
    #expect(center.toasts.map(\.text) == ["ok"])
    await clock.advance(by: .seconds(2))
    #expect(center.toasts.isEmpty)
  }

  @Test func performRunsTheActionAndDismisses() async {
    let clock = self.clock
    let center = ToastCenter(sleep: { try await clock.sleep($0) })
    var undone = false
    let id = center.show(.info, "Tarefa concluída", actionTitle: "Desfazer") { undone = true }
    center.perform(id)
    await settle()
    #expect(undone)
    #expect(center.toasts.isEmpty)
    #expect(clock.pendingSleepers == 0)
  }
}
