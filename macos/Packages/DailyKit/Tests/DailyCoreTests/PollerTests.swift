import Foundation
import Testing

@testable import DailyCore

@Suite struct PollerTests {
  let clock = VirtualClock()

  func makePoller() -> Poller {
    let clock = self.clock
    return Poller(sleep: { try await clock.sleep($0) })
  }

  @Test func stateRunsEveryTwentySecondsInTheForeground() async {
    let poller = makePoller()
    var runs: [TimeInterval] = []
    poller.register("state", foreground: .seconds(20), background: .seconds(60)) {
      runs.append(VirtualClock.seconds(clock.elapsed))
    }
    poller.start()
    await clock.advance(by: .seconds(45))
    #expect(runs == [0, 20, 40])
  }

  @Test func backgroundSwitchesToSixtySecondsAtOnce() async {
    let poller = makePoller()
    var runs: [TimeInterval] = []
    poller.register("state", foreground: .seconds(20), background: .seconds(60)) {
      runs.append(VirtualClock.seconds(clock.elapsed))
    }
    poller.start()
    await clock.advance(by: .seconds(10))
    poller.setForeground(false)
    await clock.advance(by: .seconds(50))
    #expect(runs == [0])
    await clock.advance(by: .seconds(20))
    #expect(runs == [0, 70])
    await clock.advance(by: .seconds(60))
    #expect(runs == [0, 70, 130])
  }

  @Test func returningToTheForegroundRunsAtOnce() async {
    let poller = makePoller()
    var runs: [TimeInterval] = []
    poller.register("state", foreground: .seconds(20), background: .seconds(60)) {
      runs.append(VirtualClock.seconds(clock.elapsed))
    }
    poller.start()
    await settle()
    poller.setForeground(false)
    await clock.advance(by: .seconds(30))
    poller.setForeground(true)
    await clock.advance(by: .seconds(20))
    #expect(runs == [0, 30, 50])
  }

  @Test func foregroundOnlyScopePausesInTheBackground() async {
    let poller = makePoller()
    var runs = 0
    poller.start()
    poller.register("agents", foreground: .seconds(2), background: nil) { runs += 1 }
    await clock.advance(by: .seconds(5))
    #expect(runs == 3)
    poller.setForeground(false)
    await clock.advance(by: .seconds(60))
    #expect(runs == 3)
    #expect(clock.pendingSleepers == 0)
    poller.setForeground(true)
    await clock.advance(by: .seconds(1))
    #expect(runs == 4)
  }

  @Test func aScopeNeverOverlapsItself() async {
    let poller = makePoller()
    let gate = Gate()
    var started = 0
    var finished = 0
    poller.register("state", foreground: .seconds(20), background: .seconds(60)) {
      started += 1
      if started == 1 { await gate.wait() }
      finished += 1
    }
    poller.start()
    await settle()
    // Restarting the cadence while the first run is still waiting.
    poller.setForeground(false)
    poller.setForeground(true)
    await poller.runNow("state")
    await clock.advance(by: .seconds(65))
    #expect(started == 1)
    #expect(finished == 0)

    gate.open()
    await settle()
    #expect(finished == 1)
    await clock.advance(by: .seconds(15))
    #expect(started == 2)
  }

  @Test func unregisterAndStopEndTheLoops() async {
    let poller = makePoller()
    var state = 0
    var agents = 0
    poller.register("state", foreground: .seconds(20), background: .seconds(60)) { state += 1 }
    poller.start()
    poller.register("agents", foreground: .seconds(2), background: nil) { agents += 1 }
    await clock.advance(by: .seconds(3))
    poller.unregister("agents")
    await clock.advance(by: .seconds(10))
    #expect(agents == 2)

    poller.stop()
    await clock.advance(by: .seconds(100))
    #expect(state == 1)
    #expect(clock.pendingSleepers == 0)
    #expect(poller.registeredScopes == ["state"])
  }

  @Test func scopesWaitForStart() async {
    let poller = makePoller()
    var runs = 0
    poller.register("state", foreground: .seconds(20), background: .seconds(60)) { runs += 1 }
    await clock.advance(by: .seconds(40))
    #expect(runs == 0)
    poller.start()
    await settle()
    #expect(runs == 1)
  }
}
