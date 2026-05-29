# OmnyaConnector

Rails engine for iframe-embedded modules that communicate with a host application via `postMessage`. Provides authentication context management, session persistence, CSRF-safe iframe embedding, and a Stimulus controller for the host handshake.

## Features

- **Host context management** — Receives token and context endpoint from the host via `postMessage`, fetches user/tenant context, persists it in the Rails session
- **Autonomous mode** — Operates standalone in development with configurable `user_guid` and `tenant_id`
- **CSRF-safe iframe embedding** — `SameSite=None` session cookies; `POST /module_context` unconditionally skips CSRF (protected by module-key + context-endpoint origin validation instead); Turbo/fetch write requests from within the module iframe are trusted when the Stimulus controller injects `X-Omnya-Embedded-Host-Origin` with a postMessage-established trusted host origin (guarded by `allow_trusted_origin_csrf_bypass`)
- **Content Security Policy** — Automatically merges host origins into `connect-src` and `frame-ancestors` (additive, non-destructive)
- **Stimulus controller** — Handles the full postMessage lifecycle: handshake, context fetch, token refresh on 401, periodic refresh, and host theme synchronisation
- **Browser URL sync** — Reports module route changes to the host (`external-module:navigate`) so bookmarks and browser back/forward work
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
  config.log_host_context_state = false                     # Optional debug logging, default false
end
```

All settings fall through to ENV variables when not set via the DSL.
`log_host_context_state` is initializer-only and does not have an ENV fallback.


## Security Notes: 
### iframe embedding and CSP

A module is intended to be embedded in a trusted host application iframe.

- Production removes the legacy `X-Frame-Options` response header.
- Embedding is restricted with CSP `frame-ancestors` to trusted origins.
- CSP uses per-request nonces for `script-src` so Rails/importmap inline scripts work without `unsafe-inline`.

The engine applies CSP origin merges in `omnya_connector.content_security_policy` during `app.config.after_initialize` using the resolved `host_app_origins` from `OmnyaConnector.configure` / `HOST_APP_ORIGINS`.

Merge behavior is additive (it does not overwrite existing app directives):

- `connect-src` keeps existing values and appends `host_app_origins`
- `frame-ancestors` keeps existing values and appends `:self` plus `host_app_origins`
- final source lists are de-duplicated

This keeps CSP origin handling aligned with the same resolved origin list used by Stimulus host-origin validation and module context origin validation.

For consuming apps: keep static CSP directives and nonce setup in your app initializer, but avoid dynamic `host_app_origins` lookups / dynamic `frame-ancestors` mutation there; let the gem handle those dynamic origin appends.

### CSP and Inline Styles

If the browser reports:

`Refused to apply a stylesheet because its hash, its nonce, or 'unsafe-inline' does not appear in the style-src directive of the Content Security Policy.`

the page likely contains inline styling (for example `style="..."`, `<style>...</style>`, or helper options like `style:` in ERB).

This app intentionally keeps a strict CSP for styles (`style-src :self :https`), so inline styles are blocked by design.

Use this fix pattern:

- Move inline styles to classes in `app/assets/stylesheets/application.css`.
- Replace inline attributes in views with `class:`.

Quick check for inline styles in app views:

```sh
rg -n "style=|<style" app/views
```

### Embedded CSRF handling

Third-party cookie restrictions in modern browsers mean that the session cookie may not be sent with requests from a module page embedded in a host iframe. When this happens the CSRF token in the module page's `<meta name="csrf-token">` tag does not match the server's expected token for the new (cookie-less) session, causing 422 responses on write actions.

The connector handles this with two complementary mechanisms:

**1. `POST /module_context` — unconditional `skip_forgery_protection`**

The context-sync endpoint has its own application-level security (module-key validation and context-endpoint origin checked against `host_app_origins`), so CSRF provides no additional protection. Skipping it avoids 422 failures during the periodic host context refresh when cookies are restricted.

**2. `X-Omnya-Embedded-Host-Origin` header bypass for Turbo write requests**

After the postMessage handshake succeeds, the Stimulus controller knows the trusted host origin (`activeHostOrigin`). It injects `X-Omnya-Embedded-Host-Origin: <origin>` on every Turbo-driven fetch request (via the `turbo:before-fetch-request` event). The server's `trusted_embedded_origin_request?` check validates this header against `host_app_origins` and skips CSRF when it matches.

This mechanism is only active when:
- `allow_trusted_origin_csrf_bypass` is `true`
- The raw `Origin` header is blank, `"null"`, or equals the module's own base URL (i.e. the normal Origin-based trust check is not applicable)
- The header value is present in `host_app_origins`
- The postMessage handshake has already completed (the Stimulus controller only sets `activeHostOrigin` after receiving the first host context message)

Requests before the handshake completes, or from untrusted origins, are not affected by this mechanism and continue to be subject to normal CSRF enforcement.

### X-Frame-options
Do not set an `X-Frame-Options` header on module pages. Values like `DENY` or `SAMEORIGIN` will cause browsers to block the page from loading inside the Omnya host iframe. Use `Content-Security-Policy: frame-ancestors` to control which host origins are allowed to embed the module.

Quick production checks:

```sh
curl -sSI https://todos.omnya-app.com/ | rg -i "content-security-policy|x-frame-options"
curl -sSL https://todos.omnya-app.com/ | rg -n "<script|nonce=|importmap"
```

Expected result:

- `X-Frame-Options` is absent.
- `Content-Security-Policy` contains `frame-ancestors` for the trusted host origin.
- Rendered script tags include `nonce="..."` attributes.

### SSL in development mode
Integration with the Omnya application host will only work properly in development or production when the application is served with SSL. This is mainly due to modern browser requirements enforcing strict security policies on cookies.

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
| `trusted_embedded_origin_request?` | Returns `true` for cross-origin requests whose `Origin` header is a configured trusted host origin, **or** for same-origin/no-origin requests that carry an `X-Omnya-Embedded-Host-Origin` header with a trusted host origin (set by the Stimulus controller after the postMessage handshake). Always `false` when `allow_trusted_origin_csrf_bypass` is disabled. |

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
| `module:navigate` | `{ modulePath }` | Host requested in-module navigation (optional client-side routing hook) |

Optional status panel targets: `connectionStatus`, `contextStatus`, `userLogin`, `tenantName`, `errorStatus`.

#### Embedded host origin header

Once the postMessage handshake with the host completes and `activeHostOrigin` is established, the controller automatically injects an `X-Omnya-Embedded-Host-Origin` header on every Turbo-driven fetch request (via the `turbo:before-fetch-request` event) and on the `POST /module_context` call. This header carries the trusted host origin and is used by `trusted_embedded_origin_request?` on the server to bypass CSRF verification for embedded write actions when third-party cookie restrictions make normal CSRF token matching impossible. The header is only injected when the origin is in `host_app_origins`, so it is never sent for untrusted origins.

### Browser navigation and bookmarks

The controller automatically reports internal module URL changes to the host application using:

```json
{
  "type": "external-module:navigate",
  "moduleKey": "my-module",
  "modulePath": "/orders/42?tab=history"
}
```

This enables:

- host address bar updates with `module_path`
- bookmarkable deep links
- browser Back/Forward restoration

Automatic reporting is triggered on:

- initial host connection
- `turbo:load`
- `popstate`
- `hashchange`

For client-side routing, listen for host-initiated navigation:

```javascript
document.querySelector('[data-controller="omnya-connector"]')
  .addEventListener("module:navigate", (event) => {
    const { modulePath } = event.detail
    // router.replace(modulePath)
  })
