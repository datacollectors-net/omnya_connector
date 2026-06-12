# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Gem packaging metadata updated for private GitHub Packages publishing (`allowed_push_host`, documentation URI, bug tracker URI)
- README installation updated to use the GitHub Packages source block
- Added documented local and GitHub Actions private release flow
- Host context re-sync now immediately invalidates stale tenant context on tenant switch by updating request-local context stores atomically and triggering a fingerprint-based embedded page reload when `user.guid`/`tenant.id` changes
- Navigation sync now skips pre-handshake `external-module:navigate` posts so initial Turbo events cannot target a stale inferred host origin and trigger browser target-origin mismatch errors
- Client-side host-origin validation now matches server wildcard origin rules, including subdomain-only wildcard behavior and explicit wildcard port matching, so wildcard production origins work consistently across postMessage and embedded write flows

## [0.1.0] - 2026-05-17

### Added

- Rails engine with `isolate_namespace OmnyaConnector`
- `OmnyaConnector::Configuration` with Ruby DSL (`OmnyaConnector.configure`) and ENV variable fallback
- Production validation: requires explicit HTTPS origins, module key, no wildcards
- `OmnyaConnector::HostContextFetcher` service for authenticated context retrieval from host
- `OmnyaConnector::ControllerConcern` providing host-context session management, autonomous mode, CSRF bypass for trusted origins, and logging
- `OmnyaConnector::ModuleContextsController` with `create` and `destroy` actions
- `OmnyaConnector::Current` (ActiveSupport::CurrentAttributes) for request-scoped user_guid and tenant_id
- Stimulus controller (`omnya_connector_controller.js`) for iframe postMessage communication, context refresh, and session persistence
- Engine initializers for session store (SameSite=None), CSP connect-src, and importmap JS pinning
- Install generator (`rails generate omnya_connector:install`) for route mounting, controller concern injection, and initializer setup
