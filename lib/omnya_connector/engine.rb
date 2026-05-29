module OmnyaConnector
  class Engine < ::Rails::Engine
    isolate_namespace OmnyaConnector

    initializer "omnya_connector.configuration", before: :load_config_initializers do |app|
      config = OmnyaConnector.configuration.build(Rails.env)

      app.config.x.omnya_connector = ActiveSupport::OrderedOptions.new
      app.config.x.omnya_connector.module_key                       = config[:module_key]
      app.config.x.omnya_connector.host_app_origins                 = config[:host_app_origins]
      app.config.x.omnya_connector.primary_host_origin              = config[:primary_host_origin]
      app.config.x.omnya_connector.autonomous_user_guid             = config[:autonomous_user_guid]
      app.config.x.omnya_connector.autonomous_tenant_id             = config[:autonomous_tenant_id]
      app.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = config[:allow_trusted_origin_csrf_bypass]
      app.config.x.omnya_connector.configure_session_store          = config[:configure_session_store]
      app.config.x.omnya_connector.log_host_context_state           = config[:log_host_context_state]
    end

    # Configure session store for cross-site iframe embedding.
    # SameSite=None is required so session cookies are sent in cross-origin iframe requests.
    # Set configure_session_store to false in OmnyaConnector.configure to skip this and manage it yourself.
    initializer "omnya_connector.session_store", before: :load_config_initializers do |app|
      next unless OmnyaConnector.configuration.configure_session_store

      default_secure = !Rails.env.test?
      app.config.session_store(
        :cookie_store,
        same_site: :none,
        httponly: true,
        secure: ENV.fetch("SESSION_COOKIE_SECURE", default_secure.to_s) == "true"
      )
    end

    # Append host app origins to the Content-Security-Policy connect-src directive
    # so the Stimulus controller can fetch context from the host.
    initializer "omnya_connector.content_security_policy" do |app|
      app.config.after_initialize do
        host_origins = app.config.x.omnya_connector&.host_app_origins
        next if host_origins.blank?

        if app.config.respond_to?(:content_security_policy) && app.config.content_security_policy
          app.config.content_security_policy.connect_src(
            *app.config.content_security_policy.connect_src,
            *host_origins
          )
        end
      end
    end

    # Pin the Stimulus controller JS so consuming apps using importmap-rails
    # can reference it via `pin "controllers/omnya_connector_controller"`.
    initializer "omnya_connector.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << Engine.root.join("config/importmap.rb")
      end
    end

    initializer "omnya_connector.assets" do |app|
      app.config.assets.paths << Engine.root.join("app/assets/javascripts") if app.config.respond_to?(:assets)
    end
  end
end
