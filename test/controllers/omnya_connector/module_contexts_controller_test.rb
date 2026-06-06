require "test_helper"

class OmnyaConnector::ModuleContextsControllerTest < ActionDispatch::IntegrationTest
  include EmbeddedCsrfTestHelper

  test "creates context from valid payload" do
    context_payload = {
      "user" => { "guid" => "user-guid-77" },
      "tenant" => { "id" => 700 }
    }

    with_stubbed_host_context(context_payload) do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-1",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :no_content
  end

  test "rejects invalid module key" do
    post omnya_connector.module_context_url, params: {
      module_context: {
        token: "token-1",
        context_endpoint: "https://host.example.test/external_modules/context",
        module_key: "wrong-key"
      }
    }

    assert_response :unauthorized
    assert_equal "invalid_module_key", response.parsed_body["error"]
  end

  test "returns unauthorized for fetch errors with unauthorized message" do
    with_stubbed_host_context_error("unauthorized") do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-expired",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "returns unprocessable entity for other fetch errors" do
    with_stubbed_host_context_error("context_request_failed") do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-1",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "rejects context with missing user guid" do
    context_payload = {
      "user" => { "guid" => "" },
      "tenant" => { "id" => 700 }
    }

    with_stubbed_host_context(context_payload) do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-1",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :unauthorized
    assert_equal "invalid_context", response.parsed_body["error"]
  end

  test "destroy clears host context" do
    context_payload = {
      "user" => { "guid" => "user-guid-88" },
      "tenant" => { "id" => 800 }
    }

    with_stubbed_host_context(context_payload) do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-2",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :no_content

    delete omnya_connector.module_context_url
    assert_response :no_content
  end

  test "re-sync with new tenant immediately replaces stored tenant context" do
    with_stubbed_host_context({ "user" => { "guid" => "switch-user" }, "tenant" => { "id" => 700 } }) do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-switch-a",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :no_content

    with_stubbed_host_context({ "user" => { "guid" => "switch-user" }, "tenant" => { "id" => 900 } }) do
      post omnya_connector.module_context_url, params: {
        module_context: {
          token: "token-switch-b",
          context_endpoint: "https://host.example.test/external_modules/context",
          module_key: Rails.application.config.x.omnya_connector.module_key
        }
      }
    end

    assert_response :no_content

    get "/host_context_probe",
      headers: {
        "Origin" => "https://host.example.test",
        "Accept" => "application/json"
      }

    assert_response :success
    assert_equal "switch-user", response.parsed_body["user_guid"]
    assert_equal 900, response.parsed_body["tenant_id"]
  end

  # ── ModuleContextsController CSRF bypass (skip_forgery_protection) ─────────
  #
  # ModuleContextsController unconditionally skips CSRF. These tests verify the
  # 0.5.0 regression: POST /module_context must not 422 when Origin is the module's
  # own base URL (same-origin iframe request) or absent — scenarios where third-party
  # cookie restrictions cause the CSRF token to be unverifiable.

  test "POST /module_context succeeds without CSRF token when Origin is module base URL" do
    # Regression test for 0.5.0: Origin == module base_url caused trusted_embedded_origin_request?
    # to return false, so CSRF was enforced. With skip_forgery_protection the endpoint no longer
    # depends on CSRF at all. http://www.example.com is the base_url Rails uses in integration tests.
    with_embedded_csrf_enforcement do
      with_stubbed_host_context({ "user" => { "guid" => "u-reg-1" }, "tenant" => { "id" => 10 } }) do
        post omnya_connector.module_context_url,
          params: {
            module_context: {
              token: "t",
              context_endpoint: "https://host.example.test/external_modules/context",
              module_key: Rails.application.config.x.omnya_connector.module_key
            }
          },
          headers: { "Origin" => "http://www.example.com" }
        assert_response :no_content
      end
    end
  end

  test "POST /module_context succeeds without CSRF token and no origin signals" do
    with_embedded_csrf_enforcement do
      with_stubbed_host_context({ "user" => { "guid" => "u-reg-2" }, "tenant" => { "id" => 20 } }) do
        post omnya_connector.module_context_url,
          params: {
            module_context: {
              token: "t",
              context_endpoint: "https://host.example.test/external_modules/context",
              module_key: Rails.application.config.x.omnya_connector.module_key
            }
          }
        assert_response :no_content
      end
    end
  end

  private

  def with_stubbed_host_context(payload)
    original_call = OmnyaConnector::HostContextFetcher.method(:call)
    OmnyaConnector::HostContextFetcher.define_singleton_method(:call) { |**_args| payload }
    yield
  ensure
    OmnyaConnector::HostContextFetcher.define_singleton_method(:call, original_call)
  end

  def with_stubbed_host_context_error(message)
    original_call = OmnyaConnector::HostContextFetcher.method(:call)
    OmnyaConnector::HostContextFetcher.define_singleton_method(:call) do |**_args|
      raise OmnyaConnector::HostContextFetcher::Error, message
    end
    yield
  ensure
    OmnyaConnector::HostContextFetcher.define_singleton_method(:call, original_call)
  end
end