```

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


## Step-by-Step Implementation

To integrate the OmnyaConnector into your existing Rails application, follow these steps:

### 1. Add the Gem to Your Application

Add the following to your `Gemfile`:

```ruby
source "https://rubygems.pkg.github.com/datacollectors-net" do
  gem "omnya_connector"
end
```

Run the following commands to install the gem and generate the necessary files:

```bash
bundle install
rails generate omnya_connector:install
```

### 2. Mount the Engine

Ensure the engine is mounted in your `config/routes.rb` file. By default, the generator mounts it at `/`:

```ruby
mount OmnyaConnector::Engine, at: "/"
```

### 3. Include the Controller Concern

Add the following line to your `ApplicationController` to include the OmnyaConnector functionality:

```ruby
include OmnyaConnector::ControllerConcern
```

### 4. Configure the Connector

Edit the generated initializer file at `config/initializers/omnya_connector.rb` to configure the connector. Use the provided DSL to set up your environment-specific settings. For example:

```ruby
OmnyaConnector.configure do |config|
  config.module_key = ENV["MODULE_KEY"]
  config.host_origins = ["https://example.com"]
end
```

### 5. Verify Content Security Policy (CSP)

Ensure your application’s Content Security Policy allows connections to the host origins. The connector automatically appends host origins to `connect-src`.

### 6. Test the Integration

Run your Rails server and verify the following:
- The iframe embedding works as expected.
- The host application can communicate with the module via `postMessage`.
- Authentication context is correctly managed.

### 7. Optional: Customize Styles and Scripts

You can customize the module’s appearance and behavior by editing the files in the `app/assets` directory:
- Styles: `app/assets/stylesheets/omnya_connector/application.css`
- JavaScript: `app/assets/javascripts/omnya_connector/controllers/omnya_connector_controller.js`

### 8. Deploy to Production

Before deploying, ensure the following:
- `config.host_origins` is set to a secure, HTTPS-only list of origins.
- All environment variables are correctly configured.
- The application is tested in a production-like environment.

With these steps completed, your application should be fully integrated with the OmnyaConnector.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).