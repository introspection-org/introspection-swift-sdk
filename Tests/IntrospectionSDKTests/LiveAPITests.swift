import Foundation
import Testing

@testable import IntrospectionSDK

/// CRUD walks against a real deployment: a local stack seeded by
/// `introspection-cloud`'s `scripts/seed_sdk_project.py`, or the staging
/// `sdk-tests` project. The `MockTransport` suites pin what the SDK sends; these
/// pin that a deployed API answers it, and they are what the backend coverage
/// run drives. Each test creates what it reads and deletes it again.
///
/// Skipped unless `INTROSPECTION_LIVE=1`; each test also skips when its own
/// settings are absent. Run with `swift test --filter LiveAPITests`.
///
/// Settings: `INTROSPECTION_BASE_API_URL` (or `INTROSPECTION_BASE_URL`), the
/// Control Plane; `INTROSPECTION_CLIENT_ID` / `INTROSPECTION_CLIENT_SECRET`, the
/// project's service account, whose `client_credentials` response names the Data
/// Plane (no Data Plane URL is configured); `INTROSPECTION_PROJECT`;
/// `INTROSPECTION_MEMBER_TOKEN`, a member's Data Plane token, for annotation tags,
/// which no service account is granted; `INTROSPECTION_CP_SESSION`, a member's
/// encoded `intro_cp_session` cookie, for member reads; `INTROSPECTION_RUNTIME_GROUP_ID`
/// for automations; and, when set, `INTROSPECTION_PROJECT_ID` and
/// `INTROSPECTION_ORG_ID`, checked against what the server returns.
@Suite(.enabled(if: Live.isEnabled, "Live tests run only with INTROSPECTION_LIVE=1"))
struct LiveAPITests {
    private let limit = 500

    /// The settings the service-account client reads.
    private static let serviceAccount = ["INTROSPECTION_CLIENT_ID", "INTROSPECTION_CLIENT_SECRET", "INTROSPECTION_PROJECT"]

    private func setting(_ name: String) throws -> String {
        guard let value = Live.value(name) else { try Test.cancel("\(name) is not set") }
        return value
    }

    private func controlPlaneURL() throws -> URL {
        let raw = try Live.value("INTROSPECTION_BASE_API_URL") ?? setting("INTROSPECTION_BASE_URL")
        guard let url = URL(string: raw) else { try Test.cancel("Invalid Control Plane URL: \(raw)") }
        return url
    }

    /// The project's service account, on the Data Plane its token response names.
    private func serviceAccountClient() async throws -> IntrospectionClient {
        let client = try await IntrospectionClient.fromServiceAccount(
            clientId: try setting("INTROSPECTION_CLIENT_ID"),
            clientSecret: try setting("INTROSPECTION_CLIENT_SECRET"),
            project: try setting("INTROSPECTION_PROJECT"),
            controlPlaneURL: try controlPlaneURL()
        )
        #expect(client.configuration.dataPlaneURL != nil, "the client_credentials response carries dp_url")
        return client
    }

    /// `token` on the Data Plane `discoveredFrom` was built for.
    private func client(token: String, discoveredFrom primary: IntrospectionClient) throws -> IntrospectionClient {
        IntrospectionClient(
            configuration: IntrospectionClient.Configuration(
                controlPlaneURL: try controlPlaneURL(),
                dataPlaneURL: primary.dataPlane.baseURL,
                controlPlaneCredentials: BearerToken(token)
            ))
    }

    /// A member's Control Plane session cookie, sent alone: the Control Plane authenticates a
    /// bearer ahead of the cookie, so a token beside it would answer 403 on member reads.
    private func sessionClient() throws -> IntrospectionClient {
        let cookie = "intro_cp_session=\(try setting("INTROSPECTION_CP_SESSION"))"
        return IntrospectionClient(
            configuration: IntrospectionClient.Configuration(
                controlPlaneURL: try controlPlaneURL(),
                options: HTTPClient.Options(additionalHeaders: ["Cookie": cookie])
            ))
    }

    /// A name no other run shares, so concurrent runs never collide and a crashed run's leftover is recognisable.
    private func unique(_ prefix: String) -> String {
        "sdk-\(prefix)-\(UUID().uuidString.lowercased())"
    }

