import Foundation
import Testing

@testable import IntrospectionSDK

private let now = "2026-10-19T00:00:00Z"

private func noContent() -> MockTransport.Reply {
    .response(HTTPResponse(status: 204, headers: [:], body: Data()))
}

private func page(_ record: String) -> String {
    #"{"records": [\#(record)], "count": 1, "total_count": null, "next": null}"#
}

private let apiKeyJSON = #"""
    {"id": "key-1", "org_id": "o", "project_id": "p", "created_at": "\#(now)", "name": "ci", "environment": "production",
     "allow": ["evals"], "scope": "*", "member_id": null, "key_prefix": "intro_", "key_suffix": "abcd",
     "redacted_key": "intro_...abcd", "status": "active", "expires_at": null, "last_used_at": null,
     "acknowledged_at": null, "key_display": "intro_...abcd", "prefix": "intro_"}
    """#

private let applicationJSON = #"""
    {"id": "app-1", "org_id": "o", "project_id": "p", "created_at": "\#(now)", "updated_at": "\#(now)", "name": "web",
     "application_type": "spa", "environment": "production", "redirect_uris": ["https://app.example.com/cb"],
     "allowed_origins": [], "allowed_scopes": ["openid"], "client_id": "app_123", "agent_member_id": null,
     "allowed_grants": ["authorization_code", "refresh_token"], "last_used_at": null, "revoked_at": null,
     "created_by_member_id": "m"}
    """#

private let idpJSON = #"""
    {"id": "idp-1", "org_id": "o", "application_id": "app-1", "created_at": "\#(now)", "updated_at": "\#(now)",
     "idp_provider": "okta", "issuer": "https://acme.okta.com", "client_id": "okta_client", "scopes": ["openid"],
     "external_org_id": null, "external_idp_id": null, "audience_client_id": null, "status": "active",
     "error_message": null, "disabled_at": null, "client_secret": null, "is_active": true}
    """#

private let secretJSON = #"""
    {"id": "sec-1", "org_id": "o", "application_id": "app-1", "created_at": "\#(now)", "updated_at": "\#(now)",
     "secret_prefix": "sec_", "secret_suffix": "wxyz", "name": "ci", "expires_at": null, "disabled_at": null,
     "last_used_at": null, "created_by_member_id": "m", "secret": "sec_plaintext_wxyz", "status": "active"}
    """#

private let keyJSON = #"""
    {"id": "jwk-1", "org_id": "o", "application_id": "app-1", "created_at": "\#(now)", "updated_at": "\#(now)",
     "kid": "kid-1", "algorithm": "RS256", "public_key": "-----BEGIN PUBLIC KEY-----", "created_by_member_id": null}
    """#

private let credentialJSON = #"""
    {"id": "cred-1", "org_id": "o", "project_id": "p", "created_at": "\#(now)", "updated_at": "\#(now)",
     "name": "OPENAI_API_KEY", "runtime_id": null, "runtime_group_id": "g-1", "environment": null, "has_secret": true,
     "secret_display": "sk-...wxyz", "secret_set_at": "\#(now)", "created_by_member_id": "m"}
    """#

private let variableJSON = #"""
    {"id": "var-1", "org_id": "o", "project_id": "p", "created_at": "\#(now)", "updated_at": "\#(now)", "name": "MODEL",
     "kind": "value", "value": "gpt", "runtime_id": "rt-1", "runtime_group_id": null, "environment": "staging",
     "created_by_member_id": "m"}
    """#

private let integrationJSON = #"""
    {"id": "int-1", "org_id": "o", "created_at": "\#(now)", "updated_at": "\#(now)", "type": "github", "name": "acme",
     "external_id": null, "status": "pending", "created_by_member_id": "m", "token_expires_at": null,
     "data": {"installation": 7}, "metadata": null}
    """#

private let judgeJSON = #"""
    {"id": "judge-1", "org_id": "o", "project_id": "p", "runtime_group_id": "g-1", "created_at": "\#(now)",
     "updated_at": "\#(now)", "name": "helpful", "description": null, "enabled": true, "sample_rate": 0.25,
     "source": "recipe", "repository_id": "repo-1", "recipe_git_commit_sha": "abc", "source_path": "judges/helpful.yaml",
     "definition_hash": "h1", "created_by_member_id": null}
    """#

@Suite struct ProjectAdminTests {
    // MARK: Secret

    @Test func aSecretNeverPrintsItsPlaintext() throws {
        let secret: Secret = "hunter2"
        #expect(secret.plaintext == "hunter2")
        #expect("\(secret)" == "Secret(<redacted>)")
        #expect(String(reflecting: secret) == "Secret(<redacted>)")
        var dumped = ""
        dump(CredentialCreate(name: "K", secret: secret), to: &dumped)
        #expect(!dumped.contains("hunter2"))
        let encoded = try JSONCoding.encoder.encode(secret)
        #expect(String(decoding: encoded, as: UTF8.self) == #""hunter2""#)
        #expect(try JSONCoding.decoder.decode(Secret.self, from: encoded) == secret)
    }

    // MARK: API keys

    @Test func apiKeyCreateNamesTheProjectAndRedactsThePlaintext() async throws {
        let created = apiKeyJSON.replacingOccurrences(
            of: #""prefix": "intro_"}"#, with: #""prefix": "intro_", "api_key": "intro_plain_abcd"}"#)
        let transport = MockTransport(status: 201, json: created)
        let key = try await makeClient(transport).apiKeys.create(ApiKeyCreate(name: "ci", allow: [.evals]), project: "acme/web")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/api-keys")
        #expect(transport.last?.query["project"] == ["acme/web"])
        #expect(transport.last?.json == ["name": "ci", "allow": ["evals"]])
        #expect(transport.last?.request.url.host == "cp.test")
        #expect(key.key.status == .active)
        #expect(key.key.allow == [.evals])
        #expect(key.key.createdAt == ISO8601.parse(now))
        #expect(key.apiKey?.plaintext == "intro_plain_abcd")
        #expect(!"\(key)".contains("intro_plain_abcd"))
        #expect(!String(reflecting: key).contains("intro_plain_abcd"))
        let roundTrip = try JSONCoding.decoder.decode(ApiKeyCreated.self, from: JSONCoding.encoder.encode(key))
        #expect(roundTrip == key)
    }

    @Test func apiKeyListUnwrapsTheEnvelopeAndDeleteSendsTheGrace() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("GET", _): return .response(.json(#"{"api_keys": [\#(apiKeyJSON)]}"#))
            case ("DELETE", _): return noContent()
            case ("POST", "/v1/api-keys/key-1/acknowledge"): return .response(.json(#"{"acknowledged": true}"#))
            default: return .response(.json(apiKeyJSON))
            }
        }
        let keys = makeClient(transport).apiKeys

        let listed = try await keys.list(ApiKeyListParams(project: "web", expiring: true))
        #expect(listed.map(\.id) == ["key-1"])
        #expect(listed.first?.keyDisplay == "intro_...abcd")
        #expect(transport.last?.query == ["project": ["web"], "expiring": ["true"]])

        let updated = try await keys.update("key-1", ApiKeyUpdate(name: "renamed", allow: []), project: "web")
        #expect(updated.id == "key-1")
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/api-keys/key-1")
        #expect(transport.last?.json == ["name": "renamed", "allow": []])

        try await keys.delete("key-1", expiresIn: 3600, project: "web")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.query == ["project": ["web"], "expires_in": ["3600"]])
        try await keys.delete("key/1")
        #expect(transport.last?.request.url.absoluteString == "https://cp.test/v1/api-keys/key%2F1")

        let ack = try await keys.acknowledge("key-1")
        #expect(ack.acknowledged == true)
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.request.body == nil)
    }

    // MARK: Applications

    @Test func applicationCrudAddressesTheProject() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return noContent()
            case ("GET", "/v1/applications"): return .response(.json(page(applicationJSON)))
            default: return .response(.json(applicationJSON))
            }
        }
        let applications = makeClient(transport).applications

        let all = try await applications.list(ApplicationListParams(project: "web", limit: 5)).collect()
        #expect(all.first?.applicationType == .spa)
        #expect(all.first?.allowedGrants == [.authorizationCode, .refreshToken])
        #expect(transport.last?.query == ["project": ["web"], "limit": ["5"]])

        _ = try await applications.create(
            ApplicationCreate(name: "web", applicationType: .spa, redirectUris: ["https://app.example.com/cb"]), project: "web")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.json == ["name": "web", "application_type": "spa", "redirect_uris": ["https://app.example.com/cb"]])

        let fetched = try await applications.get("app-1", project: "web")
        #expect(fetched.clientId == "app_123")
        #expect(transport.last?.path == "/v1/applications/app-1")
        #expect(transport.last?.query["project"] == ["web"])

        _ = try await applications.update("app-1", ApplicationUpdate(allowedScopes: ["openid", "email"]))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["allowed_scopes": ["openid", "email"]])
        #expect(transport.last?.query == [:])

        try await applications.delete("app-1", project: "web")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.path == "/v1/applications/app-1")
    }

    @Test func applicationIdpsSecretsAndKeysNestUnderTheApplication() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return noContent()
            case ("GET", "/v1/applications/app-1/idps"): return .response(.json(page(idpJSON)))
            case ("GET", "/v1/applications/app-1/secrets"): return .response(.json(page(secretJSON)))
            case ("GET", "/v1/applications/app-1/keys"): return .response(.json("[\(keyJSON)]"))
            case (_, let path) where path.hasSuffix("/idps"): return .response(.json(idpJSON, status: 201))
            case (_, let path) where path.hasSuffix("/secrets"): return .response(.json(secretJSON, status: 201))
            default: return .response(.json(keyJSON, status: 201))
            }
        }
        let applications = makeClient(transport).applications

        let idps = try await applications.idps.list("app-1", ApplicationChildListParams(limit: 10)).collect()
        #expect(idps.first?.idpProvider == .okta)
        #expect(idps.first?.isActive == true)
        #expect(transport.last?.query == ["limit": ["10"]])
        let idp = try await applications.idps.create(
            "app-1",
            ApplicationIdpCreate(idpProvider: .okta, issuer: "https://acme.okta.com", clientId: "okta_client", clientSecret: "okta_secret"))
        #expect(idp.status == .active)
        #expect(
            transport.last?.json == [
                "idp_provider": "okta", "issuer": "https://acme.okta.com", "client_id": "okta_client", "client_secret": "okta_secret",
            ])
        try await applications.idps.delete("app-1", "idp-1")
        #expect(transport.last?.path == "/v1/applications/app-1/idps/idp-1")

        let secrets = try await applications.secrets.list("app-1").collect()
        #expect(secrets.first?.status == .active)
        let secret = try await applications.secrets.create("app-1", name: "ci")
        #expect(transport.last?.json == ["name": "ci"])
        #expect(secret.secret?.plaintext == "sec_plaintext_wxyz")
        #expect(!"\(secret)".contains("sec_plaintext_wxyz"))
        try await applications.secrets.delete("app-1", "sec-1", expiresIn: 600)
        #expect(transport.last?.path == "/v1/applications/app-1/secrets/sec-1")
        #expect(transport.last?.query == ["expires_in": ["600"]])

        let keys = try await applications.keys.list("app-1")
        #expect(keys.first?.kid == "kid-1")
        let key = try await applications.keys.create("app-1")
        #expect(key.algorithm == "RS256")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.request.body == nil)
        try await applications.keys.delete("app-1", "jwk-1")
        #expect(transport.last?.path == "/v1/applications/app-1/keys/jwk-1")
        #expect(transport.requests.allSatisfy { $0.request.url.host == "cp.test" })
    }

    // MARK: Credentials and variables

    @Test func credentialsWriteTheSecretAndReadOnlyItsHint() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return noContent()
            case ("GET", "/v1/credentials"): return .response(.json(page(credentialJSON)))
            default: return .response(.json(credentialJSON))
            }
        }
        let credentials = makeClient(transport).credentials

        let listed = try await credentials.list(
            RuntimeSettingListParams(project: "web", runtimeId: "rt-1", runtime: "agent", environment: .staging, limit: 20)
        ).firstPage()
        #expect(listed.records.first?.hasSecret == true)
        #expect(listed.records.first?.secretDisplay == "sk-...wxyz")
        #expect(
            transport.last?.query == [
                "project": ["web"], "runtime_id": ["rt-1"], "runtime": ["agent"], "environment": ["staging"], "limit": ["20"],
            ])

        let created = try await credentials.create(CredentialCreate(name: "OPENAI_API_KEY", secret: "sk-live", runtimeGroupId: "g-1"))
        #expect(created.runtimeGroupId == "g-1")
        #expect(transport.last?.json == ["name": "OPENAI_API_KEY", "secret": "sk-live", "runtime_group_id": "g-1"])

        _ = try await credentials.get("cred-1", project: "web")
        #expect(transport.last?.path == "/v1/credentials/cred-1")
        _ = try await credentials.update("cred-1", CredentialUpdate(secret: "sk-rotated"), project: "web")
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["secret": "sk-rotated"])
        try await credentials.delete("cred-1")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.path == "/v1/credentials/cred-1")
    }

    @Test func variablesHaveNoReadOne() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return noContent()
            case ("GET", _): return .response(.json(page(variableJSON)))
            default: return .response(.json(variableJSON))
            }
        }
        let variables = makeClient(transport).variables

        let all = try await variables.list(RuntimeSettingListParams(environment: .staging)).collect()
        #expect(all.first?.kind == .value)
        #expect(all.first?.environment == .staging)
        #expect(transport.last?.query == ["environment": ["staging"]])

        _ = try await variables.create(VariableCreate(name: "MODEL", value: "gpt", runtimeId: "rt-1"), project: "web")
        #expect(transport.last?.json == ["name": "MODEL", "value": "gpt", "runtime_id": "rt-1"])
        #expect(transport.last?.query == ["project": ["web"]])
        _ = try await variables.update("var-1", VariableUpdate(value: "OPENAI_API_KEY", kind: .credential))
        #expect(transport.last?.path == "/v1/variables/var-1")
        #expect(transport.last?.json == ["value": "OPENAI_API_KEY", "kind": "credential"])
        try await variables.delete("var-1", project: "web")
        #expect(transport.last?.request.method == "DELETE")
    }

    // MARK: Integrations and judges

    @Test func integrationsAreOrgWideAndSendTheirType() async throws {
        let transport = MockTransport { request, _ in
            switch (request.method, request.url.path) {
            case ("DELETE", _): return noContent()
            case ("GET", "/v1/integrations"): return .response(.json(page(integrationJSON)))
            default: return .response(.json(integrationJSON))
            }
        }
        let integrations = makeClient(transport).integrations

        let all = try await integrations.list(IntegrationListParams(limit: 2)).collect()
        #expect(all.first?.integrationType == .github)
        #expect(all.first?.data?["installation"] == 7)
        #expect(transport.last?.query == ["limit": ["2"]])

        let created = try await integrations.create(IntegrationCreate(integrationType: .github, name: "acme"))
        #expect(created.status == .pending)
        #expect(transport.last?.json == ["type": "github", "name": "acme"])
        #expect(transport.last?.query == [:])

        _ = try await integrations.get("int-1")
        #expect(transport.last?.path == "/v1/integrations/int-1")
        _ = try await integrations.update(
            "int-1", IntegrationUpdate(code: "oauth-code", redirectUri: "https://app.example.com/cb", slackInteractivityEnabled: false))
        #expect(
            transport.last?.json == [
                "code": "oauth-code", "redirect_uri": "https://app.example.com/cb", "slack_interactivity_enabled": false,
            ])
        try await integrations.delete("int-1")
        #expect(transport.last?.request.method == "DELETE")
    }

    @Test func judgesUpdateOnlyTheirOperationalState() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/judges" ? .response(.json(page(judgeJSON))) : .response(.json(judgeJSON))
        }
        let judges = makeClient(transport).judges

        let listed = try await judges.list(JudgeListParams(project: "web", runtimeGroupId: "g-1")).firstPage()
        #expect(listed.records.first?.sampleRate == 0.25)
        #expect(listed.records.first?.sourcePath == "judges/helpful.yaml")
        #expect(transport.last?.query == ["project": ["web"], "runtime_group_id": ["g-1"]])

        let judge = try await judges.get("judge-1")
        #expect(judge.definitionHash == "h1")
        _ = try await judges.update("judge-1", JudgeUpdate(enabled: false, sampleRate: 0.5), project: "web")
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.path == "/v1/judges/judge-1")
        #expect(transport.last?.json == ["enabled": false, "sample_rate": 0.5])
        #expect(transport.last?.query == ["project": ["web"]])
    }
}
