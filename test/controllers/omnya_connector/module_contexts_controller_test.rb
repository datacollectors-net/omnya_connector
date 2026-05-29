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

  # ── trusted_embedded_origin_request? – Referer fallback ───────────────────

  test "trusted_embedded_origin_request? is true when Origin blank but Referer is trusted" do
    with_embedded_csrf_enforcement do
      with_stubbed_host_context({ "user" => { "guid" => "u1" }, "tenant" => { "id" => 1 } }) do
        post omnya_connector.module_context_url,
          params: {
            module_context: {
              token: "t",
              context_endpoint: "https://host.example.test/external_modules/context",
              module_key: Rails.application.config.x.omnya_connector.module_key
            }
          },
          headers: { "Referer" => "https://host.example.test/page" }
        assert_response :no_content
      end
    end
  end

  test "trusted_embedded_origin_request? is true when Origin is 'null' but Referer is trusted" do
    with_embedded_csrf_enforcement do
      with_stubbed_host_context({ "user" => { "guid" => "u2" }, "tenant" => { "id" => 2 } }) do
        post omnya_connector.module_context_url,
          params: {
            module_context: {
              token: "t",
              context_endpoint: "https://host.example.test/external_modules/context",
              module_key: Rails.application.config.x.omnya_connector.module_key
            }
          },
          headers: { "Origin" => "null", "Referer" => "https://host.example.test/page" }
        assert_response :no_content
      end
    end
  end

  test "trusted_embedded_origin_request? is false when Origin blank and Referer is untrusted" do
    with_embedded_csrf_enforcement do
      post omnya_connector.module_context_url,
        params: {
          module_context: {
            token: "t",
            context_endpoint: "https://host.example.test/external_modules/context",
            module_key: Rails.application.config.x.omnya_connector.module_key
          }
        },
        headers: { "Referer" => "https://evil.example.com/page" }
      assert_response :unprocessable_content
    end
  end

  test "trusted_embedded_origin_request? is false when Origin blank and Referer absent" do
    with_embedded_csrf_enforcement do
      post omnya_connector.module_context_url,
        params: {
          module_context: {
            token: "t",
            context_endpoint: "https://host.example.test/external_modules/context",
            module_key: Rails.application.config.x.omnya_connector.module_key
          }
        }
      assert_response :unprocessable_content
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
