import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct StrictSchemaTests {
    private struct Inner: Decodable { let name: String }
    private struct Outer: Decodable {
        let id: String
        let items: [Inner]
        let note: String?
    }
    private struct Open: Decodable, OpenSchema { let kind: String }
    private struct Wrapper: Decodable { let open: Open }

    /// Reads through every container shape a hand-written `init(from:)` can use.
    private struct Shapes: Decodable {
        enum Keys: String, CodingKey { case meta, list, base, gap }
        enum Meta: String, CodingKey { case kind }
        let values: [String?]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let meta = try container.nestedContainer(keyedBy: Meta.self, forKey: .meta)
            _ = try meta.decode(String.self, forKey: .kind)
            var list = try container.nestedUnkeyedContainer(forKey: .list)
            #expect(list.count == 4 && decoder.userInfo.isEmpty)
            var values: [String?] = []
            while !list.isAtEnd {
                if try list.decodeNil() {
                    values.append(nil)
                } else if let object = try? list.nestedContainer(keyedBy: Meta.self) {
                    values.append(try object.decode(String.self, forKey: .kind))
                } else if var nested = try? list.nestedUnkeyedContainer() {
                    values.append(try nested.decode(String.self))
                } else {
                    values.append(try list.superDecoder().singleValueContainer().decode(String.self))
                }
            }
            #expect(throws: DecodingError.self) { try list.decode(String.self) }
            _ = try container.superDecoder(forKey: .base).container(keyedBy: Meta.self).decode(String.self, forKey: .kind)
            _ = try container.superDecoder().singleValueContainer().decode(Int.self)
            #expect(throws: DecodingError.self) { try container.decode(String.self, forKey: .gap) }
            self.values = values
        }
    }

    private struct Primitives: Decodable {
        let url: URL
        let data: Data
        let amount: Decimal
        let ratio: Float
        let small: Int8
        let flag: Bool
    }

    private struct BigCount: Decodable { let count: Int }

    private func client(_ json: String, strict: Bool) -> HTTPClient {
        var options = HTTPClient.Options()
        options.strictSchema = strict
        return HTTPClient(baseURL: URL(string: "https://api.test")!, transport: MockTransport(json: json), options: options)
    }

    private func drift<T: Decodable>(_ json: String, as type: T.Type, route: String = "/v1/things") async -> IntrospectionError? {
        do {
            _ = try await client(json, strict: true).json("GET", route, as: T.self)
            return nil
        } catch {
            return error as? IntrospectionError
        }
    }

    @Test func offToleratesAnUnknownField() async throws {
        let decoded = try await client(#"{"id":"a","items":[],"color":"red"}"#, strict: false).json("GET", "/v1/things", as: Outer.self)
        #expect(decoded.id == "a")
    }

    @Test func onNamesTheRouteAndEveryPath() async throws {
        let json = #"{"id":"a","color":"red","items":[{"name":"x"},{"name":"y","size":2,"extra":{"deep":1}}]}"#
        let error = try #require(await drift(json, as: Outer.self))
        #expect(error.kind == .decoding)
        #expect(error.code == StrictSchema.errorCode)
        #expect(error.unmodelledFields == ["$.color", "$.items[1].extra", "$.items[1].size"])
        #expect(error.message == "/v1/things: response fields this SDK does not model: $.color, $.items[1].extra, $.items[1].size")
    }

    @Test func aMatchingResponsePasses() async throws {
        let decoded = try await client(#"{"id":"a","items":[{"name":"x"}]}"#, strict: true).json("GET", "/v1/things", as: Outer.self)
        #expect(decoded.items.count == 1)
    }

    @Test func nullForAModelledOptionalIsNotDrift() async throws {
        #expect(await drift(#"{"id":"a","items":[],"note":null}"#, as: Outer.self) == nil)
        let run = #"{"id":"r","task_id":"t","status":"completed","error":null,"completion_reason":null,"created_at":null}"#
        #expect(await drift(run, as: TaskRun.self) == nil)
    }

    @Test func displayIdsRecipeAgentsAndTagArchivesAreModelled() async throws {
        let project = #"""
            {"id":"p","org_id":"o","deployment_id":"d","name":"Main","slug":"main","description":null,"settings":{},
             "created_by_member_id":null,"display_id_prefixes":{"issue":"BUG","report":"R","observation":"F","task":"T"}}
            """#
        #expect(await drift(project, as: Project.self, route: "/v1/projects/p") == nil)
        let recipe = #"""
            {"id":"r","name":"walk","agents":["agent","triage"],"issue_providers":["linear"],"created_at":"2026-11-01T00:00:00Z"}
            """#
        #expect(await drift(recipe, as: Recipe.self, route: "/v1/recipes/r") == nil)
        let tag = #"""
            {"kind":"access","name":"acme-old","color":null,"description":null,"created_at":"2026-11-01T00:00:00Z",
             "updated_at":"2026-11-02T00:00:00Z","archived_at":"2026-11-02T00:00:00.123456Z","replaced_by":"acme","archived_names":[]}
            """#
        #expect(await drift(tag, as: SDKTag.self, route: "/v1/tags/access/acme-old") == nil)
        let issue = #"""
            {"id":"i","org_id":"o","project_id":"p","title":"t","description":"d","priority":"medium","status":"open",
             "revision":1,"display_index":7,"display_key":"BUG-7","tags":[],"metadata":{}}
            """#
        #expect(await drift(issue, as: Issue.self, route: "/v1/issues/i") == nil)
    }

    @Test func signInIssueWarningsAndDiagnosticSeverityAreModelled() async throws {
        let org = #"""
            {"id":"o","name":"Acme","slug":"acme","external_org_id":null,"image_url":null,"hosted_git":true,
             "sign_in":{"passkey_requirement":"except_sso","restrict_invites_to_domains":true}}
            """#
        #expect(await drift(org, as: Organization.self, route: "/v1/organizations/me") == nil)
        let decoded = try await client(org, strict: true).json("GET", "/v1/organizations/me", as: Organization.self)
        #expect(decoded.signIn == SignInSettings(passkeyRequirement: .exceptSso, restrictInvitesToDomains: true))
        let unknown = try JSONCoding.decoder.decode(SignInSettings.self, from: Data(#"{"passkey_requirement":"hardware_key"}"#.utf8))
        #expect(unknown.passkeyRequirement == "hardware_key")
        #expect(unknown.restrictInvitesToDomains == nil)

        let issue = #"""
            {"id":"i","org_id":"o","project_id":"p","title":"t","description":"d","priority":"medium","status":"open",
             "revision":1,"tags":[],"metadata":{},"warnings":["comments beyond 500 were left out"]}
            """#
        #expect(await drift(issue, as: Issue.self, route: "/v1/issues/i") == nil)
        let read = try await client(issue, strict: true).json("GET", "/v1/issues/i", as: Issue.self)
        #expect(read.warnings == ["comments beyond 500 were left out"])

        let recipe = #"""
            {"id":"r","validation":{"status":"valid","diagnostics":[
              {"code":"R001","path":"agents/agent.yaml","span":{"line":1,"column":2},"message":"m","help":null,"severity":"warning"}]},
             "git_commit_sha":"543b8db50a83aa1e2f3c4d5e6f708192a3b4c5d6"}
            """#
        let pinned = try await client(recipe, strict: true).json("GET", "/v1/recipes/r", as: Recipe.self)
        #expect(pinned.validation?.diagnostics?.first?.severity == .warning)
        #expect(RecipeValidationDiagnostic().severity == nil)

        let runtime = #"{"id":"rt","recipe_ref":"main","git_commit_sha":"543b8db50a83aa1e2f3c4d5e6f708192a3b4c5d6"}"#
        #expect(await drift(runtime, as: Runtime.self, route: "/v1/runtimes/rt") == nil)
    }

    @Test func imageBuildMetadataKeepsTheDataPlanesOwnMembers() async throws {
        let page = #"""
            {"records":[{"id":"rt","image_build_status":"ready","image_build_metadata":{"image_tag":"t","built_at":"2026-11-12T00:00:00Z",
              "size_bytes":1024,"external_image_name":"img","verdict_by":"2026-11-12T00:10:00Z",
              "cli_version":"0.81.0","harbor_adapter_version":"0.16.0","future_flag":true}}],"count":1,"next":null}
            """#
        #expect(await drift(page, as: Page<Runtime>.self, route: "/v1/runtimes") == nil)
        let runtimes = try await client(page, strict: true).json("GET", "/v1/runtimes", as: Page<Runtime>.self)
        let metadata = try #require(runtimes.records.first?.imageBuildMetadata)
        #expect(metadata.imageTag == "t")
        #expect(metadata.sizeBytes == 1024)
        #expect(metadata.verdictBy == ISO8601.parse("2026-11-12T00:10:00Z"))
        #expect(metadata.extra == ["cli_version": "0.81.0", "harbor_adapter_version": "0.16.0", "future_flag": true])
        let wire = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(metadata))
        #expect(wire["cli_version"] == "0.81.0")
        #expect(wire["image_tag"] == "t")
        #expect(try JSONCoding.decoder.decode(RuntimeImageBuildMetadata.self, from: JSONCoding.encoder.encode(metadata)) == metadata)
        #expect(RuntimeImageBuildMetadata(imageTag: "t").extra == [:])

        // A modelled field wins over an `extra` member of the same name.
        var shadowed = RuntimeImageBuildMetadata(imageTag: "t")
        shadowed.extra = ["image_tag": "other"]
        let written = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(shadowed))
        #expect(written == ["image_tag": "t"])
    }

    @Test func connectionIntegrationsSubscriptionAndEndpointIntegrationAreModelled() async throws {
        let project = #"""
            {"id":"p","org_id":"o","deployment_id":"d","name":"Main","slug":"main","description":null,"settings":{},
             "created_by_member_id":null,"display_id_prefixes":{"issue":"I","report":"R","observation":"F","task":"T"},
             "connection_integrations":["google_workspace","microsoft_365","future_suite"]}
            """#
        #expect(await drift(project, as: Project.self, route: "/v1/projects/p") == nil)
        let read = try await client(project, strict: true).json("GET", "/v1/projects/p", as: Project.self)
        #expect(read.connectionIntegrations == [.googleWorkspace, .microsoft365, "future_suite"])

        let org = #"{"id":"o","name":"Acme","slug":"acme","hosted_git":true,"sign_in":null,"subscription_live":true}"#
        #expect(await drift(org, as: Organization.self, route: "/v1/organizations/me") == nil)
        #expect(try await client(org, strict: true).json("GET", "/v1/organizations/me", as: Organization.self).subscriptionLive == true)

        let metadata = #"{"mcp_server_id":"gmail","connector_id":null,"integration_id":"int-1","extra_hosts":[]}"#
        #expect(await drift(metadata, as: EndpointMetadata.self) == nil)
        #expect(try JSONCoding.decoder.decode(EndpointMetadata.self, from: Data(metadata.utf8)).integrationId == "int-1")
    }

    @Test func openMapsNeverReport() async throws {
        let spans = #"""
            {"object":"list","data":[{"trace_id":"t","span_id":"s","name":"chat",
              "attributes":{"introspection.tool_call_ids":["c1"],"gen_ai.anything":{"new":true}},
              "resource":{"service.name":"x","novel":1}}],"has_more":false}
            """#
        #expect(await drift(spans, as: GenAISpanList.self) == nil)
        #expect(await drift(#"{"open":{"kind":"a","novel":1}}"#, as: Wrapper.self) == nil)
    }

    @Test func listEnvelopesAreChecked() async throws {
        let error = try #require(await drift(#"{"records":[],"count":0,"cursor_v2":"x"}"#, as: Page<Member>.self, route: "/v1/members"))
        #expect(error.unmodelledFields == ["$.cursor_v2"])
        #expect(error.message.hasPrefix("/v1/members: "))
    }

    @Test func datesAndOpenEnumsDecode() async throws {
        let member = #"""
            {"id":"m","member_type":"some_new_type","seat_tier":"pro","spend_limit_cents":500,
             "created_at":"2026-11-06T08:00:00.123456Z","updated_at":1762416000}
            """#
        #expect(await drift(member, as: Member.self) == nil)
    }

    @Test func everyContainerShapeIsTracked() async throws {
        let json = #"{"meta":{"kind":"a"},"list":[null,{"kind":"k"},["x"],"y"],"base":{"kind":"b","stray":1},"super":3}"#
        let error = try #require(await drift(json, as: Shapes.self))
        #expect(error.unmodelledFields == ["$.base.stray"])
    }

    @Test func primitivesDecode() async throws {
        let json = #"{"url":"https://x.test/a","data":"aGk=","amount":1.5,"ratio":0.25,"small":3,"flag":true}"#
        #expect(await drift(json, as: Primitives.self) == nil)
    }

    @Test func aStrictDecodeFailureIsReported() async throws {
        // JSONDecoder reads Int.max exactly; the strict pass parses numbers as doubles and cannot.
        let error = try #require(await drift(#"{"count":9223372036854775807}"#, as: BigCount.self))
        #expect(error.code == StrictSchema.errorCode)
        #expect(error.message.contains("strict decoding of BigCount failed"))
    }

    @Test func compactionDecodes() async throws {
        let json = #"""
            {"object":"list","data":[],"has_more":false,"compaction":{"applied":true,"response_id":"r1","cursor":"c",
              "history":[{"response_id":"r0","at_compaction":{"turns":4,"tokens":900},"since_compaction":{"turns":4,"tokens":900}}]}}
            """#
        let list = try await client(json, strict: true).json("GET", "/v1/conversations/c/items", as: GenAISpanList.self)
        let expected = ConversationCompaction(
            applied: true, responseId: "r1", cursor: "c",
            history: [
                ConversationCompactionRecord(
                    responseId: "r0", atCompaction: CompactionCounts(turns: 4, tokens: 900),
                    sinceCompaction: CompactionCounts(turns: 4, tokens: 900))
            ])
        #expect(list.compaction == expected)
        var built = GenAISpanList(data: [], hasMore: false)
        built.compaction = expected
        #expect(built.compaction?.history?.first?.atCompaction?.tokens == 900)
    }
}
