<!--
The agent prompt at the end of each API drift alert in #main-build-alerts.
scripts/api-drift-report.sh fills the {{...}} placeholders and drops this
comment; the rest is pasted verbatim into a coding agent, so it is written as
instructions to that agent.
-->

Fix the API drift that the nightly API Contract run found in introspection-swift-sdk ({{RUN_URL}}).

Where: the introspection-swift-sdk repository. Fetch origin, create a new branch from origin/main, and work only there.

What: make the SDK match the API reference, fixing exactly the drift in the SDK drift report below and nothing else. A missing operation gets a method on the SDK and a test against MockTransport that follows AGENTS.md. Deleting a call the check reports as an unknown route (one the API no longer has) is allowed; list each deletion in the PR body. The reference changelog is context: what changed in the API since the saved copies in api-reference/ were taken.

Finish: when the drift is fixed, refresh both saved copies from staging:

curl -fsS https://api.staging.introspection.dev/openapi/controlplane.json -o api-reference/controlplane.json
curl -fsS https://api.staging.introspection.dev/openapi/dataplane.json -o api-reference/dataplane.json

Stop when the check passes: INTROSPECTION_API_CONTRACT=1 swift test --filter APIContractTests, together with swift test and scripts/lint.sh.

Limits:

- Never add an exemption, allowlist or skip of any kind to the check: the x-introspection flags in the API documents are the only classification.
- Never edit the reference URLs in Tests/IntrospectionSDKTests/APIContractTests.swift or scripts/api-drift-report.sh.
- Never weaken, skip or delete a test to make it pass.

Questions, not changes: put these in the PR body as questions and leave the code alone.

- An SDK API break: a fix that would remove or retype something callers of the SDK use today. Ask whether to break it now or deprecate it first.
- A route the reference flags for the SDK that needs a product decision (a new resource, or one that needs a different credential, such as automations, which take a member token or an Application rather than an API key).

Output: one pull request against main with a Conventional Commit title. Its body lists the drift fixed, what was deleted, and the questions above.

If a report below ends with a trim marker, run the check or oasdiff changelog against the saved copies for the full list.

SDK drift (INTROSPECTION_API_CONTRACT=1 swift test --filter APIContractTests):

{{SDK_DRIFT}}

Reference changelog (oasdiff, api-reference/ saved copies vs staging):

{{CHANGELOG}}
