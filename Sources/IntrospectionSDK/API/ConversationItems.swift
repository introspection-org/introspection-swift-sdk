import Foundation

/// OpenAI-style list envelope for conversation items. Pagination uses `next`.
public struct GenAISpanList: Codable, Sendable, Hashable {
    public var object: String?
    public var data: [GenAISpan]
    public var firstId: String?
    public var lastId: String?
    public var hasMore: Bool?
    public var next: String?
    /// Where a `from_compaction` read was anchored; absent on other reads.
    public var compaction: ConversationCompaction?

    public init(
        data: [GenAISpan], object: String? = "list", firstId: String? = nil, lastId: String? = nil, hasMore: Bool? = nil,
        next: String? = nil
    ) {
        self.data = data
        self.object = object
        self.firstId = firstId
        self.lastId = lastId
        self.hasMore = hasMore
        self.next = next
    }

    private enum CodingKeys: String, CodingKey {
        case object, data, next, compaction
        case firstId = "first_id"
        case lastId = "last_id"
        case hasMore = "has_more"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        data = try container.decodeIfPresent([GenAISpan].self, forKey: .data) ?? []
        firstId = try container.decodeIfPresent(String.self, forKey: .firstId)
        lastId = try container.decodeIfPresent(String.self, forKey: .lastId)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        next = try container.decodeIfPresent(String.self, forKey: .next)
        compaction = try container.decodeIfPresent(ConversationCompaction.self, forKey: .compaction)
    }
}

/// Where a `from_compaction` item read was anchored.
public struct ConversationCompaction: Codable, Sendable, Hashable {
    /// `false` when no compaction anchor resolved and the read started at the beginning of the conversation.
    public var applied: Bool?
    /// The response id the compaction anchor names.
    public var responseId: String?
    /// Opaque cursor positioned at the anchor item.
    public var cursor: String?
    /// Recorded compactions, oldest first.
    public var history: [ConversationCompactionRecord]?

    public init(
        applied: Bool? = nil, responseId: String? = nil, cursor: String? = nil, history: [ConversationCompactionRecord]? = nil
    ) {
        self.applied = applied
        self.responseId = responseId
        self.cursor = cursor
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case applied, cursor, history
        case responseId = "response_id"
    }
}

/// One recorded compaction.
public struct ConversationCompactionRecord: Codable, Sendable, Hashable {
    /// The last response recorded before the compaction applied.
    public var responseId: String?
    /// Turn count and context size when it applied.
    public var atCompaction: CompactionCounts?
    /// Turns and tokens since the previous compaction.
    public var sinceCompaction: CompactionCounts?

    public init(responseId: String? = nil, atCompaction: CompactionCounts? = nil, sinceCompaction: CompactionCounts? = nil) {
        self.responseId = responseId
        self.atCompaction = atCompaction
        self.sinceCompaction = sinceCompaction
    }

    private enum CodingKeys: String, CodingKey {
        case responseId = "response_id"
        case atCompaction = "at_compaction"
        case sinceCompaction = "since_compaction"
    }
}

/// Root-agent turns and tokens, at a compaction or across the segment before it.
public struct CompactionCounts: Codable, Sendable, Hashable {
    public var turns: Int?
    public var tokens: Int?

    public init(turns: Int? = nil, tokens: Int? = nil) {
        self.turns = turns
        self.tokens = tokens
    }
}
