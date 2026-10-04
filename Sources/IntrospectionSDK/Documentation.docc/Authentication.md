# Authentication

Choose a credential for each kind of caller: servers, service accounts, the end users of your app, and interactive sign-in.

## Overview

| Caller | Credential | Entry point |
| --- | --- | --- |
| Server or script | API key | `IntrospectionClient(controlPlaneURL:credentials:)` with ``BearerToken`` |
| Backend acting for your users | Service account | `IntrospectionClient.fromServiceAccount(clientId:clientSecret:project:controlPlaneURL:)` |
| End users signed in with your identity provider | Federated token exchange | `IntrospectionClient.federated(subjectToken:clientID:project:controlPlaneURL:)` |
| End users signed in with Introspection | Hosted login | ``AuthClient`` |

## API keys and service accounts

Both run agents through a ``Runner``. Opening a runner names the end user the work is for, so tasks, files and conversations are scoped to that user:

```swift
let client = try await IntrospectionClient.fromServiceAccount(
    clientId: clientID, clientSecret: clientSecret, project: "my-project"
)
let runner = try await client.runtimes("customer-agent").run(
    identity: RunnerIdentity(userId: "user_123"),
    ttlSeconds: 900
)
```

The identity names a `customer` member, created on first use. ``RunnerIdentity/tags`` are access-bearing, so they seed a new member only; ``RunnerIdentity/metadata`` grants nothing, so it seeds a new member and is merged into an existing one, the asserted keys overwriting keys of the same name (an admin's included). Find members by it with ``MemberListParams/metadata``.

The runner's own token drives the Data Plane and pins the runtime; it never needs refreshing during its lifetime. Call ``Runner/refresh()`` to mint a new session, and ``Runner/close()`` to refuse further requests locally.

## Federated identity providers

When your app already signs users in with Supabase, Auth0, Okta or another OpenID provider, keep that provider and its SDK. An Introspection Application of type Direct JWKS, federated to the provider's issuer, exchanges the provider's token for a platform token for a `customer` member. No app backend is involved.

```swift
import IntrospectionSDK
import Supabase

let client = try await IntrospectionClient.federated(
    subjectToken: { try await supabase.auth.session.accessToken },
    clientID: "intro_app_...",
    project: "my-project",
    controlPlaneURL: URL(string: "https://api.introspection.dev")!
)
let run = try await client.tasks.start(prompt: "Hello", TaskCreate(runtimeId: runtimeId))
let next = try await client.tasks.runs.create(run.run.taskId, TaskRunCreate(text: "And then?", runtimeId: runtimeId))
```

The member is the same on every sign-in, because it is derived from the federation and the provider's `sub`. The SDK exchanges again before the platform token expires and after a `401`, asking `subjectToken` for a current provider token each time. Sign out with the provider's SDK.

A federated token is not a runner token, so a task runs on your agent only when its create and runs name the runtime version (`runtimeId`). Customer tokens are refused on Control Plane routes, so resolve that id on your backend with a service account (`GET /v1/runtimes`, through ``RuntimesAPI``) and hand it to the app with the session, the same way the JavaScript browser client receives it. A runtime gets a new version id on every deploy, so fetch it per session rather than hard-coding it.

The provider must sign with asymmetric keys (ES256 or RS256), and the Application's federation must name its issuer, for Supabase `https://<ref>.supabase.co/auth/v1`.

## Hosted login

``AuthClient`` manages an Introspection session the way the Supabase Auth client does: sign in, persist, refresh, sign out, and observe changes.

```swift
let auth = AuthClient(configuration: .init(
    controlPlaneURL: URL(string: "https://api.introspection.dev")!,
    clientID: "intro_app_...",
    project: "my-project",
    method: .hostedLogin,
    storage: KeychainSessionStorage()
))

let presenter = HostedLoginPresenter(anchor: window)
try await presenter.signIn(with: auth, redirectURI: "https://app.example.com/auth/callback")

let client = try await auth.client()
```

`HostedLoginPresenter` uses `ASWebAuthenticationSession`, and `KeychainSessionStorage` keeps the session in the Keychain, readable only after first unlock and never synced off the device. Both are available on Apple platforms.

## Every grant

``AuthAPI`` exposes each OAuth grant directly: client credentials, token exchange, JWT bearer, authorization code with ``PKCE``, refresh, device code and revoke. ``OIDC`` discovers and talks to any external issuer.
