module TrModule
  class Engine < ::Rails::Engine
    isolate_namespace TrModule

    initializer "tr_module.configuration", before: :load_config_initializers do |app|
      config = TrModule.configuration.build(Rails.env)

      app.config.x.tr_module = ActiveSupport::OrderedOptions.new
      app.config.x.tr_module.module_key                       = config[:module_key]
      app.config.x.tr_module.host_app_origins                 = config[:host_app_origins]
      app.config.x.tr_module.primary_host_origin              = config[:primary_host_origin]
      app.config.x.tr_module.autonomous_user_guid             = config[:autonomous_user_guid]
      app.config.x.tr_module.autonomous_tenant_id             = config[:autonomous_tenant_id]
      app.config.x.tr_module.allow_trusted_origin_csrf_bypass = config[:allow_trusted_origin_csrf_bypass]
      app.config.x.tr_module.configure_session_store          = config[:configure_session_store]
    end

    # Configure session store for cross-site iframe embedding.
    # SameSite=None is required so session cookies are sent in cross-origin iframe requests.
    # Set configure_session_store to false in TrModule.configure to skip this and manage it yourself.
    initializer "tr_module.session_store", before: :load_config_initializers do |app|
      next unless TrModule.configuration.configure_session_store

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
    initializer "tr_module.content_security_policy" do |app|
      app.config.after_initialize do
        host_origins = app.config.x.tr_module&.host_app_origins
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
    # can reference it via `pin "controllers/tr_module_controller"`.
    initializer "tr_module.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << Engine.root.join("config/importmap.rb")
      end
    end

    initializer "tr_module.assets" do |app|
      app.config.assets.paths << Engine.root.join("app/assets/javascripts") if app.config.respond_to?(:assets)
    end
  end
end
