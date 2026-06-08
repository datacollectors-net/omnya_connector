module OmnyaConnector
  class Configuration
    DEV_DEFAULT_ORIGINS = [
      "https://localhost:3020",
      "https://*.dcdev.eu:3443",
      "https://127.0.0.1:3020",
      "https://localhost:5173",
      "https://127.0.0.1:5173"
    ].freeze

    TEST_DEFAULT_ORIGINS = [ "https://host.example.test" ].freeze

    attr_accessor :module_key,
                  :host_app_origins,
                  :host_app_origins_explicitly_set,
                  :autonomous_user_guid,
                  :autonomous_tenant_id,
                  :allow_trusted_origin_csrf_bypass,
                  :configure_session_store,
                  :log_host_context_state

    def initialize
      @module_key = nil
      @host_app_origins = nil
      @host_app_origins_explicitly_set = false
      @autonomous_user_guid = nil
      @autonomous_tenant_id = nil
      @allow_trusted_origin_csrf_bypass = nil
      @configure_session_store = true
      @log_host_context_state = false
    end

    # Resolves all settings (DSL values with ENV fallback) and returns a
    # frozen options hash suitable for Rails.application.config.x.omnya_connector.
    def build(env)
      resolved_module_key       = (@module_key || ENV.fetch("MODULE_KEY", "")).to_s.strip
      resolved_origins_raw      = (@host_app_origins || ENV.fetch("HOST_APP_ORIGINS", "")).to_s
      resolved_explicitly_set   = @host_app_origins_explicitly_set || ENV.key?("HOST_APP_ORIGINS")
      resolved_autonomous_guid  = @autonomous_user_guid || ENV["AUTONOMOUS_USER_GUID"]
      resolved_autonomous_tid   = @autonomous_tenant_id || ENV["AUTONOMOUS_TENANT_ID"]
      resolved_csrf_bypass      = if @allow_trusted_origin_csrf_bypass.nil?
                                    ENV.fetch("ALLOW_TRUSTED_ORIGIN_CSRF_BYPASS", env.development? ? "true" : "false") == "true"
      else
                                    @allow_trusted_origin_csrf_bypass
      end

      origins = parse_origins(resolved_origins_raw, env)
      validate_production!(origins, resolved_module_key, resolved_explicitly_set, env)

      {
        module_key: resolved_module_key,
        host_app_origins: origins,
        primary_host_origin: origins.first.to_s,
        autonomous_user_guid: parse_autonomous_guid(resolved_autonomous_guid, env, default: "dev-user-guid-1"),
        autonomous_tenant_id: parse_autonomous_id(resolved_autonomous_tid, env, default: 1),
        allow_trusted_origin_csrf_bypass: resolved_csrf_bypass,
        configure_session_store: @configure_session_store,
        log_host_context_state: @log_host_context_state
      }
    end

    private

    def parse_origins(raw, env)
      origins = raw.split(",").map(&:strip).reject(&:blank?)

      origins.concat(DEV_DEFAULT_ORIGINS) if env.development?
      origins.concat(TEST_DEFAULT_ORIGINS) if env.test? && origins.empty?

      origins.uniq
    end

    def validate_production!(origins, module_key, explicitly_set, env)
      return unless env.production?

      unless explicitly_set
        raise "HOST_APP_ORIGINS must be explicitly set in production"
      end

      if module_key.blank?
        raise "MODULE_KEY must be present in production"
      end

      if origins.empty?
        raise "HOST_APP_ORIGINS must include at least one allowed host origin in production"
      end

      wildcard_origin = origins.find { |origin| origin.include?("*") }
      if wildcard_origin
        raise "HOST_APP_ORIGINS cannot include wildcard origins in production"
      end

      insecure_origin = origins.find { |origin| !origin.start_with?("https://") }
      if insecure_origin
        raise "HOST_APP_ORIGINS must use https origins in production"
      end
    end

    def parse_autonomous_guid(value, env, default:)
      raw_value = value.presence || (env.development? ? default : nil)
      raw_value.to_s.strip.presence
    end

    def parse_autonomous_id(value, env, default:)
      raw_value = value.presence || (env.development? ? default.to_s : nil)
      return nil if raw_value.blank?

      Integer(raw_value)
    rescue ArgumentError
      nil
    end
  end
end
