import Foundation
import InlineSnapshotTesting
import IntrospectionSDK
import Testing

// Steps 0–5: the project, the service account, the hosted repository, the recipe, the runtime's settings.
extension Walk {
    func step0CleanSlate() async throws {
        // Every run starts in a project of its own, created here on the login's deployment and deleted by the
        // teardown. A record run writes both ids beside the recording, which is all replay needs to send the
        // same calls.
        loginProject = try await owner.projects.get(settings.bootstrapProjectId)
        // A run that crashed before its teardown left its project behind; one still running is younger than the
        // cutoff. Measured from this run's own slug, so replay decides as the recording did.
        guard let now = walkProjectBorn(settings.projectSlug) else {
            throw WalkError("the walk's own slug carries its time: \(settings.projectSlug)")
        }
        for other in try await owner.projects.list().all() {
            guard let born = walkProjectBorn(other.slug ?? ""), now - born > WALK.staleAfterSeconds else { continue }
            try await owner.projects.delete(other.id)
        }
        project = try await owner.projects.create(
            ProjectCreate(name: WALK.projectName, deploymentId: loginProject.deploymentId ?? "", slug: settings.projectSlug))
        if mode == .record {
            try FileManager.default.createDirectory(at: WalkPaths.recordingDir, withIntermediateDirectories: true)
            try Data(
                "{\"project_id\":\"\(loginProject.id)\",\"project_slug\":\"\(settings.projectSlug)\"}\n".utf8
            ).write(to: WalkPaths.bootstrap)
        }
        // The owner's Data Plane token for the project: it carries `git:push`, which no service account can,
        // and the member-only Data Plane writes (access tags, annotations).
        let minted = try await owner.auth.mintDataPlaneToken(DataPlaneTokenRequest(project: project.id, expiresHours: 24))
        memberToken = minted.accessToken
        try check(minted.projectId == project.id, "the token names the project")
        member = client(token: memberToken, dataPlaneURL: settings.dpUrl)
    }

    func step1Project() async throws {
        // The slug is new on every live run, so the snapshot leaves it out.
        snap(try stable(project, removing: ["name", "slug", "description"])) {
            """
            {
              "created_by_member_id" : "[uuid]",
              "deployment_id" : "[uuid]",
              "id" : "[uuid]",
              "org_id" : "[uuid]"
            }
            """
        }
        originalDescription = project.description
        let read = try await owner.projects.get(project.id)
        try check(read.id == project.id, "the project reads back")
        let listed = try await owner.projects.list().firstPage()
        try check(listed.records.contains { $0.id == project.id }, "the project is listed")

        let updated = try await owner.projects.update(project.id, ProjectUpdate(description: "The SDK end-to-end walk ran here"))
        try check(updated.description == "The SDK end-to-end walk ran here", "the description updates")
        // A PATCH with only nulls is "no fields to update", so a project that had no description gets an empty one back.
        let restored = try await owner.projects.update(project.id, ProjectUpdate(description: originalDescription ?? ""))
        try check((restored.description ?? "") == (originalDescription ?? ""), "the description is restored")

        // A sibling is created and deleted while the walk's project is in use.
        let sibling = try await owner.projects.create(
            ProjectCreate(
                name: "\(project.name ?? "") (walk)", deploymentId: project.deploymentId ?? "",
                slug: "\(project.slug ?? "")\(WALK.siblingSuffix)"))
        try check(sibling.deploymentId == project.deploymentId, "the sibling is on the same deployment")
        snap(try stable(sibling, removing: ["name", "slug"])) {
            """
            {
              "created_by_member_id" : "[uuid]",
              "deployment_id" : "[uuid]",
              "id" : "[uuid]",
              "org_id" : "[uuid]"
            }
            """
        }
        try await owner.projects.delete(sibling.id)
        try await expectNotFound({ try await owner.projects.get(sibling.id) }, "the deleted sibling")
    }

