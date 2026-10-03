# AGENTS.md

Guidance for anyone contributing to this repository, humans and coding agents alike. Read it before opening a pull request.

## Workflow

```sh
scripts/setup-hooks.sh   # once: installs the pre-commit hook
swift build
swift test
scripts/lint.sh --fix    # swift format, then the strict lint CI runs
scripts/coverage.sh      # tests with the line-coverage floor
```

No Swift toolchain? `scripts/docker-test.sh` runs the tests in `swift:6.1-noble`.

The pre-commit hook runs the lint, a warnings-as-errors build and the coverage-gated tests. CI runs the same checks plus a secrets scan, actionlint, Apple-platform builds (including iOS and documentation), and the PR title check. CI is the source of truth.

## Pull requests and releases

- **The PR title is a Conventional Commit**: `feat:`, `fix:`, `docs:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:`, with an optional scope (`feat(auth):`). Breaking changes use `feat!:` or a `BREAKING CHANGE:` footer. The title becomes the squash commit, and release-please derives the version and changelog from it.
- **Releases** come from the release-please PR. Merging it tags `vX.Y.Z`, which is what Swift Package Manager installs. Never tag by hand and never edit `version.txt`, `CHANGELOG.md` or the `x-release-please-version` lines.
- **Pre-1.0**, a `feat` bumps the minor version and a `fix` the patch; a breaking change bumps the minor version.

## Code conventions

- **No dependencies.** The package is Foundation only and must build on Linux (`FoundationNetworking` under `#if canImport`). Apple-only code (Keychain, AuthenticationServices) is guarded with `#if canImport(...)` and is compiled by the macOS CI job.
- **The wire format is the server's.** Model properties are camelCase Swift with an explicit `CodingKeys` enum for every snake_case wire name. Never set a key-coding strategy: it would also rewrite the keys of open-ended `JSONValue` metadata.
- **Decoding never fails on an unknown value.** Response fields are optional unless the server guarantees them, and status-like fields are `RawRepresentable` structs with static constants, so a value added on the server still decodes.
- **Ids are `String`, timestamps are `Date`**, open-ended objects are `JSONObject` / `JSONValue`.
- **Every path segment goes through `pathSegment(_:)`.**
- **Semantic-convention strings** (`gen_ai.*`, `introspection.*`, event names, AG-UI custom events) are defined once in `SemanticConventions.swift` and pinned by its tests.
- **Public API**: required parameters first, optional ones with defaults after; one short `///` line per public declaration, plus anything non-obvious about server behaviour.
- **Comments** record what the code cannot say (a server quirk, a constraint, a decision); they do not narrate the next line.

## Tests

- Every resource is tested against `MockTransport`: request method, path, query and body encoding, and decoding of realistic server JSON taken from the server models.
- The coverage floor in `scripts/coverage.sh` is a do-not-regress gate. Add tests for new code; lower the floor only with an explicit justification in the PR.
- `IdentityModesTests` drives every way of authenticating (API key, service account runner with end-user identity, federated exchange, hosted login, device code) through a fake platform. `LiveIdentityTests` runs the same modes against a deployment when `INTROSPECTION_LIVE=1`; `live-tests.yml` runs it nightly and on demand in the `build` environment.
- Examples in `Examples/` must keep compiling: CI builds them with the package.
- `APIContractTests` compares the SDK's wire surface with the published OpenAPI references. It is skipped unless `INTROSPECTION_API_CONTRACT=1` and runs daily in CI; a red run means the API moved.
