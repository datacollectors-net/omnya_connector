# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-17

### Added

- Rails engine with `isolate_namespace TrModule`
- `TrModule::Configuration` with Ruby DSL (`TrModule.configure`) and ENV variable fallback
- Production validation: requires explicit HTTPS origins, module key, no wildcards
- `TrModule::HostContextFetcher` service for authenticated context retrieval from host
- `TrModule::ControllerConcern` providing host-context session management, autonomous mode, CSRF bypass for trusted origins, and logging
- `TrModule::ModuleContextsController` with `create` and `destroy` actions
- `TrModule::Current` (ActiveSupport::CurrentAttributes) for request-scoped user_guid and tenant_id
- Stimulus controller (`tr_module_controller.js`) for iframe postMessage communication, context refresh, and session persistence
- Engine initializers for session store (SameSite=None), CSP connect-src, and importmap JS pinning
- Install generator (`rails generate tr_module:install`) for route mounting, controller concern injection, and initializer setup
