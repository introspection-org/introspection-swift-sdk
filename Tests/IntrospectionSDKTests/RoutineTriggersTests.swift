import Foundation
import Testing

@testable import IntrospectionSDK

private let triggerJSON = #"""
    {
      "created_at": "2026-11-01T10:00:00Z", "updated_at": "2026-11-01T10:00:00Z",
      "org_id": "0199a1b2-0000-7000-8000-0000000000aa", "project_id": "0199a1b2-0000-7000-8000-0000000000bb",
      "id": "0199a1b2-0000-7000-8000-000000000101", "routine_id": "0199a1b2-0000-7000-8000-000000000001",
      "source": "connector", "provider": "webhook", "connector_slug": "ci-alerts",
      "event_types": ["deploy.failed"],
      "filter": {"channel_ids": null, "emoji": null, "team_ids": null, "to_states": null, "repository_ids": null,
                 "branches": null, "payload_fields": {"environment": ["production"]}},
      "enabled": true
    }
    """#

private let triggeredRoutineJSON = #"""
    {
      "created_at": "2026-11-01T10:00:00Z", "updated_at": "2026-11-01T10:00:00Z",
      "org_id": "0199a1b2-0000-7000-8000-0000000000aa", "project_id": "0199a1b2-0000-7000-8000-0000000000bb",
      "id": "0199a1b2-0000-7000-8000-000000000001", "name": "Triage failed deploys", "description": null,
      "enabled": true, "runtime_group_id": "rg-1", "task_id": null, "created_by_member_id": "m1",
      "execution_blocked_reason": null, "can_manage": true, "tags": [], "trigger_type": "manual",
      "cron_schedule": null, "kind": null, "prompt": "Deploy @parameters.deploy_id failed.", "metadata": null,
      "last_triggered_at": null, "next_trigger_at": null, "owner_role": "operator",
      "triggers": [\#(triggerJSON)]
    }
    """#

@Suite struct RoutineTriggersTests {
    @Test func decodesARoutineAndItsTriggers() throws {
        let body = Data(triggeredRoutineJSON.utf8)
        #expect(try StrictSchema.unmodelled(Routine.self, in: body).isEmpty)
        let routine = try JSONCoding.decoder.decode(Routine.self, from: body)
        let trigger = try #require(routine.triggers?.first)
        #expect(trigger.id == "0199a1b2-0000-7000-8000-000000000101")
        #expect(trigger.routineId == routine.id)
        #expect(trigger.source == .connector)
        #expect(trigger.provider == .webhook)
        #expect(trigger.connectorSlug == "ci-alerts")
        #expect(trigger.eventTypes == ["deploy.failed"])
        #expect(trigger.filter == RoutineTriggerFilter(payloadFields: ["environment": ["production"]]))
        #expect(trigger.enabled == true)
        #expect(trigger.createdAt == ISO8601.parse("2026-11-01T10:00:00Z"))

        let minimal = try JSONCoding.decoder.decode(
            Routine.self, from: Data(#"{"id":"a","name":"n","trigger_type":"manual"}"#.utf8))
        #expect(minimal.triggers == nil)
    }

    @Test func createEncodesTriggers() async throws {
        let transport = MockTransport(status: 201, json: triggeredRoutineJSON)
        _ = try await makeClient(transport).routines.create(
            RoutineCreate(
                name: "Triage failed deploys", triggerType: .manual, prompt: "Deploy @parameters.deploy_id failed.",
                runtimeGroupId: "rg-1",
                triggers: [
                    .connector(
                        "ci-alerts", eventTypes: ["deploy.failed"],
                        filter: RoutineTriggerFilter(payloadFields: ["environment": ["production"]])),
                    RoutineTriggerSpec(
                        provider: .slack, eventTypes: [.slackMessagePosted], source: .integration,
                        filter: RoutineTriggerFilter(channelIds: ["C1"]), enabled: false),
                ]))
        #expect(transport.last?.path == "/v1/routines")
        let expected: JSONValue = [
            "name": "Triage failed deploys", "trigger_type": "manual", "prompt": "Deploy @parameters.deploy_id failed.",
            "runtime_group_id": "rg-1",
            "triggers": [
                [
                    "source": "connector", "provider": "webhook", "connector_slug": "ci-alerts", "event_types": ["deploy.failed"],
                    "filter": ["payload_fields": ["environment": ["production"]]],
                ],
                [
                    "source": "integration", "provider": "slack", "event_types": ["slack.message.posted"],
                    "filter": ["channel_ids": ["C1"]], "enabled": false,
                ],
            ],
        ]
        #expect(transport.last?.json == expected)
    }

    @Test func updateKeepsNamedTriggersAndClearsWithAnEmptyList() async throws {
        let transport = MockTransport(json: triggeredRoutineJSON)
        let api = makeClient(transport).routines
        let routine = try await api.get("r1")
        let stored = try #require(routine.triggers?.first)

        let merged = RoutineTriggerSpec(
            provider: .github, eventTypes: [.githubPullRequestMerged], filter: RoutineTriggerFilter(branches: ["main"]))
        _ = try await api.update("r1", RoutineUpdate(triggers: [RoutineTriggerSpec(keeping: stored), merged]))
        #expect(transport.last?.request.method == "PATCH")
        let expected: JSONValue = [
            "triggers": [
                [
                    "id": "0199a1b2-0000-7000-8000-000000000101", "source": "connector", "provider": "webhook",
                    "connector_slug": "ci-alerts", "event_types": ["deploy.failed"],
                    "filter": ["payload_fields": ["environment": ["production"]]],
                    "enabled": true,
                ],
                ["provider": "github", "event_types": ["github.pull_request.merged"], "filter": ["branches": ["main"]]],
            ]
        ]
        #expect(transport.last?.json == expected)

        _ = try await api.update("r1", RoutineUpdate(triggers: []))
        #expect(transport.last?.json == ["triggers": []])
    }

    @Test func manualTriggerForcedToAttachUploadsParametersWithoutReadingTheRoutine() async throws {
        let transport = MockTransport { request, index in
            request.url.path == "/v1/files"
                ? .response(.json(uploadedParametersJSON(id: "file-\(index)"), status: 201))
                : .response(.json(triggerResponseJSON, status: 202))
        }
        let api = makeClient(transport).routines
        let parameters: JSONObject = ["deploy_id": "dep_42", "attempts": 3, "context": ["service": "billing"]]
        let response = try await api.trigger(
            "r1", parameters: .inline(parameters), files: [TaskFileRef(id: "file-runbook", name: "runbook.md")], attachParametersFile: true)

        let requests = transport.requests
        #expect(requests.count == 2)
        let upload = try #require(requests.first?.json)
        #expect(requests.first?.request.method == "POST")
        #expect(requests.first?.path == "/v1/files")
        #expect(upload["content"] == #"{"attempts":3,"context":{"service":"billing"},"deploy_id":"dep_42"}"#)
        #expect(upload["mime_type"] == "application/json")
        #expect(upload["ttl_seconds"] == 2_592_000)
        let name = try #require(upload["name"]?.stringValue)
        #expect(name.hasPrefix("routine-parameters/"))
        #expect(name.hasSuffix(".json"))
        #expect(UUID(uuidString: String(name.dropFirst("routine-parameters/".count).dropLast(".json".count))) != nil)

        #expect(transport.last?.path == "/v1/routines/r1/trigger")
        let expected: JSONValue = [
            "parameters": ["deploy_id": "dep_42", "attempts": 3, "context": ["service": "billing"]],
            "files": [["id": "file-0", "name": "parameters.json"], ["id": "file-runbook", "name": "runbook.md"]],
        ]
        #expect(transport.last?.json == expected)
        #expect(response.status == .triggered)
        #expect(response.routineId == "r1")
        #expect(response.taskId == "t1")
        #expect(response.runId == "run-1")
        #expect(response.result == nil)
        #expect(response.enqueued == nil)
        #expect(response.conversations == nil)

        _ = try await api.trigger("r1", parameters: .inline(parameters), attachParametersFile: true)
        let second = try #require(transport.requests.dropLast().last?.json?["name"]?.stringValue)
        #expect(second != name, "each run's parameters file gets its own name")
    }

    @Test func manualTriggerWithAParametersFileSendsOnlyTheReference() async throws {
        let transport = MockTransport(status: 202, json: triggerResponseJSON)
        _ = try await makeClient(transport).routines.trigger(
            "r1", parameters: .file(id: "file-params"), files: [TaskFileRef(id: "file-runbook", name: "runbook.md")])
        #expect(transport.requests.count == 1)
        #expect(transport.last?.path == "/v1/routines/r1/trigger")
        let expected: JSONValue = [
            "files": [["id": "file-params", "name": "parameters.json"], ["id": "file-runbook", "name": "runbook.md"]]
        ]
        #expect(transport.last?.json == expected)
    }

    @Test func manualTriggerWithoutParametersSendsNoBody() async throws {
        let transport = MockTransport(status: 202, json: triggerResponseJSON)
        _ = try await makeClient(transport).routines.trigger("r1")
        #expect(transport.requests.count == 1)
        #expect(transport.last?.request.body == nil)

        _ = try await makeClient(transport).routines.trigger("r1", files: [TaskFileRef(id: "file-runbook")])
        #expect(transport.last?.json == ["files": [["id": "file-runbook"]]])
    }

    @Test func manualTriggerWithAnUploadedFileNeitherReadsNorUploads() async throws {
        let transport = MockTransport(status: 202, json: triggerResponseJSON)
        let file = try JSONCoding.decoder.decode(File.self, from: Data(uploadedParametersJSON(id: "file-up").utf8))
        _ = try await makeClient(transport).routines.trigger("r1", parameters: .file(file), attachParametersFile: true)
        #expect(transport.requests.map(\.path) == ["/v1/routines/r1/trigger"])
        #expect(transport.last?.json == ["files": [["id": "file-up", "name": "parameters.json"]]])
        #expect(RoutineParameters.file(file) == .file(id: "file-up"))
        #expect(["a": 1] as RoutineParameters == .inline(["a": 1]))
    }

    @Test func manualTriggerWithALocalFileSendsItsObjectAsInlineParameters() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("routine-parameters-\(UUID().uuidString).json")
        try Data(#"{"deploy_id":"dep_42","attempts":3}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = MockTransport { request, _ in
            switch request.url.path {
            case "/v1/routines/r1": return .response(.json(triggeredRoutineJSON))
            case "/v1/files": return .response(.json(uploadedParametersJSON(id: "file-p"), status: 201))
            default: return .response(.json(triggerResponseJSON, status: 202))
            }
        }
        let api = makeClient(transport).routines

        _ = try await api.trigger("r1", parameters: .path(url))
        #expect(transport.requests.map(\.path) == ["/v1/routines/r1", "/v1/files", "/v1/routines/r1/trigger"])
        #expect(transport.requests[1].json?["content"] == #"{"attempts":3,"deploy_id":"dep_42"}"#)
        let expected: JSONValue = [
            "parameters": ["deploy_id": "dep_42", "attempts": 3], "files": [["id": "file-p", "name": "parameters.json"]],
        ]
        #expect(transport.last?.json == expected)

        _ = try await api.trigger("r1", parameters: .path(url), attachParametersFile: false)
        #expect(transport.requests.count == 4)
        #expect(transport.last?.json == ["parameters": ["deploy_id": "dep_42", "attempts": 3]])
    }

    @Test func manualTriggerRejectsALocalFileThatIsNotAnObject() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("routine-parameters-\(UUID().uuidString).json")
        try Data("[1, 2]".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = MockTransport(status: 202, json: triggerResponseJSON)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).routines.trigger("r1", parameters: .path(url))
        }
        #expect(error.kind == .invalidRequest)
        #expect(transport.requests.isEmpty)
    }

    @Test func manualTriggerReadsTheRoutineToDecideTheUpload() async throws {
        let synthesisJSON = #"{"id":"r-syn","name":"n","trigger_type":"manual","kind":"observation_synthesis"}"#
        let transport = MockTransport { request, _ in
            switch request.url.path {
            case "/v1/routines/r-syn": return .response(.json(synthesisJSON))
            case "/v1/routines/r1": return .response(.json(triggeredRoutineJSON))
            case "/v1/files": return .response(.json(uploadedParametersJSON(id: "file-p"), status: 201))
            default: return .response(.json(triggerResponseJSON, status: 202))
            }
        }
        let api = makeClient(transport).routines

        _ = try await api.trigger("r-syn", parameters: ["conversation_ids": ["conv-1"]])
        #expect(transport.requests.map(\.request.method) == ["GET", "POST"])
        #expect(transport.requests.map(\.path) == ["/v1/routines/r-syn", "/v1/routines/r-syn/trigger"])
        #expect(transport.last?.json == ["parameters": ["conversation_ids": ["conv-1"]]])

        _ = try await api.trigger("r1", parameters: ["deploy_id": "dep_42"])
        #expect(transport.requests.dropFirst(2).map(\.path) == ["/v1/routines/r1", "/v1/files", "/v1/routines/r1/trigger"])
        let expected: JSONValue = ["parameters": ["deploy_id": "dep_42"], "files": [["id": "file-p", "name": "parameters.json"]]]
        #expect(transport.last?.json == expected)
    }

    @Test func manualTriggerForcedNotToAttachSendsParametersInline() async throws {
        let transport = MockTransport(status: 202, json: triggerResponseJSON)
        _ = try await makeClient(transport).routines.trigger("r1", parameters: ["deploy_id": "dep_42"], attachParametersFile: false)
        #expect(transport.requests.map(\.path) == ["/v1/routines/r1/trigger"])
        #expect(transport.last?.json == ["parameters": ["deploy_id": "dep_42"]])
    }

    @Test func manualTriggerOfAHeldRoutineSkipsTheUploadWhereTheServerRefusesFiles() async throws {
        let transport = MockTransport(status: 202, json: triggerResponseJSON)
        let api = makeClient(transport).routines
        let synthesis = try JSONCoding.decoder.decode(
            Routine.self, from: Data(#"{"id":"r-syn","name":"n","trigger_type":"manual","kind":"observation_synthesis"}"#.utf8))
        let posting = try JSONCoding.decoder.decode(
            Routine.self, from: Data(#"{"id":"r-post","name":"n","trigger_type":"manual","task_id":"t-1"}"#.utf8))

        _ = try await api.trigger(synthesis, parameters: ["conversation_ids": ["conv-1"]])
        #expect(transport.requests.count == 1)
        #expect(transport.last?.path == "/v1/routines/r-syn/trigger")
        #expect(transport.last?.json == ["parameters": ["conversation_ids": ["conv-1"]]])

        _ = try await api.trigger(posting, parameters: ["deploy_id": "dep_42"])
        #expect(transport.requests.count == 2)
        #expect(transport.last?.json == ["parameters": ["deploy_id": "dep_42"]])
    }

    @Test func manualTriggerOfAHeldPromptRoutineUploadsItsParameters() async throws {
        let transport = MockTransport { request, _ in
            request.url.path == "/v1/files"
                ? .response(.json(uploadedParametersJSON(id: "file-p"), status: 201))
                : .response(.json(triggerResponseJSON, status: 202))
        }
        let routine = try JSONCoding.decoder.decode(Routine.self, from: Data(triggeredRoutineJSON.utf8))
        _ = try await makeClient(transport).routines.trigger(routine, parameters: ["deploy_id": "dep_42"])
        #expect(transport.requests.map(\.path) == ["/v1/files", "/v1/routines/0199a1b2-0000-7000-8000-000000000001/trigger"])
        let expected: JSONValue = ["parameters": ["deploy_id": "dep_42"], "files": [["id": "file-p", "name": "parameters.json"]]]
        #expect(transport.last?.json == expected)
    }

    @Test func readsTheTriggerOnRunAndSkipEvents() async throws {
        let triggered = #"""
            {"id":"0199a1b2-0000-5000-8000-000000000011","timestamp":"2026-11-02T09:00:02Z",
             "event_name":"introspection.routines.triggered",
             "payload":{"routine_id":"r1","routine_name":"Triage failed deploys","prompt":"Deploy @parameters.deploy_id failed.",
                        "trigger_type":"manual","slot":null,"task_id":"t1","posted":false,"member_id":"m1",
                        "runtime_group_id":"rg-1","triggered_by_member_id":null,
                        "event":{"trigger_id":"tr-1","event_type":"deploy.failed","delivery_id":"webhook:msg_1"}}}
            """#
        let skipped = #"""
            {"id":"0199a1b2-0000-5000-8000-000000000012","timestamp":"2026-11-02T09:00:05Z",
             "event_name":"introspection.routines.skipped",
             "payload":{"routine_id":"r1","trigger_type":"manual","slot":null,"task_id":null,"reason":"trigger_busy",
                        "event":{"trigger_id":"tr-1","event_type":"deploy.failed","delivery_id":"webhook:msg_2"}}}
            """#
        let transport = MockTransport(json: #"{"records":[\#(triggered),\#(skipped)],"count":2,"next":null}"#)
        let events = try await makeClient(transport).events.list(EventListParams(eventName: .routineTriggered)).collect()

        let run = try #require(events[0].routineTriggered)
        #expect(run.event == RoutineTriggerEventRef(triggerId: "tr-1", eventType: "deploy.failed", deliveryId: "webhook:msg_1"))
        let skip = try #require(events[1].routineSkipped)
        #expect(skip.reason == .triggerBusy)
        #expect(skip.slot == nil)
        #expect(skip.event?.deliveryId == "webhook:msg_2")
    }

    @Test func readsTheRunFromTaskMetadata() throws {
        let task = try JSONCoding.decoder.decode(
            IntrospectionTask.self,
            from: Data(
                #"""
                {"id":"t1","routine_id":"r1","metadata":{"trigger_source":"trigger",
                 "routine_trigger":{"trigger_id":"tr-1","event_type":"deploy.failed","delivery_id":"webhook:msg_1"},
                 "unresolved_parameters":["service"]}}
                """#.utf8))
        #expect(task.routineRunSource == .trigger)
        #expect(task.routineTrigger?.triggerId == "tr-1")
        #expect(task.unresolvedParameters == ["service"])

        let scheduled = IntrospectionTask(id: "t2", metadata: [RoutineTaskMetadataKeys.triggerSource: "scheduled"])
        #expect(scheduled.routineRunSource == .scheduled)
        #expect(scheduled.routineTrigger == nil)
        #expect(scheduled.unresolvedParameters == nil)
        #expect(IntrospectionTask(id: "t3").routineRunSource == nil)
    }

    @Test func metadataKeysAndCatalogueMatchTheServer() {
        #expect(RoutineTaskMetadataKeys.triggerSource == "trigger_source")
        #expect(RoutineTaskMetadataKeys.routineTrigger == "routine_trigger")
        #expect(RoutineTaskMetadataKeys.unresolvedParameters == "unresolved_parameters")
        #expect(RoutineRunSource.trigger.rawValue == "trigger")
        #expect(RoutineSkipReason.triggerBusy.rawValue == "trigger_busy")
        #expect(RoutineTriggerEventType.wildcard.rawValue == "*")
        #expect(RoutineTriggerEventType.webhookReceived.rawValue == "webhook.received")
        #expect(RoutineTriggerEventType.githubWorkflowRunFailed.rawValue == "github.workflow_run.failed")
        #expect(RoutineTriggerEventType.linearIssueStatusChanged.rawValue == "linear.issue.status_changed")
    }

    // MARK: Webhook connectors

    @Test func webhookConnectorIsCreatedWithoutASecret() async throws {
        let transport = MockTransport(status: 201, json: webhookConnectorJSON)
        let hook = try await makeClient(transport).connectors.create(.webhook(name: "CI alerts", slug: "ci-alerts"))
        #expect(try StrictSchema.unmodelled(Connector.self, in: Data(webhookConnectorJSON.utf8)).isEmpty)
        #expect(transport.last?.json == ["name": "CI alerts", "provider": "webhook", "auth_mode": "static", "slug": "ci-alerts"])
        #expect(hook.provider == "webhook")
    }

    @Test func webhookSecretsListCurrentFirstUnderTheConnector() async throws {
        let page =
            #"{"records": [\#(webhookSecretJSON(id: "5e6f7a8b", status: "current")), "#
            + #"\#(webhookSecretJSON(id: "1a2b3c4d", status: "previous", createdAt: "2026-11-01T00:00:00Z"))], "#
            + #""count": 2, "total_count": null, "next": null}"#
        let current = try #require(ISO8601.parse("2026-11-02T00:00:00Z"))
        let previous = try #require(ISO8601.parse("2026-11-01T00:00:00Z"))
        let transport = MockTransport(json: page)

        let api = makeClient(transport).connectors.secrets
        let secrets = try await api.list("con-w", ConnectorListParams(project: "web", limit: 10)).collect()
        #expect(transport.last?.request.method == "GET")
        #expect(transport.last?.path == "/v1/connectors/con-w/secrets")
        #expect(transport.last?.query == ["project": ["web"], "limit": ["10"]])
        #expect(try StrictSchema.unmodelled(Page<WebhookSecret>.self, in: Data(page.utf8)).isEmpty)
        #expect(
            secrets == [
                WebhookSecret(id: "5e6f7a8b", type: .standardWebhooks, status: .current, createdAt: current),
                WebhookSecret(id: "1a2b3c4d", type: .standardWebhooks, status: .previous, createdAt: previous),
            ])
    }

    @Test func webhookSecretCreateWithATypeIssuesTheFirst() async throws {
        let created = webhookSecretCreatedJSON(type: "bearer", secret: "whtok_AAAA")
        let transport = MockTransport(status: 201, json: created)

        let secret = try await makeClient(transport).connectors.secrets.create("con-w", type: .bearer)
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/connectors/con-w/secrets")
        #expect(transport.last?.json == ["type": "bearer"])
        #expect(try StrictSchema.unmodelled(WebhookSecretCreated.self, in: Data(created.utf8)).isEmpty)
        #expect(secret.id == "1a2b3c4d")
        #expect(secret.type == .bearer)
        #expect(secret.status == .current)
        #expect(secret.createdAt == ISO8601.parse("2026-11-02T00:00:00Z"))
        #expect(secret.secret.plaintext == "whtok_AAAA")
        #expect(!"\(secret)".contains("whtok_AAAA"))
    }

    @Test func webhookSecretCreateWithoutATypeRotates() async throws {
        let transport = MockTransport(status: 201, json: webhookSecretCreatedJSON(type: "standard_webhooks", secret: "whsec_BBBB"))

        let secret = try await makeClient(transport).connectors.secrets.create("con-w", project: "web")
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.query == ["project": ["web"]])
        #expect(transport.last?.json == [:])
        #expect(secret.type == .standardWebhooks)
        #expect(secret.secret.plaintext == "whsec_BBBB")
    }

    @Test func webhookSecretDeleteNamesTheKeyId() async throws {
        let transport = MockTransport { _, _ in .response(HTTPResponse(status: 204, headers: [:], body: Data())) }

        try await makeClient(transport).connectors.secrets.delete("con-w", secretId: "1a2b3c4d")
        #expect(transport.last?.request.method == "DELETE")
        #expect(transport.last?.path == "/v1/connectors/con-w/secrets/1a2b3c4d")
        #expect(transport.last?.request.body == nil)
    }

    @Test(arguments: ["", ".", ".."])
    func webhookSecretDeleteRefusesADotSegment(_ secretId: String) async throws {
        let transport = MockTransport { _, _ in .response(HTTPResponse(status: 204, headers: [:], body: Data())) }

        await #expect(throws: IntrospectionError.self) {
            try await makeClient(transport).connectors.secrets.delete("con-w", secretId: secretId)
        }
        #expect(transport.last == nil)
    }

    @Test(arguments: [
        (422, IntrospectionError.Kind.validation), (409, IntrospectionError.Kind.conflict), (404, IntrospectionError.Kind.notFound),
    ])
    func webhookSecretCreateSurfacesTheServerRefusal(status: Int, kind: IntrospectionError.Kind) async throws {
        let transport = MockTransport(status: status, json: #"{"detail": "refused"}"#)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).connectors.secrets.create("con-w")
        }
        #expect(error.kind == kind)
        #expect(transport.requests.count == 1)
    }

    @Test(arguments: [(409, IntrospectionError.Kind.conflict), (404, IntrospectionError.Kind.notFound)])
    func webhookSecretDeleteSurfacesTheServerRefusal(status: Int, kind: IntrospectionError.Kind) async throws {
        let transport = MockTransport(status: status, json: #"{"detail": "refused"}"#)
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).connectors.secrets.delete("con-w", secretId: "5e6f7a8b")
        }
        #expect(error.kind == kind)
    }
}

private let triggerResponseJSON = #"{"status":"triggered","routine_id":"r1","task_id":"t1","run_id":"run-1","reason":null,"result":null}"#

private func uploadedParametersJSON(id: String) -> String {
    #"""
    {"id":"\#(id)","org_id":"o","project_id":"p","created_at":"2026-11-02T09:00:00Z","updated_at":"2026-11-02T09:00:00Z",
     "name":"routine-parameters/x.json","file_type":"filesystem","storage_path":"org/proj/files/x.json",
     "mime_type":"application/json","metadata":{},"tags":[],"member_id":"m","task_id":null,
     "generated_output_task_id":null,"size_bytes":64,"version":1,"parent_id":null,"storage_version_id":null,
     "expires_at":"2026-12-02T09:00:00Z"}
    """#
}

private let webhookConnectorJSON = #"""
    {"id": "con-w", "org_id": "o", "project_id": "p", "created_at": "2026-11-01T00:00:00Z",
     "updated_at": "2026-11-01T00:00:00Z", "slug": "ci-alerts", "name": "CI alerts", "provider": "webhook",
     "auth_mode": "static", "environment": "production", "agent_member_id": null, "authorization_endpoint": null,
     "token_endpoint": null, "scopes": [], "api_hosts": [], "client_id": null, "person_server_url": null,
     "application_id": null, "assertion_audience": null, "webhook_url": null, "status": "active",
     "created_by_member_id": "m", "metadata": {}, "policy_entities": [], "requires_runtime": false}
    """#

private func webhookSecretJSON(
    id: String, type: String = "standard_webhooks", status: String, createdAt: String = "2026-11-02T00:00:00Z"
) -> String {
    #"{"id": "\#(id)", "type": "\#(type)", "status": "\#(status)", "created_at": "\#(createdAt)"}"#
}

private func webhookSecretCreatedJSON(type: String, secret: String) -> String {
    #"{"id": "1a2b3c4d", "type": "\#(type)", "status": "current", "created_at": "2026-11-02T00:00:00Z", "secret": "\#(secret)"}"#
}
