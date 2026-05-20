# OmnyaConnector

Rails engine for iframe-embedded modules that communicate with a host application via `postMessage`. Provides authentication context management, session persistence, CSRF-safe iframe embedding, and a Stimulus controller for the host handshake.

## Features

- **Host context management** — Receives token and context endpoint from the host via `postMessage`, fetches user/tenant context, persists it in the Rails session
- **Autonomous mode** — Operates standalone in development with configurable `user_guid` and `tenant_id`
- **CSRF-safe iframe embedding** — `SameSite=None` session cookies, optional CSRF bypass for trusted host origins
- **Content Security Policy** — Automatically appends host origins to `connect-src`
- **Stimulus controller** — Handles the full postMessage lifecycle: handshake, context fetch, token refresh on 401, periodic refresh, and host theme synchronisation
- **Dark-mode / theme sync** — Applies the host's light/dark/system preference to the module page via `data-host-theme-preference` and the `dark` CSS class
- **Ruby DSL configuration** — `OmnyaConnector.configure` block with ENV variable fallback
- **Production validation** — Enforces HTTPS-only origins, no wildcards, explicit origin list, module key presence

## Installation

Add to your Gemfile:

```ruby
source "https://rubygems.pkg.github.com/datacollectors-net" do
  gem "omnya_connector"
end
```

Run the install generator:

```bash
bundle install
rails generate omnya_connector:install
```

This will:
1. Mount the engine at `/` in your routes
2. Add `include OmnyaConnector::ControllerConcern` to your `ApplicationController`
3. Create `config/initializers/omnya_connector.rb` with configuration template

## Configuration

Configure in `config/initializers/omnya_connector.rb`. DSL values take precedence over ENV variables.

```ruby
OmnyaConnector.configure do |config|
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

The `OmnyaConnector::ControllerConcern` provides these methods (also available as view helpers):

| Method | Description |
|--------|-------------|
| `current_host_user_guid` | Resolved user GUID (session → autonomous → dev default) |
| `current_host_tenant_id` | Resolved tenant ID (session → autonomous → dev default) |
| `omnya_connector_module_key` | Configured module key |
| `omnya_connector_host_app_origins` | List of allowed host origins |
| `omnya_connector_autonomous_user_guid` | Autonomous mode user GUID |
| `omnya_connector_autonomous_tenant_id` | Autonomous mode tenant ID |
| `require_host_context!` | Before-action guard: redirects/returns 401 if context missing |
| `trusted_embedded_origin_request?` | Check if request comes from a trusted host origin |

### CurrentAttributes

Access the request-scoped context anywhere:

```ruby
OmnyaConnector::Current.user_guid
OmnyaConnector::Current.tenant_id
```

### Stimulus controller

Add to your layout:

```erb
<div
  data-controller="omnya-connector"
  data-omnya-connector-module-key-value="<%= omnya_connector_module_key %>"
  data-omnya-connector-host-origins-value="<%= omnya_connector_host_app_origins.to_json %>"
  data-omnya-connector-autonomous-user-guid-value="<%= omnya_connector_autonomous_user_guid %>"
  data-omnya-connector-autonomous-tenant-id-value="<%= omnya_connector_autonomous_tenant_id %>"
>
```

The controller dispatches these custom events on its element:

| Event | Detail | Description |
|-------|--------|-------------|
| `module:host-connected` | `{}` | Host responded to handshake |
| `module:context-updated` | `{ context }` | Context fetched and persisted |
| `module:context-unavailable` | `{ message }` | Context fetch or persistence failed |
| `module:theme-updated` | `{ preference, effectiveMode }` | Host theme applied to the page |

Optional status panel targets: `connectionStatus`, `contextStatus`, `userLogin`, `tenantName`, `errorStatus`.

### Host theme integration

On connect the controller automatically sends `external-module:request-theme` to the host. The host responds (and re-sends on every theme change) with an `external-module:theme` message:

```json
{
  "type": "external-module:theme",
  "moduleKey": "my-module",
  "preference": "dark",
  "effectiveMode": "dark"
}
```

`preference` is the user's stored setting (`light`, `dark`, or `system`); `effectiveMode` is the resolved value (`light` or `dark`).

The controller applies the theme immediately:

- Sets `document.documentElement.dataset.hostThemePreference` to `preference`
- Toggles the `dark` CSS class on `<html>` based on `effectiveMode`
- Dispatches `module:theme-updated` on the controller element

Hook into theme changes in your own JavaScript:

```javascript
document.querySelector('[data-controller="omnya-connector"]')
  .addEventListener("module:theme-updated", (event) => {
    const { preference, effectiveMode } = event.detail
    // e.g. update a chart theme, re-render a canvas, etc.
  })
```

Or with Tailwind's `dark:` variants — no JavaScript needed: the `dark` class on `<html>` is all Tailwind requires.

### Mount path

The engine is designed to be mounted at root:

```ruby
mount OmnyaConnector::Engine => "/"
```

If mounted at a prefix (e.g. `"/omnya_connector"`), update the `MODULE_CONTEXT_PATH` constant in the Stimulus controller JS accordingly.

## Engine initializers

The engine automatically configures:

- **Session store** — `cookie_store` with `SameSite=None`, `httponly: true`, `secure: true` (disable with `configure_session_store = false`)
- **CSP** — Appends host origins to `connect-src` directive
- **Importmap** — Pins the Stimulus controller JS for auto-discovery

## Releasing

### Local release

Build and validate the gem:

```bash
bundle exec rake test
bundle exec rake build
```

Push to RubyGems (requires MFA and a configured credentials file):

```bash
bundle exec rake release
```

This pushes to GitHub Packages at:

- `https://rubygems.pkg.github.com/datacollectors-net`

Your `~/.gem/credentials` must include a `:github:` token with package write permissions.

### GitHub Actions release

Pushing a version tag (for example `v0.2.1`) triggers the publish workflow.

Required repository secret:

- `GITHUB_PACKAGES_TOKEN` — GitHub token with `write:packages` permission

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
