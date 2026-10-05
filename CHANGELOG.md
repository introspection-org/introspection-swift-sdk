# Changelog

## [0.3.0](https://github.com/introspection-org/introspection-swift-sdk/compare/v0.2.2...v0.3.0) (2026-10-05)


### ⚠ BREAKING CHANGES

* **automations:** AutomationMetadata no longer has runtimeGroupId. The runtime group is the top-level runtimeGroupId on AutomationCreate and AutomationUpdate; the server rejects runtime_group_id inside metadata.

### Features

* **automations:** task targets, one-off slots and trigger events ([#22](https://github.com/introspection-org/introspection-swift-sdk/issues/22)) ([bb3bf92](https://github.com/introspection-org/introspection-swift-sdk/commit/bb3bf92356b7e766baa614f47a714cdbd91e086a))
* **members:** member tags and metadata ([#23](https://github.com/introspection-org/introspection-swift-sdk/issues/23)) ([2d1d637](https://github.com/introspection-org/introspection-swift-sdk/commit/2d1d6375f96773800eced503602ceaf05f472a7e))

## [0.2.2](https://github.com/introspection-org/introspection-swift-sdk/compare/v0.2.1...v0.2.2) (2026-10-04)


### Bug Fixes

* **auth:** drop a sign-in response superseded by sign-out or a newer sign-in ([#19](https://github.com/introspection-org/introspection-swift-sdk/issues/19)) ([ea31d5a](https://github.com/introspection-org/introspection-swift-sdk/commit/ea31d5a63dd2a557871b963caf711504ed9a539d))

## [0.2.1](https://github.com/introspection-org/introspection-swift-sdk/compare/v0.2.0...v0.2.1) (2026-10-04)


### Bug Fixes

* build as a dependency of an Xcode app ([#14](https://github.com/introspection-org/introspection-swift-sdk/issues/14)) ([4d14d2e](https://github.com/introspection-org/introspection-swift-sdk/commit/4d14d2e9937ecf1b21a9dba10c2da04121241bd8))

## [0.2.0](https://github.com/introspection-org/introspection-swift-sdk/compare/v0.1.0...v0.2.0) (2026-10-03)


### ⚠ BREAKING CHANGES

* harden stream recovery and session transitions ([#12](https://github.com/introspection-org/introspection-swift-sdk/issues/12))

### Features

* **files:** filter file lists by metadata ([#10](https://github.com/introspection-org/introspection-swift-sdk/issues/10)) ([93e7083](https://github.com/introspection-org/introspection-swift-sdk/commit/93e708373f4a92a5377d618867b722459e9e1c30))


### Bug Fixes

* harden stream recovery and session transitions ([#12](https://github.com/introspection-org/introspection-swift-sdk/issues/12)) ([2e09a10](https://github.com/introspection-org/introspection-swift-sdk/commit/2e09a10398598c0190f0418597403336876ba43f))

## 0.1.0 (2026-10-03)


### ⚠ BREAKING CHANGES

* requires iOS 18 / macOS 15 and a Swift 6.2 or newer toolchain.

### Features

* add the Introspection Swift SDK ([#1](https://github.com/introspection-org/introspection-swift-sdk/issues/1)) ([57bff8d](https://github.com/introspection-org/introspection-swift-sdk/commit/57bff8d87391fa65484c2979ff75dc8c38ef220a))


### Bug Fixes

* **auth:** send email codes to /v1/oauth/email/code ([#8](https://github.com/introspection-org/introspection-swift-sdk/issues/8)) ([df51391](https://github.com/introspection-org/introspection-swift-sdk/commit/df5139189859d03e8914369eed720e7cc90f498e))
