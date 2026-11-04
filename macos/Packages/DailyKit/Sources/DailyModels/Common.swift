/// The `{ ok: true }` most writes answer with (`NextResponse.json({ ok: true })`
/// across `app/api/**`, and `writeDone` in `lib/api/jira.ts:30-33`).
public struct OKResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool

  public init(ok: Bool) {
    self.ok = ok
  }
}
