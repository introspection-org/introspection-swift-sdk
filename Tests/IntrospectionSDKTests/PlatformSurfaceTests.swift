import Foundation
import Synchronization
import Testing

@testable import IntrospectionSDK

private let now = "2026-10-19T00:00:00Z"

private func failing(_ status: Int, _ body: String) -> MockTransport {
    MockTransport(status: status, json: body)
}

private func error(_ operation: () async throws -> some Any) async -> IntrospectionError? {
    do {
        _ = try await operation()
        return nil
    } catch {
        return error as? IntrospectionError
    }
}

@Suite struct ApprovalDecisionTests {
    private static let approvalJSON = #"""
        {"id": "a-1", "org_id": "o", "project_id": "p", "kind": "mission", "status": "denied", "agent_id": "agent",
         "member_id": "m", "mission_id": null, "description": "Send the mail", "resource": null, "budget": null, "summary": null,
         "decided_budget": null, "decided_by_member_id": "m-2", "decided_at": "\#(now)", "expires_at": "\#(now)",
         "created_at": "\#(now)", "updated_at": "\#(now)"}
        """#

    @Test func decidesAsAMember() async throws {
        let transport = MockTransport(json: Self.approvalJSON)
        let approval = try await makeClient(transport).approvals.decide("a/1", ApprovalDecision(status: .denied, decidedBy: .member("m-2")))
        #expect(approval.status == .denied)
        #expect(approval.decidedByMemberId == "m-2")
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.request.url.absoluteString.hasSuffix("/v1/aauth/approvals/a%2F1") == true)
        #expect(transport.last?.json == ["status": "denied", "decided_by": ["member_id": "m-2"]])
    }

    @Test func decidesAsAnIdentityWithLessBudget() async throws {
        let transport = MockTransport(json: Self.approvalJSON)
        _ = try await makeClient(transport).approvals.decide(
            "a-1",
            ApprovalDecision(
                status: .approved, decidedBy: .identity(ApproverIdentity(userId: "u-1")),
                budget: ApprovalBudget(amount: 500, unit: "USD", decimals: 2)))
        #expect(
            transport.last?.json == [
                "status": "approved", "decided_by": ["identity": ["user_id": "u-1"]],
                "budget": ["amount": 500, "unit": "USD", "decimals": 2],
            ])
    }

    @Test func aMissingApprovalIsNotFound() async {
        let transport = failing(404, #"{"detail": "The Person Server is not enabled"}"#)
        let refused = await error {
            try await makeClient(transport).approvals.decide("a-1", ApprovalDecision(status: .denied, decidedBy: .member("m")))
        }
        #expect(refused?.kind == .notFound)
    }
}

@Suite struct EndpointCreateTests {
    private static let endpointJSON = #"""
        {"id": "e-1", "org_id": "o", "project_id": "p", "name": "walk-api", "host": "walk-api.example.com", "base_url": null,
         "kind": "api", "metadata": {"extra_hosts": []}, "headers": {"X-Walk": "${WALK_SECRET}"}, "header_names": ["X-Walk"],
         "credential_refs": ["WALK_SECRET"], "created_by_member_id": "m", "created_at": "\#(now)", "updated_at": "\#(now)",
         "mcp_check": {"check_id": "c-1", "status": "ok", "requested_at": "\#(now)", "requested_by_member_id": null,
         "checked_at": "\#(now)", "server_name": "hello", "tools": ["echo"], "error_message": null}}
        """#

    @Test func createsAnEndpoint() async throws {
        let transport = MockTransport(json: Self.endpointJSON)
        let endpoint = try await makeClient(transport).endpoints.create(
            EndpointCreate(
                name: "walk-api", host: "walk-api.example.com", headers: ["X-Walk": "${WALK_SECRET}"], kind: .api,
                baseUrl: "https://walk-api.example.com/v1", verifyPath: "/health"),
            project: "walk")
        #expect(endpoint.credentialRefs == ["WALK_SECRET"])
        #expect(endpoint.mcpCheck?.status == .ok)
        #expect(endpoint.mcpCheck?.tools == ["echo"])
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/endpoints")
        #expect(transport.last?.query == ["project": ["walk"]])
        #expect(
            transport.last?.json == [
                "name": "walk-api", "host": "walk-api.example.com", "headers": ["X-Walk": "${WALK_SECRET}"], "kind": "api",
                "base_url": "https://walk-api.example.com/v1", "verify_path": "/health",
            ])
    }

    @Test func headersAreAlwaysSent() async throws {
        let transport = MockTransport(json: Self.endpointJSON)
        _ = try await makeClient(transport).endpoints.create(EndpointCreate(name: "n", host: "h.example.com"))
        #expect(transport.last?.json == ["name": "n", "host": "h.example.com", "headers": [:]])
        #expect(transport.last?.query == [:])
    }

    @Test func aFailedVerificationIsRefused() async {
        let transport = failing(422, #"{"detail": "verify_path answered 500"}"#)
        let refused = await error { try await makeClient(transport).endpoints.create(EndpointCreate(name: "n", host: "h.example.com")) }
        #expect(refused?.kind == .validation)
    }
}

@Suite struct RepositoryAccessTokenTests {
    @Test func mintsAToken() async throws {
        let transport = MockTransport(
            json: #"{"provider": "github", "token": "ghs_x", "expires_at": "\#(now)", "repository": "acme/hello"}"#)
        let grant = try await makeClient(transport).repositories.accessToken("r/1", permissions: ["contents": "read"])
        #expect(grant.token.plaintext == "ghs_x")
        #expect(grant.repository == "acme/hello")
        #expect("\(grant)".contains("ghs_x") == false)
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.request.url.absoluteString.hasSuffix("/v1/repositories/r%2F1/access-token") == true)
        #expect(transport.last?.json == ["permissions": ["contents": "read"]])
    }

    @Test func noPermissionsSendsAnEmptyObject() async throws {
        let transport = MockTransport(json: #"{"provider": "github", "token": "t", "expires_at": "\#(now)", "repository": "a/b"}"#)
        _ = try await makeClient(transport).repositories.accessToken("r-1")
        #expect(transport.last?.json == [:])
    }

    @Test func aSessionWithNoRuntimeIsRefused() async {
        let transport = failing(403, #"{"detail": "Only a runtime session may mint a repository token"}"#)
        let refused = await error { try await makeClient(transport).repositories.accessToken("r-1") }
        #expect(refused?.status == 403)
    }
}

@Suite struct RemotesTests {
    @Test func readsTheConnectionProtocol() async throws {
        let transport = MockTransport(
            json: #"""
                {"endpoint": "/v1/remotes/connect", "protocol": "websocket",
                 "authentication": {"method": "bearer", "description": "A development credential", "example": "Authorization: Bearer ..."},
                 "handshake": ["attach_request"], "schema_version": 3, "encoding": "protobuf",
                 "message_protocol": {"remote_to_cloud": [{"frame": "attach_request", "description": "Attach"}],
                 "cloud_to_remote": [{"frame": "attach_response", "description": "Attached"}]}}
                """#)
        let docs = try await makeClient(transport).remotes.connectDocs()
        #expect(docs.protocol == "websocket")
        #expect(docs.schemaVersion == 3)
        #expect(docs.authentication.method == "bearer")
        #expect(docs.messageProtocol.remoteToCloud.map(\.frame) == ["attach_request"])
        #expect(docs.messageProtocol.cloudToRemote.map(\.frame) == ["attach_response"])
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.path == "/v1/remotes/connect")
    }

    @Test func anUnauthenticatedReadFails() async {
        let transport = failing(401, #"{"detail": "Not authenticated"}"#)
        let refused = await error { try await makeClient(transport).remotes.connectDocs() }
        #expect(refused?.kind == .authentication)
    }
}

@Suite struct SignInRouteTests {
    @Test func aDevelopmentCredentialExchangesAnAccessToken() async throws {
        let transport = MockTransport(json: #"{"access_token": "dev", "token_type": "bearer", "expires_in": 900}"#)
        let token = try await makeClient(transport).auth.developmentCredential(accessToken: "login")
        #expect(token.accessToken == "dev")
        #expect(transport.last?.path == "/v1/oauth/token")
        let form = transport.last?.bodyString ?? ""
        #expect(form.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange"))
        #expect(form.contains("client_id=cli"))
        #expect(form.contains("subject_token=login"))
        #expect(form.contains("subject_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token"))
    }

    @Test func aDevelopmentCredentialRefusalNamesTheGrantError() async {
        let transport = failing(400, #"{"error": "invalid_grant", "error_description": "not a login"}"#)
        let refused = await error { try await makeClient(transport).auth.developmentCredential(accessToken: "x") }
        #expect(refused?.oauthError == "invalid_grant")
    }

    @Test func logoutSendsTheCookieAndTakesTheRedirectAsTheAnswer() async throws {
        let transport = MockTransport { _, _ in
            .response(HTTPResponse(status: 307, headers: ["location": "https://idp.example.com/logout"], body: Data()))
        }
        try await makeClient(transport).auth.oidcLogout(cpSession: "cookie-value")
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.path == "/v1/oidc/logout")
        #expect(transport.last?.request.headers["Cookie"] == "intro_cp_session=cookie-value")
        #expect(transport.last?.request.headers["Authorization"] == nil)
        #expect(transport.last?.request.followRedirects == false)
    }

    @Test func aFailedLogoutThrows() async {
        let transport = failing(500, #"{"detail": "boom"}"#)
        let refused = await error { try await makeClient(transport).auth.oidcLogout(cpSession: "c") }
        #expect(refused?.status == 500)
    }

    @Test func requestsFollowRedirectsByDefault() {
        #expect(HTTPRequest(method: "GET", url: URL(string: "https://example.com")!).followRedirects)
    }

    @Test func aNetworkFailureIsPolledThrough() async throws {
        let transport = MockTransport { _, attempt in
            attempt == 0
                ? .failure(URLError(.notConnectedToInternet))
                : .response(.json(#"{"access_token": "signed-in", "token_type": "bearer"}"#))
        }
        let device = DeviceAuthorization(deviceCode: "d", userCode: "u", verificationUri: "https://x", expiresIn: 600, interval: 1)
        let auth = AuthAPI(controlPlaneURL: URL(string: "https://cp.test")!, transport: transport, options: .init(maxRetries: 0))
        let token = try await auth.pollDeviceToken(device, sleep: { _ in })
        #expect(token.accessToken == "signed-in")
    }

    @Test(arguments: [(0, 1.0), (5, 5.0), (3600, 60.0)])
    func thePollIntervalStaysInBounds(interval: Int, expected: TimeInterval) async throws {
        let transport = MockTransport(json: #"{"access_token": "t", "token_type": "bearer"}"#)
        let device = DeviceAuthorization(deviceCode: "d", userCode: "u", verificationUri: "https://x", expiresIn: 600, interval: interval)
        let slept = Mutex<[TimeInterval]>([])
        _ = try await makeClient(transport).auth.pollDeviceToken(device, sleep: { seconds in slept.withLock { $0.append(seconds) } })
        #expect(slept.withLock { $0 } == [expected])
    }
}

@Suite struct AppConnectionFilterTests {
    private static let grantJSON = #"""
        {"id": "c-1", "owner": "project", "member_id": null,
         "connector": {"id": "k-1", "slug": "hello-mcp", "provider": "hello-mcp", "peering": null}, "subject_type": "app",
         "app": "hello-mcp", "provider_account_id": null, "account_name": null, "healthy": true, "status": "active",
         "last_verified_at": "\#(now)", "created_by_member_id": "m", "created_at": "\#(now)", "updated_at": "\#(now)"}
        """#

    @Test func aProjectGrantHasNoMember() async throws {
        let transport = MockTransport(json: #"{"records": [\#(Self.grantJSON)], "count": 1, "next": null}"#)
        let page = try await makeClient(transport).connections.list(
            AppConnectionListParams(connectorId: "k-1", subjectType: .app, peering: "peer", limit: 5)
        ).firstPage()
        let grant = try #require(page.records.first)
        #expect(grant.memberId == nil)
        #expect(grant.owner == .project)
        #expect(grant.connector?.slug == "hello-mcp")
        #expect(grant.status == .active)
        #expect(transport.last?.path == "/v1/connections")
        #expect(transport.last?.query == ["connector_id": ["k-1"], "subject_type": ["app"], "peering": ["peer"], "limit": ["5"]])
    }

    @Test func aMissingConnectorIsNotFound() async {
        let transport = failing(404, #"{"detail": "Not found"}"#)
        let refused = await error {
            try await makeClient(transport).connections.list(AppConnectionListParams(connectorId: "k")).firstPage()
        }
        #expect(refused?.kind == .notFound)
    }
}
