import Foundation
import InlineSnapshotTesting
import IntrospectionSDK
import Testing

// Steps 6–11: the connector, the runtime, the grant, the input file, the task and its evidence.
extension Walk {
    func step6Connector() async throws {
        let discovered = try await sa.connectors.discoverOAuth(issuer: WALK.mcpIssuer)
        try check(discovered.authorizationEndpoint != nil, "the issuer publishes its metadata")
        // Naming the issuer alone makes the Control Plane discover the endpoints, register a client dynamically
        // and record PKCE support; endpoints passed by hand would skip that and the grant would fail.
        connector = try await sa.connectors.create(
            ConnectorCreate(
                name: WALK.connectorName, provider: WALK.connectorName, authMode: .oauthStored, slug: WALK.connectorName,
                apiHosts: [URL(string: WALK.mcpEndpoint)?.host ?? ""], issuer: WALK.mcpIssuer))
        snap(try stable(connector)) {
            """
            {
              "agent_member_id" : "[uuid]",
              "api_hosts" : [
                "example-server.modelcontextprotocol.io"
              ],
              "auth_mode" : "oauth_stored",
              "authorization_endpoint" : "[url]",
              "client_id" : "[uuid]",
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "environment" : "production",
              "id" : "[uuid]",
              "metadata" : {
                "issuer" : "[url]",
                "oauth" : {
                  "client_registration" : "dynamic",
                  "code_challenge_methods_supported" : [
                    "S256"
                  ],
                  "registration_endpoint" : "[url]",
                  "resource" : "[url]",
                  "token_endpoint_auth_methods_supported" : [
                    "none"
                  ]
                }
              },
              "name" : "hello-mcp",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "provider" : "hello-mcp",
              "requires_runtime" : false,
              "scopes" : [

              ],
              "slug" : "hello-mcp",
              "status" : "pending",
              "token_endpoint" : "[url]",
              "updated_at" : "[timestamp]"
            }
            """
        }
        let read = try await sa.connectors.get(connector.id)
        try check(read.slug == WALK.connectorName, "the connector reads back")
        let listed = try await sa.connectors.list().all()
        try check(listed.contains { $0.id == connector.id }, "the connector is listed")
        let updated = try await sa.connectors.update(connector.id, ConnectorUpdate(name: "\(WALK.connectorName) (walk)"))
        try check(updated.name == "\(WALK.connectorName) (walk)", "the connector is renamed")
    }

    func step7Runtime() async throws {
        // The push versioned the group at the recipe's commit; that version is the runtime the walk runs on.
        let params = RuntimeListParams(project: project.id, runtime: WALK.runtimeSlug)
        let built: (Runtime?) -> Bool = { ["ready", "failed"].contains($0?.imageBuildStatus?.rawValue) }
        let versioned = try await settled(
            "push-versioned runtime bake", mode: mode, timeout: .seconds(1800), interval: .seconds(10),
            read: { try await sa.runtimes.list(params).all().first { $0.recipeId == recipe.id } },
            poll: { try await saQuiet.runtimes.list(params).all().first { $0.recipeId == recipe.id } },
            done: built)
        let versionedRuntime = try #require(versioned)
        runtime = versionedRuntime
        try check(runtime.imageBuildStatus == .ready, runtime.imageBuildErrorMessage ?? "the runtime baked")
        snap(try stable(runtime)) {
            """
            {
              "config_json" : {
                "connectors" : [
                  "hello-mcp"
                ]
              },
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "description" : "Harbor E2B task calling a development MCP server",
              "environments" : [
                "staging",
                "production"
              ],
              "id" : "[uuid]",
              "image_build_metadata" : {
                "built_at" : "[timestamp]",
                "external_image_name" : "[redacted]",
                "image_tag" : "[redacted]",
                "size_bytes" : "[number]",
                "verdict_by" : "[timestamp]"
              },
              "image_build_status" : "ready",
              "kind" : "byor",
              "llm_mode" : "managed",
              "name" : "hello-mcp",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "recipe_id" : "[uuid]",
              "recipe_kind" : "production",
              "recipe_ref" : "main",
              "runtime_group_id" : "[uuid]",
              "slug" : "hello-mcp",
              "updated_at" : "[timestamp]"
            }
            """
        }

        // A version's identity in its group is its recipe, so the next version pins the walk's own recipe.
        // todo: the SDK has no runtimes.create or runtimes.update.
        let created: Runtime = try await raw(sa.controlPlane).json(
            "POST", "/v1/runtimes",
            body: [
                "project": .string(project.id), "recipe_id": pinnedRecipe["id"] ?? .null, "name": .string(WALK.runtimeSlug),
                "slug": .string(WALK.runtimeSlug), "config_json": ["connectors": [.string(WALK.connectorName)]],
            ])
        try check(created.runtimeGroupId == runtime.runtimeGroupId, "the new version joins the group")
        runtimeV2 = try await settled(
            "runtime bake", mode: mode, timeout: .seconds(1800), interval: .seconds(10),
            read: { try await sa.runtimes.get(created.id) }, poll: { try await saQuiet.runtimes.get(created.id) },
            done: { built($0) })
        try check(runtimeV2.imageBuildStatus == .ready, runtimeV2.imageBuildErrorMessage ?? "the second version baked")
        let described: Runtime = try await raw(sa.controlPlane).json(
            "PATCH", "/v1/runtimes/\(runtimeV2.id)", body: ["description": "the walk's own version"])
        try check(described.description == "the walk's own version", "the version's description updates")
        // The list serves the group's live version, the newest one.
        let listed = try await sa.runtimes.list(params).all()
        try check(listed.contains { $0.runtimeGroupId == runtime.runtimeGroupId }, "the group is listed")
    }

