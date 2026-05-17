require "tr_module/version"
require "tr_module/configuration"
require "tr_module/engine"

module TrModule
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
