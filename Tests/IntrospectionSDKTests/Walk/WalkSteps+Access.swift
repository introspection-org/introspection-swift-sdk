import Foundation
import InlineSnapshotTesting
import IntrospectionSDK
import Testing

/// What one person can open of Avery's work.
struct Reads: Equatable, CustomStringConvertible {
    var conversation: Bool
    var task: Bool
    var file: Bool
    var output: Bool

    static let none = Reads(conversation: false, task: false, file: false, output: false)
    static let all = Reads(conversation: true, task: true, file: true, output: true)
    /// Casey holds one of the task's two tags, which opens the task and its conversation; the output file
    /// carries no tags of its own, so a tag reader cannot open it.
    static let byTag = Reads(conversation: true, task: true, file: false, output: false)

    var description: String { "conversation \(conversation), task \(task), file \(file), output \(output)" }
}

// Steps 17–19: access across personas, members and keys, the teardown.
extension Walk {
    func step17Access() async throws {
        // Drew, the administrator: an application bound to the organisation's admin agent member, whose
        // client-credentials token is privileged.
        let agents = try await owner.members.list(MemberListParams(memberType: .agent)).all()
        let adminAgentId = try #require(agents.last { $0.role == "admin" }?.id, "the organisation's admin agent")
        let drewApp = try await owner.applications.create(
            ApplicationCreate(
                name: WALK.adminName, applicationType: .serviceAccount,
                allowedScopes: ["conversations:read", "tasks:read", "files:read", "shares:read", "shares:delete"],
                agentMemberId: adminAgentId),
            project: project.id)
        let drewSecret = try await owner.applications.secrets.create(drewApp.id, name: "drew")
        let drewToken = try await owner.auth.clientCredentials(
            clientId: drewApp.clientId ?? "", clientSecret: try #require(drewSecret.secret).plaintext, project: project.id)
        let drew = client(token: drewToken.accessToken, dataPlaneURL: drewToken.dpUrl.flatMap(URL.init(string:)))

        var people: [String: (id: String, client: Runner)] = [:]
        for (name, tags) in WALK.personas {
            let externalUserId = "user:walk-\(name)"
            let displayName = name.prefix(1).uppercased() + name.dropFirst()
            // Members have no public delete, so a persona from an earlier run is reused and its name and tags set again.
            let existing = try await owner.members.list(MemberListParams(memberType: .customer, externalUserIds: [externalUserId]))
                .firstPage()
            let id: String
            if let found = existing.records.first {
                id = found.id
                _ = try await owner.members.update(id, MemberUpdate(name: displayName, tags: tags))
            } else {
                id = try await owner.members.create(
                    .customer(CustomerMemberCreate(externalUserId: externalUserId, name: displayName, tags: tags))
                ).id
            }
            let client = try await sa.runtimes.run(
                runtime.id, RunRequest(identity: RunnerIdentity(userId: "walk-\(name)"), agentName: settings.agent))
            people[name] = (id, client)
        }
        let avery = try #require(people["avery"]), blake = try #require(people["blake"])
        let casey = try #require(people["casey"]), emery = try #require(people["emery"])
        let work = try await averysWork(avery.client)

        func reads(_ who: any DataPlaneResources) async throws -> Reads {
            func can(_ read: () async throws -> some Any) async throws -> Bool { !(try await isNotFound(read)) }
            return Reads(
                conversation: try await can { try await who.conversations.get(work.conversation) },
                task: try await can { try await who.tasks.get(work.task) },
                file: try await can { try await who.files.get(work.file) },
                output: try await can { try await who.files.get(work.output) })
        }
        func matrix() async throws -> [String: Reads] {
            [
                "avery": try await reads(avery.client), "blake": try await reads(blake.client), "casey": try await reads(casey.client),
                "drew": try await reads(drew), "emery": try await reads(emery.client),
            ]
        }
        let before = try await matrix()
        try check(before == ["avery": .all, "blake": .none, "casey": .byTag, "drew": .all, "emery": .none], "before any share: \(before)")

        // A share to one member, and one to everyone holding the platform group tag.
        let toBlake = try await avery.client.shares.create(
            ShareCreate(resourceType: .conversation, resourceId: work.conversation, grantedMemberId: blake.id))
        let toPlatform = try await avery.client.shares.create(
            ShareCreate(resourceType: .file, resourceId: work.file, grantedTag: WALK.groupTag))
        var caseyShared = Reads.byTag
        caseyShared.file = true
        let shared = try await matrix()
        // A conversation share opens the conversation, never the task.
        let blakeShared = Reads(conversation: true, task: false, file: false, output: false)
        try check(
            shared == ["avery": .all, "blake": blakeShared, "casey": caseyShared, "drew": .all, "emery": .none],
            "a member share and a tag share: \(shared)")

        // A share naming neither opens the conversation to the whole project.
        let toProject = try await avery.client.shares.create(ShareCreate(resourceType: .conversation, resourceId: work.conversation))
        let projectWide = try await matrix()
        try check(projectWide["emery"] == blakeShared, "a project-wide share: \(projectWide)")

        // Revoked, every share stops granting. A runner cannot hold `shares:delete`, so Drew revokes them.
        for share in [toBlake, toPlatform, toProject] { try await drew.shares.delete(share.id) }
        let revoked = try await matrix()
        try check(revoked == before, "every share revoked: \(revoked)")

        try await member.files.delete(work.file)
        try await member.tasks.delete(work.task)
        try await owner.applications.delete(drewApp.id, project: project.id)
    }

    /// Avery makes everything first: a task tagged for the platform group, its conversation and output file,
    /// and a file of their own.
    private func averysWork(_ avery: Runner) async throws -> (task: String, conversation: String, file: String, output: String) {
        let memberQuiet = client(token: memberToken, dataPlaneURL: settings.dpUrl, quiet: true)
        let started = try await avery.tasks.start(
            TaskCreate(
                prompt: WALK.prompt(settings), agentName: settings.agent, idleTimeoutSeconds: 180, metadata: ["suite": "walk"],
                conversationMetadata: ["suite": "walk", "persona": "avery"], tags: [WALK.groupTag, "suite:walk"]))
        _ = try await started.text()
        let startedId = try #require(started.task?.id)
        let task = try await settled(
            "Avery's task", mode: mode, timeout: .seconds(300), interval: .seconds(5), read: { try await avery.tasks.get(startedId) },
            poll: { try await memberQuiet.tasks.get(startedId) },
            done: { ["idle", "awaiting_user", "completed"].contains($0.status.rawValue) })
        try check(task.tags == [WALK.groupTag, "suite:walk"], "the task carries both tags")
        // A row carrying two tags is found by either one.
        for tag in [WALK.groupTag, "suite:walk"] {
            let found = try await member.tasks.list(TaskListParams(tag: tag)).all()
            try check(found.contains { $0.id == task.id }, "the task list by \(tag)")
        }
        try check(task.conversationMetadata == ["suite": "walk", "persona": "avery"], "the conversation metadata")
        let outputs = try await settled(
            "Avery's output", mode: mode, read: { try await member.files.list(FileListParams(taskId: task.id)).firstPage().records },
            poll: { try await memberQuiet.files.list(FileListParams(taskId: task.id)).firstPage().records },
            done: { $0.contains { $0.name.hasSuffix(WALK.outputFileName) } })
        let output = try #require(outputs.first { $0.name.hasSuffix(WALK.outputFileName) })
        _ = try await settled(
            "Avery's conversation", mode: mode, read: { try await member.conversations.get(task.id) },
            poll: { try await memberQuiet.conversations.get(task.id) }, done: { ($0.metrics?.llmCallCount ?? 0) > 0 })
        let file = try await avery.files.createText(
            FileCreateText(content: "Avery's notes", name: WALK.personaFileName, mimeType: "text/plain", metadata: ["suite": "walk"]))
        // Both keys must sit on the conversation (ANDed).
        let filtered = try await member.conversations.list(ConversationListParams(metadata: ["suite": "walk", "persona": "avery"])).all()
        try check(filtered.contains { $0.id == task.id }, "conversation_metadata filters")
        return (task.id, task.id, file.id, output.id)
    }

    func step18MembersAndKeys() async throws {
        let members = try await owner.members.list().all()
        _ = try await owner.members.get(try #require(members.first).id)
        let org = try await owner.organizations.current()
        // An invite outlives the project, so a repeat run finds the one the last run sent; and a person belongs to
        // one organisation, so the address names this one.
        let email = "walk-member@\(org.slug ?? "").example.com"
        let invited: Member
        if let found = members.first(where: { $0.email == email }) {
            invited = found
        } else {
            invited = try await owner.members.create(.business(BusinessMemberCreate(email: email, name: "Walk member", role: "member")))
        }
        try check(invited.email == email && invited.role == "member", "the invited member")
        let renamed = try await owner.members.update(invited.id, MemberUpdate(name: "Walk member (renamed)"))
        try check(renamed.name == "Walk member (renamed)", "the member is renamed")
        let me = try await owner.members.me()
        try check(me.orgId == project.orgId, "the caller's organisation")
        let apiKey = try await sa.apiKeys.create(
            ApiKeyCreate(name: WALK.apiKeyName, environment: .development, allow: [.runtimes]), project: project.id)
        try check(apiKey.apiKey != nil, "the plaintext key is returned once")
        snap(try stable(apiKey, removing: ["api_key"])) {
            """
            {
              "allow" : [
                "runtimes"
              ],
              "created_at" : "[timestamp]",
              "environment" : "development",
              "id" : "[uuid]",
              "key_display" : "[redacted]",
              "key_prefix" : "[redacted]",
              "key_suffix" : "[redacted]",
              "member_id" : "[uuid]",
              "name" : "walk",
              "org_id" : "[uuid]",
              "prefix" : "[redacted]",
              "project_id" : "[uuid]",
              "redacted_key" : "[redacted]",
              "scope" : "telemetry:write projects:read repositories:read recipes:read recipes:write runtimes:read runtimes:write experiments:read experiments:write tasks:read tasks:write tasks:delete files:read files:write conversations:read events:read metrics:read shares:read shares:write shares:delete connectors:read connectors:write annotations:read approvals:read approvals:write",
              "status" : "active"
            }
            """
        }
        let keys = try await sa.apiKeys.list(ApiKeyListParams(project: project.id))
        try check(keys.contains { $0.id == apiKey.key.id }, "the key is listed")
        _ = try await sa.apiKeys.update(apiKey.key.id, ApiKeyUpdate(name: "\(WALK.apiKeyName) (renamed)"), project: project.id)
        _ = try await sa.apiKeys.acknowledge(apiKey.key.id, project: project.id)
        // The organisation's name and slug are whoever is running the walk.
        try check(org.slug?.isEmpty == false, "the organisation has a slug")
        snap(try stable(org, removing: ["name", "slug"])) {
            """
            {
              "external_org_id" : "[id]",
              "hosted_git" : true,
              "id" : "[uuid]"
            }
            """
        }
    }

    func step19Teardown() async throws {
        // The default file list omits the upload a task holds, so it goes by id.
        try await sa.files.delete(inputFile.id)
        try await removeWalkResources(dataPlane: sa)
        try await expectNotFound({ try await sa.tasks.get(task.id) }, "the task")
        try await expectNotFound({ try await sa.files.get(inputFile.id) }, "the input file")
        try await expectNotFound({ try await sa.runtimes.get(runtimeV2.id) }, "the runtime")
        try await expectNotFound({ try await sa.connectors.get(connector.id) }, "the connector")
        try await expectNotFound({ try await sa.recipes.get(recipe.id) }, "the recipe")
        try await expectNotFound({ try await owner.applications.get(application.id, project: project.id) }, "the application")
        // The login's project is untouched: still there, as it was.
        let after = try await owner.projects.get(project.id)
        try check((after.description ?? "") == (originalDescription ?? ""), "the project is as it was")
    }

    /// Everything the walk creates, found by its fixed names and removed in reverse, so step 0 clears a crashed
    /// run and step 19 clears this one. Deleting is the owner's where a `:delete` scope is never minted to an
    /// application; the member's Data Plane token, or the service account's, does the rest.
    func removeWalkResources(dataPlane dp: IntrospectionClient) async throws {
        for key in try await owner.apiKeys.list(ApiKeyListParams(project: project.id))
        where [WALK.apiKeyName, "\(WALK.apiKeyName) (renamed)"].contains(key.name ?? "") {
            try await owner.apiKeys.delete(key.id, project: project.id)
        }
        for automation in try await member.automations.list().all() where automation.name == WALK.automationName {
            try await member.automations.delete(automation.id)
        }
        try await ignoringNotFound { try await member.tags.delete(.access, WALK.tagName) }
        for task in try await dp.tasks.list().all() where task.metadata?["suite"] == "walk" { try await dp.tasks.delete(task.id) }
        let walkFiles = try await dp.files.list().all()
            .filter { [WALK.inputFileName, WALK.personaFileName].contains($0.name) || $0.name.hasSuffix(WALK.outputFileName) }.map(\.id)
        for share in try await dp.shares.list(ShareListParams(resourceType: .file)).all() where walkFiles.contains(share.resourceId) {
            try await dp.shares.delete(share.id)
        }
        for id in walkFiles { try await ignoringNotFound { try await dp.files.delete(id) } }
        for experiment in try await owner.experiments.list(ExperimentListParams(project: project.id)).all()
        where WALK.experimentNames.contains(experiment.name ?? "") {
            try await owner.experiments.delete(experiment.id, project: project.id)
        }
        try await removeRuntimeResources()
    }

    private func removeRuntimeResources() async throws {
        let cp = raw(owner.controlPlane)
        let inProject = [("project", project.id)]
        // Deleting the group's live version takes its siblings with it. todo: the SDK has no runtimes.delete.
        for runtime in try await owner.runtimes.list(RuntimeListParams(project: project.id, runtime: WALK.runtimeSlug)).all() {
            try await ignoringNotFound { try await cp.empty("DELETE", "/v1/runtimes/\(runtime.id)", query: inProject) }
        }
        // todo: the SDK has no endpoints resource.
        let endpoints: JSONValue = try await cp.json("GET", "/v1/endpoints", query: inProject + [("mcp_server_id", WALK.mcpServerId)])
        for endpoint in endpoints["records"]?.arrayValue ?? [] {
            try await ignoringNotFound {
                try await cp.empty("DELETE", "/v1/endpoints/\(endpoint["id"]?.stringValue ?? "")", query: inProject)
            }
        }
        for connector in try await owner.connectors.list(ConnectorListParams(project: project.id)).all()
        where connector.slug == WALK.connectorName {
            for connection in try await owner.connectors.connections.list(connector.id).all() {
                try await owner.connectors.connections.revoke(connector.id, connection.id)
            }
            try await owner.connectors.delete(connector.id, project: project.id)
        }
        for variable in try await owner.variables.list(RuntimeSettingListParams(project: project.id)).all()
        where variable.name == WALK.variableName {
            try await owner.variables.delete(variable.id, project: project.id)
        }
        for credential in try await owner.credentials.list(RuntimeSettingListParams(project: project.id)).all()
        where credential.name == WALK.credentialName {
            try await owner.credentials.delete(credential.id, project: project.id)
        }
        // todo: the SDK has no recipes.delete or repositories.delete.
        for repository in try await owner.repositories.list(project: project.id, slug: WALK.recipeSlug) {
            for recipe in try await owner.recipes.list(RecipeListParams(project: project.id, repositoryId: repository.id)).all() {
                try await cp.empty("DELETE", "/v1/recipes/\(recipe.id)", query: inProject)
            }
            try await cp.empty("DELETE", "/v1/repositories/\(repository.id)", query: inProject)
        }
        for application in try await owner.applications.list(ApplicationListParams(project: project.id)).all()
        where (application.name ?? "").hasPrefix(WALK.applicationName) || application.name == WALK.adminName {
            try await owner.applications.delete(application.id, project: project.id)
        }
    }
}
