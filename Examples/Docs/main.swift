// Compiled Swift equivalents of the snippets on docs.introspection.dev. Each
// `// #region docs:<id>` ... `// #endregion docs:<id>` pair marks exactly the
// lines a docs page shows; the setup around it (client construction,
// placeholder values, stubs for the app's own code) stays outside.
//
// The examples are compiled by CI, not run: they need a deployment. Running
// the target only lists the pages it covers:
//
//     swift run DocsExamples

let pages = [
    "reference/authentication", "observe/patterns", "identity/agents", "identity/sharing",
    "patterns/add-to-your-app", "patterns/agent-follow-ups", "patterns/approve-outside", "patterns/ask-the-user",
    "patterns/files", "patterns/multi-tenant", "patterns/per-user-tools",
    "patterns/structured-output", "patterns/trigger", "patterns/web-chat", "reference/swift",
]
print("Docs snippets for:")
for page in pages { print("  \(page)") }
