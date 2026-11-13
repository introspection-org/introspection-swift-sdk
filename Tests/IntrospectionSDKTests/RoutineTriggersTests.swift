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
      "parameters": {"deploy_id": "/data/id"},
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
        #expect(trigger.parameters == ["deploy_id": "/data/id"])
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
                        filter: RoutineTriggerFilter(payloadFields: ["environment": ["production"]]),
                        parameters: ["deploy_id": "/data/id"]),
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
                    "filter": ["payload_fields": ["environment": ["production"]]], "parameters": ["deploy_id": "/data/id"],
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
                    "filter": ["payload_fields": ["environment": ["production"]]], "parameters": ["deploy_id": "/data/id"],
                    "enabled": true,
                ],
                ["provider": "github", "event_types": ["github.pull_request.merged"], "filter": ["branches": ["main"]]],
            ],
        ]
        #expect(transport.last?.json == expected)

        _ = try await api.update("r1", RoutineUpdate(triggers: []))
        #expect(transport.last?.json == ["triggers": []])
    }

    @Test func manualTriggerSendsParametersAndReadsTheRun() async throws {
        let transport = MockTransport(
            status: 202,
            json: #"{"status":"triggered","routine_id":"r1","task_id":"t1","run_id":null,"reason":null,"result":null}"#)
        let response = try await makeClient(transport).routines.trigger(
            "r1", parameters: ["deploy_id": "dep_42", "attempts": 3, "context": ["service": "billing"]])
        #expect(transport.last?.request.method == "POST")
        #expect(transport.last?.path == "/v1/routines/r1/trigger")
        #expect(transport.last?.json == ["parameters": ["deploy_id": "dep_42", "attempts": 3, "context": ["service": "billing"]]])
        #expect(response.status == .triggered)
        #expect(response.taskId == "t1")
        #expect(response.result == nil)
        #expect(response.enqueued == nil)
        #expect(response.conversations == nil)
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

    @Test func webhookConnectorReturnsItsSecretOnCreateAndRotation() async throws {
        let created = #"""
            {"id": "con-w", "org_id": "o", "project_id": "p", "created_at": "2026-11-01T00:00:00Z",
             "updated_at": "2026-11-01T00:00:00Z", "slug": "ci-alerts", "name": "CI alerts", "provider": "webhook",
             "auth_mode": "static", "environment": "production", "agent_member_id": null, "authorization_endpoint": null,
             "token_endpoint": null, "scopes": [], "api_hosts": [], "client_id": null, "person_server_url": null,
             "application_id": null, "assertion_audience": null, "webhook_url": null, "status": "active",
             "created_by_member_id": "m", "metadata": {"webhook_auth": "standard_webhooks"}, "policy_entities": [],
             "previous_signing_secret_expires_at": null, "webhook_auth": "standard_webhooks", "requires_runtime": false,
             "signing_secret": "whsec_AAAA"}
            """#
        let rotated = created.replacingOccurrences(of: "\"whsec_AAAA\"", with: "\"whsec_BBBB\"")
            .replacingOccurrences(
                of: "\"previous_signing_secret_expires_at\": null",
                with: "\"previous_signing_secret_expires_at\": \"2026-11-02T00:00:00Z\"")
            .replacingOccurrences(
                of: "\"webhook_auth\": \"standard_webhooks\", \"requires", with: "\"webhook_auth\": \"bearer\", \"requires")
        let transport = MockTransport { request, _ in
            .response(.json(request.method == "POST" ? created : rotated))
        }
        let connectors = makeClient(transport).connectors

        let hook = try await connectors.create(.webhook(name: "CI alerts", slug: "ci-alerts"))
        #expect(try StrictSchema.unmodelled(Connector.self, in: Data(created.utf8)).isEmpty)
        #expect(transport.last?.json == ["name": "CI alerts", "provider": "webhook", "auth_mode": "static", "slug": "ci-alerts"])
        #expect(hook.signingSecret == "whsec_AAAA")
        #expect(hook.webhookAuth == .standardWebhooks)
        #expect(hook.previousSigningSecretExpiresAt == nil)

        _ = try await connectors.create(.webhook(name: "Pager", webhookAuth: .bearer))
        #expect(transport.last?.json == ["name": "Pager", "provider": "webhook", "auth_mode": "static", "webhook_auth": "bearer"])

        let next = try await connectors.update("con-w", ConnectorUpdate(webhookAuth: .bearer, rotateSigningSecret: true))
        #expect(transport.last?.request.method == "PATCH")
        #expect(transport.last?.json == ["webhook_auth": "bearer", "rotate_signing_secret": true])
        #expect(next.signingSecret == "whsec_BBBB")
        #expect(next.webhookAuth == .bearer)
        #expect(next.previousSigningSecretExpiresAt == ISO8601.parse("2026-11-02T00:00:00Z"))
    }
}
