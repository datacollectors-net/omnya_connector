module OmnyaConnector
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    desc "Install OmnyaConnector engine: mount routes, include controller concern, copy initializer"

    def mount_engine
      route 'mount OmnyaConnector::Engine => "/"'
    end

    def include_controller_concern
      inject_into_class(
        "app/controllers/application_controller.rb",
        "ApplicationController",
        "  include OmnyaConnector::ControllerConcern\n"
      )
    end

    def copy_initializer
      template "initializer.rb", "config/initializers/omnya_connector.rb"
    end

    def verify_https_readiness
      production_config_path = File.join(destination_root, "config/environments/production.rb")

      unless File.exist?(production_config_path)
        say_status :warning,
                   "HTTPS readiness check skipped: config/environments/production.rb not found.",
                   :yellow
        print_https_deployment_guidance
        return
      end

      production_config = File.read(production_config_path)
      force_ssl_enabled = production_config.match?(/^\s*config\.force_ssl\s*=\s*true\b/)

      if force_ssl_enabled
        say_status :ok,
                   "HTTPS readiness check passed: config.force_ssl = true in production.",
                   :green
      else
        say_status :warning,
                   "HTTPS readiness check failed: set config.force_ssl = true in config/environments/production.rb.",
                   :yellow
      end

      print_https_deployment_guidance
    end

    private

    def print_https_deployment_guidance
      say_status :warning,
                 "OmnyaConnector requires HTTPS in embedded deployment so SameSite=None secure cookies are accepted by browsers.",
                 :yellow
      say_status :warning,
                 "Keep SESSION_COOKIE_SECURE=true in production and verify reverse proxy forwarding (X-Forwarded-Proto=https).",
                 :yellow
    end
  end
end
