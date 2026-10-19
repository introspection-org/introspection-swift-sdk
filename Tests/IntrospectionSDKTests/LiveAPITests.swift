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
/// Control Plane; `INTROSPECTION_DP_URL`, the Data Plane; `INTROSPECTION_TOKEN`,
/// the project's API key; `INTROSPECTION_MEMBER_TOKEN`, a member's Data Plane
/// token, for the writes no API key capability grants (share deletes, tags,
/// automations); `INTROSPECTION_CP_SESSION`, a member's encoded
/// `intro_cp_session` cookie, for member-authored Control Plane reads;
/// `INTROSPECTION_PROJECT`; `INTROSPECTION_RUNTIME_GROUP_ID` for automations,
/// which the seed does not create; and, when set, `INTROSPECTION_PROJECT_ID` and
/// `INTROSPECTION_ORG_ID`, checked against what the server returns.
@Suite(.enabled(if: Live.isEnabled, "Live tests run only with INTROSPECTION_LIVE=1"))
struct LiveAPITests {
    private let limit = 500

    private enum Credential {
        /// The project's API key.
        case apiKey
        /// A member's Control Plane session cookie, with the API key on the Data Plane.
        case session
        /// A member's Data Plane token.
        case member
    }

    private func setting(_ name: String) throws -> String {
        guard let value = Live.value(name) else { try Test.cancel("\(name) is not set") }
        return value
    }

    private func url(_ name: String) throws -> URL {
        let raw = try setting(name)
        guard let url = URL(string: raw) else { try Test.cancel("Invalid \(name): \(raw)") }
        return url
    }

    private func client(_ credential: Credential) throws -> IntrospectionClient {
        switch credential {
        case .apiKey:
            return try client(token: try setting("INTROSPECTION_TOKEN"))
        case .session:
            // The Control Plane authenticates a bearer token ahead of the session cookie, so the
            // cookie goes alone: an API key beside it would answer 403 on member-authored reads.
            let cookie = "intro_cp_session=\(try setting("INTROSPECTION_CP_SESSION"))"
            return try client(
                controlPlane: nil, dataPlane: BearerToken(try setting("INTROSPECTION_TOKEN")), headers: ["Cookie": cookie])
        case .member:
            return try client(token: try setting("INTROSPECTION_MEMBER_TOKEN"))
        }
    }

    private func client(token: String) throws -> IntrospectionClient {
        try client(controlPlane: BearerToken(token), dataPlane: nil)
    }

