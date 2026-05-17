module TrModule
  class ModuleContextsController < ApplicationController
    # Allow trusted host-embedded calls when third-party cookies interfere with CSRF checks.
    skip_forgery_protection only: %i[create], if: :trusted_embedded_origin_request?

    def create
      payload = params.expect(module_context: [ :token, :context_endpoint, :module_key ])
      log_host_context_state(event: "module_context.create.received")

      return render_invalid_module_key unless payload[:module_key] == tr_module_module_key

      context = TrModule::HostContextFetcher.call(
        token: payload[:token],
        context_endpoint: payload[:context_endpoint],
        allowed_origins: tr_module_host_app_origins
      )

      user_guid = normalized_host_context_guid(context.dig("user", "guid"))
      tenant_id = normalized_host_context_id(context.dig("tenant", "id"))

      return render_invalid_context(user_guid, tenant_id) if user_guid.nil? || tenant_id.nil?

      persist_host_context(user_guid, tenant_id)

      head :no_content
    rescue TrModule::HostContextFetcher::Error => e
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