    func step2Application() async throws {
        application = try await owner.applications.create(
            ApplicationCreate(name: WALK.applicationName, applicationType: .serviceAccount, allowedScopes: WALK.applicationScopes),
            project: project.id)
        snap(try stable(application)) {
            """
            {
              "agent_member_id" : "[uuid]",
              "allowed_grants" : [
                "client_credentials"
              ],
              "allowed_origins" : [

              ],
              "allowed_scopes" : [
                "projects:read",
                "repositories:read",
                "repositories:write",
                "repositories:delete",
                "recipes:read",
                "recipes:write",
                "runtimes:read",
                "runtimes:write",
                "experiments:read",
                "experiments:write",
                "tasks:read",
                "tasks:write",
                "tasks:delete",
                "tasks:eval",
                "tasks:exec",
                "files:read",
                "files:write",
                "files:delete",
                "conversations:read",
                "events:read",
                "metrics:read",
                "shares:read",
                "shares:write",
                "shares:delete",
                "connectors:read",
                "connectors:write",
                "connections:read",
                "connections:write",
                "connections:delete",
                "automations:read",
                "automations:write",
                "annotations:read",
                "approvals:read",
                "approvals:write",
                "images:read",
                "images:write",
                "api_keys:read",
                "api_keys:write",
                "api_keys:delete",
                "applications:read",
                "applications:write",
                "applications:delete",
                "credentials:read",
                "credentials:write",
                "credentials:delete",
                "endpoints:read",
                "endpoints:write",
                "endpoints:delete",
                "variables:read",
                "variables:write",
                "variables:delete",
                "judges:read",
                "judges:write",
                "telemetry:write"
              ],
              "application_type" : "service_account",
              "client_id" : "[redacted]",
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "environment" : "production",
              "id" : "[uuid]",
              "name" : "sdk-coverage-walk",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "redirect_uris" : [

              ],
              "updated_at" : "[timestamp]"
            }
            """
        }

        let first = try await owner.applications.secrets.create(application.id, name: "first")
        let secret = try #require(first.secret, "the plaintext is returned once")
        let minted = try await owner.auth.clientCredentials(
            clientId: application.clientId ?? "", clientSecret: secret.plaintext, project: project.id)
        let dpUrl = try #require(minted.dpUrl.flatMap(URL.init(string:)), "the token response names the Data Plane")
        sa = client(token: minted.accessToken, dataPlaneURL: dpUrl)
        saQuiet = client(token: minted.accessToken, dataPlaneURL: dpUrl, quiet: true)

        let listed = try await owner.applications.list(ApplicationListParams(project: project.id)).firstPage()
        try check(listed.records.contains { $0.id == application.id }, "the application is listed")
        let read = try await owner.applications.get(application.id, project: project.id)
        try check(read.clientId == application.clientId, "the application reads back")
        let renamed = try await owner.applications.update(
            application.id, ApplicationUpdate(name: "\(WALK.applicationName)-renamed"), project: project.id)
        try check(renamed.name == "\(WALK.applicationName)-renamed", "the application is renamed")

        try await rotateSecrets(revoking: first.id)
        try await signingKeys()
        try await identityProviders()
    }

    /// The application is created holding one signing key; a second is added and revoked.
    private func signingKeys() async throws {
        let keys = try await owner.applications.keys.list(application.id)
        try check(keys.count == 1, "an application starts with one signing key")
        let key = try await owner.applications.keys.create(application.id)
        let both = try await owner.applications.keys.list(application.id)
        try check(Set(both.map(\.id)) == Set(keys.map(\.id) + [key.id]), "the second key is listed")
        try await owner.applications.keys.delete(application.id, key.id)
    }

    /// A service account signs nobody in, so it refuses an identity provider; a federated application takes one,
    /// checked by its issuer.
    private func identityProviders() async throws {
        let body = ApplicationIdpCreate(issuer: WALK.idpIssuer)
        try await refusal(400, "an identity provider on a service account") {
            try await owner.applications.idps.create(application.id, body)
        }
        let federated = try await owner.applications.create(
            ApplicationCreate(name: "\(WALK.applicationName)-federated", applicationType: .jwks), project: project.id)
        let idp = try await owner.applications.idps.create(federated.id, body)
        try check(idp.issuer == WALK.idpIssuer, "the identity provider names the issuer")
        snap(try stable(idp))
        let listed = try await owner.applications.idps.list(federated.id).all()
        try check(listed.map(\.id) == [idp.id], "the identity provider is listed")
        try await owner.applications.idps.delete(federated.id, idp.id)
        let after = try await owner.applications.idps.list(federated.id).all()
        try check(after.isEmpty, "the identity provider is deleted")
        try await owner.applications.delete(federated.id, project: project.id)
    }

