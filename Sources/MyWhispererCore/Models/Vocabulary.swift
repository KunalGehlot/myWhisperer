import Foundation

/// A word or phrase the user wants spelled a particular way.
public struct DictionaryEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var term: String
    public var addedAt: Date

    public init(id: UUID = UUID(), term: String, addedAt: Date = Date()) {
        self.id = id
        self.term = term
        self.addedAt = addedAt
    }
}

/// A spoken cue that expands into stored text ("my calendar link" → URL).
public struct Snippet: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: String
    public var expansion: String
    public var addedAt: Date

    public init(id: UUID = UUID(), trigger: String, expansion: String, addedAt: Date = Date()) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.addedAt = addedAt
    }
}
