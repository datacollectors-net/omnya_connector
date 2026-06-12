require "omnya_connector/version"
require "omnya_connector/configuration"
require "omnya_connector/origin_matcher"
require "omnya_connector/engine"

module OmnyaConnector
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
