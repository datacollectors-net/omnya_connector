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
  end
end
