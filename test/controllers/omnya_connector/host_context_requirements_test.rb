require "test_helper"

class OmnyaConnector::HostContextRequirementsTest < ActionDispatch::IntegrationTest
  TRUSTED_ORIGIN = "https://host.example.test"

  test "embedded request with missing session returns unauthorized and does not use autonomous fallback" do
    with_autonomous_values("autonomous-user", 456) do
      get host_context_probe_url,
        headers: {
          "Origin" => TRUSTED_ORIGIN,
          "Accept" => "application/json"
        }

      assert_response :unauthorized
      assert_equal "host_context_missing", response.parsed_body["error"]
    end
  end

  test "embedded request with valid session returns session-backed host context" do
    with_autonomous_values("autonomous-user", 456) do
      with_stubbed_host_context({ "user" => { "guid" => "embedded-user" }, "tenant" => { "id" => 77 } }) do
        post omnya_connector.module_context_url, params: {
          module_context: {
            token: "token-embedded",
            context_endpoint: "https://host.example.test/external_modules/context",
            module_key: Rails.application.config.x.omnya_connector.module_key
          }
        }
      end

      assert_response :no_content

      get host_context_probe_url,
        headers: {
          "Origin" => TRUSTED_ORIGIN,
          "Accept" => "application/json"
        }

      assert_response :success
      assert_equal "embedded-user", response.parsed_body["user_guid"]
      assert_equal 77, response.parsed_body["tenant_id"]
    end
  end

  test "standalone request still uses autonomous fallback in development-style mode" do
    with_autonomous_values("autonomous-user", 456) do
      get host_context_probe_url, headers: { "Accept" => "application/json" }

      assert_response :success
      assert_equal "autonomous-user", response.parsed_body["user_guid"]
      assert_equal 456, response.parsed_body["tenant_id"]
    end
  end

  private

  def host_context_probe_url
    "/host_context_probe"
  end

  def with_autonomous_values(user_guid, tenant_id)
    original_user_guid = Rails.application.config.x.omnya_connector.autonomous_user_guid
    original_tenant_id = Rails.application.config.x.omnya_connector.autonomous_tenant_id

    Rails.application.config.x.omnya_connector.autonomous_user_guid = user_guid
    Rails.application.config.x.omnya_connector.autonomous_tenant_id = tenant_id

    yield
  ensure
    Rails.application.config.x.omnya_connector.autonomous_user_guid = original_user_guid
    Rails.application.config.x.omnya_connector.autonomous_tenant_id = original_tenant_id
  end

  def with_stubbed_host_context(payload)
    original_call = OmnyaConnector::HostContextFetcher.method(:call)
    OmnyaConnector::HostContextFetcher.define_singleton_method(:call) { |**_args| payload }
    yield
  ensure
    OmnyaConnector::HostContextFetcher.define_singleton_method(:call, original_call)
  end
end