    private func expectFailure<R>(
        _ kind: IntrospectionError.Kind, status: Int, sourceLocation: SourceLocation = #_sourceLocation,
        _ operation: () async throws -> R
    ) async {
        let error = await #expect(throws: IntrospectionError.self, sourceLocation: sourceLocation) { _ = try await operation() }
        #expect(error?.kind == kind, "\(String(describing: error))", sourceLocation: sourceLocation)
        #expect(error?.status == status, "\(String(describing: error))", sourceLocation: sourceLocation)
    }

    /// Run `walk`; when it fails, run `cleanup` on a best-effort basis before rethrowing.
    private func cleaningUp(_ walk: () async throws -> Void, cleanup: () async throws -> Void) async throws {
        do {
            try await walk()
        } catch {
            try? await cleanup()
            throw error
        }
    }

    // MARK: Files

    @Test(Live.requires(serviceAccount))
    func filesCrudWalk() async throws {
        let files = try await serviceAccountClient().files
        let name = unique("file") + ".txt"
        let content = "hello from the swift sdk"

        let created = try await files.createText(
            FileCreateText(content: content, name: name, mimeType: "text/plain", metadata: ["suite": "live"]))
        try await cleaningUp {
            if let projectId = Live.value("INTROSPECTION_PROJECT_ID") { #expect(created.projectId == projectId) }

            let fetched = try await files.get(created.id)
            #expect(fetched.name == name)

            let listed = try await files.list(FileListParams(includeTotal: true, name: name)).collect(limit: limit)
            #expect(listed.contains { $0.id == created.id })

            let renamed = unique("renamed") + ".txt"
            let updated = try await files.update(created.id, FileUpdate(name: renamed, metadata: ["suite": "live-updated"]))
            #expect(updated.name == renamed)

            let body = try await files.download(created.id)
            #expect(String(decoding: body, as: UTF8.self) == content)

            let version = try await files.versions.create(
                created.id, FileUpload(data: Data("second version".utf8), filename: renamed, name: renamed, contentType: "text/plain"))
            let versions = try await files.versions.list(created.id).collect(limit: limit)
            #expect(versions.contains { $0.id == version.id })
            _ = try await files.versions.get(created.id, version.id)

            try await files.delete(created.id)
            await expectFailure(.notFound, status: 404) { try await files.get(created.id) }
        } cleanup: {
            try await files.delete(created.id)
        }
    }

    // MARK: Upload and shares

    @Test(Live.requires(serviceAccount))
    func uploadAndSharesCrudWalk() async throws {
        let client = try await serviceAccountClient()
        let name = unique("shared") + ".bin"
        let file = try await client.files.upload(
            FileUpload(data: Data("shared bytes".utf8), filename: name, name: name, contentType: "application/octet-stream"))
        try await cleaningUp {
            let tag = unique("audience")
            let share = try await client.shares.create(ShareCreate(resourceType: .file, resourceId: file.id, grantedTag: tag))
            #expect(share.grantedTag == tag)
            try await cleaningUp {
                let fetched = try await client.shares.get(share.id)
                #expect(fetched.resourceId == file.id)

                let listed = try await client.shares.list(ShareListParams(resourceType: .file, resourceId: file.id))
                    .collect(limit: limit)
                #expect(listed.contains { $0.id == share.id })

                // `visible_from` windows a conversation's history; a file share refuses it.
                await expectFailure(.validation, status: 422) {
                    try await client.shares.update(share.id, ShareUpdate(visibleFrom: Date(timeIntervalSince1970: 1_767_225_600)))
                }

                try await client.shares.delete(share.id)
                await expectFailure(.notFound, status: 404) { try await client.shares.get(share.id) }
            } cleanup: {
                try await client.shares.delete(share.id)
            }
            try await client.files.delete(file.id)
        } cleanup: {
            try await client.files.delete(file.id)
        }
    }

    // MARK: Tags

    @Test(Live.requires(serviceAccount + ["INTROSPECTION_MEMBER_TOKEN"]))
    func tagsCrudWalk() async throws {
        let client = try await serviceAccountClient()
        let accessTags = client.tags
        // `annotations:write` is granted to members only, never to a service account.
        let annotationTags = try self.client(token: try setting("INTROSPECTION_MEMBER_TOKEN"), discoveredFrom: client).tags
        let access = unique("access")

        _ = try await accessTags.create(.access(name: access))
        let created = try await annotationTags.create(.annotation(name: unique("label"), color: "#f97316"))
        try await cleaningUp {
            #expect(created.kind == .annotation)
            #expect(try await accessTags.get(.access, access).name == access)
            #expect(try await annotationTags.get(.annotation, created.name).color?.lowercased() == "#f97316")

            let listed = try await annotationTags.list(TagListParams(kind: .annotation)).collect(limit: limit)
            #expect(listed.contains { $0.name == created.name })

            let updated = try await annotationTags.update(
                .annotation, created.name, TagUpdate(color: "#22c55e", description: "recolored"))
            #expect(updated.color?.lowercased() == "#22c55e")
            #expect(updated.description == "recolored")

            try await annotationTags.delete(.annotation, created.name)
            try await accessTags.delete(.access, access)
            await expectFailure(.notFound, status: 404) { try await annotationTags.get(.annotation, created.name) }
        } cleanup: {
            try? await annotationTags.delete(.annotation, created.name)
            try await accessTags.delete(.access, access)
        }
    }

    // MARK: Automations

    /// An automation dispatches into a runtime group, which the seed does not create.
    @Test(Live.requires(serviceAccount + ["INTROSPECTION_RUNTIME_GROUP_ID"]))
    func automationsCrudWalk() async throws {
        let automations = try await serviceAccountClient().automations
        let created = try await automations.create(
            AutomationCreate(
                name: unique("automation"),
                triggerType: .manual,
                description: "created by the swift sdk live suite",
                prompt: "Reply with exactly: hi",
                runtimeGroupId: try setting("INTROSPECTION_RUNTIME_GROUP_ID"),
                enabled: false
            ))
        try await cleaningUp {
            #expect(try await automations.get(created.id).id == created.id)

            let listed = try await automations.list().collect(limit: limit)
            #expect(listed.contains { $0.id == created.id })

            let updated = try await automations.update(created.id, AutomationUpdate(description: "updated"))
            #expect(updated.description == "updated")

            try await automations.delete(created.id)
            let remaining = try await automations.list().collect(limit: limit)
            #expect(!remaining.contains { $0.id == created.id })
            // Fails today: the DP reads automations with deleted ones included and
            // returns no deleted_at, so a deleted automation reads back as live.
            await expectFailure(.notFound, status: 404) { try await automations.get(created.id) }
        } cleanup: {
            try await automations.delete(created.id)
        }
    }

    // MARK: Control Plane reads

    @Test(Live.requires(serviceAccount))
    func controlPlaneReads() async throws {
        let client = try await serviceAccountClient()
        let project = try setting("INTROSPECTION_PROJECT")

        _ = try await client.runtimes.list(RuntimeListParams(project: project)).collect(limit: limit)
        _ = try await client.recipes.list(RecipeListParams(project: project)).collect(limit: limit)
        _ = try await client.experiments.list(ExperimentListParams(project: project)).collect(limit: limit)
        _ = try await client.connectors.list().collect(limit: limit)
        await expectFailure(.notFound, status: 404) { try await client.recipes.get(UUID().uuidString.lowercased()) }
    }

    // MARK: Telemetry reads

    @Test(Live.requires(serviceAccount))
    func telemetryReads() async throws {
        let client = try await serviceAccountClient()
        _ = try await client.conversations.list().firstPage()
        let events = try await client.events.list(EventListParams(eventName: .annotation)).firstPage()
        #expect(events.records.allSatisfy { $0.eventName == .annotation })
    }

    // MARK: Members with a Control Plane session

    /// `members:read` is granted to members only, never to a service account.
    @Test(Live.requires("INTROSPECTION_CP_SESSION"))
    func membersReadsWithSession() async throws {
        let members = try sessionClient().members
        let listed = try await members.list().collect(limit: limit)
        let first = try #require(listed.first, "the seeded org has members")
        let fetched = try await members.get(first.id)
        #expect(fetched.id == first.id)
        if let orgId = Live.value("INTROSPECTION_ORG_ID") { #expect(fetched.orgId == orgId) }
    }

    // MARK: Rejected credentials

    @Test(Live.requires(serviceAccount))
    func rejectedCredentialsAreTyped() async throws {
        let auth = AuthAPI(controlPlaneURL: try controlPlaneURL())
        await expectFailure(.authentication, status: 401) {
            try await auth.clientCredentials(
                clientId: try setting("INTROSPECTION_CLIENT_ID"), clientSecret: "not-the-secret",
                project: try setting("INTROSPECTION_PROJECT"))
        }

        let bogus = try client(token: "intro_dev_not_a_real_key", discoveredFrom: try await serviceAccountClient())
        await expectFailure(.authentication, status: 401) { try await bogus.files.get(UUID().uuidString.lowercased()) }
    }
}
