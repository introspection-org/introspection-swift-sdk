// docs: observe/patterns
//
// IntrospectionLogs needs the `Telemetry` package trait.

#if Telemetry
import IntrospectionSDK
import IntrospectionTelemetry

enum ObservePatterns {
    static func feedbackEvents(user: SignedInUser, task: IntrospectionTask) async throws {
        // #region docs:observe/patterns/feedback-events
        let logs = try IntrospectionLogs(serviceName: "support-api")

        try IntrospectionTelemetry.withUserId(user.id) {
            logs.feedback(
                "thumbs_down",
                comments: "Applied the wrong refund rule",
                conversationId: task.conversationId,
                previousResponseId: task.metadata?["last_response"]?["response_id"]?.stringValue  // the answer being rated
            )
            try logs.track("case_closed", properties: ["value": 1, "plan": "pro"])
        }
        await logs.flush()
        // #endregion docs:observe/patterns/feedback-events
    }
}
#endif
