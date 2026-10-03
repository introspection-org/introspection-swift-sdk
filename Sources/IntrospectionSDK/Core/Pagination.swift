import Foundation

/// One page of a cursor-paginated list. Accepts the standard `{records, count,
/// total_count, next}` envelope and the `{data, has_more, next}` shape some
/// reads use.
public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    public let records: [Item]
    public let count: Int
    public let totalCount: Int?
    /// Opaque cursor for the next page; nil when exhausted.
    public let next: String?
    public let hasMore: Bool?

    public init(records: [Item], count: Int? = nil, totalCount: Int? = nil, next: String? = nil, hasMore: Bool? = nil) {
        self.records = records
        self.count = count ?? records.count
        self.totalCount = totalCount
        self.next = next
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case records, data, count, next
        case totalCount = "total_count"
        case hasMore = "has_more"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decodeIfPresent([Item].self, forKey: .records)
            ?? container.decodeIfPresent([Item].self, forKey: .data)
            ?? []
        records = items
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
        let cursor = try container.decodeIfPresent(String.self, forKey: .next)
        next = (cursor?.isEmpty ?? true) ? nil : cursor
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
    }
}

/// A lazy, auto-paging list. Iterate it with `for try await` to stream every
/// item across pages (each page is fetched only when reached), or call
/// `firstPage()` for one page with its envelope.
public struct Paginator<Item: Decodable & Sendable>: AsyncSequence, Sendable {
    public typealias Element = Item

    private let fetch: @Sendable (String?) async throws -> Page<Item>
    private let start: String?

    public init(start: String? = nil, fetch: @escaping @Sendable (String?) async throws -> Page<Item>) {
        self.start = start
        self.fetch = fetch
    }

    /// The first page, with no further pages fetched.
    public func firstPage() async throws -> Page<Item> {
        try await fetch(start)
    }

    /// The page at an explicit cursor.
    public func page(at cursor: String?) async throws -> Page<Item> {
        try await fetch(cursor)
    }

    /// Collect every item, or at most `limit` items.
    public func collect(limit: Int? = nil) async throws -> [Item] {
        var items: [Item] = []
        for try await item in self {
            items.append(item)
            if let limit, items.count >= limit { break }
        }
        return items
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(fetch: fetch, cursor: start)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let fetch: @Sendable (String?) async throws -> Page<Item>
        private var cursor: String?
        private var buffer: [Item] = []
        private var index = 0
        private var exhausted = false
        private var started = false

        init(fetch: @escaping @Sendable (String?) async throws -> Page<Item>, cursor: String?) {
            self.fetch = fetch
            self.cursor = cursor
        }

        public mutating func next() async throws -> Item? {
            while index >= buffer.count {
                if exhausted { return nil }
                let requested = cursor
                let page = try await fetch(requested)
                buffer = page.records
                index = 0
                started = true
                // A cursor that does not move is exhaustion, not another page.
                if let next = page.next, next != requested {
                    cursor = next
                } else {
                    exhausted = true
                }
            }
            defer { index += 1 }
            return buffer[index]
        }
    }
}

extension HTTPClient {
    /// A paginator over a `GET` list route that takes `next` as its cursor parameter.
    public func paginate<Item: Decodable & Sendable>(
        _ path: String,
        query: Query = Query(),
        start: String? = nil,
        as _: Item.Type = Item.self
    ) -> Paginator<Item> {
        Paginator(start: start) { [self] cursor in
            var pageQuery = query
            pageQuery.set("next", cursor)
            return try await json("GET", path, query: pageQuery, as: Page<Item>.self)
        }
    }
}
