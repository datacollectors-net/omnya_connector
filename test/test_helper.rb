ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)
  end
end

# Wraps a test block with real CSRF enforcement and the trusted-origin bypass
# enabled, then restores both settings afterwards. Use this in integration tests
# that exercise the embedded-write CSRF bypass path.
module EmbeddedCsrfTestHelper
  def with_embedded_csrf_enforcement
    original_forgery = ActionController::Base.allow_forgery_protection
    original_bypass  = Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass

    ActionController::Base.allow_forgery_protection = true
    Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = true

    yield
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery
    Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = original_bypass
  end
end
