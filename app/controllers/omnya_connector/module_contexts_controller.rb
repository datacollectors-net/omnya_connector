module OmnyaConnector
  class ModuleContextsController < ApplicationController
    # Context sync and teardown actions carry their own application-level security
    # (module_key validation + context_endpoint origin check against host_app_origins),
    # so CSRF verification adds no meaningful protection here. Skipping it unconditionally
    # avoids 422 failures when third-party cookies are restricted and the session cookie
    # cannot be round-tripped with the CSRF token.
    skip_forgery_protection

    def create
      payload = params.expect(module_context: [ :token, :context_endpoint, :module_key ])
      log_host_context_state(event: "module_context.create.received")

      return render_invalid_module_key unless payload[:module_key] == omnya_connector_module_key

      context = OmnyaConnector::HostContextFetcher.call(
        token: payload[:token],
        context_endpoint: payload[:context_endpoint],
        allowed_origins: omnya_connector_host_app_origins
      )

      user_guid = normalized_host_context_guid(context.dig("user", "guid"))
      tenant_id = normalized_host_context_id(context.dig("tenant", "id"))

      return render_invalid_context(user_guid, tenant_id) if user_guid.nil? || tenant_id.nil?

      previous_user_guid = normalized_host_context_guid(session[:host_context_user_guid])
      previous_tenant_id = normalized_host_context_id(session[:host_context_tenant_id])

      persist_host_context(user_guid, tenant_id)

      context_changed = previous_user_guid != user_guid || previous_tenant_id != tenant_id
      response.set_header("X-Omnya-Context-Changed", context_changed ? "1" : "0")
      response.set_header("X-Omnya-Context-Fingerprint", "#{user_guid}:#{tenant_id}")

      head :no_content
    rescue OmnyaConnector::HostContextFetcher::Error => e
      log_host_context_state(
        event: "module_context.create.fetch_error",
        details: { fetch_error: e.message }
      )
      clear_host_context_session!

      status = e.message == "unauthorized" ? :unauthorized : :unprocessable_entity
      render json: { error: e.message }, status: status
    end

    def destroy
      log_host_context_state(event: "module_context.destroy.received")
      clear_host_context_session!

      head :no_content
    end

    private

    def render_invalid_module_key
      clear_host_context_session!
      render json: { error: "invalid_module_key" }, status: :unauthorized
    end

    def render_invalid_context(user_guid, tenant_id)
      log_host_context_state(
        event: "module_context.create.invalid_context",
        details: {
          fetched_user_guid: user_guid,
          fetched_tenant_id: tenant_id
        }
      )
      clear_host_context_session!
      render json: { error: "invalid_context" }, status: :unauthorized
    end
  end
end
