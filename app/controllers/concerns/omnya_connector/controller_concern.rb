module OmnyaConnector
  module ControllerConcern
    extend ActiveSupport::Concern

    IFRAME_FETCH_DEST_HEADER = "Sec-Fetch-Dest".freeze
    IFRAME_FETCH_DEST_VALUE = "iframe".freeze

    included do
      before_action :enforce_iframe_navigation
      # Must run before assign_current_host_context so the assignment reads the
      # freshly persisted values when a param-based fallback applies.
      before_action :persist_host_context_from_params
      before_action :assign_current_host_context
      skip_forgery_protection if: :trusted_embedded_origin_request?

      helper_method :omnya_connector_module_key,
                    :omnya_connector_host_app_origins,
                    :omnya_connector_autonomous_user_guid,
                    :omnya_connector_autonomous_tenant_id,
                    :omnya_connector_autonomous_user_time_zone,
                    :omnya_connector_autonomous_user_language,
                    :current_host_user_guid,
                    :current_host_tenant_id,
                    :current_host_user_time_zone,
                    :current_host_user_language,
                    :host_context_params
    end

    # Host context as request params for embedded form submissions: when third-party cookie
    # restrictions keep the session from round-tripping in the host iframe, these hidden
    # fields let persist_host_context_from_params re-establish the context on submit.
    def host_context_params
      {
        context_tenant_id: current_host_tenant_id.presence,
        context_user_guid: current_host_user_guid.presence
      }.compact
    end

    private

    def current_host_user_guid
      return @current_host_user_guid if defined?(@current_host_user_guid)

      @current_host_user_guid = normalized_host_context_guid(session[:host_context_user_guid])
      return @current_host_user_guid if @current_host_user_guid.present?
      return @current_host_user_guid = nil if embedded_request?

      @current_host_user_guid ||= omnya_connector_autonomous_user_guid || autonomous_default_guid
    end

    def current_host_tenant_id
      return @current_host_tenant_id if defined?(@current_host_tenant_id)

      @current_host_tenant_id = normalized_host_context_id(session[:host_context_tenant_id])
      return @current_host_tenant_id if @current_host_tenant_id.present?
      return @current_host_tenant_id = nil if embedded_request?

      @current_host_tenant_id ||= omnya_connector_autonomous_tenant_id || autonomous_default_id
    end

    def current_host_user_time_zone
      return @current_host_user_time_zone if defined?(@current_host_user_time_zone)

      @current_host_user_time_zone = normalized_host_context_locale_value(session[:host_context_user_time_zone])
      return @current_host_user_time_zone if @current_host_user_time_zone.present?
      return @current_host_user_time_zone = nil if embedded_request?

      @current_host_user_time_zone ||= omnya_connector_autonomous_user_time_zone || autonomous_default_time_zone
    end

    def current_host_user_language
      return @current_host_user_language if defined?(@current_host_user_language)

      @current_host_user_language = normalized_host_context_locale_value(session[:host_context_user_language])
      return @current_host_user_language if @current_host_user_language.present?
      return @current_host_user_language = nil if embedded_request?

      @current_host_user_language ||= omnya_connector_autonomous_user_language || autonomous_default_language
    end

    def assign_current_host_context
      log_host_context_state(event: "host_context.assign.before")
      OmnyaConnector::Current.user_guid = current_host_user_guid
      OmnyaConnector::Current.tenant_id = current_host_tenant_id
      OmnyaConnector::Current.user_time_zone = current_host_user_time_zone
      OmnyaConnector::Current.user_language = current_host_user_language
      log_host_context_state(
        event: "host_context.assign.after",
        details: {
          resolved_user_guid: OmnyaConnector::Current.user_guid,
          resolved_tenant_id: OmnyaConnector::Current.tenant_id,
          resolved_user_time_zone: OmnyaConnector::Current.user_time_zone,
          resolved_user_language: OmnyaConnector::Current.user_language
        }
      )
    end

    def clear_host_context_session!
      log_host_context_state(event: "host_context.clear.before")

      session.delete(:host_context_user_guid)
      session.delete(:host_context_tenant_id)
      session.delete(:host_context_user_time_zone)
      session.delete(:host_context_user_language)

      @current_host_user_guid = nil
      @current_host_tenant_id = nil
      @current_host_user_time_zone = nil
      @current_host_user_language = nil
      OmnyaConnector::Current.user_guid = nil
      OmnyaConnector::Current.tenant_id = nil
      OmnyaConnector::Current.user_time_zone = nil
      OmnyaConnector::Current.user_language = nil

      log_host_context_state(event: "host_context.clear.after")
    end

    def require_host_context!
      if embedded_request?
        session_user_guid = normalized_host_context_guid(session[:host_context_user_guid])
        session_tenant_id = normalized_host_context_id(session[:host_context_tenant_id])
        return if session_user_guid.present? && session_tenant_id.present?

        # Development only: where the handshake cookie does not round-trip in the host iframe,
        # Turbo redirect-follows arrive with an empty session and a self-referencing Referer,
        # so redirecting loops forever (ERR_TOO_MANY_REDIRECTS). Fall back to the autonomous
        # dev defaults — the same values non-embedded requests already resolve to — so guarded
        # pages stay reachable. Production keeps the original guard behavior.
        if Rails.env.development?
          persist_host_context(
            omnya_connector_autonomous_user_guid || autonomous_default_guid,
            omnya_connector_autonomous_tenant_id || autonomous_default_id
          )

          session_user_guid = normalized_host_context_guid(session[:host_context_user_guid])
          session_tenant_id = normalized_host_context_id(session[:host_context_tenant_id])
          return if session_user_guid.present? && session_tenant_id.present?
        end
      else
        return if current_host_user_guid.present? && current_host_tenant_id.present?
      end

      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: "Host context not available." }
        format.json { render json: { error: "host_context_missing" }, status: :unauthorized }
      end
    end

    # Persist host context from trusted request params before guards run when session cookies are unavailable.
    def persist_host_context_from_params
      return unless trusted_embedded_context_param_request?

      user_guid = normalized_host_context_guid(params[:context_user_guid])
      tenant_id = normalized_host_context_id(params[:context_tenant_id])
      return if user_guid.blank? || tenant_id.blank?

      persist_host_context(user_guid, tenant_id)
    end

    # Restrict param-based context fallback to embedded trusted-origin requests only.
    def trusted_embedded_context_param_request?
      params[:context_user_guid].present? && params[:context_tenant_id].present? && embedded_request?
    end

    # Block direct top-level HTML access when enabled, requiring iframe navigation.
    def enforce_iframe_navigation
      return unless omnya_connector_enforce_iframe_navigation?
      return unless request.get? && request.format.html?
      return if iframe_navigation_request?

      render plain: "This application can only be opened from the host application iframe.", status: :forbidden
    end

    def iframe_navigation_request?
      return true if request.headers[IFRAME_FETCH_DEST_HEADER].to_s.casecmp?(IFRAME_FETCH_DEST_VALUE)

      embedded_request?
    end

    def omnya_connector_enforce_iframe_navigation?
      Rails.application.config.x.omnya_connector.enforce_iframe_navigation
    end

    def trusted_embedded_origin_request?
      return false unless Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass

      embedded_request?
    end

    def embedded_request?
      # Check 1: Cross-origin request where the Origin header names a trusted host.
      # This covers the canonical embedded case where the host domain differs from the module domain.
      origin = effective_request_origin
      return true if origin.present? && origin != request.base_url && trusted_origin?(origin)

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

      trusted_origin?(embedded_host)
    end

    def trusted_origin?(origin)
      OmnyaConnector::OriginMatcher.origin_allowed?(origin, omnya_connector_host_app_origins)
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

    def omnya_connector_autonomous_user_time_zone
      Rails.application.config.x.omnya_connector.autonomous_user_time_zone
    end

    def omnya_connector_autonomous_user_language
      Rails.application.config.x.omnya_connector.autonomous_user_language
    end

    def autonomous_default_guid
      Rails.env.development? ? "dev-user-guid-1" : nil
    end

    def autonomous_default_id
      Rails.env.development? ? 1 : nil
    end

    def autonomous_default_time_zone
      Rails.env.development? ? "UTC" : nil
    end

    def autonomous_default_language
      Rails.env.development? ? "en" : nil
    end

    def normalized_host_context_guid(value)
      value.to_s.strip.presence
    end

    def normalized_host_context_id(value)
      return nil if value.blank?

      id = Integer(value, exception: false)
      id&.positive? ? id : nil
    end

    def normalized_host_context_locale_value(value)
      value.to_s.strip.presence
    end

    def persist_host_context(user_guid, tenant_id, user_time_zone = nil, user_language = nil)
      persisted_user_guid = normalized_host_context_guid(user_guid)
      persisted_tenant_id = normalized_host_context_id(tenant_id)
      persisted_user_time_zone = normalized_host_context_locale_value(user_time_zone)
      persisted_user_language = normalized_host_context_locale_value(user_language)

      session[:host_context_user_guid] = persisted_user_guid
      session[:host_context_tenant_id] = persisted_tenant_id
      session[:host_context_user_time_zone] = persisted_user_time_zone
      session[:host_context_user_language] = persisted_user_language

      # Keep all request-local context stores aligned so tenant switches never
      # read stale values within the same request lifecycle.
      @current_host_user_guid = persisted_user_guid
      @current_host_tenant_id = persisted_tenant_id
      @current_host_user_time_zone = persisted_user_time_zone
      @current_host_user_language = persisted_user_language
      OmnyaConnector::Current.user_guid = persisted_user_guid
      OmnyaConnector::Current.tenant_id = persisted_tenant_id
      OmnyaConnector::Current.user_time_zone = persisted_user_time_zone
      OmnyaConnector::Current.user_language = persisted_user_language

      log_host_context_state(
        event: "host_context.persisted",
        details: {
          persisted_user_guid: session[:host_context_user_guid],
          persisted_tenant_id: session[:host_context_tenant_id],
          persisted_user_time_zone: session[:host_context_user_time_zone],
          persisted_user_language: session[:host_context_user_language]
        }
      )
    end

    def log_host_context_state(event:, details: {})
      return unless omnya_connector_log_host_context_state?

      raw_user_guid = session[:host_context_user_guid]
      raw_tenant_id = session[:host_context_tenant_id]
      raw_user_time_zone = session[:host_context_user_time_zone]
      raw_user_language = session[:host_context_user_language]

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
          raw_host_context_user_time_zone: raw_user_time_zone,
          raw_host_context_user_language: raw_user_language,
          normalized_host_context_user_guid: normalized_host_context_guid(raw_user_guid),
          normalized_host_context_tenant_id: normalized_host_context_id(raw_tenant_id),
          normalized_host_context_user_time_zone: normalized_host_context_locale_value(raw_user_time_zone),
          normalized_host_context_user_language: normalized_host_context_locale_value(raw_user_language),
          autonomous_user_guid: omnya_connector_autonomous_user_guid,
          autonomous_tenant_id: omnya_connector_autonomous_tenant_id,
          autonomous_user_time_zone: omnya_connector_autonomous_user_time_zone,
          autonomous_user_language: omnya_connector_autonomous_user_language
        }.merge(details)
      )
    end

    def omnya_connector_log_host_context_state?
      Rails.application.config.x.omnya_connector.log_host_context_state
    end
  end
end
