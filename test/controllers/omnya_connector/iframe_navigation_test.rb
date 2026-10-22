require "test_helper"

# Integration tests for the enforce_iframe_navigation guard: when enabled, direct
# top-level HTML access is blocked unless the request comes from an iframe or a
# trusted embedded origin.
class OmnyaConnector::IframeNavigationTest < ActionDispatch::IntegrationTest
  TRUSTED_ORIGIN = "https://host.example.test"

  setup do
    @original_enforce = Rails.application.config.x.omnya_connector.enforce_iframe_navigation
    Rails.application.config.x.omnya_connector.enforce_iframe_navigation = true
  end

  teardown do
    Rails.application.config.x.omnya_connector.enforce_iframe_navigation = @original_enforce
  end

  test "blocks direct top-level HTML access when enabled" do
    get "/host_context_probe", headers: { "Accept" => "text/html" }

    assert_response :forbidden
    assert_match "can only be opened from the host application iframe", response.body
  end

  test "allows requests with Sec-Fetch-Dest iframe header" do
    with_autonomous_values("autonomous-user", 456) do
      get "/host_context_probe", headers: { "Accept" => "application/json", "Sec-Fetch-Dest" => "iframe" }

      assert_response :success
      assert_equal "autonomous-user", response.parsed_body["user_guid"]
    end
  end

  test "allows embedded requests from trusted origins" do
    get "/host_context_probe", headers: { "Origin" => TRUSTED_ORIGIN, "Accept" => "application/json" }

    # The navigation guard passes; the host context guard then rejects because no session exists.
    assert_response :unauthorized
  end

  test "does not block non-HTML requests when enabled" do
    post "/widgets", headers: { "Accept" => "application/json" }

    assert_response :no_content
  end

  test "allows direct HTML access when disabled" do
    Rails.application.config.x.omnya_connector.enforce_iframe_navigation = false

    with_autonomous_values("autonomous-user", 456) do
      get "/host_context_probe", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_equal "autonomous-user", response.parsed_body["user_guid"]
    end
  end

  private

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
end
