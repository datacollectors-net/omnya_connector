module OmnyaConnector
  module ControllerConcern
    extend ActiveSupport::Concern

    included do
      before_action :assign_current_host_context

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

      origin = request.headers["Origin"].to_s
      return false if origin.blank?
      return false if origin == request.base_url

      omnya_connector_host_app_origins.include?(origin)
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
  end
end
