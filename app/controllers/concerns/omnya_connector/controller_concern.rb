module OmnyaConnector
  module ControllerConcern
    extend ActiveSupport::Concern

    included do
      before_action :assign_current_host_context
      skip_forgery_protection if: :trusted_embedded_origin_request?

      helper_method :omnya_connector_module_key,
                    :omnya_connector_host_app_origins,
                    :omnya_connector_autonomous_user_guid,
                    :omnya_connector_autonomous_tenant_id,
                    :current_host_user_guid,
                    :current_host_tenant_id
    end

    private

    def current_host_user_guid
      @current_host_user_guid ||= normalized_host_context_guid(session[:host_context_user_guid]) ||
        omnya_connector_autonomous_user_guid ||
        autonomous_default_guid
    end

    def current_host_tenant_id
      @current_host_tenant_id ||= normalized_host_context_id(session[:host_context_tenant_id]) ||
        omnya_connector_autonomous_tenant_id ||
        autonomous_default_id
    end

    def assign_current_host_context
      log_host_context_state(event: "host_context.assign.before")
      OmnyaConnector::Current.user_guid = current_host_user_guid
      OmnyaConnector::Current.tenant_id = current_host_tenant_id
      log_host_context_state(
        event: "host_context.assign.after",
        details: {
          resolved_user_guid: OmnyaConnector::Current.user_guid,
          resolved_tenant_id: OmnyaConnector::Current.tenant_id
        }
      )
    end

    def clear_host_context_session!
      log_host_context_state(event: "host_context.clear.before")

      session.delete(:host_context_user_guid)
      session.delete(:host_context_tenant_id)

      @current_host_user_guid = nil
      @current_host_tenant_id = nil
      OmnyaConnector::Current.user_guid = nil
      OmnyaConnector::Current.tenant_id = nil

      log_host_context_state(event: "host_context.clear.after")
    end

    def require_host_context!
      return if current_host_user_guid.present? && current_host_tenant_id.present?

      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: "Host context not available." }
        format.json { render json: { error: "host_context_missing" }, status: :unauthorized }
      end
    end

    def trusted_embedded_origin_request?
      return false unless Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass

      # Check 1: Cross-origin request where the Origin header names a trusted host.
      # This covers the canonical embedded case where the host domain differs from the module domain.
      origin = effective_request_origin
      return true if origin.present? && origin != request.base_url && omnya_connector_host_app_origins.include?(origin)

      # Check 2: Turbo/fetch requests issued from within the module iframe itself carry
      # Origin == module base_url (same origin), Origin "null" (sandboxed iframe), or no Origin
      # at all — none of which identify the embedding host. In these cases the Stimulus
      # controller injects X-Omnya-Embedded-Host-Origin with the host origin it established
      # during the postMessage handshake. Validate that header against the trusted allowlist.
      # The header can only be set by JavaScript running in the module's own origin, so this
      # is equivalent in trust level to a same-origin request from a known embedding context.
      raw_origin = request.headers["Origin"].to_s
      return false unless raw_origin.blank? || raw_origin == "null" || raw_origin == request.base_url

      embedded_host = request.headers["X-Omnya-Embedded-Host-Origin"].to_s.strip.presence
      return false if embedded_host.blank?

      omnya_connector_host_app_origins.include?(embedded_host)
    end

    def effective_request_origin
      raw = request.headers["Origin"].to_s
      return referrer_origin if raw.blank? || raw == "null"

      raw
    end

    def referrer_origin
      return nil if request.referer.blank?

      uri = URI.parse(request.referer)
      return nil unless uri.scheme && uri.host

      standard_port = (uri.scheme == "https" && uri.port == 443) ||
                      (uri.scheme == "http" && uri.port == 80)
      standard_port ? "#{uri.scheme}://#{uri.host}" : "#{uri.scheme}://#{uri.host}:#{uri.port}"
    rescue URI::InvalidURIError
      nil
    end

    def omnya_connector_module_key
      Rails.application.config.x.omnya_connector.module_key
    end

    def omnya_connector_host_app_origins
      Rails.application.config.x.omnya_connector.host_app_origins
    end

    def omnya_connector_autonomous_user_guid
      Rails.application.config.x.omnya_connector.autonomous_user_guid
    end

    def omnya_connector_autonomous_tenant_id
      Rails.application.config.x.omnya_connector.autonomous_tenant_id
    end

    def autonomous_default_guid
      Rails.env.development? ? "dev-user-guid-1" : nil
    end

    def autonomous_default_id
      Rails.env.development? ? 1 : nil
    end

    def normalized_host_context_guid(value)
      value.to_s.strip.presence
    end

    def normalized_host_context_id(value)
      return nil if value.blank?

      id = Integer(value, exception: false)
      id&.positive? ? id : nil
    end

    def persist_host_context(user_guid, tenant_id)
      session[:host_context_user_guid] = user_guid
      session[:host_context_tenant_id] = tenant_id
      log_host_context_state(
        event: "host_context.persisted",
        details: {
          persisted_user_guid: session[:host_context_user_guid],
          persisted_tenant_id: session[:host_context_tenant_id]
        }
      )
    end

    def log_host_context_state(event:, details: {})
      return unless omnya_connector_log_host_context_state?

      raw_user_guid = session[:host_context_user_guid]
      raw_tenant_id = session[:host_context_tenant_id]

      Rails.logger.info(
        {
          event: event,
          request_id: request.request_id,
          controller: self.class.name,
          action: action_name,
          path: request.fullpath,
          cookie_header_present: request.headers["Cookie"].present?,
          session_id_present: request.session_options[:id].present?,
          session_keys: session.to_hash.keys.sort,
          raw_host_context_user_guid: raw_user_guid,
          raw_host_context_tenant_id: raw_tenant_id,
          normalized_host_context_user_guid: normalized_host_context_guid(raw_user_guid),
          normalized_host_context_tenant_id: normalized_host_context_id(raw_tenant_id),
          autonomous_user_guid: omnya_connector_autonomous_user_guid,
          autonomous_tenant_id: omnya_connector_autonomous_tenant_id
        }.merge(details)
      )
    end

    def omnya_connector_log_host_context_state?
      Rails.application.config.x.omnya_connector.log_host_context_state
    end
  end
end