    /// Rotate: a second secret, then the first revoked.
    private func rotateSecrets(revoking firstId: String) async throws {
        let second = try await owner.applications.secrets.create(application.id, name: "second")
        let secrets = try await owner.applications.secrets.list(application.id).firstPage()
        snap(.array(try secrets.records.map { try stable($0, removing: ["secret"]) })) {
            """
            [
              {
                "application_id" : "[uuid]",
                "created_at" : "[timestamp]",
                "created_by_member_id" : "[uuid]",
                "id" : "[uuid]",
                "name" : "second",
                "org_id" : "[uuid]",
                "secret_prefix" : "[redacted]",
                "secret_suffix" : "[redacted]",
                "status" : "active",
                "updated_at" : "[timestamp]"
              },
              {
                "application_id" : "[uuid]",
                "created_at" : "[timestamp]",
                "created_by_member_id" : "[uuid]",
                "id" : "[uuid]",
                "name" : "first",
                "org_id" : "[uuid]",
                "secret_prefix" : "[redacted]",
                "secret_suffix" : "[redacted]",
                "status" : "active",
                "updated_at" : "[timestamp]"
              }
            ]
            """
        }
        try await owner.applications.secrets.delete(application.id, firstId)
        try check(second.id != firstId, "a second secret")
    }

    func step3Repository() async throws {
        let created = try await sa.repositories.create(
            HostedRepositoryCreate(slug: WALK.recipeSlug, defaultBranch: "main"), project: project.id)
        let gitURL = try #require(created.url, "the credential-free Git transport URL")
        snap(try stable(created)) {
            """
            {
              "created_at" : "[timestamp]",
              "default_branch" : "main",
              "id" : "[uuid]",
              "is_recipe_source" : false,
              "name" : "hello-mcp",
              "project_id" : "[uuid]",
              "provider" : "introspection",
              "provisioning_status" : "pending",
              "seed_template" : "pi-agent",
              "slug" : "hello-mcp",
              "url" : "[url]"
            }
            """
        }

        // Provisioning seeds the hosted copy with the deployment's template; that first push pins a recipe. A
        // runtime made from it registers the group's slug, which lets the next push version the group.
        repository = try await settled(
            "hosted repository", mode: mode,
            read: { try await sa.repositories.get(created.id, project: project.id) },
            poll: { try await saQuiet.repositories.get(created.id, project: project.id) },
            done: { ["ready", "failed"].contains($0.provisioningStatus) })
        try check(repository.provisioningStatus == "ready", "the repository is provisioned")
        let seeded = try await settled(
            "seed recipe", mode: mode,
            read: { try await sa.recipes.list(RecipeListParams(project: project.id)).all() },
            poll: { try await saQuiet.recipes.list(RecipeListParams(project: project.id)).all() },
            done: { $0.contains { $0.repositoryId == repository.id } })
        let seedRecipe = try #require(seeded.first { $0.repositoryId == repository.id })
        let seedRuntime = try await sa.runtimes.create(
            RuntimeCreate(name: WALK.runtimeSlug, project: project.id, recipeId: seedRecipe.id, slug: WALK.runtimeSlug))
        try check(seedRuntime.slug == WALK.runtimeSlug, "the seed runtime takes the slug")

        if mode != .replay, let recipeDir {
            try await pushRecipe(recipeDir, url: gitURL, bearer: memberToken)
            self.recipeDir = nil
        }
        let listed = try await sa.repositories.list(project: project.id, slug: WALK.recipeSlug)
        try check(listed.contains { $0.id == repository.id }, "the repository is listed by slug")
    }

