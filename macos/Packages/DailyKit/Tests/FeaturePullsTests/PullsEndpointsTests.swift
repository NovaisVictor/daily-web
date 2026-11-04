import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import FeaturePulls

@Suite struct PullsEndpointsTests {
  private func describe<T>(_ endpoint: Endpoint<T>) -> String {
    "\(endpoint.method.rawValue) \(endpoint.path) \(FakeAPIClient.encode(endpoint.body) ?? "-")"
  }

  @Test func repositoryEndpoints() {
    #expect(describe(PullsEndpoints.repos) == "GET /api/pulls/repos -")
    #expect(!PullsEndpoints.repos.idempotent)
    #expect(describe(PullsEndpoints.addRepo("acme/web")) == #"POST /api/pulls/repos {"repo":"acme/web"}"#)
    #expect(describe(PullsEndpoints.removeRepo("acme/web")) == #"DELETE /api/pulls/repos {"repo":"acme/web"}"#)
    #expect(
      describe(PullsEndpoints.setAuthors(repo: "acme/web", ["ana", "bruno"]))
        == #"PUT /api/pulls/repos/authors {"authors":["ana","bruno"],"repo":"acme/web"}"#)
  }

  @Test func pullRequestWrites() {
    let item = pull(repo: "acme/web", number: 12)
    #expect(
      describe(PullsEndpoints.review(item, .init(event: .approve, body: nil)))
        == #"POST /api/pulls/acme/web/12/reviews {"event":"APPROVE"}"#)
    #expect(
      describe(PullsEndpoints.review(item, .init(event: .requestChanges, body: "faltou teste")))
        == #"POST /api/pulls/acme/web/12/reviews {"body":"faltou teste","event":"REQUEST_CHANGES"}"#)
    #expect(
      describe(PullsEndpoints.comment(item, body: "ok")) == #"POST /api/pulls/acme/web/12/comments {"body":"ok"}"#)
    #expect(
      describe(PullsEndpoints.requestReviewers(item, ["ana", "team:core"]))
        == #"POST /api/pulls/acme/web/12/reviewers {"reviewers":["ana","team:core"]}"#)
    #expect(
      describe(PullsEndpoints.merge(item, method: .rebase, headSha: testSha))
        == #"POST /api/pulls/acme/web/12/merge {"headSha":"\#(testSha)","method":"rebase"}"#)
    #expect(
      describe(PullsEndpoints.rerun(item, headSha: testSha))
        == #"POST /api/pulls/acme/web/12/rerun {"headSha":"\#(testSha)"}"#)
  }

  /// `app/api/pulls/shared.ts` reads the idempotency headers on every pulls write.
  @Test func everyPullsWriteIsIdempotent() {
    let item = pull()
    let flags = [
      PullsEndpoints.addRepo("a/b").idempotent,
      PullsEndpoints.removeRepo("a/b").idempotent,
      PullsEndpoints.setAuthors(repo: "a/b", []).idempotent,
      PullsEndpoints.review(item, .init(event: .approve)).idempotent,
      PullsEndpoints.comment(item, body: "x").idempotent,
      PullsEndpoints.requestReviewers(item, ["a"]).idempotent,
      PullsEndpoints.merge(item, method: .squash, headSha: testSha).idempotent,
      PullsEndpoints.rerun(item, headSha: testSha).idempotent,
    ]
    #expect(flags.allSatisfy { $0 })
  }

  @Test func jiraSyncLookupAndMove() {
    let lookup = PullsEndpoints.jiraSync(key: "TT-1", intent: .inProgress)
    #expect(describe(lookup) == "GET /api/pulls/jira-sync -")
    #expect(
      lookup.query == [URLQueryItem(name: "key", value: "TT-1"), URLQueryItem(name: "intent", value: "in-progress")])
    let move = PullsEndpoints.transition(key: "TT-1", transitionId: "31")
    #expect(describe(move) == #"POST /api/jira/issues/TT-1/transitions {"transitionId":"31"}"#)
    #expect(!move.idempotent)
  }

  @Test func ownerAndRepoArePercentEncoded() {
    #expect(PullsEndpoints.path(pull(repo: "a b/c+d", number: 1), "merge") == "/api/pulls/a%20b/c%2Bd/1/merge")
  }
}
