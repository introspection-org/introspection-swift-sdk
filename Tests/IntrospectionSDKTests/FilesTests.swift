import Foundation
import Testing

@testable import IntrospectionSDK

private let fileJSON = #"""
    {"id":"0199a1b2-0000-7000-8000-000000000001","org_id":"0199a1b2-0000-7000-8000-0000000000aa",
     "project_id":"0199a1b2-0000-7000-8000-0000000000bb","created_at":"2026-10-01T12:00:00.123456Z",
     "updated_at":"2026-10-01T12:00:01Z","name":"memory/user/notes.md","file_type":"filesystem",
     "storage_path":"org/proj/files/x/notes.md","mime_type":"text/markdown",
     "metadata":{"original_filename":"notes.md","blob_checksum":"abc"},"tags":["customer:acme"],
     "member_id":"0199a1b2-0000-7000-8000-0000000000cc","task_id":null,"generated_output_task_id":null,
     "size_bytes":42,"version":3,"parent_id":"0199a1b2-0000-7000-8000-000000000000",
     "storage_version_id":"v3","expires_at":null,"some_new_field":true}
    """#

@Suite struct FilesTests {
    @Test func listEncodesEveryFilterAndPaginates() async throws {
        let transport = MockTransport { request, index in
            index == 0
                ? .response(.json(#"{"records":[\#(fileJSON)],"count":1,"total_count":2,"next":"c2"}"#))
                : .response(.json(#"{"records":[\#(fileJSON)],"count":1,"total_count":2,"next":null}"#))
        }
        let client = makeClient(transport)
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let files = try await client.files.list(
            FileListParams(
                limit: 1, includeTotal: true, includeVersions: true, shareIds: ["s1", "s2"], name: "a.md",
                nameContains: "not", fileType: .upload, category: .memory, contentFormat: .markdown, versioned: false,
                storagePath: "p", taskId: "t1", conversationId: "c1", memberId: "m1", tag: "customer:acme",
                createdAfter: created, createdBefore: created, updatedAfter: created, updatedBefore: created
            )
        ).collect()

        #expect(files.count == 2)
        #expect(transport.requests.count == 2)
        let first = try #require(transport.requests.first)
        #expect(first.request.method == "GET")
        #expect(first.path == "/v1/files")
        let q = first.query
        #expect(q["limit"] == ["1"])
        #expect(q["include_total"] == ["true"])
        #expect(q["include_versions"] == ["true"])
        #expect(q["share_id"] == ["s1", "s2"])
        #expect(q["name_contains"] == ["not"])
        #expect(q["file_type"] == ["upload"])
        #expect(q["category"] == ["memory"])
        #expect(q["content_format"] == ["markdown"])
        #expect(q["versioned"] == ["false"])
        #expect(q["conversation_id"] == ["c1"])
        #expect(q["member_id"] == ["m1"])
        #expect(q["tag"] == ["customer:acme"])
        #expect(q["created_after"] == [ISO8601.format(created)])
        #expect(q["updated_before"] == [ISO8601.format(created)])
        #expect(q["next"] == nil)
        #expect(transport.requests[1].query["next"] == ["c2"])

        let file = try #require(files.first)
        #expect(file.name == "memory/user/notes.md")
        #expect(file.fileType == .filesystem)
        #expect(file.tags == ["customer:acme"])
        #expect(file.version == 3)
        #expect(file.sizeBytes == 42)
        #expect(file.metadata?["blob_checksum"] == "abc")
        #expect(file.taskId == nil)
        #expect(file.createdAt != nil)
    }

    @Test func listEncodesMetadataSortAndOrderAndKeepsThemAcrossPages() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? .response(.json(#"{"records":[\#(fileJSON)],"count":1,"next":"c2"}"#))
                : .response(.json(#"{"records":[],"count":0,"next":null}"#))
        }
        let files = try await makeClient(transport).files.list(
            FileListParams(tag: "ark:goal", metadata: ["status": "open", "feed_id": "f:1"], sort: .updatedAt, order: .asc)
        ).collect()

        #expect(files.count == 1)
        #expect(transport.requests.count == 2)
        for request in transport.requests {
            #expect(request.query["metadata"] == ["feed_id:f:1", "status:open"])
            #expect(request.query["sort"] == ["updated_at"])
            #expect(request.query["direction"] == ["asc"])
            #expect(request.query["tag"] == ["ark:goal"])
        }
        #expect(transport.requests[1].query["next"] == ["c2"])
    }

    @Test func listOmitsMetadataSortAndOrderByDefault() async throws {
        let transport = MockTransport { _, _ in .response(.json(#"{"records":[],"count":0}"#)) }
        _ = try await makeClient(transport).files.list(FileListParams(metadata: [:])).firstPage()

        let q = try #require(transport.requests.first).query
        #expect(q["metadata"] == nil)
        #expect(q["sort"] == nil)
        #expect(q["direction"] == nil)
        #expect(FileSortField.createdAt.rawValue == "created_at")
    }

    @Test func uploadSendsMultipart() async throws {
        let transport = MockTransport(status: 201, json: fileJSON)
        let client = makeClient(transport)
        _ = try await client.files.upload(
            FileUpload(
                data: Data("hello".utf8), filename: "notes.md", name: "memory/user/notes.md", fileType: .upload,
                metadata: ["source": "ios"], ttlSeconds: 3600
            ))
        let request = try #require(transport.last)
        #expect(request.request.method == "POST")
        #expect(request.path == "/v1/files")
        #expect(request.request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = request.bodyString
        #expect(body.contains(#"name="file"; filename="notes.md""#))
        #expect(body.contains("Content-Type: text/markdown"))
        #expect(body.contains("hello"))
        #expect(body.contains("name=\"name\"\r\n\r\nmemory/user/notes.md"))
        #expect(body.contains("name=\"file_type\"\r\n\r\nupload"))
        #expect(body.contains("name=\"metadata\"\r\n\r\n{\"source\":\"ios\"}"))
        #expect(body.contains("name=\"ttl_seconds\"\r\n\r\n3600"))
    }

    @Test func createTextSendsJSONAndRequiresATarget() async throws {
        let transport = MockTransport(status: 201, json: fileJSON)
        let client = makeClient(transport)
        _ = try await client.files.createText(
            FileCreateText(
                content: "# Notes", name: "notes.md", mimeType: "text/markdown", metadata: ["k": 1],
                expectedSha256: String(repeating: "a", count: 64), ttlSeconds: 60
            ))
        #expect(transport.last?.request.headers["Content-Type"] == "application/json")
        #expect(
            transport.last?.json == [
                "content": "# Notes", "name": "notes.md", "mime_type": "text/markdown", "metadata": ["k": 1],
                "expected_sha256": .string(String(repeating: "a", count: 64)), "ttl_seconds": 60,
            ])

        let error = try await #require(throws: IntrospectionError.self) { try await client.files.createText(FileCreateText(content: "x")) }
        #expect(error.kind == .invalidRequest)
        #expect(transport.requests.count == 1)
    }

    @Test func createStampsTagsInBothShapes() async throws {
        let transport = MockTransport(status: 201, json: fileJSON)
        let client = makeClient(transport)
        _ = try await client.files.createText(FileCreateText(content: "goal", name: "ark/goals/g1.md", tags: ["ark:goal"]))
        #expect(transport.last?.json == ["content": "goal", "name": "ark/goals/g1.md", "tags": ["ark:goal"]])

        _ = try await client.files.upload(
            FileUpload(data: Data("story".utf8), filename: "s1.md", tags: ["ark:story", "feed:f1"]))
        let body = try #require(transport.last).bodyString
        #expect(body.contains("name=\"tags\"\r\n\r\nark:story\r\n"))
        #expect(body.contains("name=\"tags\"\r\n\r\nfeed:f1\r\n"))

        _ = try await client.files.upload(FileUpload(data: Data("x".utf8), filename: "x.md"))
        #expect(!(try #require(transport.last).bodyString.contains("name=\"tags\"")))
    }

    @Test func getUpdateDeleteDownload() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            case (_, "/v1/files/f%2F1/content"), (_, "/v1/files/f/1/content"):
                return .response(
                    HTTPResponse(status: 200, headers: ["content-type": "text/plain", "x-version": "3"], body: Data("bytes".utf8)))
            default: return .response(.json(fileJSON))
            }
        }
        let client = makeClient(transport)
        _ = try await client.files.get("f1", shareId: "s1")
        #expect(transport.last?.path == "/v1/files/f1")
        #expect(transport.last?.query["share_id"] == ["s1"])

        _ = try await client.files.update("f1", FileUpdate(name: "b.md", tags: []))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["name": "b.md", "tags": []])

        try await client.files.delete("f1")
        #expect(transport.last?.request.method == "DELETE")

        let data = try await client.files.download("f/1")
        #expect(String(decoding: data, as: UTF8.self) == "bytes")
        #expect(transport.last?.request.url.absoluteString.hasSuffix("/v1/files/f%2F1/content") ?? false)

        let stream = try await client.files.downloadStream("f/1")
        #expect(stream.headers["x-version"] == "3")
        let streamed = try await stream.collect()
        #expect(String(decoding: streamed, as: UTF8.self) == "bytes")
        #expect(transport.last?.request.headers["Accept"] == "*/*")
    }

    @Test func versions() async throws {
        let transport = MockTransport { request, _ in
            request.url.path.hasSuffix("/versions") && request.method == "GET"
                ? .response(.json(#"{"records":[\#(fileJSON)],"count":1,"total_count":null,"next":null}"#))
                : .response(.json(fileJSON))
        }
        let client = makeClient(transport)
        let page = try await client.files.versions.list("f1", FileVersionListParams(limit: 5)).firstPage()
        #expect(page.records.count == 1)
        #expect(transport.last?.path == "/v1/files/f1/versions")
        #expect(transport.last?.query["limit"] == ["5"])

        _ = try await client.files.versions.get("f1", "v2")
        #expect(transport.last?.path == "/v1/files/f1/versions/v2")

        _ = try await client.files.versions.createText("f1", FileCreateText(content: "new", expectedSha256: "ab"))
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/files/f1/versions")
        #expect(transport.last?.json == ["content": "new", "file_id": "f1", "expected_sha256": "ab"])

        _ = try await client.files.versions.create("f1", FileUpload(data: Data([0, 1]), filename: "a.bin", fileType: .upload))
        let body = transport.last?.bodyString ?? ""
        #expect(body.contains("Content-Type: application/octet-stream"))
        #expect(!body.contains("file_type"))
    }
}
