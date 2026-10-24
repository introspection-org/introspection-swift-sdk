import Foundation
import InlineSnapshotTesting
import IntrospectionSDK
import Testing

// Steps 13–16: telemetry reads, the eval and its experiment, sandbox commands, automations.
extension Walk {
    func step13TelemetryReads() async throws {
        // A fixed window, so the request replays; the walk's conversation is within it by construction.
        _ = try await sa.metrics.query(
            MetricQueryRequest(
                view: .conversations, metrics: [MetricSpec(.count)], from: ISO8601.parse("2026-01-01T00:00:00Z")!,
                to: ISO8601.parse("2027-01-01T00:00:00Z")!, filters: [MetricFilter("runtime_id", .eq, .string(runtime.id))]))

        // Access tags are an administrator's to write: the owner's token, not the service account.
        let tag = try await member.tags.create(.access(name: "walk", description: "the walk's tag"))
        snap(try stable(tag)) {
            """
            {
              "created_at" : "[timestamp]",
              "description" : "the walk's tag",
              "kind" : "access",
              "name" : "walk",
              "updated_at" : "[timestamp]"
            }
            """
        }
        _ = try await member.tags.get(.access, "walk")
        _ = try await member.tags.update(.access, "walk", .description("the walk's tag, updated"))
        let tags = try await member.tags.list(TagListParams(kind: .access)).all()
        try check(tags.contains { $0.name == "walk" }, "the tag is listed")

        // A tag share's grantor must hold the tag, so the file is shared to the owner member directly.
        let owners = try await owner.members.list().all()
        let share = try await sa.shares.create(
            ShareCreate(resourceType: .file, resourceId: outputFile.id, grantedMemberId: try #require(owners.first).id))
        snap(try stable(share)) {
            """
            {
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "granted_member_id" : "[uuid]",
              "id" : "[uuid]",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "resource_id" : "[uuid]",
              "resource_type" : "file",
              "updated_at" : "[timestamp]",
              "url" : "[url]"
            }
            """
        }
        _ = try await sa.shares.get(share.id)
        let shares = try await sa.shares.list(ShareListParams(resourceType: .file)).all()
        try check(shares.contains { $0.id == share.id }, "the share is listed")

        try await annotations()
        try await emptyReads()
    }

    private func annotations() async throws {
        // The annotation targets the conversation's first item (its span).
        let items = try await sa.conversations.items.list(conversationId).firstPage()
        guard let first = items.records.first, let spanId = first.spanId else { return }
        let traceId = first.traceId
        let span = AnnotationTarget(traceId: traceId, spanId: spanId)
        // Event ids derived from the span, so the requests replay; the SDK would mint them.
        _ = try await member.annotations.create(span, .labels(["walk"]), eventId: spanEventId(traceId, spanId, "labels"))
        // Reviewers by email resolve through the Control Plane's member list, which a member's Data Plane token
        // cannot read; the walk clears them, which needs no lookup, and reaches the check made before any request.
        _ = try await member.annotations.create(span, .reviewers([]), eventId: spanEventId(traceId, spanId, "reviewers"))
        do {
            _ = try await member.annotations.create(span, .reviewers([" "]))
            throw WalkError("a blank reviewer email is refused before any request")
        } catch let error as IntrospectionError where error.kind == .validation {}
        let annotations = try await member.annotations.list(AnnotationListParams(conversationId: conversationId)).all()
        // An annotation reads back once the processor has landed it; on the local stack it stays `visible: false`.
        if settings.target != "compose" {
            try check(annotations.first?.labels?.contains("walk") == true, "the annotation reads back")
        }
        let params = EventListParams(eventName: .annotation, conversationId: conversationId)
        let events = try await sa.events.list(params).all()
        if let event = events.first { _ = try await sa.events.get(event.id) }
        // todo: the SDK has no events.listArrow, and annotations.facets takes no conversation filter.
        let dp = raw(member.dataPlane)
        let table = try await raw(sa.dataPlane).data(
            "/v1/events", query: [("event_name", "introspection.annotation"), ("conversation_id", conversationId)],
            accept: "application/vnd.apache.arrow.stream")
        try check(!table.isEmpty, "the Arrow event list")
        let facets: JSONValue = try await dp.json("GET", "/v1/annotations/facets", query: [("conversation_id", conversationId)])
        try check(facets != .null, "the facets")
        _ = try await member.annotations.navigation(span)
    }

    private func emptyReads() async throws {
        // The AAuth surfaces, read empty. todo: the SDK has no AAuth resources.
        let dp = raw(sa.dataPlane)
        let missions: JSONValue = try await dp.json("GET", "/v1/aauth/missions")
        try check(missions["records"] == [], "no missions")
        let approvals: JSONValue = try await dp.json("GET", "/v1/aauth/approvals")
        try check(approvals["records"] == [], "no approvals")
        // `/v1/connections` is the apps a member connects through an app (Pipedream) connector; with none on the
        // project every route answers 404.
        try await expectNotFound({ try await member.connections.list().firstPage() }, "an app connection list")
        try await expectNotFound({ try await member.connections.get("019a1000-0000-7000-8000-0000000000c1") }, "an app connection")
        try await expectNotFound({ try await member.connections.delete("019a1000-0000-7000-8000-0000000000c1") }, "a deleted connection")
        try await expectNotFound({ try await member.connections.create(app: "gmail", runtime: WALK.runtimeSlug) }, "a new connection")
        // A client with no runtime of its own refuses before any request.
        do {
            _ = try await member.connections.create(app: "gmail")
            throw WalkError("a connection with no runtime is refused before any request")
        } catch let error as IntrospectionError where error.kind == .invalidRequest {}
    }

    func step14Eval() async throws {
        // What eval compose services run as, and the org's provider installs.
        let images = try await sa.images.list().firstPage()
        if let image = images.records.first { _ = try await sa.images.get(image.id) }
        _ = try await owner.integrations.list().firstPage()
        let judges = try await sa.judges.list(JudgeListParams(project: project.id, runtimeGroupId: runtime.runtimeGroupId)).firstPage()
        let greeting = try #require(judges.records.first { $0.name == "greeting" }, "the recipe's judge is synced")
        judge = greeting
        let readJudge = try await sa.judges.get(judge.id, project: project.id)
        try check(readJudge.name == "greeting", "the judge reads back")
        _ = try await sa.judges.update(judge.id, JudgeUpdate(enabled: true, sampleRate: 1), project: project.id)

        // A trial needs the evals capability, which the runner's session never carries; the service account holds
        // `tasks:eval` and names the runtime.
        let created = try await sa.tasks.create(
            TaskCreate(
                prompt: WALK.prompt(settings), kind: .eval, agentName: settings.agent, runtimeId: runtime.id,
                idleTimeoutSeconds: 120, metadata: ["suite": "walk"], commands: true))
        evalTask = created.task
        try check(evalTask.metadata?["suite"] == "walk", "the trial carries the walk's metadata")
        snap(try stable(evalTask, removing: ["metadata"])) {
            #"""
            {
              "agent" : {
                "sandbox_status" : "provisioning"
              },
              "created_at" : "[timestamp]",
              "display_index" : "[number]",
              "id" : "[uuid]",
              "is_archived" : false,
              "kind" : "eval",
              "last_user_message_at" : "[timestamp]",
              "member_id" : "[uuid]",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "runtime_group_id" : "[uuid]",
              "runtime_id" : "[uuid]",
              "status" : "pending",
              "tags" : [

              ],
              "title" : "Call the `echo` tool from the declared `hello-mcp` MCP server with the message `hello from the public MCP`. Write the echoed value exactly, with no quotes or additional formatting, to `\/workspace\/outputs\/greeting.txt`. Then run `echo $WALK_MARKER` in…",
              "updated_at" : "[timestamp]"
            }
            """#
        }
        // Read the run's stream to its end, then let the row settle: the judge grades the trajectory.
        for try await _ in sa.tasks.runs.stream(evalTask.id, created.run.id) {}
        let settledStatuses = ["idle", "awaiting_user", "completed", "failed"]
        evalTask = try await settled(
            "the trial", mode: mode, read: { try await sa.tasks.get(evalTask.id) }, poll: { try await saQuiet.tasks.get(evalTask.id) },
            done: { settledStatuses.contains($0.status.rawValue) })
        try check(["idle", "awaiting_user", "completed"].contains(evalTask.status.rawValue), "the trial ran")
        try await experiments()
    }

    /// An experiment over the walk's two runtime versions, graded by the recipe's judge.
    private func experimentCreate(_ name: String) -> ExperimentCreate {
        ExperimentCreate(
            project: project.id, runtime: runtime.runtimeGroupId ?? "", name: name,
            goalJson: ExperimentGoal(kind: "composite", components: [.judge(judge.id, weight: 1)]),
            arms: [
                ExperimentArmCreate(runtimeId: runtime.id, armLabel: "v1"),
                ExperimentArmCreate(runtimeId: runtimeV2.id, armLabel: "v2"),
            ])
    }

    private func experiments() async throws {
        experiment = try await sa.experiments.create(experimentCreate(WALK.experimentNames[0]))
        snap(try stable(experiment)) {
            """
            {
              "arms" : [
                {
                  "arm_label" : "v1",
                  "id" : "[uuid]",
                  "initial_weight" : 50,
                  "runtime_id" : "[uuid]"
                },
                {
                  "arm_label" : "v2",
                  "id" : "[uuid]",
                  "initial_weight" : 50,
                  "runtime_id" : "[uuid]"
                }
              ],
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "environment" : "production",
              "goal_json" : {
                "components" : [
                  {
                    "judge_definition_hash" : "[digest]",
                    "judge_id" : "[uuid]",
                    "source" : "judge",
                    "weight" : 1
                  }
                ],
                "direction" : "maximize",
                "kind" : "composite"
              },
              "hash_key_fields" : [
                "user.id",
                "anonymous.id",
                "conversation.id"
              ],
              "id" : "[uuid]",
              "name" : "The walk's experiment",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "routing_strategy" : "beta_sample",
              "runtime_group_id" : "[uuid]",
              "sample_rate" : 1,
              "scoring_interval_seconds" : 300,
              "status" : "draft",
              "updated_at" : "[timestamp]"
            }
            """
        }
        _ = try await sa.experiments.get(experiment.id)
        _ = try await sa.experiments.update(experiment.id, ExperimentUpdate(description: "two versions, one judge"))
        let started = try await sa.experiments.start(experiment.id)
        try check(started.status?.rawValue == "running", "the experiment runs")
        let listed = try await sa.experiments.list(ExperimentListParams(project: project.id)).all()
        try check(listed.contains { $0.id == experiment.id }, "the experiment is listed")
        try await endExperiments()
    }

    private func endExperiments() async throws {
        // Bandit routing needs a stable subject to assign an arm to.
        _ = try await sa.experiments.run(experiment.id, RunRequest(identity: RunnerIdentity(userId: "sdk-walk-user")))
        let ended = try await sa.experiments.end(experiment.id)
        snap(try stable(ended)) {
            """
            {
              "arms" : [
                {
                  "arm_label" : "v1",
                  "id" : "[uuid]",
                  "initial_weight" : 50,
                  "runtime_id" : "[uuid]"
                },
                {
                  "arm_label" : "v2",
                  "id" : "[uuid]",
                  "initial_weight" : 50,
                  "runtime_id" : "[uuid]"
                }
              ],
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "description" : "two versions, one judge",
              "ended_at" : "[timestamp]",
              "environment" : "production",
              "goal_json" : {
                "components" : [
                  {
                    "judge_definition_hash" : "[digest]",
                    "judge_id" : "[uuid]",
                    "source" : "judge",
                    "weight" : 1
                  }
                ],
                "direction" : "maximize",
                "kind" : "composite"
              },
              "hash_key_fields" : [
                "user.id",
                "anonymous.id",
                "conversation.id"
              ],
              "id" : "[uuid]",
              "name" : "The walk's experiment",
              "org_id" : "[uuid]",
              "project_id" : "[uuid]",
              "routing_strategy" : "beta_sample",
              "runtime_group_id" : "[uuid]",
              "sample_rate" : 1,
              "scoring_interval_seconds" : 300,
              "started_at" : "[timestamp]",
              "status" : "ended",
              "updated_at" : "[timestamp]"
            }
            """
        }
        let second = try await sa.experiments.create(experimentCreate(WALK.experimentNames[1]))
        _ = try await sa.experiments.start(second.id)
        let cancelled = try await sa.experiments.cancel(second.id)
        try check(cancelled.status?.rawValue == "cancelled", "the second experiment is cancelled")
        try await owner.experiments.delete(second.id, project: project.id)
    }

    func step15Commands() async throws {
        let finished = ["succeeded", "completed", "failed", "cancelled"]
        let command = { (spec: TaskCommandSpec) async throws -> TaskCommand in
            let created = try await self.sa.tasks.commands.create(self.evalTask.id, spec)
            return try await settled(
                "task command", mode: self.mode, read: { try await self.sa.tasks.commands.get(self.evalTask.id, created.id) },
                poll: { try await self.saQuiet.tasks.commands.get(self.evalTask.id, created.id) },
                done: { finished.contains($0.status?.rawValue ?? "") })
        }
        let exec = try await command(.exec(command: ["cat", "/workspace/outputs/\(WALK.outputFileName)"], timeoutSeconds: 30))
        snap(try stable(exec)) {
            #"""
            {
              "created_at" : "[timestamp]",
              "exit_code" : 0,
              "finished_at" : "[timestamp]",
              "id" : "[uuid]",
              "kind" : "exec",
              "spec" : {
                "command" : [
                  "cat",
                  "\/workspace\/outputs\/greeting.txt"
                ],
                "cwd" : null,
                "kind" : "exec",
                "service" : null,
                "timeout_seconds" : 30
              },
              "started_at" : "[timestamp]",
              "status" : "completed",
              "stderr" : "",
              "stdout" : "Echo: hello from the public MCP",
              "task_id" : "[uuid]",
              "updated_at" : "[timestamp]"
            }
            """#
        }
        try check(exec.stdout?.trimmingCharacters(in: .whitespacesAndNewlines) == WALK.echoResult, "the sandbox holds the output")
        let download = try await command(.download(path: "/workspace/outputs/\(WALK.outputFileName)"))
        try check(download.outputFileId != nil, "the download produced a file")
        let listed = try await sa.tasks.commands.list(evalTask.id).firstPage()
        try check(listed.records.count >= 2, "both commands are listed")

        // Judging calls the judge's own grader model; on the scripted target that is the model double, which
        // returns no verdict, so a judgement is asserted only where a real model grades.
        let params = EventListParams(eventName: .judgement, judgeId: judge.id)
        let judgements = try await settled(
            "judgement", mode: mode, timeout: .seconds(1800), interval: .seconds(10), read: { try await sa.events.list(params).all() },
            poll: { try await saQuiet.events.list(params).all() }, done: { !$0.isEmpty || settings.agent == "scripted" })
        if settings.agent != "scripted" { try check(!judgements.isEmpty, "the recipe's judge graded the trial") }
    }

    func step16Automations() async throws {
        // An automation its owner creates posts into that owner's own task; the first task was archived and
        // unarchived, which the trigger still refuses, so the trial is the one it posts into.
        automation = try await sa.automations.create(
            AutomationCreate(
                name: WALK.automationName, triggerType: .manual, prompt: WALK.secondTurn(settings), runtimeGroupId: runtime.runtimeGroupId,
                taskId: evalTask.id))
        snap(try stable(automation)) {
            #"""
            {
              "can_manage" : true,
              "created_at" : "[timestamp]",
              "created_by_member_id" : "[uuid]",
              "enabled" : true,
              "id" : "[uuid]",
              "name" : "The walk's automation",
              "org_id" : "[uuid]",
              "owner_role" : "operator",
              "project_id" : "[uuid]",
              "prompt" : "Reply with the single word done. <<SCRIPT {\"reply\":\"done\"}>>",
              "runtime_group_id" : "[uuid]",
              "tags" : [

              ],
              "task_id" : "[uuid]",
              "trigger_type" : "manual",
              "updated_at" : "[timestamp]"
            }
            """#
        }
        let triggered = try await sa.automations.trigger(automation.id)
        snap(try stable(triggered)) {
            """
            {
              "automation_id" : "[uuid]",
              "status" : "triggered",
              "task_id" : "[uuid]"
            }
            """
        }
        _ = try await sa.automations.get(automation.id)
        _ = try await sa.automations.update(automation.id, AutomationUpdate(description: "triggered once by the walk"))
        let listed = try await sa.automations.list().all()
        try check(listed.contains { $0.id == automation.id }, "the automation is listed")
    }
}
