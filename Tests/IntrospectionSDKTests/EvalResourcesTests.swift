import Foundation
import Testing

@testable import IntrospectionSDK

private let imageJSON = #"""
    {"id": "img-1", "kind": "service", "name": "hello-mcp/mcp-server", "content_id": "sha256:c0ffee",
     "source_kind": "mirror", "source": {"kind": "mirror", "reference": "ghcr.io/acme/mcp@sha256:abc"},
     "build_platform": "linux/amd64", "service": null, "repository_id": null, "git_sha": null, "git_ref": null, "path": "",
     "runtime_id": null, "task_id": null, "trigger": null, "base_image_digest": null, "base_image_tag": null,
     "external_artifacts": null, "external_image_name": null, "status": "ready",
     "image_ref": "registry.dp.test/hello-mcp/mcp-server", "image_digest": "sha256:def", "size_bytes": 1048576,
     "warnings": [], "error": null, "scan_status": "passed", "scan_started_at": null, "scanned_at": "2026-10-19T00:01:00Z",
     "scan_db_built_at": null, "scan_summary": {"critical": 0}, "scan_report_file_id": null,
     "created_at": "2026-10-19T00:00:00Z", "updated_at": "2026-10-19T00:01:00Z", "started_at": null,
     "finished_at": "2026-10-19T00:01:00Z", "last_used_at": null, "evicted_at": null, "retired_at": null}
    """#

private let commandJSON = #"""
    {"id": "cmd-1", "task_id": "t-1", "kind": "exec", "spec": {"kind": "exec", "command": ["ls", "-la"], "timeout_seconds": 300},
     "status": "completed", "exit_code": 0, "stdout": "total 0\n", "stderr": "", "output_file_id": null, "error": null,
     "created_at": "2026-10-19T00:00:00Z", "updated_at": "2026-10-19T00:00:02Z", "started_at": "2026-10-19T00:00:01Z",
     "finished_at": "2026-10-19T00:00:02Z"}
    """#

@Suite struct EvalResourcesTests {
    // MARK: Images

    @Test func imagesListFiltersAndDecodes() async throws {
        let transport = MockTransport(json: #"{"records": [\#(imageJSON)], "count": 1, "next": "n2"}"#)
        let page = try await makeClient(transport).images.list(
            ImageListParams(kind: .service, status: .ready, name: "hello-mcp/mcp-server", runtimeId: "rt-1", limit: 10)
        ).firstPage()
        #expect(transport.last?.request.url.host == "dp.test")
        #expect(transport.last?.path == "/v1/images")
        #expect(
            transport.last?.query == [
                "kind": ["service"], "status": ["ready"], "name": ["hello-mcp/mcp-server"], "runtime_id": ["rt-1"], "limit": ["10"],
            ])
        #expect(page.next == "n2")
        let image = try #require(page.records.first)
        #expect(image.sourceKind == .mirror)
        #expect(image.source?["reference"] == "ghcr.io/acme/mcp@sha256:abc")
        #expect(image.scanStatus == .passed)
        #expect(image.scanSummary?["critical"] == 0)
        #expect(image.sizeBytes == 1_048_576)
        #expect(image.pullReference == "registry.dp.test/hello-mcp/mcp-server@sha256:def")
        #expect(IntrospectionImage(id: "x").pullReference == nil)
    }

    @Test(arguments: [
        (
            ImageSource.context(fileId: "f-1", dockerfile: "docker/Dockerfile", platform: "linux/arm64"),
            JSONValue.object(["kind": "context", "file_id": "f-1", "dockerfile": "docker/Dockerfile", "platform": "linux/arm64"])
        ),
        (ImageSource.context(fileId: "f-1"), JSONValue.object(["kind": "context", "file_id": "f-1"])),
        (
            ImageSource.mirror(reference: "ghcr.io/acme/mcp@sha256:abc"),
            JSONValue.object(["kind": "mirror", "reference": "ghcr.io/acme/mcp@sha256:abc"])
        ),
    ])
    func imageCreateTagsItsSource(source: ImageSource, expected: JSONValue) async throws {
        let transport = MockTransport(status: 201, json: imageJSON)
        _ = try await makeClient(transport).images.create(ImageCreate(name: "hello-mcp/mcp-server", source: source))
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/images")
        #expect(transport.last?.json == ["name": "hello-mcp/mcp-server", "source": expected])
    }

    @Test func imageCreateSendsProvenanceAndScan() async throws {
        let transport = MockTransport(status: 201, json: imageJSON)
        _ = try await makeClient(transport).images.create(
            ImageCreate(
                name: "hello-mcp/mcp-server", source: .mirror(reference: "ghcr.io/acme/mcp@sha256:abc"),
                provenance: ImageProvenance(service: "mcp", repositoryId: "repo-1", gitSha: "abc", path: "services/mcp"), scan: false))
        #expect(
            transport.last?.json == [
                "name": "hello-mcp/mcp-server", "source": ["kind": "mirror", "reference": "ghcr.io/acme/mcp@sha256:abc"],
                "provenance": ["service": "mcp", "repository_id": "repo-1", "git_sha": "abc", "path": "services/mcp"], "scan": false,
            ])
    }

    @Test func imageGetAndDelete() async throws {
        let transport = MockTransport { request, _ in
            request.method == "DELETE" ? .response(HTTPResponse(status: 204, headers: [:], body: Data())) : .response(.json(imageJSON))
        }
        let images = makeClient(transport).images
        let image = try await images.get("img-1")
        #expect(image.status == .ready)
        #expect(transport.last?.path == "/v1/images/img-1")
        try await images.delete("img-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.path == "/v1/images/img-1")
    }

    @Test func theRunnerExposesImages() async throws {
        let transport = MockTransport(json: imageJSON)
        let runner = try Runner(
            spec: RunnerSpec(sessionId: "s", deployment: RunnerDeployment(endpoint: "https://dp-runner.test"), sessionToken: "tok"),
            transport: transport)
        _ = try await runner.images.get("img-1")
        #expect(transport.last?.request.url.absoluteString == "https://dp-runner.test/v1/images/img-1")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer tok")
    }

    // MARK: Task commands

    @Test(arguments: [
        (
            TaskCommandSpec.exec(command: ["ls", "-la"], cwd: "/work", timeoutSeconds: 30, service: "db"),
            JSONValue.object(["kind": "exec", "command": ["ls", "-la"], "cwd": "/work", "timeout_seconds": 30, "service": "db"])
        ),
        (TaskCommandSpec.exec(command: ["true"]), JSONValue.object(["kind": "exec", "command": ["true"]])),
        (
            TaskCommandSpec.upload(fileId: "f-1", path: "/work/in.txt"),
            JSONValue.object(["kind": "upload", "file_id": "f-1", "path": "/work/in.txt"])
        ),
        (TaskCommandSpec.download(path: "/work/out.txt"), JSONValue.object(["kind": "download", "path": "/work/out.txt"])),
        (
            TaskCommandSpec.download(path: "/work/out.txt", service: "db"),
            JSONValue.object(["kind": "download", "path": "/work/out.txt", "service": "db"])
        ),
    ])
    func commandCreateTagsItsKind(spec: TaskCommandSpec, expected: JSONValue) async throws {
        let transport = MockTransport(status: 201, json: commandJSON)
        let command = try await makeClient(transport).tasks.commands.create("t-1", spec)
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/tasks/t-1/commands")
        #expect(transport.last?.json == expected)
        #expect(command.status?.isTerminal == true)
        #expect(command.exitCode == 0)
        #expect(command.stdout == "total 0\n")
        #expect(command.spec?["command"] == ["ls", "-la"])
    }

    @Test func commandListFiltersByStatus() async throws {
        let transport = MockTransport(json: #"{"records": [\#(commandJSON)], "count": 1}"#)
        let all = try await makeClient(transport).tasks.commands.list("t-1", TaskCommandListParams(status: .completed, limit: 5)).collect()
        #expect(all.map(\.id) == ["cmd-1"])
        #expect(transport.last?.path == "/v1/tasks/t-1/commands")
        #expect(transport.last?.query == ["status": ["completed"], "limit": ["5"]])
        #expect(TaskCommandStatus.running.isTerminal == false)
        #expect(TaskCommandStatus.failed.isTerminal)
    }

    @Test func commandGetCapsTheWaitBelowTheRequestTimeout() async throws {
        let transport = MockTransport(json: commandJSON)
        let commands = makeClient(transport).tasks.commands
        _ = try await commands.get("t-1", "cmd-1")
        #expect(transport.last?.path == "/v1/tasks/t-1/commands/cmd-1")
        #expect(transport.last?.query == [:])
        _ = try await commands.get("t-1", "cmd-1", waitSeconds: 20)
        #expect(transport.last?.query == ["wait_seconds": ["20"]])
        _ = try await commands.get("t-1", "cmd-1", waitSeconds: 600)
        #expect(transport.last?.query == ["wait_seconds": ["\(TaskCommandsAPI.maxWaitSeconds)"]])

        let short = HTTPClient(
            baseURL: URL(string: "https://dp.test")!, transport: transport, options: HTTPClient.Options(timeout: 30))
        _ = try await TaskCommandsAPI(http: short).get("t-1", "cmd-1", waitSeconds: 600)
        #expect(transport.last?.query == ["wait_seconds": ["20"]])
    }

    @Test(
        arguments: [
            (10, 60, 10), (55, 60, 50), (55, nil, 50), (55, 30, 20), (5, 8, 0), (-3, 60, 0),
        ] as [(Int, TimeInterval?, Int)])
    func cappedWait(requested: Int, timeout: TimeInterval?, expected: Int) {
        #expect(TaskCommandsAPI.cappedWait(requested, timeout: timeout) == expected)
        #expect(TaskCommandsAPI.maxWaitSeconds < Int(HTTPClient.Options().timeout ?? 0))
    }
}
