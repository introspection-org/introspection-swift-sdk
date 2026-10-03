import Foundation
import Testing

@testable import IntrospectionSDK

private let runtimeJSON = #"""
    {
      "id": "0195c0de-0000-7000-8000-000000000001",
      "org_id": "0195c0de-0000-7000-8000-0000000000a1",
      "project_id": "0195c0de-0000-7000-8000-0000000000b1",
      "runtime_group_id": "0195c0de-0000-7000-8000-0000000000c1",
      "name": "Customer agent",
      "slug": "customer-agent",
      "description": null,
      "kind": "byor",
      "llm_mode": "managed",
      "config_json": {"connectors": [{"slug": "gmail"}]},
      "recipe_id": "0195c0de-0000-7000-8000-0000000000d1",
      "recipe_kind": "production",
      "recipe_ref": "main",
      "environments": ["production", "staging"],
      "image_build_status": "ready",
      "image_build_error_message": null,
      "image_build_metadata": {"image_tag": "sha-abc", "size_bytes": 1024},
      "created_by_member_id": "0195c0de-0000-7000-8000-0000000000e1",
      "yanked_at": null,
      "yanked_reason": null,
      "environment_ref": {"production": "main"},
      "created_at": "2026-09-01T10:00:00.123456Z",
      "updated_at": "2026-09-02T10:00:00Z",
      "some_new_field": 42
    }
    """#

private func specJSON(endpoint: String = "https://dp-gcp01.test", token: String = "locator-1", session: String = "sess-1") -> String {
    #"""
    {
      "session_id": "\#(session)",
      "deployment": {"endpoint": "\#(endpoint)", "slug": "gcp01", "region": "us-east1"},
      "session_token": "\#(token)",
      "expires_at": "2026-10-03T13:00:00Z",
      "runtime_context": {
        "runtime_id": "0195c0de-0000-7000-8000-000000000001",
        "runtime_group_id": "0195c0de-0000-7000-8000-0000000000c1",
        "experiment_id": null,
        "recipe_id": "0195c0de-0000-7000-8000-0000000000d1",
        "recipe_repository_id": null,
        "recipe_git_ref": "main",
        "recipe_git_commit_sha": "abc123",
        "arm_label": null,
        "agent_name": "agent",
        "identity": {"user_id": "u_42", "anonymous_id": null, "conversation_id": null, "tags": null},
        "caller": {"ip": "1.2.3.4", "app": {"name": "ios"}}
      }
    }
    """#
}

@Suite struct RunnerTests {
    @Test func runtimeListEncodesFiltersAndDecodes() async throws {
        let transport = MockTransport(json: #"{"records": [\#(runtimeJSON)], "count": 1, "next": null}"#)
        let client = makeClient(transport)
        let page = try await client.runtimes.list(
            RuntimeListParams(
                project: "acme", runtime: "customer-agent", environment: .staging, limit: 5, next: "c1"
            )
        ).firstPage()
        let request = try #require(transport.last)
        #expect(request.request.method == "GET")
        #expect(request.request.url.host == "cp.test")
        #expect(request.path == "/v1/runtimes")
        #expect(request.query["project"] == ["acme"])
        #expect(request.query["runtime"] == ["customer-agent"])
        #expect(request.query["environment"] == ["staging"])
        #expect(request.query["limit"] == ["5"])
        #expect(request.query["next"] == ["c1"])
        #expect(request.request.headers["Authorization"] == "Bearer cp-token")

        let runtime = try #require(page.records.first)
        #expect(runtime.slug == "customer-agent")
        #expect(runtime.kind == .byor)
        #expect(runtime.environments == [.production, .staging])
        #expect(runtime.imageBuildStatus == .ready)
        #expect(runtime.imageBuildMetadata?.sizeBytes == 1024)
        #expect(runtime.environmentRef?["production"] == "main")
        #expect(runtime.configJson?["connectors"]?[0]?["slug"]?.stringValue == "gmail")
        #expect(runtime.createdAt != nil)
    }

    @Test func getRuntimeWithInclude() async throws {
        let body = runtimeJSON.replacingOccurrences(
            of: #""some_new_field": 42"#,
            with:
                #""mcp_requirements": [{"environment": "production", "state": "authorization_required", "mcp_server_id": "gmail", "connection_status": "refresh_failed", "candidate_connector_ids": []}]"#
        )
        let transport = MockTransport(json: body)
        let runtime = try await makeClient(transport).runtimes.get("rt/1", project: "acme", include: [.mcpRequirements])
        #expect(try #require(transport.last).request.url.absoluteString.hasPrefix("https://cp.test/v1/runtimes/rt%2F1?"))
        #expect(transport.last?.query["include"] == ["mcp_requirements"])
        #expect(runtime.mcpRequirements?.first?.connectionStatus == .refreshFailed)
        #expect(runtime.mcpRequirements?.first?.mcpServerId == "gmail")
    }

    @Test func resolveAsksForNewestOneAndThrowsNotFound() async throws {
        let transport = MockTransport(json: #"{"records": [], "count": 0}"#)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).runtimes.resolve("missing", project: "acme")
        }
        #expect(error.kind == .notFound)
        #expect(error.message == "Runtime 'missing' not found in project acme")
        #expect(transport.requests.count == 1)
        #expect(transport.last?.query["runtime"] == ["missing"])
        #expect(transport.last?.query["limit"] == ["1"])
    }

    @Test func runtimeHandleResolvesOnEveryRunAndBuildsRunner() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("GET", "/v1/runtimes"):
                return .response(.json(#"{"records": [\#(runtimeJSON)], "count": 1}"#))
            case ("POST", "/v1/runtimes/0195c0de-0000-7000-8000-000000000001/run"):
                return .response(.json(specJSON()))
            default:
                return .response(.json(#"{"records": [], "count": 0}"#))
            }
        }
        let client = makeClient(transport)
        let request = RunRequest(
            identity: RunnerIdentity(userId: "u_42", tags: ["tier:gold"]),
            caller: RunCaller(ip: "1.2.3.4", library: RunCallerLibrary(name: "introspection-swift"), extra: ["app": ["name": "ios"]]),
            agentName: "support",
            ttlSeconds: 600,
            scope: "tasks:read tasks:write",
            environment: .staging,
            bindingsRequired: false
        )
        let handle = client.runtimes("customer-agent")
        let runner = try await handle.run(request)
        _ = try await client.runtime("customer-agent").run(request)

        let lists = transport.requests.filter { $0.path == "/v1/runtimes" }
        #expect(lists.count == 2, "the selector is resolved on every run")

        let post = try #require(transport.requests.first { $0.request.method == "POST" })
        let body = try #require(post.json)
        #expect(body["identity"]?["user_id"]?.stringValue == "u_42")
        #expect(body["identity"]?["tags"]?[0]?.stringValue == "tier:gold")
        #expect(body["identity"]?["anonymous_id"] == nil, "nil fields are omitted")
        #expect(body["caller"]?["ip"]?.stringValue == "1.2.3.4")
        #expect(body["caller"]?["app"]?["name"]?.stringValue == "ios")
        #expect(body["caller"]?["library"]?["name"]?.stringValue == "introspection-swift")
        #expect(body["agent_name"]?.stringValue == "support")
        #expect(body["ttl_seconds"]?.intValue == 600)
        #expect(body["scope"]?.stringValue == "tasks:read tasks:write")
        #expect(body["environment"]?.stringValue == "staging")
        #expect(body["bindings_required"]?.boolValue == false)
        #expect(body["recipe_id"] == nil)

        #expect(runner.sessionId == "sess-1")
        #expect(runner.sessionToken == "locator-1")
        #expect(runner.deployment.slug == "gcp01")
        #expect(runner.deployment.region == "us-east1")
        #expect(runner.runtimeId == "0195c0de-0000-7000-8000-000000000001")
        #expect(runner.runtimeGroupId == "0195c0de-0000-7000-8000-0000000000c1")
        #expect(runner.experimentId == nil)
        #expect(runner.context.identity?.userId == "u_42")
        #expect(runner.context.caller?.extra["app"]?["name"]?.stringValue == "ios")
        #expect(runner.expiresAt == ISO8601.parse("2026-10-03T13:00:00Z"))
        #expect(runner.source == .runtime(id: "0195c0de-0000-7000-8000-000000000001", request: request, project: nil))
    }

    @Test func runnerTalksToDeploymentWithSessionToken() async throws {
        let transport = MockTransport { request, _ in
            request.url.host == "cp.test" ? .response(.json(specJSON())) : .response(.json(#"{"ok": true}"#))
        }
        let client = IntrospectionClient(
            configuration: .init(
                controlPlaneURL: URL(string: "https://cp.test")!,
                dataPlaneURL: URL(string: "https://dp.test")!,
                controlPlaneCredentials: BearerToken("cp-token"),
                transport: transport,
                options: .init(maxRetries: 0, additionalHeaders: ["X-Custom": "1"], userAgent: "test-agent")
            ))
        let runner = try await client.runtimes.run("rt-1", project: "acme")
        #expect(transport.last?.query["project"] == ["acme"])
        #expect(transport.last?.json == [:], "an empty run request encodes as {}")

        let connection: any DataPlaneConnection = runner
        _ = try await connection.dataPlane.json("GET", "/v1/tasks", as: JSONValue.self)
        let dp = try #require(transport.last)
        #expect(dp.request.url.absoluteString == "https://dp-gcp01.test/v1/tasks")
        #expect(dp.request.headers["Authorization"] == "Bearer locator-1")
        #expect(dp.request.headers["User-Agent"] == "test-agent")
        #expect(dp.request.headers["X-Custom"] == "1")
        #expect(runner.dataPlaneEndpoint.absoluteString == "https://dp-gcp01.test")
    }

    @Test func refreshRepointsRunnerAtFreshSession() async throws {
        let transport = MockTransport { request, index in
            if request.url.host == "cp.test" {
                return index == 0
                    ? .response(.json(specJSON()))
                    : .response(.json(specJSON(endpoint: "https://dp-gcp02.test/", token: "locator-2", session: "sess-2")))
            }
            return .response(.json("{}"))
        }
        let client = makeClient(transport)
        let request = RunRequest(identity: RunnerIdentity(userId: "u_1"))
        let runner = try await client.runtimes.run("rt-1", request, project: "acme")
        try await runner.refresh()
        let refresh = try #require(transport.requests.last)
        #expect(refresh.path == "/v1/runtimes/rt-1/run")
        #expect(refresh.query["project"] == ["acme"])
        #expect(refresh.json?["identity"]?["user_id"]?.stringValue == "u_1")
        #expect(runner.sessionId == "sess-2")

        _ = try await runner.dataPlane.json("GET", "/v1/files", as: JSONValue.self)
        #expect(transport.last?.request.url.absoluteString == "https://dp-gcp02.test/v1/files")
        #expect(transport.last?.request.headers["Authorization"] == "Bearer locator-2")
    }

    @Test func closeFailsRequestsBeforeTheNetwork() async throws {
        let transport = MockTransport(json: specJSON())
        let runner = try await makeClient(transport).runtimes.run("rt-1")
        runner.close()
        #expect(runner.isClosed)
        let before = transport.requests.count
        let request = try await #require(throws: IntrospectionError.self) {
            try await runner.dataPlane.json("GET", "/v1/tasks", as: JSONValue.self)
        }
        #expect(request.kind == .runnerExpired)
        #expect(request.code == "runner_expired")
        let refresh = try await #require(throws: IntrospectionError.self) { try await runner.refresh() }
        #expect(refresh.kind == .runnerExpired)
        #expect(transport.requests.count == before)
    }

    @Test func runnerFromBareSpec() async throws {
        let spec = try JSONCoding.decoder.decode(RunnerSpec.self, from: Data(specJSON().utf8))
        let roundTrip = try JSONCoding.decoder.decode(RunnerSpec.self, from: JSONCoding.encoder.encode(spec))
        #expect(roundTrip == spec)

        let transport = MockTransport(json: "{}")
        let runner = try Runner(spec: spec, transport: transport)
        _ = try await runner.dataPlane.json("GET", "/v1/conversations", as: JSONValue.self)
        #expect(transport.last?.request.url.absoluteString == "https://dp-gcp01.test/v1/conversations")
        #expect(runner.source == nil)
        let error = try await #require(throws: IntrospectionError.self) { try await runner.refresh() }
        #expect(error.kind == .invalidRequest)

        var bad = spec
        bad.deployment.endpoint = "not a url"
        #expect(throws: (any Error).self) { try Runner(spec: bad, transport: transport) }
    }

    @Test func experimentRunAndLifecycle() async throws {
        let experimentJSON = #"""
            {
              "id": "exp-1", "org_id": "o", "project_id": "p", "name": "Shorter prompt",
              "description": null, "runtime_group_id": "g", "environment": "production",
              "goal_json": {"kind": "composite", "direction": "maximize", "components": [
                {"source": "judge", "judge_id": "j1", "judge_definition_hash": "h", "weight": 1.0, "guard": {"min": 0.2}},
                {"source": "telemetry", "column": "latency_ms", "aggregation": "p95", "weight": 0.5, "guard": null}
              ]},
              "scoring_interval_seconds": 300, "hash_key_fields": ["user_id"], "sample_rate": 0.5,
              "status": "running", "routing_strategy": "beta_sample", "started_at": "2026-10-01T00:00:00Z",
              "ended_at": null, "posterior_json": {"a": {"alpha": 2}}, "weights_json": {"arm-1": 60, "arm-2": 40},
              "arms": [{"id": "arm-1", "runtime_id": "rt-1", "arm_label": "control", "agent_overrides": null, "initial_weight": 0}],
              "created_by_member_id": "m", "archived_at": null, "halted_at": null, "halted_reason": null,
              "created_at": "2026-09-30T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"
            }
            """#
        let transport = MockTransport { request, _ in
            if request.url.path.hasSuffix("/run") { return .response(.json(specJSON())) }
            if request.method == "DELETE" { return .response(HTTPResponse(status: 204, headers: [:], body: Data())) }
            if request.url.path == "/v1/experiments" && request.method == "GET" {
                return .response(.json(#"{"records": [\#(experimentJSON)], "count": 1}"#))
            }
            return .response(.json(experimentJSON))
        }
        let client = makeClient(transport)

        let listed = try await client.experiments.list(ExperimentListParams(project: "acme", runtime: "agent", status: .running)).collect()
        #expect(listed.first?.goalJson?.components.first?.guard?.min == 0.2)
        #expect(listed.first?.weightsJson?["arm-1"] == 60)
        #expect(listed.first?.arms?.first?.armLabel == "control")
        #expect(transport.last?.query["status"] == ["running"])

        let handle = client.experiments("exp-1", project: "acme")
        let started = try await handle.start()
        #expect(started.status == .running)
        #expect(transport.last?.path == "/v1/experiments/exp-1/start")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.query["project"] == ["acme"])
        _ = try await handle.end()
        #expect(transport.last?.path == "/v1/experiments/exp-1/end")
        _ = try await handle.cancel()
        #expect(transport.last?.path == "/v1/experiments/exp-1/cancel")

        let runner = try await handle.run(RunRequest(identity: RunnerIdentity(anonymousId: "anon-1")))
        #expect(transport.last?.path == "/v1/experiments/exp-1/run")
        #expect(transport.last?.json?["identity"]?["anonymous_id"]?.stringValue == "anon-1")
        #expect(
            runner.source == .experiment(id: "exp-1", request: RunRequest(identity: RunnerIdentity(anonymousId: "anon-1")), project: "acme")
        )

        try await client.experiments.delete("exp-1", project: "acme")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.query["project"] == ["acme"])
    }

    @Test func experimentCreateAndUpdateBodies() async throws {
        let transport = MockTransport(json: #"{"id": "exp-1"}"#)
        let client = makeClient(transport)
        _ = try await client.experiments.create(
            ExperimentCreate(
                project: "acme",
                runtime: "customer-agent",
                name: "Shorter prompt",
                goalJson: ExperimentGoal(direction: .maximize, components: [.judge("j1", weight: 2, guard: ExperimentGoalGuard(min: 0.1))]),
                arms: [
                    ExperimentArmCreate(runtimeId: "rt-1", armLabel: "control"),
                    ExperimentArmCreate(runtimeId: "rt-2", armLabel: "variant", agentOverrides: ["agent": "short"]),
                ],
                sampleRate: 0.25
            ))
        let body = try #require(transport.last?.json)
        #expect(body["runtime"]?.stringValue == "customer-agent")
        #expect(body["goal_json"]?["kind"]?.stringValue == "composite")
        #expect(body["goal_json"]?["components"]?[0]?["source"]?.stringValue == "judge")
        #expect(body["goal_json"]?["components"]?[0]?["judge_id"]?.stringValue == "j1")
        #expect(body["goal_json"]?["components"]?[0]?["guard"]?["min"]?.doubleValue == 0.1)
        #expect(body["arms"]?[1]?["agent_overrides"]?["agent"]?.stringValue == "short")
        #expect(body["sample_rate"]?.doubleValue == 0.25)
        #expect(body["description"] == nil)

        _ = try await client.experiments.update("exp-1", ExperimentUpdate(description: "why"))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["description": "why"])

        _ = try await client.experiments.create(document: ["name": "raw", "project": "acme"])
        #expect(transport.last?.json?["name"]?.stringValue == "raw")
    }

    @Test func runCallerRoundTripKeepsExtraKeys() throws {
        let json = #"{"ip": "1.1.1.1", "user_agent": "UA", "page": {"path": "/x"}, "device": {"model": "iPhone"}, "timezone": "UTC"}"#
        let caller = try JSONCoding.decoder.decode(RunCaller.self, from: Data(json.utf8))
        #expect(caller.userAgent == "UA")
        #expect(caller.page?.path == "/x")
        #expect(caller.extra["device"]?["model"]?.stringValue == "iPhone")
        #expect(caller.extra["ip"] == nil)
        let encoded = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(caller))
        #expect(encoded["timezone"]?.stringValue == "UTC")
        #expect(encoded["user_agent"]?.stringValue == "UA")
    }
}
