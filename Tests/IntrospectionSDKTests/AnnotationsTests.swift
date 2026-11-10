import Foundation
import Testing

@testable import IntrospectionSDK

@Suite struct AnnotationsTests {
    @Test func annotationStateDecodesAnOlderDataPlaneRow() throws {
        let row =
            #"{"trace_id": "0123456789abcdef0123456789abcdef", "span_id": "0123456789abcdef", "conversation_id": "conv", "labels": ["bug"], "assignee_member_ids": ["m-2"], "annotator_member_ids": ["m-1"], "commenter_member_ids": ["m-1"], "has_comment": true, "human_commenter_member_ids": ["m-3"], "has_human_comment": true, "comment_count": 2, "latest_comment": "see", "latest_comment_member_id": "m-1", "latest_comment_actor_member_id": null, "latest_comment_actor_type": null, "updated_at": "2026-10-01T00:00:00Z", "updated_by_member_id": "m-1", "assignment_event_id": null}"#
        let state = try JSONCoding.decoder.decode(AnnotationState.self, from: Data(row.utf8))
        #expect(state.reviewerMemberIds == ["m-3"])
        #expect(state.updatedByMemberId == "m-1")
        #expect(state.commentCount == 2)
        #expect(state.comments == nil)

        let encoded = try JSONCoding.decoder.decode(JSONValue.self, from: JSONCoding.encoder.encode(state))
        #expect(encoded["reviewer_member_ids"] == .array([.string("m-3")]))
        #expect(encoded["human_commenter_member_ids"] == nil)
    }

    @Test func annotationListLoadsCommentsWhenIncluded() async throws {
        let human =
            #"{"event_id": "ev-1", "comment": "see", "member_id": "m-1", "actor_member_id": null, "actor_member_type": null, "created_at": "2026-10-01T00:00:00Z"}"#
        let agent =
            #"{"event_id": "ev-2", "comment": "done", "member_id": "m-1", "actor_member_id": "m-7", "actor_member_type": "agent", "created_at": "2026-10-02T00:00:00Z"}"#
        let transport = MockTransport(
            json:
                #"{"records": [{"trace_id": "t1", "span_id": "s1", "comment_count": 2, "comments": [\#(human), \#(agent)]}, {"trace_id": "t1", "span_id": "s2", "comment_count": 0, "comments": []}], "count": 2, "next": null}"#
        )
        let states = try await makeClient(transport).annotations.list(AnnotationListParams(include: [.comments])).collect()
        #expect(transport.last?.query["include"] == ["comments"])

        let comments = try #require(states.first?.comments)
        #expect(comments.map(\.eventId) == ["ev-1", "ev-2"])
        #expect(comments.map(\.comment) == ["see", "done"])
        #expect(comments.map(\.memberId) == ["m-1", "m-1"])
        #expect(comments.map(\.actorMemberId) == [nil, "m-7"])
        #expect(comments.map(\.actorMemberType) == [nil, "agent"])
        #expect(comments.first?.createdAt == ISO8601.parse("2026-10-01T00:00:00Z"))
        #expect(states.first?.commentCount == 2)
        #expect(states.last?.comments == [])
    }

    @Test func annotationListRejectsConflictingFilters() async throws {
        let transport = MockTransport(json: "{}")
        let error = try await #require(throws: IntrospectionError.self) {
            try await makeClient(transport).annotations.list(AnnotationListParams(annotatedByMemberId: "m", annotatedByEmail: "a@x"))
                .collect()
        }
        #expect(error.code == "conflicting_annotation_annotator_filters")
        #expect(transport.requests.isEmpty)
    }

    @Test func annotationNavigation() async throws {
        let transport = MockTransport(
            json:
                #"{"previous": null, "current": {"trace_id": "t", "span_id": "s"}, "next": null, "current_position": 0, "total_count": 1}"#
        )
        let annotations = makeClient(transport).annotations
        let window = try await annotations.navigation(AnnotationTarget(traceId: "t", spanId: "s"), labels: ["bug"], lookbackDays: 7)
        #expect(window.current?.spanId == "s")
        #expect(window.totalCount == 1)
        #expect(transport.last?.path == "/v1/annotations/navigation")
        #expect(transport.last?.query["trace_id"] == ["t"])
        #expect(transport.last?.query["lookback_days"] == ["7"])
    }

    @Test func annotationListReadsADatasetSizeFromTheTotal() async throws {
        let transport = MockTransport(
            json:
                #"{"records": [{"trace_id": "t", "span_id": "s", "updated_at": "2026-10-01T00:00:00Z"}], "count": 1, "total_count": 42, "next": "p2"}"#
        )
        let params = AnnotationListParams(labels: ["bug"], includeTotal: true, limit: 1, lookbackDays: 30)
        let page = try await makeClient(transport).annotations.list(params).page(at: nil)
        #expect(page.totalCount == 42)
        #expect(page.records.first?.updatedAt != nil)
        #expect(transport.last?.query["label"] == ["bug"])
        #expect(transport.last?.query["limit"] == ["1"])
        #expect(transport.last?.query["include_total"] == ["true"])
        #expect(transport.last?.query["lookback_days"] == ["30"])
    }
}