    /// `dataPlane` nil sends the Control Plane credential to both planes.
    private func client(
        controlPlane credentials: (any CredentialProvider)?, dataPlane: (any CredentialProvider)?,
        headers: [String: String] = [:]
    ) throws -> IntrospectionClient {
        let controlPlane = try Live.value("INTROSPECTION_BASE_API_URL").flatMap(URL.init(string:)) ?? url("INTROSPECTION_BASE_URL")
        return IntrospectionClient(
            configuration: IntrospectionClient.Configuration(
                controlPlaneURL: controlPlane,
                dataPlaneURL: try url("INTROSPECTION_DP_URL"),
                controlPlaneCredentials: credentials,
                dataPlaneCredentials: dataPlane,
                options: HTTPClient.Options(additionalHeaders: headers)
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

    @Test(Live.requires("INTROSPECTION_TOKEN", "INTROSPECTION_DP_URL"))
    func filesCrudWalk() async throws {
        let files = try client(.apiKey).files
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

    @Test(Live.requires("INTROSPECTION_TOKEN", "INTROSPECTION_MEMBER_TOKEN", "INTROSPECTION_DP_URL"))
    func uploadAndSharesCrudWalk() async throws {
        let client = try client(.apiKey)
        let member = try self.client(.member)
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

                // No API key capability carries `shares:delete`, so a member removes it.
                try await member.shares.delete(share.id)
                await expectFailure(.notFound, status: 404) { try await client.shares.get(share.id) }
            } cleanup: {
                try await member.shares.delete(share.id)
            }
            try await client.files.delete(file.id)
        } cleanup: {
            try await client.files.delete(file.id)
        }
    }

    // MARK: Tags

    @Test(Live.requires("INTROSPECTION_MEMBER_TOKEN", "INTROSPECTION_DP_URL"))
    func tagsCrudWalk() async throws {
        let tags = try client(.member).tags
        let access = unique("access")

        _ = try await tags.create(.access(name: access))
        let created = try await tags.create(.annotation(name: unique("label"), color: "#f97316"))
        try await cleaningUp {
            #expect(created.kind == .annotation)
            #expect(try await tags.get(.access, access).name == access)
            #expect(try await tags.get(.annotation, created.name).color?.lowercased() == "#f97316")

            let listed = try await tags.list(TagListParams(kind: .annotation)).collect(limit: limit)
            #expect(listed.contains { $0.name == created.name })

            let updated = try await tags.update(.annotation, created.name, TagUpdate(color: "#22c55e", description: "recolored"))
            #expect(updated.color?.lowercased() == "#22c55e")
            #expect(updated.description == "recolored")

            try await tags.delete(.annotation, created.name)
            try await tags.delete(.access, access)
            await expectFailure(.notFound, status: 404) { try await tags.get(.annotation, created.name) }
        } cleanup: {
            try? await tags.delete(.annotation, created.name)
            try await tags.delete(.access, access)
        }
    }

    // MARK: Automations

    /// An automation dispatches into a runtime group, which the seed does not create.
    @Test(Live.requires("INTROSPECTION_MEMBER_TOKEN", "INTROSPECTION_DP_URL", "INTROSPECTION_RUNTIME_GROUP_ID"))
    func automationsCrudWalk() async throws {
        let automations = try client(.member).automations
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
            // A get reads soft-deleted automations too, so the delete shows as absence from the list.
            let remaining = try await automations.list().collect(limit: limit)
            #expect(!remaining.contains { $0.id == created.id })
        } cleanup: {
            try await automations.delete(created.id)
        }
    }

    // MARK: Control Plane reads

    @Test(Live.requires("INTROSPECTION_TOKEN", "INTROSPECTION_DP_URL", "INTROSPECTION_PROJECT"))
    func controlPlaneReads() async throws {
        let client = try client(.apiKey)
        let project = try setting("INTROSPECTION_PROJECT")

        _ = try await client.runtimes.list(RuntimeListParams(project: project)).collect(limit: limit)
        _ = try await client.recipes.list(RecipeListParams(project: project)).collect(limit: limit)
        _ = try await client.experiments.list(ExperimentListParams(project: project)).collect(limit: limit)
        _ = try await client.connectors.list().collect(limit: limit)
        await expectFailure(.notFound, status: 404) { try await client.recipes.get(UUID().uuidString.lowercased()) }
    }

    // MARK: Telemetry reads

    @Test(Live.requires("INTROSPECTION_TOKEN", "INTROSPECTION_DP_URL"))
    func telemetryReads() async throws {
        let client = try client(.apiKey)
        _ = try await client.conversations.list().firstPage()
        let events = try await client.events.list(EventListParams(eventName: .annotation)).firstPage()
        #expect(events.records.allSatisfy { $0.eventName == .annotation })
    }

    // MARK: Members with a Control Plane session

    @Test(Live.requires("INTROSPECTION_TOKEN", "INTROSPECTION_CP_SESSION", "INTROSPECTION_DP_URL"))
    func membersReadsWithSession() async throws {
        let members = try client(.session).members
        let listed = try await members.list().collect(limit: limit)
        let first = try #require(listed.first, "the seeded org has members")
        let fetched = try await members.get(first.id)
        #expect(fetched.id == first.id)
        if let orgId = Live.value("INTROSPECTION_ORG_ID") { #expect(fetched.orgId == orgId) }
    }

    // MARK: Rejected credentials

    @Test(Live.requires("INTROSPECTION_DP_URL"))
    func rejectedCredentialsAreTyped() async throws {
        let client = try client(token: "intro_dev_not_a_real_key")
        await expectFailure(.authentication, status: 401) { try await client.files.get(UUID().uuidString.lowercased()) }
    }
}
