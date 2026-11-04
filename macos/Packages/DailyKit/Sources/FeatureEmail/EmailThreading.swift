import DailyModels
import Foundation

/// A conversation: messages tied by references or by subject
/// (`EmailThread` in `lib/types.ts`, built by `lib/parsers/threads.ts`).
nonisolated struct EmailThread: Identifiable, Equatable, Sendable {
  /// The key (`account:id`) of the message that roots the conversation.
  var id: String
  /// The oldest message's subject without reply prefixes.
  var subject: String
  /// Oldest first.
  var messages: [EmailEnvelope]
  /// Senders in the order they first wrote.
  var participants: [String]
  var unreadCount: Int
  var lastDate: String

  /// Only the received ones: a sent uid points at another message inside the
  /// origin folder, and deleting a conversation must not delete your own copy.
  var received: [EmailEnvelope] { messages.filter { $0.mailbox == .inbox } }
}

extension EmailEnvelope {
  /// `account:id`, the key the web uses for a message (`EmailPanel.tsx`, `key`).
  nonisolated var key: String { "\(account):\(id)" }
}

/// `lib/parsers/threads.ts`.
nonisolated enum EmailThreading {
  /// Reply and forward prefixes in English, Portuguese and Spanish.
  private static var replyPrefix: Regex<Substring> {
    #/^\s*(?:(?:re|res|res\.|ref|fw|fwd|enc|rv)\s*(?:\[\d+\])?\s*:\s*)+/#.ignoresCase()
  }

  static func normalizeSubject(_ subject: String) -> String {
    var current = subject
    // A loop because real subjects carry spaces and brackets between prefixes.
    for _ in 0..<10 {
      let next = current.replacing(replyPrefix, with: "", maxReplacements: 1)
      if next == current { break }
      current = next
    }
    return current.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Message-Ids come as `<a@b>`; not every server sends the brackets.
  private static func normalizeId(_ value: String) -> String {
    var trimmed = Substring(value.trimmingCharacters(in: .whitespacesAndNewlines))
    if trimmed.hasPrefix("<") { trimmed = trimmed.dropFirst() }
    if trimmed.hasSuffix(">") { trimmed = trimmed.dropLast() }
    return trimmed.lowercased()
  }

  /// Joins messages by references (reliable, across accounts) and by
  /// normalized subject inside one account.
  static func threads(_ messages: [EmailEnvelope]) -> [EmailThread] {
    var sets = DisjointSets()
    var ownerOfMessageId: [String: String] = [:]
    var ownerOfSubject: [String: String] = [:]

    for message in messages {
      let key = message.key
      sets.add(key)
      let own = normalizeId(message.messageId)
      guard !own.isEmpty else { continue }
      if let earlier = ownerOfMessageId[own] {
        sets.union(earlier, key)
      } else {
        ownerOfMessageId[own] = key
      }
    }

    // Second pass: every known Message-Id has an owner now, so a reply listed
    // before its original still finds its thread.
    for message in messages {
      let key = message.key
      for reference in message.references {
        if let target = ownerOfMessageId[normalizeId(reference)] { sets.union(target, key) }
      }
      let subject = normalizeSubject(message.subject).lowercased()
      // Without a subject there is nothing to compare.
      guard !subject.isEmpty else { continue }
      let bySubject = "\(message.account) \(subject)"
      if let earlier = ownerOfSubject[bySubject] {
        sets.union(earlier, key)
      } else {
        ownerOfSubject[bySubject] = key
      }
    }

    var rootOrder: [String] = []
    var byRoot: [String: [EmailEnvelope]] = [:]
    for message in messages {
      let root = sets.root(message.key)
      if byRoot[root] == nil { rootOrder.append(root) }
      byRoot[root, default: []].append(message)
    }

    return rootOrder.compactMap { root -> EmailThread? in
      guard let list = byRoot[root] else { return nil }
      let ordered = list.stableSorted { $0.date < $1.date }
      guard let first = ordered.first, let last = ordered.last else { return nil }
      var participants: [String] = []
      for message in ordered where !message.from.isEmpty && !participants.contains(message.from) {
        participants.append(message.from)
      }
      return EmailThread(
        id: root,
        subject: normalizeSubject(first.subject),
        messages: ordered,
        participants: participants,
        unreadCount: ordered.filter(\.unread).count,
        lastDate: last.date
      )
    }
  }
}

/// Union-find with path halving, like `Grupos` in `lib/parsers/threads.ts`.
nonisolated private struct DisjointSets {
  private var parent: [String: String] = [:]

  mutating func add(_ key: String) {
    if parent[key] == nil { parent[key] = key }
  }

  mutating func root(_ key: String) -> String {
    add(key)
    var current = key
    while let up = parent[current], up != current {
      let grand = parent[up] ?? up
      parent[current] = grand
      current = grand
    }
    return current
  }

  mutating func union(_ a: String, _ b: String) {
    let rootA = root(a)
    let rootB = root(b)
    if rootA != rootB { parent[rootB] = rootA }
  }
}

extension Array {
  /// JavaScript's `sort` is stable and the web relies on it for ties; Swift's is not.
  nonisolated func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
    enumerated()
      .sorted { lhs, rhs in
        if areInIncreasingOrder(lhs.element, rhs.element) { return true }
        if areInIncreasingOrder(rhs.element, lhs.element) { return false }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }
}
