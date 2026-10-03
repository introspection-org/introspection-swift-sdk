# Runs and streaming

Start tasks, stream their answers as they are written, and continue the conversation.

## Overview

A task is one conversation with an agent; each message you send starts a run on it. A run streams AG-UI events over Server-Sent Events, which the SDK resumes after a dropped connection using `Last-Event-ID`.

## Stream an answer

```swift
let handle = try await runner.tasks.start(prompt: "Write a haiku about Swift.")
for try await event in handle.stream() {
    switch event.eventType {
    case .textMessageContent, .textMessageChunk:
        print(event.delta ?? "", terminator: "")
    case .runError:
        print("failed:", event.message ?? "")
    default:
        break
    }
}
```

Each ``AGUIEvent`` keeps the full event as `raw` ``JSONValue`` and exposes the common fields (`delta`, `messageId`, `toolCallId`, `snapshot`, ...) as properties, so an event type added on the server still decodes.

``RunStreamOptions`` controls how long to wait for the run to become ready, the overall timeout and the reconnect budget.

## Continue a task

```swift
let next = try await runner.tasks.runs.create(handle.run.taskId, text: "Another one, about Rust.")
let answer = try await next.text()
```

A task accepts one reply at a time. Sending while a reply is still being delivered fails with an ``IntrospectionError`` of kind `.conflict`.

## Build a transcript

``TranscriptAccumulator`` folds live events into ordered transcript entries (messages, tool calls, delegations) for display. Stored conversations come back as GenAI spans from ``ConversationsAPI`` and fold into the same entries, so a screen can render history and the live run together.
