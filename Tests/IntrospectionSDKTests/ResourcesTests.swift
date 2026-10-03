import Foundation
import XCTest

@testable import IntrospectionSDK

private func noContent() -> MockTransport.Reply {
    .response(HTTPResponse(status: 204, headers: [:], body: Data()))
}

private let connectorJSON = #"""
    {
      "id": "con-1", "org_id": "o", "project_id": "p", "created_at": "2026-09-01T00:00:00Z",
      "updated_at": "2026-09-01T00:00:00Z", "slug": "slack", "name": "Slack", "provider": "slack",
      "auth_mode": "oauth_stored", "environment": "production", "agent_member_id": null,
      "authorization_endpoint": "https://slack.com/oauth/v2/authorize", "token_endpoint": null,
      "scopes": ["chat:write"], "api_hosts": ["slack.com"], "client_id": "cid", "person_server_mode": null,
      "person_server_url": null, "approval_policy": "human", "application_id": null,
      "assertion_audience": null, "webhook_url": null, "status": "active", "created_by_member_id": "m",
      "metadata": {"team": "T1"}, "requires_runtime": true
    }
    """#

private let connectionJSON = #"""
    {
      "id": "cx-1", "org_id": "o", "created_at": "2026-09-01T00:00:00Z", "updated_at": "2026-09-01T00:00:00Z",
      "subject_type": "workspace", "scopes_granted": ["chat:write"], "connector_id": "con-1",
      "member_id": "m-ws", "created_by_member_id": "m-op", "runtime_group_id": "g", "provider_app": null,
      "provider_account_id": "T1", "status": "active", "token_expires_at": null
    }
    """#

private func member(_ id: String, _ email: String?, deactivated: Bool = false) -> String {
    let emailJSON = email.map { "\"\($0)\"" } ?? "null"
    return
        #"{"id": "\#(id)", "org_id": "o", "email": \#(emailJSON), "name": null, "role": "member", "member_type": "business", "is_deactivated": \#(deactivated), "tags": [], "is_external_credential_agent": false, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"}"#
}

final class ResourcesTests: XCTestCase {
    // MARK: Recipes

    func testRecipesListAndGet() async throws {
        let recipe = #"""
            {"id": "rec-1", "org_id": "o", "project_id": "p", "repository_id": "repo-1", "name": "agent", "slug": "agent",
             "description": null, "git_ref": "main", "git_commit_sha": "abc", "git_commit_subject": "init", "sub_path": null,
             "created_by_member_id": "m", "mcp_servers": [{"id": "gmail", "required": true, "tools": {"include": ["send"], "exclude": []}}],
             "validation": {"status": "invalid", "validator_name": "recipe-check", "validator_version": "1.0", "checked_at": "2026-09-01T00:00:00Z",
               "error_message": null, "diagnostics": [{"code": "E1", "path": "agents/agent.yaml", "span": {"line": 3, "column": 1}, "message": "bad", "help": null}]},
             "created_at": "2026-09-01T00:00:00Z", "updated_at": "2026-09-01T00:00:00Z"}
            """#
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/recipes"
                ? .response(.json(#"{"records": [\#(recipe)], "count": 1, "next": "n2"}"#)) : .response(.json(recipe))
        }
        let client = makeClient(transport)
        let page = try await client.recipes.list(RecipeListParams(project: "acme", name: "agent", repositoryId: "repo-1", limit: 10))
            .firstPage()
        XCTAssertEqual(page.next, "n2")
        XCTAssertEqual(transport.last?.query["repository_id"], ["repo-1"])
        XCTAssertEqual(transport.last?.query["name"], ["agent"])
        let fetched = try await client.recipes.get("rec-1", project: "acme")
        XCTAssertEqual(transport.last?.path, "/v1/recipes/rec-1")
        XCTAssertEqual(fetched.validation?.status, .invalid)
        XCTAssertEqual(fetched.validation?.diagnostics?.first?.span?.line, 3)
        XCTAssertEqual(fetched.mcpServers?.first?.tools?.include, ["send"])
    }

    // MARK: Connectors

    func testConnectorCrud() async throws {
        let transport = MockTransport { request, _ in
            switch request.method {
            case "DELETE": return noContent()
            case "GET" where request.url.path == "/v1/connectors":
                return .response(.json(#"{"records": [\#(connectorJSON)], "count": 1}"#))
            default: return .response(.json(connectorJSON))
            }
        }
        let connectors = makeClient(transport).connectors

        let all = try await connectors.list(ConnectorListParams(project: "acme", limit: 50)).collect()
        XCTAssertEqual(all.first?.authMode, .oauthStored)
        XCTAssertEqual(all.first?.requiresRuntime, true)
        XCTAssertEqual(all.first?.metadata?["team"]?.stringValue, "T1")
        XCTAssertEqual(transport.last?.query["project"], ["acme"])

        _ = try await connectors.create(
            ConnectorCreate(
                name: "Slack", provider: "slack", authMode: .oauthStored, scopes: ["chat:write"],
                clientId: "cid", clientSecret: "shh", metadata: ["k": "v"]
            ))
        let created = try XCTUnwrap(transport.last?.json)
        XCTAssertEqual(created["auth_mode"]?.stringValue, "oauth_stored")
        XCTAssertEqual(created["client_secret"]?.stringValue, "shh")
        XCTAssertEqual(created["metadata"]?["k"]?.stringValue, "v")
        XCTAssertNil(created["slug"])
        XCTAssertNil(transport.last?.query["project"])

        _ = try await connectors.update("con-1", ConnectorUpdate(status: .active, signingSecret: "sig"))
        XCTAssertEqual(transport.last?.request.method, "PATCH")
        XCTAssertEqual(transport.last?.json, ["status": "active", "signing_secret": "sig"])

        let got = try await connectors.get("con-1")
        XCTAssertEqual(got.approvalPolicy, .human)
        try await connectors.delete("con-1", project: "acme")
        XCTAssertEqual(transport.last?.request.method, "DELETE")
        XCTAssertEqual(transport.last?.path, "/v1/connectors/con-1")
    }

    func testConnectorAppsAndDiscovery() async throws {
        let transport = MockTransport { request, _ in
            if request.url.path.hasSuffix("discover-oauth") {
                return .response(
                    .json(
                        #"""
                        {"issuer": "https://auth.example", "authorization_endpoint": "https://auth.example/authorize",
                         "token_endpoint": "https://auth.example/token", "registration_endpoint": null,
                         "token_endpoint_auth_methods_supported": ["none"], "code_challenge_methods_supported": ["S256"],
                         "scopes_supported": [], "client_id_metadata_document_supported": true, "resource": "https://mcp.example/mcp",
                         "redirect_uri": "https://cp.test/v1/oauth/connections/callback", "client_id": "https://cp.test/client.json",
                         "client_secret": null, "client_registration": "client_id_metadata_document"}
                        """#))
            }
            return .response(
                .json(#"{"data": [{"slug": "linear", "name": "Linear", "icon_url": null, "mcp_url": "https://mcp.linear.app/mcp"}]}"#))
        }
        let connectors = makeClient(transport).connectors
        let apps = try await connectors.listApps("con-1", query: "lin", limit: 5)
        XCTAssertEqual(apps.first?.slug, "linear")
        XCTAssertEqual(transport.last?.path, "/v1/connectors/con-1/apps")
        XCTAssertEqual(transport.last?.query["q"], ["lin"])

        let custom = try await connectors.searchCustomApps(query: "linear")
        XCTAssertEqual(custom.first?.mcpUrl, "https://mcp.linear.app/mcp")
        XCTAssertEqual(transport.last?.path, "/v1/connectors/custom/apps")

        let discovery = try await connectors.discoverOAuth(issuer: "https://mcp.example/mcp")
        XCTAssertEqual(transport.last?.request.method, "POST")
        XCTAssertEqual(transport.last?.json, ["issuer": "https://mcp.example/mcp"])
        XCTAssertEqual(discovery.clientRegistration, .clientIdMetadataDocument)
        XCTAssertEqual(discovery.codeChallengeMethodsSupported, ["S256"])
    }

    func testAuthorizeBody() async throws {
        let transport = MockTransport(
            json: #"{"authorize_url": "https://slack.com/oauth?state=x", "expires_in": 600, "expires_at": "2026-10-03T12:10:00Z"}"#)
        let authorization = try await makeClient(transport).connectors.authorize(
            "con-1",
            ConnectorAuthorizeParams(
                identity: RunnerIdentity(userId: "cust-9"),
                runtime: "customer-agent",
                binding: ConnectorAuthorizeBinding(environment: .production, mcpServerId: "slack", url: "https://mcp.slack.com/mcp"),
                subject: .user,
                returnUrl: "https://app.example/done",
                expiresIn: 3600
            ), project: "acme")
        XCTAssertEqual(authorization.expiresIn, 600)
        let request = try XCTUnwrap(transport.last)
        XCTAssertEqual(request.path, "/v1/oauth/connections/authorize")
        XCTAssertEqual(request.query["project"], ["acme"])
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["connector_id"]?.stringValue, "con-1")
        XCTAssertEqual(body["runtime"]?.stringValue, "customer-agent")
        XCTAssertEqual(body["identity"]?["user_id"]?.stringValue, "cust-9")
        XCTAssertEqual(body["binding"]?["mcp_server_id"]?.stringValue, "slack")
        XCTAssertEqual(body["subject"]?.stringValue, "user")
        XCTAssertEqual(body["return_url"]?.stringValue, "https://app.example/done")
        XCTAssertEqual(body["expires_in"]?.intValue, 3600)
        XCTAssertNil(body["app"])
    }

    func testConnectionsAndTokenBroker() async throws {
        let transport = MockTransport { request, _ in
            if request.method == "DELETE" { return noContent() }
            if request.url.path == "/v1/oauth/connections/token" {
                let body = request.body.flatMap { try? JSONCoding.decoder.decode(JSONValue.self, from: $0) }
                if body?["subject"]?.stringValue == "person" {
                    return .response(
                        .json(
                            #"{"status": "authorization_pending", "mission_id": "mis-1", "approval_url": "https://consent.test/m/mis-1?cap=x"}"#,
                            status: 202))
                }
                return .response(.json(#"{"token": "xoxb-1", "token_type": "bearer", "expires_at": null, "scopes": ["chat:write"]}"#))
            }
            if request.url.path.hasSuffix("/connections") && request.method == "GET" {
                return .response(.json(#"{"records": [\#(connectionJSON)], "count": 1}"#))
            }
            return .response(.json(connectionJSON))
        }
        let connections = makeClient(transport).connectors.connections

        let listed = try await connections.list("con-1", ConnectionListParams(limit: 10)).collect()
        XCTAssertEqual(listed.first?.subjectType, .workspace)
        XCTAssertEqual(listed.first?.providerAccountId, "T1")
        XCTAssertEqual(transport.last?.path, "/v1/connectors/con-1/connections")

        _ = try await connections.create("con-1", ConnectionCreate(accessToken: "tok", subjectType: .app, scopesGranted: ["a"]))
        XCTAssertEqual(transport.last?.json?["access_token"]?.stringValue, "tok")
        XCTAssertEqual(transport.last?.json?["subject_type"]?.stringValue, "app")

        _ = try await connections.get("con-1", "cx-1")
        XCTAssertEqual(transport.last?.path, "/v1/connectors/con-1/connections/cx-1")
        try await connections.revoke("con-1", "cx-1")
        XCTAssertEqual(transport.last?.request.method, "DELETE")

        let token = try await connections.getToken("con-1")
        XCTAssertEqual(token.token?.token, "xoxb-1")
        XCTAssertEqual(transport.last?.json, ["connector_id": "con-1"])

        let pending = try await connections.getToken(
            "con-1",
            ConnectionTokenParams(
                subject: .person, action: "booking.reserve",
                requestedPermissions: ConnectionMissionConstraints(host: "api.example", limits: ["amount_max": 100])
            ))
        XCTAssertEqual(pending, .authorizationPending(missionId: "mis-1", approvalUrl: "https://consent.test/m/mis-1?cap=x"))
        XCTAssertNil(pending.token)
        XCTAssertEqual(transport.last?.json?["requested_permissions"]?["limits"]?["amount_max"]?.intValue, 100)
        XCTAssertEqual(transport.last?.json?["action"]?.stringValue, "booking.reserve")
    }

    // MARK: Repositories

    func testRepositoriesListAndGetUseControlPlane() async throws {
        let repo =
            #"{"id": "repo-1", "project_id": "p", "integration_id": null, "url": "https://git.test/acme/agent.git", "name": "agent", "slug": "agent", "provider": "hosted", "default_branch": "main", "provisioning_status": "ready", "seed_template": "pi-agent", "created_at": "2026-09-01T00:00:00Z", "pushed_at": null, "head_commit_sha": "abc", "is_recipe_source": true}"#
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/repositories" ? .response(.json("[\(repo)]")) : .response(.json(repo))
        }
        let repositories = makeClient(transport).repositories
        let all = try await repositories.list(project: "acme", slug: "agent")
        XCTAssertEqual(all.first?.isRecipeSource, true)
        XCTAssertEqual(transport.last?.request.url.host, "cp.test")
        XCTAssertEqual(transport.last?.query["slug"], ["agent"])
        let one = try await repositories.get("repo-1", project: "acme")
        XCTAssertEqual(one.provider, "hosted")
        XCTAssertEqual(transport.last?.path, "/v1/repositories/repo-1")
    }

    func testRepositoryContentsPagesDirectoryAndReadsFiles() async throws {
        let transport = MockTransport { request, _ in
            let url = request.url.absoluteString
            if url.contains("/contents/src/My%20File.md") {
                return .response(
                    .json(
                        #"{"type": "file", "name": "My File.md", "path": "src/My File.md", "size": 5, "sha": "s", "commit_sha": "c", "encoding": "base64", "content": "aGVsbG8=", "truncated": false}"#
                    ))
            }
            if url.contains("cursor=p2") {
                return .response(
                    .json(
                        #"{"type": "dir", "path": "src", "commit_sha": "c", "records": [{"name": "b", "path": "src/b", "type": "dir", "size": 0, "sha": "s2"}], "count": 1, "next": null}"#
                    ))
            }
            return .response(
                .json(
                    #"{"type": "dir", "path": "src", "commit_sha": "c", "records": [{"name": "a.md", "path": "src/a.md", "type": "file", "size": 3, "sha": "s1"}], "count": 1, "next": "p2"}"#
                ))
        }
        let contents = makeClient(transport).repositories.contents
        let entries = try await contents("repo-1", path: "/src/", ref: "main", limit: 1).collect()
        XCTAssertEqual(entries.map(\.path), ["src/a.md", "src/b"])
        XCTAssertEqual(entries.last?.type, .dir)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].request.url.host, "dp.test")
        XCTAssertEqual(transport.requests[0].path, "/v1/repositories/repo-1/contents/src")
        XCTAssertEqual(transport.requests[0].query["ref"], ["main"])
        XCTAssertNil(transport.requests[0].query["cursor"])
        XCTAssertEqual(transport.requests[1].query["cursor"], ["p2"])

        let file = try await contents.get("repo-1", path: "src/My File.md")
        guard case let .file(read) = file else { return XCTFail("expected a file") }
        XCTAssertEqual(read.text, "hello")
        XCTAssertEqual(read.data, Data("hello".utf8))

        do {
            _ = try await contents.list("repo-1", path: "src/My File.md").collect()
            XCTFail("expected a validation error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .validation)
            XCTAssertEqual(error.code, "repository_path_is_file")
        }

        _ = try await contents.get("repo-1")
        XCTAssertEqual(transport.last?.path, "/v1/repositories/repo-1/contents")
    }

    func testRepositoryCommitsAndMerges() async throws {
        let commit =
            #"{"sha": "c1", "parents": ["c0"], "message": "init", "author": {"name": "A", "email": "a@x", "date": "2026-09-01T00:00:00Z"}, "committer": {"name": "A"}}"#
        let transport = MockTransport { request, index in
            let path = request.url.path
            if path.hasSuffix("/merges") {
                return index == 4
                    ? noContent()
                    : .response(
                        .json(#"{"sha": "m1", "base": "main", "head": "feature", "head_sha": "h1", "parents": ["b0", "h1"]}"#, status: 201))
            }
            if path.hasSuffix("/commits/c1") {
                return .response(
                    .json(
                        #"{"sha": "c1", "parents": [], "message": "init", "author": {"name": "A"}, "committer": {"name": "A"}, "files": [{"filename": "a.md", "status": "added", "additions": 1, "deletions": 0, "changes": 1}], "patch": "diff --git"}"#
                    ))
            }
            let cursor = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value
            return cursor == nil
                ? .response(.json(#"{"records": [\#(commit)], "count": 1, "next": "k2"}"#))
                : .response(
                    .json(#"{"records": [\#(commit.replacingOccurrences(of: "\"c1\"", with: "\"c2\""))], "count": 1, "next": null}"#))
        }
        let repositories = makeClient(transport).repositories
        let commits = try await repositories.commits("repo-1", RepositoryCommitsParams(sha: "main", path: "src", limit: 1)).collect()
        XCTAssertEqual(commits.map(\.sha), ["c1", "c2"])
        XCTAssertEqual(transport.requests[0].query["sha"], ["main"])
        XCTAssertEqual(transport.requests[0].query["path"], ["src"])
        XCTAssertNil(transport.requests[0].query["next"])
        XCTAssertEqual(transport.requests[1].query["cursor"], ["k2"])

        let detail = try await repositories.commit("repo-1", sha: "c1")
        XCTAssertEqual(detail.files?.first?.status, "added")
        XCTAssertEqual(detail.patch, "diff --git")

        let merged = try await repositories.merge("repo-1", RepositoryMergeCreate(base: "main", head: "feature", commitMessage: "ship"))
        XCTAssertEqual(merged?.headSha, "h1")
        XCTAssertEqual(transport.last?.json, ["base": "main", "head": "feature", "commit_message": "ship"])
        XCTAssertEqual(transport.last?.request.url.host, "dp.test")
        let upToDate = try await repositories.merge("repo-1", RepositoryMergeCreate(base: "main", head: "feature"))
        XCTAssertNil(upToDate)
    }

    // MARK: Annotations

    func testAnnotationListResolvesEmailsOnceAcrossPages() async throws {
        let transport = MockTransport { request, _ in
            if request.url.host == "cp.test" {
                return .response(
                    .json(
                        #"{"records": [\#(member("m-1", " Ana@Example.com ")), \#(member("m-2", "bo@example.com")), \#(member("m-3", "ana@example.com", deactivated: true))], "count": 3}"#
                    ))
            }
            let next = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "next" }?.value
            let state =
                #"{"trace_id": "0123456789abcdef0123456789abcdef", "span_id": "0123456789abcdef", "conversation_id": "conv", "labels": ["bug"], "assignee_member_ids": ["m-2"], "annotator_member_ids": ["m-1"], "has_comment": true, "comment_count": 2, "latest_comment": "see", "latest_comment_member_id": "m-1", "updated_at": "2026-10-01T00:00:00Z", "updated_by_member_id": "m-1", "assignment_event_id": null}"#
            return .response(.json(#"{"records": [\#(state)], "count": 1, "next": \#(next == nil ? "\"p2\"" : "null")}"#))
        }
        let annotations = makeClient(transport).annotations
        let states = try await annotations.list(
            AnnotationListParams(
                annotatedByEmail: "ana@example.com", assignedToEmail: "BO@example.com", labels: ["bug", "ux"], status: .assigned
            )
        ).collect()
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states.first?.labels, ["bug"])
        XCTAssertEqual(states.first?.commentCount, 2)

        let memberCalls = transport.requests.filter { $0.request.url.host == "cp.test" }
        XCTAssertEqual(memberCalls.count, 1)
        XCTAssertEqual(memberCalls.first?.path, "/v1/members")
        XCTAssertEqual(memberCalls.first?.query["member_type"], ["business"])
        XCTAssertEqual(memberCalls.first?.query["limit"], ["1000"])

        let reads = transport.requests.filter { $0.request.url.host == "dp.test" }
        XCTAssertEqual(reads.count, 2)
        XCTAssertEqual(reads[0].query["annotated_by_member_id"], ["m-1"])
        XCTAssertEqual(reads[0].query["assignee_member_id"], ["m-2"])
        XCTAssertEqual(reads[0].query["label"], ["bug", "ux"])
        XCTAssertEqual(reads[0].query["status"], ["assigned"])
        XCTAssertEqual(reads[1].query["next"], ["p2"])
        XCTAssertEqual(reads[1].query["annotated_by_member_id"], ["m-1"])
    }

    func testAnnotationListRejectsConflictingFilters() async {
        let transport = MockTransport(json: "{}")
        do {
            _ = try await makeClient(transport).annotations.list(AnnotationListParams(annotatedByMemberId: "m", annotatedByEmail: "a@x"))
                .collect()
            XCTFail("expected a validation error")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.code, "conflicting_annotation_annotator_filters")
        } catch { XCTFail("\(error)") }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAnnotationCreateResolvesReviewersAndReportsVisibility() async throws {
        let transport = MockTransport { request, index in
            if request.url.host == "cp.test" {
                return .response(
                    .json(
                        #"{"records": [\#(member("m-1", "ana@example.com")), \#(member("m-2", "dup@example.com")), \#(member("m-3", "dup@example.com"))], "count": 3}"#
                    ))
            }
            if index == 1 {
                return .response(HTTPResponse(status: 204, headers: ["x-introspection-event-id": "ev-server"], body: Data()))
            }
            return .response(.json(#"{"event_id": "ev-2", "visible": false}"#, status: 202))
        }
        let annotations = makeClient(transport).annotations
        let target = AnnotationTarget(traceId: "0123456789abcdef0123456789abcdef", spanId: "0123456789abcdef")

        let first = try await annotations.create(target, .reviewers(["ANA@example.com"], comment: "please look"))
        XCTAssertTrue(first.visible)
        XCTAssertEqual(first.eventId, "ev-server")
        let body = try XCTUnwrap(transport.last?.json)
        XCTAssertEqual(body["trace_id"]?.stringValue, target.traceId)
        XCTAssertEqual(body["assignee_member_ids"], ["m-1"])
        XCTAssertEqual(body["comment"]?.stringValue, "please look")
        XCTAssertNil(body["labels"])
        let eventId = try XCTUnwrap(body["event_id"]?.stringValue)
        XCTAssertEqual(eventId.count, 36)
        XCTAssertEqual(Array(eventId)[14], "7")

        let second = try await annotations.create(target, .labels(["bug"]), eventId: "ev-2")
        XCTAssertFalse(second.visible)
        XCTAssertEqual(second.eventId, "ev-2")
        XCTAssertEqual(transport.last?.json?["labels"], ["bug"])
        XCTAssertEqual(transport.last?.json?["event_id"]?.stringValue, "ev-2")

        let before = transport.requests.count
        _ = try await annotations.create(target, .reviewers([]))
        XCTAssertEqual(transport.requests.count, before + 1, "an empty reviewer snapshot needs no lookup")
        XCTAssertEqual(transport.last?.json?["assignee_member_ids"], [])

        do {
            _ = try await annotations.create(target, .reviewers(["dup@example.com"]))
            XCTFail("expected a conflict")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .conflict)
            XCTAssertEqual(error.code, "annotation_reviewer_ambiguous")
        }
        do {
            _ = try await annotations.create(target, .reviewers(["nobody@example.com"]))
            XCTFail("expected notFound")
        } catch let error as IntrospectionError {
            XCTAssertEqual(error.kind, .notFound)
            XCTAssertEqual(error.code, "annotation_reviewer_not_found")
        }
        for mutation in [AnnotationMutation(labels: ["a"], assigneeMemberIds: ["m"]), AnnotationMutation(), .comment("  ")] {
            do {
                _ = try await annotations.create(target, mutation)
                XCTFail("expected a validation error for \(mutation)")
            } catch let error as IntrospectionError {
                XCTAssertEqual(error.kind, .validation)
            }
        }
    }

    func testAnnotationFacetsAndNavigation() async throws {
        let transport = MockTransport { request, _ in
            request.url.path.hasSuffix("facets")
                ? .response(.json(#"[{"dimension": "label", "value": "bug", "count": 3}]"#))
                : .response(
                    .json(
                        #"{"previous": null, "current": {"trace_id": "t", "span_id": "s"}, "next": null, "current_position": 0, "total_count": 1}"#
                    ))
        }
        let annotations = makeClient(transport).annotations
        let facets = try await annotations.facets()
        XCTAssertEqual(facets.first?.count, 3)
        let window = try await annotations.navigation(AnnotationTarget(traceId: "t", spanId: "s"), labels: ["bug"])
        XCTAssertEqual(window.current?.spanId, "s")
        XCTAssertEqual(window.totalCount, 1)
        XCTAssertEqual(transport.last?.path, "/v1/annotations/navigation")
        XCTAssertEqual(transport.last?.query["trace_id"], ["t"])
    }

    func testProjectLabels() async throws {
        let label =
            ##"{"slug": "bug", "color": "#f97316", "description": null, "created_at": "2026-09-01T00:00:00Z", "updated_at": "2026-09-01T00:00:00Z"}"##
        let transport = MockTransport { request, _ in
            request.method == "GET" && request.url.path == "/v1/project-labels"
                ? .response(.json(#"{"records": [\#(label)], "count": 1}"#))
                : .response(.json(label))
        }
        let labels = makeClient(transport).projectLabels
        let all = try await labels.list(ProjectLabelListParams(search: "bu")).collect()
        XCTAssertEqual(all.first?.color, "#f97316")
        XCTAssertEqual(transport.last?.request.url.host, "dp.test")
        XCTAssertEqual(transport.last?.query["search"], ["bu"])

        _ = try await labels.create(ProjectLabelCreate(slug: "  bug ", color: "#F97316"))
        XCTAssertEqual(transport.last?.json, ["slug": "bug", "color": "#f97316"])

        _ = try await labels.update("bug", ProjectLabelUpdate(description: nil))
        XCTAssertEqual(transport.last?.request.method, "PATCH")
        XCTAssertEqual(transport.last?.bodyString, #"{"description":null}"#)

        let before = transport.requests.count
        for bad in [
            ProjectLabelCreate(slug: " ", color: "#ffffff"), ProjectLabelCreate(slug: "a", color: "orange"),
            ProjectLabelCreate(slug: "a", color: "#12345g"),
        ] {
            do {
                _ = try await labels.create(bad)
                XCTFail("expected a validation error")
            } catch let error as IntrospectionError {
                XCTAssertEqual(error.kind, .validation)
            }
        }
        XCTAssertEqual(transport.requests.count, before)
    }

    // MARK: Organization

    func testOrganizationProjectsAndMembers() async throws {
        let transport = MockTransport { request, _ in
            switch request.url.path {
            case "/v1/organizations/current":
                return .response(
                    .json(#"{"id": "o", "name": "Acme", "slug": "acme", "external_org_id": null, "image_url": null, "hosted_git": true}"#))
            case "/v1/projects":
                return .response(
                    .json(
                        #"{"records": [{"id": "p", "org_id": "o", "deployment_id": "d", "name": "Main", "slug": "main", "description": null, "settings": {"x": 1}, "created_by_member_id": null}], "count": 1}"#
                    ))
            case "/v1/members":
                return .response(.json(#"{"records": [\#(member("m-1", "ana@example.com"))], "count": 1}"#))
            case "/v1/oidc/me":
                return .response(
                    .json(
                        #"{"authenticated": true, "org_id": "o", "member_id": "m-1", "email": "ana@example.com", "name": "Ana", "picture": null, "feature_flags": {"beta": true}}"#
                    ))
            default:
                return .response(.json(#"{"id": "p", "name": "Main", "slug": "main", "description": null}"#))
            }
        }
        let client = makeClient(transport)
        let org = try await client.organizations.current()
        XCTAssertEqual(org.slug, "acme")
        XCTAssertEqual(org.hostedGit, true)

        let projects = try await client.projects.list(ProjectListParams(project: "main")).collect()
        XCTAssertEqual(projects.first?.deploymentId, "d")
        XCTAssertEqual(projects.first?.settings?["x"]?.intValue, 1)
        let project = try await client.projects.get("main")
        XCTAssertEqual(project.id, "p")
        XCTAssertEqual(transport.last?.path, "/v1/projects/main")

        let members = try await client.members.list(
            MemberListParams(memberType: .customer, tag: "customer:acme", ids: ["a", "b"], externalUserIds: ["user:1"])
        ).collect()
        XCTAssertEqual(members.first?.memberType, .business)
        XCTAssertEqual(transport.last?.query["id"], ["a", "b"])
        XCTAssertEqual(transport.last?.query["external_user_id"], ["user:1"])
        XCTAssertEqual(transport.last?.query["member_type"], ["customer"])
        XCTAssertEqual(transport.last?.query["tag"], ["customer:acme"])

        let me = try await client.members.me()
        XCTAssertEqual(me.memberId, "m-1")
        XCTAssertEqual(me.featureFlags?["beta"]?.boolValue, true)
    }

    func testAnnotationEventIdIsUUIDv7() {
        let id = makeAnnotationEventId(now: Date(timeIntervalSince1970: 1_700_000_000))
        let parts = id.split(separator: "-")
        XCTAssertEqual(parts.map(\.count), [8, 4, 4, 4, 12])
        XCTAssertTrue(parts[2].hasPrefix("7"))
        XCTAssertTrue(["8", "9", "a", "b"].contains(parts[3].prefix(1)))
        XCTAssertEqual(String(parts[0]) + String(parts[1]), String(format: "%012llx", UInt64(1_700_000_000_000)))
    }
}
