import Foundation
import Testing

@testable import IntrospectionSDK

private let now = "2026-10-19T00:00:00Z"
private let sha = "543b8db50a83aa1e2f3c4d5e6f708192a3b4c5d6"

private func noContent() -> MockTransport.Reply {
    .response(HTTPResponse(status: 204, headers: [:], body: Data()))
}

private func page(_ record: String, next: String? = nil) -> String {
    #"{"records": [\#(record)], "count": 1, "next": \#(next.map { "\"\($0)\"" } ?? "null")}"#
}

private let projectJSON = #"""
    {"id": "p-1", "org_id": "o", "deployment_id": "d-1", "name": "Walk", "slug": "walk", "description": null,
     "settings": null, "created_by_member_id": "m"}
    """#

private let peeringJSON = #"""
    {"id": "pr-1", "org_id": "o", "project_id": "p-1", "runtime_group_id": "g-1", "granted_org_id": null,
     "granted_project_id": "p-2", "granted_deployment_id": null, "expires_at": null, "created_by_member_id": "m",
     "created_at": "\#(now)", "updated_at": "\#(now)", "deleted_at": null}
    """#

private let recipeJSON = #"""
    {"id": "r-1", "org_id": "o", "project_id": "p-1", "repository_id": "repo-1", "name": "hello-mcp", "description": null,
     "git_ref": "main", "git_commit_sha": "\#(sha)", "sub_path": ".", "slug": "hello-mcp-main-543b8db50a83",
     "created_by_member_id": "m", "created_at": "\#(now)", "updated_at": "\#(now)",
     "validation": {"status": "pending", "diagnostics": []}}
    """#

private let runtimeJSON = #"""
    {"id": "rt-2", "org_id": "o", "project_id": "p-1", "runtime_group_id": "g-1", "name": "hello-mcp", "slug": "hello-mcp",
     "description": null, "kind": "byor", "llm_mode": "managed", "config_json": {"connectors": ["hello-mcp"]},
     "recipe_id": "r-1", "recipe_kind": "production", "recipe_ref": "main", "image_build_status": "pending",
     "created_at": "\#(now)", "updated_at": "\#(now)"}
    """#

private let repositoryJSON = #"""
    {"id": "repo-1", "project_id": "p-1", "name": "hello-mcp", "slug": "hello-mcp", "provider": "introspection",
     "default_branch": "main", "provisioning_status": "pending", "seed_template": "pi-agent", "is_recipe_source": false,
     "url": "https://git.test/hello-mcp.git", "created_at": "\#(now)"}
    """#

private let endpointJSON = #"""
    {"id": "e-1", "org_id": "o", "project_id": "p-1", "name": "hello-mcp", "host": "example-server.modelcontextprotocol.io",
     "base_url": "https://example-server.modelcontextprotocol.io/mcp", "kind": "mcp",
     "metadata": {"mcp_server_id": "hello-mcp", "connector_id": "c-1", "provider_app": null, "extra_hosts": [],
                  "auth_audience": null},
     "assertion_claims": null, "runtime_id": null, "runtime_group_id": "g-1", "environment": "production",
     "verify_path": null, "headers": {}, "header_names": [], "credential_refs": [], "last_verified_at": null,
     "authorized_application_id": null, "created_by_member_id": "m", "created_at": "\#(now)", "updated_at": "\#(now)"}
    """#

private let missionJSON = #"""
    {"id": "mi-1", "org_id": "o", "project_id": "p-1", "s256": "abc", "mission": "Book a flight", "agent_id": "agent-1",
     "member_id": "m", "resources": ["https://travel.test"], "budget": {"usd": 500}, "spent": 0,
     "log": [{"at": "\#(now)", "entry": "searching"}], "expires_at": "\#(now)", "completed_at": null,
     "created_at": "\#(now)", "updated_at": "\#(now)"}
    """#

private let approvalJSON = #"""
    {"id": "ap-1", "org_id": "o", "project_id": "p-1", "kind": "auth_token", "status": "pending", "agent_id": "agent-1",
     "member_id": "m", "mission_id": "mi-1", "description": "Book the flight", "resource": "https://travel.test",
     "budget": null, "summary": "One seat", "decided_budget": null, "decided_by_member_id": null, "decided_at": null,
     "expires_at": "\#(now)", "created_at": "\#(now)", "updated_at": "\#(now)"}
    """#

@Suite struct LifecycleResourcesTests {
    // MARK: Projects

    @Test func projectCreateUpdateAndDeleteSendTheServersBodies() async throws {
        let transport = MockTransport { request, _ in
            request.method == "DELETE" ? noContent() : .response(.json(projectJSON, status: request.method == "POST" ? 201 : 200))
        }
        let projects = makeClient(transport).projects

        let created = try await projects.create(ProjectCreate(name: "Walk", deploymentId: "d-1", slug: "walk"))
        #expect(created.deploymentId == "d-1")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.request.url.absoluteString == "https://cp.test/v1/projects")
        #expect(transport.last?.json == ["name": "Walk", "deployment_id": "d-1", "slug": "walk"])

        _ = try await projects.create(ProjectCreate(name: "Ark", deploymentId: "d-1", description: "seeded", includeArk: true))
        #expect(transport.last?.json == ["name": "Ark", "deployment_id": "d-1", "description": "seeded", "include_ark": true])

        _ = try await projects.update("walk", ProjectUpdate(description: ""))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/projects/walk")
        #expect(transport.last?.json == ["description": ""])

        try await projects.delete("p/1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.request.url.absoluteString == "https://cp.test/v1/projects/p%2F1")
    }

    @Test func peeringsAreReadUnderTheProjectAndNarrowByRuntimeOrGrant() async throws {
        let transport = MockTransport { request, _ in
            .response(.json(request.url.path.hasSuffix("/peerings") ? page(peeringJSON) : peeringJSON))
        }
        let projects = makeClient(transport).projects

        let offered = try await projects.peerings("walk", runtime: "hello-mcp", limit: 10, next: "c1").firstPage()
        #expect(offered.records.map(\.grantedProjectId) == ["p-2"])
        #expect(offered.records.first?.runtimeGroupId == "g-1")
        #expect(offered.records.first?.createdAt != nil)
        #expect(offered.records.first?.expiresAt == nil)
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.path == "/v1/projects/walk/peerings")
        #expect(transport.last?.query == ["runtime": ["hello-mcp"], "limit": ["10"], "next": ["c1"]])

        _ = try await projects.peerings("walk").collect()
        #expect(transport.last?.query == [:])

        _ = try await projects.peerings("p-2", granted: true).collect()
        #expect(transport.last?.path == "/v1/projects/p-2/peerings")
        #expect(transport.last?.query == ["granted": ["true"]])

        let one = try await projects.peering("p/1", "pr-1")
        #expect(one.id == "pr-1")
        #expect(RuntimePeering(id: "pr-1").projectId == nil)
        #expect(one.projectId == "p-1")
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.request.url.absoluteString == "https://cp.test/v1/projects/p%2F1/peerings/pr-1")
    }

    // MARK: Recipes

    @Test func recipeCreatePinsACommitAndUpdateAndDeleteNameTheProject() async throws {
        let transport = MockTransport { request, _ in
            request.method == "DELETE" ? noContent() : .response(.json(recipeJSON, status: request.method == "POST" ? 201 : 200))
        }
        let recipes = makeClient(transport).recipes

        let pinned = try await recipes.create(
            RecipeCreate(name: "hello-mcp", project: "p-1", repositoryId: "repo-1", gitRef: "main", gitCommitSha: sha))
        #expect(pinned.gitCommitSha == sha)
        #expect(transport.last?.path == "/v1/recipes")
        #expect(transport.last?.query.isEmpty == true)
        #expect(
            transport.last?.json
                == ["name": "hello-mcp", "project": "p-1", "repository_id": "repo-1", "git_ref": "main", "git_commit_sha": .string(sha)])

        _ = try await recipes.update("r-1", RecipeUpdate(description: "The walk's recipe"), project: "p-1")
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/recipes/r-1")
        #expect(transport.last?.query == ["project": ["p-1"]])
        #expect(transport.last?.json == ["description": "The walk's recipe"])

        try await recipes.delete("r-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.query.isEmpty == true)
    }

    // MARK: Runtimes

    @Test func runtimeCreateJoinsTheGroupAndUpdateAndDeleteAddressTheVersion() async throws {
        let transport = MockTransport { request, _ in
            request.method == "DELETE" ? noContent() : .response(.json(runtimeJSON, status: request.method == "POST" ? 201 : 200))
        }
        let runtimes = makeClient(transport).runtimes

        let created = try await runtimes.create(
            RuntimeCreate(
                name: "hello-mcp", project: "p-1", recipeId: "r-1", slug: "hello-mcp", configJson: ["connectors": ["hello-mcp"]]))
        #expect(created.runtimeGroupId == "g-1")
        #expect(created.imageBuildStatus == .pending)
        #expect(transport.last?.path == "/v1/runtimes")
        #expect(
            transport.last?.json
                == [
                    "name": "hello-mcp", "project": "p-1", "recipe_id": "r-1", "slug": "hello-mcp",
                    "config_json": ["connectors": ["hello-mcp"]],
                ])

        _ = try await runtimes.update(
            "rt-2", RuntimeUpdate(description: "the walk's own version", environment: .staging, environmentRef: ["staging": nil]))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/runtimes/rt-2")
        #expect(
            transport.last?.json == [
                "description": "the walk's own version", "environment": "staging", "environment_ref": ["staging": nil],
            ])

        try await runtimes.delete("rt-2", project: "p-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.query == ["project": ["p-1"]])
    }

    // MARK: Repositories

    @Test func hostedRepositoryCreateAndDeleteGoToTheControlPlane() async throws {
        let transport = MockTransport { request, _ in
            request.method == "DELETE" ? noContent() : .response(.json(repositoryJSON, status: 201))
        }
        let repositories = makeClient(transport).repositories

        let created = try await repositories.create(HostedRepositoryCreate(slug: "hello-mcp", defaultBranch: "main"), project: "p-1")
        #expect(created.provisioningStatus == "pending")
        #expect(transport.last?.request.url.host == "cp.test")
        #expect(transport.last?.query == ["project": ["p-1"]])
        #expect(transport.last?.json == ["provider": "introspection", "slug": "hello-mcp", "default_branch": "main"])

        _ = try await repositories.create(HostedRepositoryCreate(slug: "seeded", seedTemplate: "pi-agent"))
        #expect(transport.last?.json == ["provider": "introspection", "slug": "seeded", "seed_template": "pi-agent"])

        try await repositories.delete("repo-1", project: "p-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.path == "/v1/repositories/repo-1")
    }

    @Test func branchesPageOnTheirCursor() async throws {
        let transport = MockTransport { request, _ in
            let cursor = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }
            return cursor == nil
                ? .response(.json(page(#"{"name": "main", "sha": "\#(sha)"}"#, next: "c2")))
                : .response(.json(page(#"{"name": "walk", "sha": "\#(sha)", "committed_at": "\#(now)"}"#)))
        }
        let branches = try await makeClient(transport).repositories
            .branches("repo-1", RepositoryBranchesParams(query: "a", sort: .name, limit: 1)).collect()
        #expect(branches.map(\.name) == ["main", "walk"])
        #expect(branches.last?.committedAt == now)
        #expect(transport.last?.request.url.host == "dp.test")
        #expect(transport.last?.path == "/v1/repositories/repo-1/branches")
        #expect(transport.last?.query == ["q": ["a"], "sort": ["name"], "limit": ["1"], "cursor": ["c2"]])
    }

    // MARK: Endpoints

    @Test func endpointsListReadUpdateAndDeleteInTheProject() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return noContent()
            case ("GET", "/v1/endpoints"): return .response(.json(page(endpointJSON)))
            default: return .response(.json(endpointJSON))
            }
        }
        let endpoints = makeClient(transport).endpoints

        let listed = try await endpoints.list(
            EndpointListParams(project: "p-1", kind: .mcp, runtime: "hello-mcp", environment: .production, mcpServerId: "hello-mcp")
        ).firstPage()
        let endpoint = try #require(listed.records.first)
        #expect(endpoint.kind == .mcp)
        #expect(endpoint.metadata?.mcpServerId == "hello-mcp")
        #expect(endpoint.metadata?.connectorId == "c-1")
        #expect(endpoint.headers == [:])
        #expect(endpoint.environment == .production)
        #expect(
            transport.last?.query
                == [
                    "project": ["p-1"], "kind": ["mcp"], "runtime": ["hello-mcp"], "environment": ["production"],
                    "mcp_server_id": ["hello-mcp"],
                ])

        let read = try await endpoints.get("e-1", project: "p-1")
        #expect(read.runtimeGroupId == "g-1")
        #expect(transport.last?.path == "/v1/endpoints/e-1")

        _ = try await endpoints.update("e-1", EndpointUpdate(name: "hello-mcp (walk)"), project: "p-1")
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.query == ["project": ["p-1"]])
        #expect(transport.last?.json == ["name": "hello-mcp (walk)"])

        try await endpoints.delete("e-1", project: "p-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.path == "/v1/endpoints/e-1")
    }

    // MARK: AAuth

    @Test func missionsAndApprovalsListAndReadOnTheDataPlane() async throws {
        let transport = MockTransport { request, _ in
            switch request.url.path {
            case "/v1/aauth/missions": return .response(.json(page(missionJSON)))
            case "/v1/aauth/approvals": return .response(.json(page(approvalJSON)))
            case "/v1/aauth/missions/mi-1": return .response(.json(missionJSON))
            default: return .response(.json(approvalJSON))
            }
        }
        let client = makeClient(transport)

        let missions = try await client.missions.list(MissionListParams(memberId: "m", limit: 5)).firstPage()
        #expect(missions.records.first?.budget == ["usd": 500])
        #expect(missions.records.first?.log?.first?.entry == "searching")
        #expect(transport.last?.request.url.host == "dp.test")
        #expect(transport.last?.query == ["member_id": ["m"], "limit": ["5"]])
        #expect(try await client.missions.get("mi-1").mission == "Book a flight")

        let approvals = try await client.approvals.list(
            ApprovalListParams(status: [.pending, .approved], kind: .authToken, missionId: "mi-1")
        ).firstPage()
        #expect(approvals.records.first?.status == .pending)
        #expect(approvals.records.first?.kind == .authToken)
        #expect(transport.last?.query == ["status": ["pending", "approved"], "kind": ["auth_token"], "mission_id": ["mi-1"]])
        let approval = try await client.approvals.get("ap-1")
        #expect(approval.summary == "One seat")
        #expect(transport.last?.path == "/v1/aauth/approvals/ap-1")
    }

    // MARK: Models

    @Test func modelsBuiltInCodeRoundTripThroughTheirWireNames() throws {
        let at = try #require(ISO8601.parse(now))
        let endpoint = Endpoint(
            id: "e-1", orgId: "o", projectId: "p-1", name: "hello-mcp", host: "mcp.test", baseUrl: "https://mcp.test/mcp", kind: .mcp,
            metadata: EndpointMetadata(
                mcpServerId: "hello-mcp", connectorId: "c-1", providerApp: "gmail", extraHosts: ["*.mcp.test"], authAudience: "aud"),
            headers: ["X-Key": "${KEY}"], headerNames: ["X-Key"], credentialRefs: ["KEY"], assertionClaims: ["role": "user"],
            authorizedApplicationId: "app-1", runtimeId: "rt-1", runtimeGroupId: "g-1", environment: .staging, verifyPath: "/health",
            lastVerifiedAt: at, createdByMemberId: "m", createdAt: at, updatedAt: at)
        let mission = Mission(
            id: "mi-1", orgId: "o", projectId: "p-1", mission: "Book", s256: "abc", agentId: "agent-1", memberId: "m",
            resources: ["https://travel.test"], budget: ["usd": 5], spent: 1, log: [MissionLogEntry(at: at, entry: "booked")],
            expiresAt: at, completedAt: at, createdAt: at, updatedAt: at)
        let approval = Approval(
            id: "ap-1", orgId: "o", projectId: "p-1", kind: .completion, status: .denied, agentId: "agent-1", memberId: "m",
            missionId: "mi-1", description: "Done", resource: "https://travel.test", budget: ["usd": 5], summary: "s",
            decidedBudget: ["usd": 0], decidedByMemberId: "m2", decidedAt: at, expiresAt: at, createdAt: at, updatedAt: at)
        let branch = RepositoryBranch(name: "main", sha: sha, committedAt: now)

        #expect(try roundTrip(endpoint) == endpoint)
        #expect(try roundTrip(mission) == mission)
        #expect(try roundTrip(approval) == approval)
        #expect(try roundTrip(branch) == branch)
        let json = try JSONValue.from(endpoint)
        #expect(json["metadata"]?["extra_hosts"] == ["*.mcp.test"])
        #expect(json["authorized_application_id"] == "app-1")
        #expect(try JSONValue.from(approval)["decided_by_member_id"] == "m2")
    }

    // MARK: Arrow reads

    @Test func arrowReadsAskForTheArrowStreamAndReturnItsBytes() async throws {
        let arrow = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x10])
        let transport = MockTransport { _, _ in
            .response(HTTPResponse(status: 200, headers: ["content-type": "application/vnd.apache.arrow.stream"], body: arrow))
        }
        let client = makeClient(transport)

        #expect(try await client.conversations.exportArrow("conv-1") == arrow)
        #expect(transport.last?.path == "/v1/conversations/conv-1/export")
        #expect(transport.last?.request.headers["Accept"] == "application/vnd.apache.arrow.stream")

        #expect(try await client.conversations.listArrow(ConversationListParams(next: "n2", runtimeGroupId: "g-1")) == arrow)
        #expect(transport.last?.path == "/v1/conversations")
        #expect(transport.last?.query == ["runtime_group_id": ["g-1"], "next": ["n2"]])
        #expect(transport.last?.request.headers["Accept"] == "application/vnd.apache.arrow.stream")

        #expect(try await client.events.listArrow(EventListParams(eventName: .annotation, conversationId: "conv-1")) == arrow)
        #expect(transport.last?.path == "/v1/events")
        #expect(transport.last?.query == ["event_name": ["introspection.annotation"], "conversation_id": ["conv-1"]])
        #expect(transport.last?.request.headers["Accept"] == "application/vnd.apache.arrow.stream")
    }
}

private func roundTrip<T: Codable>(_ value: T) throws -> T {
    try JSONCoding.decoder.decode(T.self, from: JSONCoding.encoder.encode(value))
}