    func step8ConnectionAndEndpoint() async throws {
        let returnURL = "\(settings.baseApiUrl.absoluteString)/walk/connected"
        let started = try await sa.connectors.authorize(
            connector.id,
            ConnectorAuthorizeParams(
                runtime: runtime.runtimeGroupId,
                binding: ConnectorAuthorizeBinding(environment: .production, mcpServerId: WALK.mcpServerId, url: WALK.mcpEndpoint),
                returnUrl: returnURL))
        let landed = try await followAuthorization(
            started.authorizeUrl, transport: transport, baseApiUrl: settings.baseApiUrl, cookie: settings.cpSession, returnURL: returnURL)
        let landedQuery = Dictionary((landed.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        try check(landedQuery["status"] == "active", "the grant lands active")
        let connectionId = try #require(landedQuery["connection_id"])
        let connection = try await sa.connectors.connections.get(connector.id, connectionId)
        snap(try stable(connection)) {
            """
            {
              "connector_id" : "[uuid]",
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "id" : "[uuid]",
              "org_id" : "[uuid]",
              "runtime_group_id" : "[uuid]",
              "scopes_granted" : [

              ],
              "status" : "active",
              "subject_type" : "app",
              "token_expires_at" : "[timestamp]",
              "updated_at" : "[timestamp]"
            }
            """
        }
        let connections = try await sa.connectors.connections.list(connector.id).all()
        try check(connections.contains { $0.id == connectionId }, "the connection is listed")

        // todo: the SDK has no endpoints resource.
        let cp = raw(sa.controlPlane)
        let endpoints: JSONValue = try await cp.json(
            "GET", "/v1/endpoints", query: [("project", project.id), ("mcp_server_id", WALK.mcpServerId)])
        endpoint = try #require(endpoints["records"]?[0], "the grant bound an endpoint")
        snap(Stable.value(endpoint)) {
            """
            {
              "assertion_claims" : null,
              "authorized_application_id" : null,
              "base_url" : "[url]",
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "credential_refs" : [

              ],
              "environment" : "production",
              "header_names" : [

              ],
              "headers" : {

              },
              "host" : "example-server.modelcontextprotocol.io",
              "id" : "[uuid]",
              "kind" : "mcp",
              "last_verified_at" : null,
              "metadata" : {
                "auth_audience" : null,
                "connector_id" : "[uuid]",
                "extra_hosts" : [

                ],
                "mcp_server_id" : "hello-mcp",
                "provider_app" : null
              },
              "name" : "hello-mcp",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "runtime_group_id" : "[uuid]",
              "runtime_id" : null,
              "updated_at" : "[timestamp]",
              "verify_path" : null
            }
            """
        }
        let endpointId = endpoint["id"]?.stringValue ?? ""
        let read: JSONValue = try await cp.json("GET", "/v1/endpoints/\(endpointId)", query: [("project", project.id)])
        try check(read["kind"] == "mcp", "the endpoint reads back")
        let renamed: JSONValue = try await cp.json(
            "PATCH", "/v1/endpoints/\(endpointId)", query: [("project", project.id)], body: ["name": "hello-mcp (walk)"])
        try check(renamed["name"] == "hello-mcp (walk)", "the endpoint is renamed")

        // todo: connections.getToken cannot name the runtime whose grant it releases.
        let token: ConnectionTokenResult = try await cp.json(
            "POST", "/v1/oauth/connections/token",
            body: ["connector_id": .string(connector.id), "runtime": .string(runtime.runtimeGroupId ?? "")])
        snap(try stable(token)) {
            """
            {
              "expires_at" : "[timestamp]",
              "scopes" : [

              ],
              "token" : "[redacted]",
              "token_type" : "bearer"
            }
            """
        }

        let requirements = try await sa.runtimes.get(runtime.id, include: [.mcpRequirements])
        snap(try stable(requirements.mcpRequirements ?? [])) {
            """
            [

            ]
            """
        }
    }

    func step9FilesIn() async throws {
        inputFile = try await sa.files.createText(
            FileCreateText(content: WALK.inputFileText, name: WALK.inputFileName, mimeType: "text/plain", metadata: ["suite": "walk"]))
        snap(try stable(inputFile)) {
            #"""
            {
              "created_at" : "[timestamp]",
              "file_type" : "filesystem",
              "id" : "[uuid]",
              "member_id" : "[uuid]",
              "metadata" : {
                "blob_checksum" : "[digest]",
                "original_filename" : "walk-input.txt",
                "suite" : "walk"
              },
              "mime_type" : "text\/plain",
              "name" : "walk-input.txt",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "size_bytes" : "[number]",
              "storage_path" : "[uuid]\/[uuid]\/files\/[uuid]\/walk-input.txt",
              "tags" : [

              ],
              "updated_at" : "[timestamp]",
              "version" : 1
            }
            """#
        }
        let read = try await sa.files.get(inputFile.id)
        try check(read.name == WALK.inputFileName, "the file reads back")
        let body = try await sa.files.download(inputFile.id)
        try check(String(decoding: body, as: UTF8.self) == WALK.inputFileText, "the file downloads")
        let version = try await sa.files.versions.create(
            inputFile.id,
            FileUpload(
                data: Data("\(WALK.inputFileText) (v2)".utf8), filename: WALK.inputFileName, name: WALK.inputFileName,
                contentType: "text/plain"))
        let versions = try await sa.files.versions.list(inputFile.id).firstPage()
        try check(versions.records.contains { $0.id == version.id }, "the version is listed")
        _ = try await sa.files.versions.get(inputFile.id, version.id)
        let updated = try await sa.files.update(inputFile.id, FileUpdate(metadata: ["suite": "walk", "stage": "attached"]))
        try check(updated.metadata?["stage"] == "attached", "the metadata updates")
        // A file with versions is listed only with `include_versions`.
        let tagged = try await sa.files.list(FileListParams(includeVersions: true, metadata: ["suite": "walk", "stage": "attached"])).all()
        try check(tagged.contains { $0.id == inputFile.id }, "the metadata filter finds the file")
        _ = try await sa.files.update(inputFile.id, FileUpdate(tags: ["suite:walk"]))
        let byTag = try await sa.files.list(FileListParams(includeVersions: true, tag: "suite:walk")).all()
        try check(byTag.contains { $0.id == inputFile.id }, "the tag filter finds the file")
        let byName = try await sa.files.list(FileListParams(includeVersions: true, nameContains: "WALK-INPUT")).all()
        try check(byName.contains { $0.id == inputFile.id }, "the substring filter finds the file")
    }

    func step10Task() async throws {
        let idle: (IntrospectionTask) -> Bool = { ["idle", "awaiting_user", "completed"].contains($0.status.rawValue) }
        // The JS walk passes `environment: production` too; its SDK sends only the agent, so this does.
        runner = try await sa.runtimes.run(runtime.id, RunRequest(agentName: settings.agent))
        let started = try await runner.tasks.start(
            TaskCreate(
                prompt: WALK.prompt(settings), agentName: settings.agent, idleTimeoutSeconds: 180, metadata: ["suite": "walk"],
                files: [TaskFileRef(id: inputFile.id)]))
        let startedTask = try #require(started.task, "the create returns the task")
        let reply = try await started.text()
        try check(!reply.isEmpty, "the turn replied")

        // The stream ends before the row settles; the second turn needs it idle.
        task = try await settled(
            "task after its first turn", mode: mode, read: { try await runner.tasks.get(startedTask.id) },
            poll: { try await saQuiet.tasks.get(startedTask.id) }, done: idle)
        // `metadata` is the platform's and differs between a warm pod and a baked image; the walk's key is
        // asserted and the rest left out of the snapshot.
        try check(task.metadata?["suite"] == "walk", "the task carries the walk's metadata")
        snap(try stable(task, removing: ["metadata"])) {
            #"""
            {
              "created_at" : "[timestamp]",
              "display_index" : "[number]",
              "id" : "[uuid]",
              "is_archived" : false,
              "kind" : "agent",
              "last_user_message_at" : "[timestamp]",
              "member_id" : "[uuid]",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "runtime_group_id" : "[uuid]",
              "runtime_id" : "[uuid]",
              "started_at" : "[timestamp]",
              "status" : "idle",
              "tags" : [

              ],
              "title" : "Call the `echo` tool from the declared `hello-mcp` MCP server with the message `hello from the public MCP`. Write the echoed value exactly, with no quotes or additional formatting, to `\/workspace\/outputs\/greeting.txt`. Then run `echo $WALK_MARKER` in…",
              "updated_at" : "[timestamp]"
            }
            """#
        }
        conversationId = task.metadata?["conversation_id"]?.stringValue ?? task.id
        let run = try await runner.tasks.runs.get(task.id, started.run.id)
        try check(run.taskId == task.id, "the run reads back")

        let turn = try await runner.tasks.runs.create(task.id, TaskRunCreate(prompt: TaskPrompt(text: WALK.secondTurn(settings))))
        _ = try await turn.text()
        _ = try await settled(
            "task after its second turn", mode: mode, read: { try await runner.tasks.get(task.id) },
            poll: { try await saQuiet.tasks.get(task.id) }, done: idle)
        let third = try await runner.tasks.runs.create(task.id, TaskRunCreate(prompt: TaskPrompt(text: WALK.secondTurn(settings))))
        _ = try await third.cancel()
        _ = try await settled(
            "task after a cancelled turn", mode: mode, read: { try await runner.tasks.get(task.id) },
            poll: { try await saQuiet.tasks.get(task.id) }, done: { idle($0) || $0.status.rawValue == "cancelled" })

        let listed = try await runner.tasks.list().all()
        try check(listed.contains { $0.id == task.id }, "the task is listed")
        let retitled = try await runner.tasks.update(task.id, TaskUpdate(title: "The walk's task"))
        try check(retitled.title == "The walk's task", "the task is retitled")
        try await runner.tasks.archive(task.id)
        try await runner.tasks.unarchive(task.id)
    }

    func step11Evidence() async throws {
        let outputs = try await settled(
            "task output files", mode: mode, read: { try await sa.files.list(FileListParams(taskId: task.id)).all() },
            poll: { try await saQuiet.files.list(FileListParams(taskId: task.id)).all() },
            done: { $0.contains { $0.name.hasSuffix(WALK.outputFileName) } })
        let output = try #require(outputs.first { $0.name.hasSuffix(WALK.outputFileName) })
        outputFile = output
        snap(try stable(outputFile)) {
            #"""
            {
              "created_at" : "[timestamp]",
              "file_type" : "filesystem",
              "generated_output_task_id" : "[uuid]",
              "id" : "[uuid]",
              "member_id" : "[uuid]",
              "metadata" : {
                "blob_checksum" : "[digest]",
                "conversation_id" : "[uuid]",
                "original_filename" : "greeting.txt",
                "relative_path" : "greeting.txt",
                "task_id" : "[uuid]"
              },
              "mime_type" : "text\/plain",
              "name" : "tasks\/[uuid]\/outputs\/greeting.txt",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "size_bytes" : "[number]",
              "storage_path" : "[uuid]\/[uuid]\/files\/[uuid]\/greeting.txt",
              "tags" : [

              ],
              "task_id" : "[uuid]",
              "updated_at" : "[timestamp]",
              "version" : 1
            }
            """#
        }
        let content = String(decoding: try await sa.files.download(outputFile.id), as: UTF8.self)
        try check(content.trimmingCharacters(in: .whitespacesAndNewlines) == WALK.echoResult, "the output file holds the echo")

        let conversation = try await settled(
            "conversation", mode: mode, read: { try await sa.conversations.get(conversationId) },
            poll: { try await saQuiet.conversations.get(conversationId) }, done: { _ in true })
        snap(try stable(conversation)) {
            """
            {
              "agents" : [
                {
                  "depth" : 0,
                  "id" : "[redacted]",
                  "name" : "scripted"
                }
              ],
              "cost" : {
                "usd" : 0
              },
              "created_at" : "[timestamp]",
              "environment" : "production",
              "id" : "[uuid]",
              "metrics" : {
                "duration_ms" : "[number]",
                "failed_llm_call_count" : "[number]",
                "failed_tool_use_count" : "[number]",
                "has_errors" : false,
                "llm_call_count" : "[number]",
                "max_turn" : "[number]",
                "span_count" : "[number]",
                "tool_use_count" : "[number]",
                "trace_count" : "[number]"
              },
              "object" : "conversation",
              "owner" : {
                "key" : "[redacted]"
              },
              "recipe" : {
                "git_commit_sha" : "[sha]"
              },
              "runtime" : {
                "group_id" : "[uuid]",
                "id" : "[uuid]"
              },
              "service_name" : "hello-mcp",
              "task_title" : "The walk's task",
              "updated_at" : "[timestamp]",
              "usage" : {
                "output_tokens" : "[number]",
                "total_input_tokens" : "[number]",
                "total_tokens" : "[number]"
              }
            }
            """
        }
        try check((conversation.metrics?.llmCallCount ?? 0) > 0, "an LLM call")
        try check((conversation.metrics?.toolUseCount ?? 0) > 0, "a tool use")
        try check((conversation.metrics?.traceCount ?? 0) >= 2, "two traces, one per turn")
        try check((conversation.usage?.totalTokens ?? 0) > 0, "tokens used")
        try await evidenceItems()
    }

    private func evidenceItems() async throws {
        let page = try await settled(
            "conversation items", mode: mode, read: { try await sa.conversations.items.list(conversationId).firstPage() },
            poll: { try await saQuiet.conversations.items.list(conversationId).firstPage() },
            done: { jsonText($0.records).contains("echo") && jsonText($0.records).contains(WALK.variableValue) })
        let items = jsonText(page.records)
        try check(items.contains("echo"), "the hello-mcp echo tool was called")
        try check(items.contains(WALK.echoResult), "the echo result reached the conversation")
        try check(items.contains(WALK.variableValue), "the variable reached the sandbox")
        let first = try #require(page.records.first)
        _ = try await sa.conversations.items.get(conversationId, first.spanId ?? "")
        let listed = try sa.conversations.list(ConversationListParams(runtimeGroupId: runtime.runtimeGroupId))
        try check(try await listed.all().contains { $0.id == conversationId }, "the conversation is listed")
        let trajectory = try await sa.conversations.exportTrajectory(conversationId)
        try check(!trajectory.isEmpty, "the trajectory export")

        // The other export formats, the Arrow list, and a paged item list.
        let latest = try await sa.conversations.retrieve(conversationId: conversationId)
        try check(latest?.spanId != nil, "the latest LLM turn")
        let exported = try await sa.conversations.exportJSON(conversationId)
        try check(exported.data.count >= page.records.count, "the export holds every item")
        // todo: the SDK has no Arrow reads (conversations.exportArrow, conversations.listArrow).
        let dp = raw(sa.dataPlane)
        let arrow = "application/vnd.apache.arrow.stream"
        let exportedTable = try await dp.data("/v1/conversations/\(conversationId)/export", accept: arrow)
        try check(exportedTable.starts(with: [0xFF, 0xFF, 0xFF, 0xFF]), "an Arrow IPC stream")
        let streamed = try await sa.conversations.exportStream(conversationId, format: .json).collect()
        let streamedList = try JSONCoding.decoder.decode(GenAISpanList.self, from: streamed)
        // Spans can still be arriving between two exports, so each is held to the items the step already read.
        try check(streamedList.data.count >= page.records.count, "the streamed export holds every item")
        let listedTable = try await dp.data("/v1/conversations", query: [("runtime_group_id", runtime.runtimeGroupId ?? "")], accept: arrow)
        try check(!listedTable.isEmpty, "the Arrow list")
        var itemPages = 0
        for try await _ in sa.conversations.items.list(conversationId, ConversationItemListParams(limit: 1)) {
            itemPages += 1
            if itemPages == 2 { break }
        }
        try check(itemPages == 2, "a second page of items")
        // `contains` selects items by the plaintext summary of their messages.
        let toolCalls = try await sa.conversations.items.list(
            conversationId, ConversationItemListParams(contains: ["gen_ai.output.messages.parts.name:*"])
        )
        .firstPage()
        try check(jsonText(toolCalls.records).contains("echo"), "a tool-call item")
        let userTurns = try await sa.conversations.items.list(
            conversationId, ConversationItemListParams(contains: ["gen_ai.input.messages.role:user"])
        )
        .firstPage()
        try check(!userTurns.records.isEmpty, "a user turn")
    }
}