    func step4Recipe() async throws {
        let commits = try await sa.repositories.commits(repository.id, RepositoryCommitsParams(sha: "main")).firstPage()
        let head = try #require(commits.records.first, "a commit on the hosted main")
        let detail = try await sa.repositories.commit(repository.id, sha: head.sha)
        try check(detail.sha == head.sha, "the commit reads back")
        let branches = try await sa.repositories.branches(repository.id).firstPage()
        try check(branches.records.contains { $0.name == "main" }, "main is a branch")
        let entry = try await sa.repositories.contents.get(repository.id, path: "agents/scripted.yaml", ref: head.sha)
        try check(entry.path == "agents/scripted.yaml", "the agent file reads")
        let root = try await sa.repositories.contents.list(repository.id, ref: head.sha).firstPage()
        try check(root.records.contains { $0.path == "judges" }, "the recipe has judges")

        // The push versioned the manifest's recipe at the pushed commit; the create below names the same pin.
        let versioned = try await settled(
            "push-versioned recipe", mode: mode,
            read: { try await sa.recipes.list(RecipeListParams(project: project.id)).all().first { $0.gitCommitSha == head.sha } },
            poll: { try await saQuiet.recipes.list(RecipeListParams(project: project.id)).all().first { $0.gitCommitSha == head.sha } },
            done: { $0 != nil })
        let versionedRecipe = try #require(versioned)
        recipe = versionedRecipe
        // The slug carries the commit's hash, new whenever the recipe's repository moves.
        snap(try stable(recipe, removing: ["slug"])) {
            """
            {
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "description" : "Harbor E2B task calling a development MCP server",
              "git_commit_sha" : "[sha]",
              "git_ref" : "main",
              "id" : "[uuid]",
              "mcp_servers" : [
                {
                  "id" : "[redacted]",
                  "required" : true,
                  "tools" : {
                    "exclude" : [

                    ],
                    "include" : [
                      "echo"
                    ]
                  }
                }
              ],
              "name" : "hello-mcp",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "repository_id" : "[uuid]",
              "sub_path" : ".",
              "updated_at" : "[timestamp]",
              "validation" : {
                "checked_at" : "[timestamp]",
                "diagnostics" : [

                ],
                "status" : "valid",
                "validator_name" : "introspection-recipe-check",
                "validator_version" : "0.12.0"
              }
            }
            """
        }
        // A second pin of the same commit under the walk's own name: a sibling of the push's, not the same row.
        pinnedRecipe = try await sa.recipes.create(
            RecipeCreate(
                name: "hello-mcp (walk pin)", project: project.id, repositoryId: repository.id, gitRef: "main", gitCommitSha: head.sha))
        try check(pinnedRecipe.gitCommitSha == head.sha, "the pin names the commit")
        try check(pinnedRecipe.id != recipe.id, "the pin is its own row")

        let read = try await sa.recipes.get(recipe.id)
        try check(read.slug == recipe.slug, "the recipe reads back")
        let listed = try await sa.recipes.list(RecipeListParams(project: project.id)).all()
        try check(listed.contains { $0.id == recipe.id }, "the recipe is listed")
        let updated = try await sa.recipes.update(recipe.id, RecipeUpdate(description: "The walk's recipe"))
        try check(updated.description == "The walk's recipe", "the recipe's description updates")
        try await repositoryWrites(head: head.sha)
    }

    /// A recipe deleted, a merge with nothing to merge, and a Git token the server keeps for a sandbox's session.
    private func repositoryWrites(head: String) async throws {
        let doomed = try await sa.recipes.create(
            RecipeCreate(
                name: "hello-mcp (walk, deleted)", project: project.id, repositoryId: repository.id, gitRef: "main", gitCommitSha: head))
        try await owner.recipes.delete(doomed.id, project: project.id)
        try await expectNotFound({ try await sa.recipes.get(doomed.id) }, "the deleted recipe")

        // The owner's Data Plane token merges as its member.
        let merged = try await member.repositories.merge(repository.id, RepositoryMergeCreate(base: "main", head: "main"))
        try check(merged == nil, "main already contains main")
        // A Git provider token is the grant of the runtime a sandbox runs on, so a session with no runtime is refused.
        try await refusal(403, "a Git token for a session with no runtime") { try await member.repositories.accessToken(repository.id) }
    }

    func step5CredentialAndVariable() async throws {
        let credential = try await sa.credentials.create(
            CredentialCreate(name: WALK.credentialName, secret: Secret(WALK.credentialSecret)), project: project.id)
        snap(try stable(credential)) {
            """
            {
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "has_secret" : true,
              "id" : "[uuid]",
              "name" : "WALK_SECRET",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "secret_display" : "walk***0001",
              "secret_set_at" : "[timestamp]",
              "updated_at" : "[timestamp]"
            }
            """
        }
        let credentials = try await sa.credentials.list(RuntimeSettingListParams(project: project.id)).firstPage()
        try check(credentials.records.contains { $0.id == credential.id }, "the credential is listed")
        let readCredential = try await sa.credentials.get(credential.id, project: project.id)
        try check(readCredential.name == WALK.credentialName, "the credential reads back")
        _ = try await sa.credentials.update(
            credential.id, CredentialUpdate(secret: Secret("\(WALK.credentialSecret)-rotated")), project: project.id)

        let variable = try await sa.variables.create(
            VariableCreate(name: WALK.variableName, value: WALK.variableValue, kind: .value), project: project.id)
        snap(try stable(variable)) {
            """
            {
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "id" : "[uuid]",
              "kind" : "value",
              "name" : "WALK_MARKER",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "updated_at" : "[timestamp]",
              "value" : "walk-marker-7f3a"
            }
            """
        }
        let variables = try await sa.variables.list(RuntimeSettingListParams(project: project.id)).firstPage()
        try check(variables.records.contains { $0.id == variable.id }, "the variable is listed")
        let updated = try await sa.variables.update(variable.id, VariableUpdate(value: WALK.variableValue), project: project.id)
        try check(updated.value == WALK.variableValue, "the variable updates")
    }
}
