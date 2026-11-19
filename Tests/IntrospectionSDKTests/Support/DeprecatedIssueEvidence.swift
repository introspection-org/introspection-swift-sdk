@testable import IntrospectionSDK

/// The deprecated evidence lists, reached through protocols so their tests build without deprecation warnings. This file
/// does not import Testing, whose `Issue` would make the conformance below ambiguous.
protocol ReadsEvidenceLists {
    var files: [IssueFile]? { get }
    var links: [IssueLink]? { get }
    var events: [IssueEventReference]? { get }
    var spans: [IssueSpanReference]? { get }
}

protocol WritesEvidenceLists {
    var files: [IssueFile]? { get set }
    var links: [IssueLink]? { get set }
    var events: [IssueEventReference]? { get set }
    var spans: [IssueSpanReference]? { get set }
}

extension Issue: ReadsEvidenceLists {}
extension IssueCreate: WritesEvidenceLists {}
extension IssueUpdate: WritesEvidenceLists {}

func withEvidenceLists<T: WritesEvidenceLists>(
    _ body: T, files: [IssueFile], links: [IssueLink],
    events: [IssueEventReference], spans: [IssueSpanReference]
) -> T {
    var body = body
    body.files = files
    body.links = links
    body.events = events
    body.spans = spans
    return body
}
