import Foundation

/// The CRUD routes of a Control Plane collection that takes the optional `?project=` selector.
struct ProjectScopedCollection: Sendable {
    let http: HTTPClient
    let path: String

    func itemPath(_ id: String) -> String { "\(path)/\(pathSegment(id))" }

    /// The collection nested under one item, such as `/v1/applications/{id}/secrets`.
    func child(_ id: String, _ name: String) -> ProjectScopedCollection {
        ProjectScopedCollection(http: http, path: "\(itemPath(id))/\(name)")
    }

    func list<Item: Decodable & Sendable>(project: String?, limit: Int?, next: String?, filters: Query = Query()) -> Paginator<Item> {
        var query = cpProjectQuery(project)
        for item in filters.items { query.add(item.name, item.value) }
        query.add("limit", limit)
        return http.paginate(path, query: query, start: next)
    }

    func get<Item: Decodable>(_ id: String, project: String?) async throws -> Item {
        try await http.json("GET", itemPath(id), query: cpProjectQuery(project))
    }

    func create<Item: Decodable>(_ body: some Encodable, project: String?) async throws -> Item {
        try await http.json("POST", path, query: cpProjectQuery(project), body: .encode(body))
    }

    func update<Item: Decodable>(_ id: String, _ body: some Encodable, project: String?) async throws -> Item {
        try await http.json("PATCH", itemPath(id), query: cpProjectQuery(project), body: .encode(body))
    }

    func delete(_ id: String, project: String?, expiresIn: Int? = nil) async throws {
        var query = cpProjectQuery(project)
        query.add("expires_in", expiresIn)
        try await http.empty("DELETE", itemPath(id), query: query)
    }
}
