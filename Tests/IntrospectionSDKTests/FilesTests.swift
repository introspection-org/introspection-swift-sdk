import Foundation
import XCTest
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

final class FilesTests: XCTestCase {
    func testListEncodesEveryFilterAndPaginates() async throws {
        let transport = MockTransport { request, index in
            index == 0
                ? .response(.json(#"{"records":[\#(fileJSON)],"count":1,"total_count":2,"next":"c2"}"#))
                : .response(.json(#"{"records":[\#(fileJSON)],"count":1,"total_count":2,"next":null}"#))
        }
        let client = makeClient(transport)
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let files = try await client.files.list(FileListParams(
            limit: 1, includeTotal: true, includeVersions: true, shareIds: ["s1", "s2"], name: "a.md",
            nameContains: "not", fileType: .upload, category: .memory, contentFormat: .markdown, versioned: false,
            storagePath: "p", taskId: "t1", conversationId: "c1", memberId: "m1", tag: "customer:acme",
            createdAfter: created, createdBefore: created, updatedAfter: created, updatedBefore: created
        )).collect()

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(transport.requests.count, 2)
        let first = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(first.request.method, "GET")
        XCTAssertEqual(first.path, "/v1/files")
        let q = first.query
        XCTAssertEqual(q["limit"], ["1"])
        XCTAssertEqual(q["include_total"], ["true"])
        XCTAssertEqual(q["include_versions"], ["true"])
        XCTAssertEqual(q["share_id"], ["s1", "s2"])
        XCTAssertEqual(q["name_contains"], ["not"])
        XCTAssertEqual(q["file_type"], ["upload"])
        XCTAssertEqual(q["category"], ["memory"])
        XCTAssertEqual(q["content_format"], ["markdown"])
        XCTAssertEqual(q["versioned"], ["false"])
        XCTAssertEqual(q["conversation_id"], ["c1"])
        XCTAssertEqual(q["member_id"], ["m1"])
        XCTAssertEqual(q["tag"], ["customer:acme"])
        XCTAssertEqual(q["created_after"], [ISO8601.format(created)])
        XCTAssertEqual(q["updated_before"], [ISO8601.format(created)])
        XCTAssertNil(q["next"])
        XCTAssertEqual(transport.requests[1].query["next"], ["c2"])

        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.name, "memory/user/notes.md")
        XCTAssertEqual(file.fileType, .filesystem)
        XCTAssertEqual(file.tags, ["customer:acme"])
        XCTAssertEqual(file.version, 3)
        XCTAssertEqual(file.sizeBytes, 42)
        XCTAssertEqual(file.metadata?["blob_checksum"], "abc")
        XCTAssertNil(file.taskId)
        XCTAssertNotNil(file.createdAt)
    }

    func testUploadSendsMultipart() async throws {
        let transport = MockTransport(status: 201, json: fileJSON)
        let client = makeClient(transport)
        _ = try await client.files.upload(FileUpload(
            data: Data("hello".utf8), filename: "notes.md", name: "memory/user/notes.md", fileType: .upload,
            metadata: ["source": "ios"], ttlSeconds: 3600
        ))
        let request = try XCTUnwrap(transport.last)
        XCTAssertEqual(request.request.method, "POST")
        XCTAssertEqual(request.path, "/v1/files")
        XCTAssertTrue(request.request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = request.bodyString
        XCTAssertTrue(body.contains(#"name="file"; filename="notes.md""#))
        XCTAssertTrue(body.contains("Content-Type: text/markdown"))
        XCTAssertTrue(body.contains("hello"))
        XCTAssertTrue(body.contains("name=\"name\"\r\n\r\nmemory/user/notes.md"))
        XCTAssertTrue(body.contains("name=\"file_type\"\r\n\r\nupload"))
        XCTAssertTrue(body.contains("name=\"metadata\"\r\n\r\n{\"source\":\"ios\"}"))
        XCTAssertTrue(body.contains("name=\"ttl_seconds\"\r\n\r\n3600"))
    }

    func testCreateTextSendsJSONAndRequiresATarget() async throws {
        let transport = MockTransport(status: 201, json: fileJSON)
        let client = makeClient(transport)
        _ = try await client.files.createText(FileCreateText(
            content: "# Notes", name: "notes.md", mimeType: "text/markdown", metadata: ["k": 1],
            expectedSha256: String(repeating: "a", count: 64), ttlSeconds: 60
        ))
        XCTAssertEqual(transport.last?.request.headers["Content-Type"], "application/json")
        XCTAssertEqual(transport.last?.json, [
            "content": "# Notes", "name": "notes.md", "mime_type": "text/markdown", "metadata": ["k": 1],
            "expected_sha256": .string(String(repeating: "a", count: 64)), "ttl_seconds": 60,
        ])

        do {
            _ = try await client.files.createText(FileCreateText(content: "x"))
            XCTFail("expected error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .invalidRequest)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testGetUpdateDeleteDownload() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return .response(HTTPResponse(status: 204, headers: [:], body: Data()))
            case (_, "/v1/files/f%2F1/content"), (_, "/v1/files/f/1/content"):
                return .response(HTTPResponse(status: 200, headers: ["content-type": "text/plain", "x-version": "3"], body: Data("bytes".utf8)))
            default: return .response(.json(fileJSON))
            }
        }
        let client = makeClient(transport)
        _ = try await client.files.get("f1", shareId: "s1")
        XCTAssertEqual(transport.last?.path, "/v1/files/f1")
        XCTAssertEqual(transport.last?.query["share_id"], ["s1"])

        _ = try await client.files.update("f1", FileUpdate(name: "b.md", tags: []))
        XCTAssertEqual(transport.last?.request.method, "PATCH")
        XCTAssertEqual(transport.last?.json, ["name": "b.md", "tags": []])

        try await client.files.delete("f1")
        XCTAssertEqual(transport.last?.request.method, "DELETE")

        let data = try await client.files.download("f/1")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "bytes")
        XCTAssertTrue(transport.last?.request.url.absoluteString.hasSuffix("/v1/files/f%2F1/content") ?? false)

        let stream = try await client.files.downloadStream("f/1")
        XCTAssertEqual(stream.headers["x-version"], "3")
        let streamed = try await stream.collect()
        XCTAssertEqual(String(decoding: streamed, as: UTF8.self), "bytes")
        XCTAssertEqual(transport.last?.request.headers["Accept"], "*/*")
    }

    func testVersions() async throws {
        let transport = MockTransport { request, _ in
            request.url.path.hasSuffix("/versions") && request.method == "GET"
                ? .response(.json(#"{"records":[\#(fileJSON)],"count":1,"total_count":null,"next":null}"#))
                : .response(.json(fileJSON))
        }
        let client = makeClient(transport)
        let page = try await client.files.versions.list("f1", FileVersionListParams(limit: 5)).firstPage()
        XCTAssertEqual(page.records.count, 1)
        XCTAssertEqual(transport.last?.path, "/v1/files/f1/versions")
        XCTAssertEqual(transport.last?.query["limit"], ["5"])

        _ = try await client.files.versions.get("f1", "v2")
        XCTAssertEqual(transport.last?.path, "/v1/files/f1/versions/v2")

        _ = try await client.files.versions.createText("f1", FileCreateText(content: "new", expectedSha256: "ab"))
        XCTAssertEqual(transport.last?.request.method, "POST")
        XCTAssertEqual(transport.last?.path, "/v1/files/f1/versions")
        XCTAssertEqual(transport.last?.json, ["content": "new", "file_id": "f1", "expected_sha256": "ab"])

        _ = try await client.files.versions.create("f1", FileUpload(data: Data([0, 1]), filename: "a.bin", fileType: .upload))
        let body = transport.last?.bodyString ?? ""
        XCTAssertTrue(body.contains("Content-Type: application/octet-stream"))
        XCTAssertFalse(body.contains("file_type"))
    }
}
