import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import FeatureJira

/// Method, path, query and body of every Jira call (contract: `docs/contracts/api.md`).
@Suite struct JiraEndpointsTests {
  func describe<Response>(_ endpoint: Endpoint<Response>) -> String {
    let query = endpoint.query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    return "\(endpoint.method.rawValue) \(endpoint.path)\(query.isEmpty ? "" : "?\(query)") "
      + (FakeAPIClient.encode(endpoint.body) ?? "-")
  }

  @Test func watchAndPeople() {
    #expect(describe(JiraEndpoints.watch("TT-1")) == #"POST /api/jira/watch {"key":"TT-1"}"#)
    #expect(describe(JiraEndpoints.unwatch("TT-1")) == #"DELETE /api/jira/watch {"key":"TT-1"}"#)
    #expect(describe(JiraEndpoints.searchPeople("ana")) == "GET /api/jira/people/search?q=ana -")
    #expect(describe(JiraEndpoints.follow("acc:1")) == #"POST /api/jira/people {"accountId":"acc:1"}"#)
    #expect(describe(JiraEndpoints.unfollow("acc:1")) == #"DELETE /api/jira/people {"accountId":"acc:1"}"#)
    #expect(describe(JiraEndpoints.personView("712020:ab")) == "GET /api/jira/people/712020:ab -")
  }

  @Test func transitionsAndComments() {
    #expect(describe(JiraEndpoints.transitions("TT-1")) == "GET /api/jira/issues/TT-1/transitions -")
    #expect(
      describe(JiraEndpoints.transition("TT-1", id: "31"))
        == #"POST /api/jira/issues/TT-1/transitions {"transitionId":"31"}"#)
    #expect(
      describe(JiraEndpoints.comment("TT-1", body: "ok")) == #"POST /api/jira/issues/TT-1/comments {"body":"ok"}"#)
  }

  @Test func approvals() {
    #expect(describe(JiraEndpoints.approvals("TT-1")) == "GET /api/jira/issues/TT-1/approvals -")
    #expect(
      describe(JiraEndpoints.decide("TT-1", approvalId: "9", decision: .decline))
        == #"POST /api/jira/issues/TT-1/approvals {"approvalId":"9","decision":"decline"}"#)
  }

  @Test func flagBodies() {
    #expect(
      describe(JiraEndpoints.flag("TT-1", .flag(reason: "bloqueado")))
        == #"POST /api/jira/issues/TT-1/flag {"action":"flag","reason":"bloqueado"}"#)
    #expect(
      describe(JiraEndpoints.flag("TT-1", .unflag(note: nil)))
        == #"POST /api/jira/issues/TT-1/flag {"action":"unflag"}"#)
    #expect(
      describe(JiraEndpoints.flag("TT-1", .unflag(note: "liberado")))
        == #"POST /api/jira/issues/TT-1/flag {"action":"unflag","note":"liberado"}"#)
  }

  @Test func fields() {
    #expect(describe(JiraEndpoints.priorities("TT-1")) == "GET /api/jira/issues/TT-1/fields?options=priority -")
    #expect(
      describe(JiraEndpoints.edit("TT-1", .due("2026-11-30")))
        == #"PUT /api/jira/issues/TT-1/fields {"change":"due","dueDate":"2026-11-30"}"#)
    #expect(
      describe(JiraEndpoints.edit("TT-1", .due(nil)))
        == #"PUT /api/jira/issues/TT-1/fields {"change":"due","dueDate":null}"#)
    #expect(
      describe(JiraEndpoints.edit("TT-1", .priority("2")))
        == #"PUT /api/jira/issues/TT-1/fields {"change":"priority","priorityId":"2"}"#)
    #expect(
      describe(JiraEndpoints.edit("TT-1", .assignSelf)) == #"PUT /api/jira/issues/TT-1/fields {"change":"assign-self"}"#
    )
  }

  @Test func storiesEpicsAndParent() {
    #expect(
      describe(JiraEndpoints.createStory("TT-1", .init(summary: "S", description: nil)))
        == #"POST /api/jira/issues/TT-1/stories {"summary":"S"}"#)
    #expect(
      describe(JiraEndpoints.createStory("TT-1", .init(summary: "S", description: "D")))
        == #"POST /api/jira/issues/TT-1/stories {"description":"D","summary":"S"}"#)
    #expect(describe(JiraEndpoints.epics(project: "TT")) == "GET /api/jira/epics?project=TT -")
    #expect(
      describe(JiraEndpoints.setParent("TT-1", epic: "TT-9")) == #"PUT /api/jira/issues/TT-1/parent {"epic":"TT-9"}"#)
  }

  @Test func startDates() {
    #expect(describe(JiraEndpoints.startDate("TT-1")) == "GET /api/jira/issues/TT-1/start-date -")
    #expect(
      describe(JiraEndpoints.setStartDate("TT-1", date: "2026-10-01"))
        == #"PUT /api/jira/issues/TT-1/start-date {"date":"2026-10-01"}"#)
    #expect(
      describe(JiraEndpoints.startDateSuggestions(["A-1", "B-2"]))
        == "GET /api/jira/problems/start-dates?keys=A-1,B-2 -")
    #expect(
      describe(JiraEndpoints.writeStartDates([.init(key: "A-1", date: "2026-10-01")]))
        == #"POST /api/jira/problems/start-dates {"items":[{"date":"2026-10-01","key":"A-1"}]}"#)
  }

  @Test func keysArePercentEncodedAsSegments() {
    #expect(JiraEndpoints.transitions("A/B").path == "/api/jira/issues/A%2FB/transitions")
  }

  @Test func responsesDecode() throws {
    let transitions = try JSONDecoder().decode(
      JiraTransitionsResponse.self,
      from: Data(
        #"{"transitions":[{"id":"31","name":"Iniciar","to":{"name":"Em andamento","category":"indeterminate"},"requires":"screen"}]}"#
          .utf8))
    #expect(transitions.transitions[0].requires == .screen)
    let suggestion = try JSONDecoder().decode(
      JiraStartDateSuggestion.self, from: Data(#"{"date":null,"basis":null}"#.utf8))
    #expect(suggestion.date == nil)
    let results = try JSONDecoder().decode(
      JiraStartDateResultsResponse.self,
      from: Data(#"{"results":[{"key":"A-1","outcome":"refused","error":"campo"}]}"#.utf8))
    #expect(results.ok == nil && results.results[0].outcome == .refused)
  }
}
