#!/usr/bin/env python3
"""Generate the AG-UI model structs from the @ag-ui/core JSON Schema snapshot, then swift-format them.

Usage, from the repository root (Python standard library only):
  node scripts/export-ag-ui-schema.mjs <dir> > Tests/IntrospectionSDKTests/Fixtures/ag-ui-core.schema.json
  scripts/generate-ag-ui-models.py
  swift test --filter AGUISchemaParityTests
`--inits` prints the `inits` table of AGUISchemaParityTests instead of writing the sources.
The unions, enums and AGUIEventPayload in AGUIUnions.swift and AGUIEvent.swift are hand-written.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

SCHEMA = Path("Tests/IntrospectionSDKTests/Fixtures/ag-ui-core.schema.json")
OUT = Path("Sources/IntrospectionSDK/AGUI")

REF_TYPES = {
    "SubagentRunId": "String", "JsonPointer": "String", "Metadata": "JSONValue", "State": "JSONValue",
    "TextMessageRole": "TextMessageRole", "ReasoningEncryptedValueSubtype": "ReasoningEncryptedValueSubtype",
    "JsonPatch": "[JsonPatchOperation]", "Message": "Message", "PartSource": "InputContentSource",
    "InputContentSource": "InputContentSource", "InputContent": "InputContent",
    "RunFinishedOutcome": "RunFinishedOutcome", "SubagentFinishedOutcome": "SubagentFinishedOutcome",
}
STRUCT_NAME = {"InputContentDataSource": "DataSource", "InputContentUrlSource": "UrlSource"}
# A constant that belongs to another type's tag: REASONING_MESSAGE_START's role, TOOL_CALL_RESULT's role.
CONST_OWNER = {("ReasoningMessageStartEvent", "role"): "ReasoningMessage", ("ToolCallResultEvent", "role"): "ToolMessage"}
BASE_FIELDS = ["timestamp", "rawEvent", "metadata"]

MESSAGES = ["DeveloperMessage", "SystemMessage", "AssistantMessage", "UserMessage", "ToolMessage", "ActivityMessage",
            "ReasoningMessage", "ToolCall", "FunctionCall", "TextPart", "ImagePart", "AudioPart", "VideoPart",
            "DocumentPart", "InputContentDataSource", "UrlSource", "FileSource"]
TYPES = ["Interrupt", "RunFinishedSuccessOutcome", "RunFinishedInterruptOutcome", "RunFinishedCancelledOutcome",
         "SubagentFinishedSuccessOutcome", "SubagentFinishedSuspendedOutcome", "AddOperation", "RemoveOperation",
         "ReplaceOperation", "MoveOperation", "CopyOperation", "TestOperation", "RunAgentInput", "Tool", "Context",
         "ResumeEntry", "TokenUsage"]

RUN_AGENT_INPUT_DECODER = """
extension AGUI.RunAgentInput {
    // `state` may be an explicit `null`, which synthesized decoding would read as absent.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        runId = try container.decode(String.self, forKey: .runId)
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        parentRunId = try container.decodeIfPresent(String.self, forKey: .parentRunId)
        state = container.contains(.state) ? try container.decode(JSONValue.self, forKey: .state) : JSONValue?.none
        messages = try container.decode([AGUI.Message].self, forKey: .messages)
        tools = try container.decodeIfPresent([AGUI.Tool].self, forKey: .tools)
        context = try container.decodeIfPresent([AGUI.Context].self, forKey: .context)
        forwardedProps = try container.decodeIfPresent(JSONValue.self, forKey: .forwardedProps)
        resume = try container.decodeIfPresent([AGUI.ResumeEntry].self, forKey: .resume)
    }
}
"""


def swift_type(defs, owner, name, prop):
    if "$ref" in prop:
        ref = prop["$ref"].split("/")[-1]
        return REF_TYPES.get(ref, STRUCT_NAME.get(ref, ref))
    if "const" in prop:
        return "AGUIConst<%s>" % CONST_OWNER.get((owner, name), owner)
    if "enum" in prop:
        if prop["enum"] != ["resolved", "cancelled"]:
            raise SystemExit("unmapped inline enum %s.%s: %s" % (owner, name, prop["enum"]))
        return "ResumeStatus"
    if "anyOf" in prop:
        branches = json.dumps(prop["anyOf"])
        if "InputContent" in branches:
            return "MessageContent"
        if "State" in branches:
            return "JSONValue"
        raise SystemExit("unmapped anyOf %s.%s" % (owner, name))
    if not prop:
        return "JSONValue"
    if prop["type"] == "array":
        return "[%s]" % swift_type(defs, owner, name, prop["items"])
    return {"string": "String", "integer": "Int", "boolean": "Bool"}[prop["type"]]


def struct(defs, def_name, is_event):
    name = STRUCT_NAME.get(def_name, def_name)
    schema = defs[def_name]
    required = schema.get("required", [])
    props = schema["properties"]
    conform = "AGUIEventBody" if is_event else "Codable, Sendable, Hashable"
    own = [(p, s["const"]) for p, s in props.items() if "const" in s and CONST_OWNER.get((name, p), name) == name]
    if own and not is_event:
        conform = "AGUIDiscriminated, " + conform
    doc = "`%s`." % props["type"]["const"] if is_event else "AG-UI `%s`." % name
    lines = ["    /// " + doc, "    public struct %s: %s {" % (name, conform)]
    if is_event:
        camel = re.sub(r"_([a-z])", lambda m: m.group(1).upper(), props["type"]["const"].lower())
        lines.append("        public static let eventType: AGUIEventType = .%s" % camel)
    elif own:
        lines.append('        public static let discriminator = "%s"' % own[0][1])
    required_params, optional_params, assigns = [], [], []
    for prop_name, prop in props.items():
        swift = swift_type(defs, name, prop_name, prop)
        optional = prop_name not in required
        if swift.startswith("AGUIConst") and not optional:
            lines.append("        public var %s = %s()" % (prop_name, swift))
            continue
        lines.append("        public var %s: %s%s" % (prop_name, swift, "?" if optional else ""))
        (optional_params if optional else required_params).append(
            (prop_name, "%s: %s%s" % (prop_name, swift, "? = nil" if optional else "")))
        assigns.append(prop_name)
    optional_params = [p for p in optional_params if p[0] not in BASE_FIELDS] + [
        p for p in optional_params if p[0] in BASE_FIELDS]
    params = required_params + optional_params
    lines += ["", "        public init(%s) {" % ", ".join(p[1] for p in params)]
    lines += ["            self.%s = %s" % (a, a) for a in assigns]
    lines += ["        }", "    }"]
    return name, [p[0] for p in params], "\n".join(lines)


def file_text(defs, names, is_event, reason):
    body = "\n\n".join(struct(defs, n, is_event)[2] for n in names)
    return "import Foundation\n\n// jscpd:ignore-start: %s\nextension AGUI {\n%s\n}\n// jscpd:ignore-end\n" % (reason, body)


def main():
    defs = json.loads(SCHEMA.read_text())["$defs"]
    events = [ref["$ref"].split("/")[-1] for ref in defs["Event"]["oneOf"]]
    if "--inits" in sys.argv:
        for def_name, is_event in [(d, False) for d in MESSAGES + TYPES] + [(e, True) for e in events]:
            name, params, _ = struct(defs, def_name, is_event)
            args = ", ".join("%s: m.%s" % (p, p) for p in params)
            print('        "%s": { let m = try $0.decode(AGUI.%s.self); return AGUI.%s(%s) == m },'
                  % (def_name, name, name, args))
        return
    files = {
        OUT / "AGUIEvents.swift": file_text(
            defs, events, True, "one struct per AG-UI event schema, which repeat the base event fields."),
        OUT / "AGUIMessages.swift": file_text(
            defs, MESSAGES, False, "one struct per AG-UI message and content schema, which repeat their fields."),
        OUT / "AGUITypes.swift": file_text(defs, TYPES, False, "one struct per AG-UI schema, which repeat their fields.")
        + RUN_AGENT_INPUT_DECODER,
    }
    for path, text in files.items():
        path.write_text(text)
    subprocess.run(["swift", "format", "format", "--in-place", "--configuration", ".swift-format",
                    *map(str, files)], check=True)


if __name__ == "__main__":
    main()
