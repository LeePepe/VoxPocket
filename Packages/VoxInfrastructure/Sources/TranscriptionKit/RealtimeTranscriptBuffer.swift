import Foundation

/// 完成事件可能乱序：终稿使用 committed 顺序，不使用 completion 到达顺序。
struct RealtimeTranscriptBuffer: Sendable {
    private struct Item: Sendable { var partial = ""; var final: String? }
    private var items: [String: Item] = [:]
    private var seen: [String] = []
    private var committed: [String] = []
    private var storedBytes = 0
    private let maximumBytes = 1_048_576

    var commitCount: Int { committed.count }
    var partialText: String { joined(committed + seen.filter { !committed.contains($0) }, finalOnly: false) }
    var finalText: String? {
        guard !committed.isEmpty, committed.count == items.count,
              committed.allSatisfy({ items[$0]?.final != nil }) else { return nil }
        return joined(committed, finalOnly: true)
    }

    mutating func append(itemID: String, delta: String) throws {
        try ensureItem(itemID)
        guard items[itemID]?.final == nil else { return }
        guard storedBytes + delta.utf8.count <= maximumBytes else {
            throw RealtimeTranscriptionError.invalidEvent
        }
        items[itemID]?.partial += delta
        storedBytes += delta.utf8.count
    }

    mutating func complete(itemID: String, text: String) throws {
        try ensureItem(itemID)
        if let existing = items[itemID]?.final, existing != text { throw RealtimeTranscriptionError.invalidEvent }
        let previous = items[itemID]?.final ?? items[itemID]?.partial ?? ""
        let nextBytes = storedBytes - previous.utf8.count + text.utf8.count
        guard nextBytes <= maximumBytes else { throw RealtimeTranscriptionError.invalidEvent }
        storedBytes = nextBytes
        items[itemID]?.partial = ""
        items[itemID]?.final = text
    }

    mutating func commit(itemID: String) throws {
        try ensureItem(itemID)
        if !committed.contains(itemID) { committed.append(itemID) }
    }

    private mutating func ensureItem(_ id: String) throws {
        guard !id.isEmpty, id.count <= 256, items.count < 1024 || items[id] != nil else {
            throw RealtimeTranscriptionError.invalidEvent
        }
        if items[id] == nil { items[id] = Item(); seen.append(id) }
    }

    private func joined(_ ids: [String], finalOnly: Bool) -> String {
        ids.compactMap { id in
            guard let item = items[id] else { return nil }
            return item.final ?? (finalOnly ? nil : item.partial)
        }.joined()
    }
}
