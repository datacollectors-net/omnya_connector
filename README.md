# TrModule

Rails engine for iframe-embedded modules that communicate with a host application via `postMessage`. Provides authentication context management, session persistence, CSRF-safe iframe embedding, and a Stimulus controller for the host handshake.

## Features

- **Host context management** — Receives token and context endpoint from the host via `postMessage`, fetches user/tenant context, persists it in the Rails session
- **Autonomous mode** — Operates standalone in development with configurable `user_guid` and `tenant_id`
- **CSRF-safe iframe embedding** — `SameSite=None` session cookies, optional CSRF bypass for trusted host origins
- **Content Security Policy** — Automatically appends host origins to `connect-src`
- **Stimulus controller** — Handles the full postMessage lifecycle: handshake, context fetch, token refresh on 401, periodic refresh
- **Ruby DSL configuration** — `TrModule.configure` block with ENV variable fallback
- **Production validation** — Enforces HTTPS-only origins, no wildcards, explicit origin list, module key presence

## Installation

Add to your Gemfile:

```ruby
gem "tr_module", git: "https://github.com/datacollectors-net/tr_module"
```

Run the install generator:

```bash
bundle install
rails generate tr_module:install
```

This will:
1. Mount the engine at `/` in your routes
2. Add `include TrModule::ControllerConcern` to your `ApplicationController`
3. Create `config/initializers/tr_module.rb` with configuration template

## Configuration

Configure in `config/initializers/tr_module.rb`. DSL values take precedence over ENV variables.

```ruby
TrModule.configure do |config|
  config.module_key = "my-module"                          # ENV: MODULE_KEY
  config.host_app_origins = "https://host.example.com"     # ENV: HOST_APP_ORIGINS
  config.host_app_origins_explicitly_set = true             # ENV: HOST_APP_ORIGINS (presence)
  config.autonomous_user_guid = "dev-user-guid-1"          # ENV: AUTONOMOUS_USER_GUID
  config.autonomous_tenant_id = "1"                        # ENV: AUTONOMOUS_TENANT_ID
  config.allow_trusted_origin_csrf_bypass = false           # ENV: ALLOW_TRUSTED_ORIGIN_CSRF_BYPASS
  config.configure_session_store = true                     # Set false to manage session store yourself
end
```

All settings fall through to ENV variables when not set via the DSL.

## Usage

### Controller helpers

The `TrModule::ControllerConcern` provides these methods (also available as view helpers):

| Method | Description |
|--------|-------------|
| `current_host_user_guid` | Resolved user GUID (session → autonomous → dev default) |
| `current_host_tenant_id` | Resolved tenant ID (session → autonomous → dev default) |
| `tr_module_module_key` | Configured module key |
| `tr_module_host_app_origins` | List of allowed host origins |
| `tr_module_autonomous_user_guid` | Autonomous mode user GUID |
| `tr_module_autonomous_tenant_id` | Autonomous mode tenant ID |
| `require_host_context!` | Before-action guard: redirects/returns 401 if context missing |
| `trusted_embedded_origin_request?` | Check if request comes from a trusted host origin |

### CurrentAttributes

Access the request-scoped context anywhere:

```ruby
TrModule::Current.user_guid
TrModule::Current.tenant_id
```

### Stimulus controller

Add to your layout:

```erb
<div
  data-controller="tr-module"
  data-tr-module-module-key-value="<%= tr_module_module_key %>"
  data-tr-module-host-origins-value="<%= tr_module_host_app_origins.to_json %>"
  data-tr-module-autonomous-user-guid-value="<%= tr_module_autonomous_user_guid %>"
  data-tr-module-autonomous-tenant-id-value="<%= tr_module_autonomous_tenant_id %>"
>
```

The controller dispatches these custom events on its element:

| Event | Detail | Description |
|-------|--------|-------------|
| `module:host-connected` | `{}` | Host responded to handshake |
| `module:context-updated` | `{ context }` | Context fetched and persisted |
| `module:context-unavailable` | `{ message }` | Context fetch or persistence failed |

Optional status panel targets: `connectionStatus`, `contextStatus`, `userLogin`, `tenantName`, `errorStatus`.

### Mount path

The engine is designed to be mounted at root:

```ruby
mount TrModule::Engine => "/"
```

If mounted at a prefix (e.g. `"/tr_module"`), update the `MODULE_CONTEXT_PATH` constant in the Stimulus controller JS accordingly.

## Engine initializers

The engine automatically configures:

- **Session store** — `cookie_store` with `SameSite=None`, `httponly: true`, `secure: true` (disable with `configure_session_store = false`)
- **CSP** — Appends host origins to `connect-src` directive
- **Importmap** — Pins the Stimulus controller JS for auto-discovery

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
