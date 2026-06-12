# OmnyaConnector configuration
#
# DSL values take precedence; ENV variables are used as fallback.
# ENV variables: MODULE_KEY, HOST_APP_ORIGINS, AUTONOMOUS_USER_GUID,
#                AUTONOMOUS_TENANT_ID, ALLOW_TRUSTED_ORIGIN_CSRF_BYPASS,
#                SESSION_COOKIE_SECURE

OmnyaConnector.configure do |config|
  # Required in production. Identifies this module to the host application.
  # config.module_key = "my-module"

  # Comma-separated list of allowed host app origins.
  # Required and must be explicitly set in production (https only).
  # In production, wildcard origins are only allowed for approved scoped domains,
  # for example: https://*.omnya-app.com, https://*.omnya.nl.
  # config.host_app_origins = "https://host.example.com"

  # Set to true if host_app_origins is explicitly configured (required for production).
  # config.host_app_origins_explicitly_set = true

  # Override the autonomous user_guid / tenant_id used in standalone development mode.
  # config.autonomous_user_guid = "dev-user-guid-1"
  # config.autonomous_tenant_id = "1"

  # Allow trusted host origins to bypass CSRF verification for embedded iframe requests.
  # Defaults to true in development, false otherwise.
  # config.allow_trusted_origin_csrf_bypass = false

  # Set to false to skip automatic session store configuration (SameSite=None for iframes).
  # config.configure_session_store = true

  # Enable verbose host-context request/session debug logging.
  # Defaults to false.
  # config.log_host_context_state = true
end
