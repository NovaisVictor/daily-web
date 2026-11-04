import Foundation
import Testing

@testable import DailyModels

@Suite struct PanelResultTests {
  @Test func bothNullIsOff() throws {
    let result = try Fixture.decode(PanelResult<[AgendaItem]>.self, json: #"{"data":null,"error":null}"#)
    #expect(result.isOff)
  }

  @Test func errorIsNotOff() throws {
    let result = try Fixture.decode(PanelResult<[AgendaItem]>.self, json: #"{"data":null,"error":"falhou"}"#)
    #expect(!result.isOff)
    #expect(result.data == nil)
    #expect(result.error == "falhou")
  }

  @Test func emptyDataIsNotOff() throws {
    let result = try Fixture.decode(PanelResult<[AgendaItem]>.self, json: #"{"data":[],"error":null}"#)
    #expect(!result.isOff)
    #expect(result.data == [])
  }

  @Test func absentKeysDecodeAsOff() throws {
    let result = try Fixture.decode(PanelResult<SlackDigest>.self, json: "{}")
    #expect(result.isOff)
  }

  @Test func roundTripsEachShape() throws {
    let shapes: [PanelResult<[String]>] = [
      PanelResult(data: nil, error: nil),
      PanelResult(data: nil, error: "x"),
      PanelResult(data: ["a"], error: nil),
    ]
    for shape in shapes {
      let decoded = try JSONDecoder().decode(PanelResult<[String]>.self, from: JSONEncoder().encode(shape))
      #expect(decoded == shape)
    }
  }
}
