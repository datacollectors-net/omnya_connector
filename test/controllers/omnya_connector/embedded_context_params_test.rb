require "test_helper"

# Integration tests for the param-based host context fallback.
#
# When third-party cookie restrictions keep the session from round-tripping in the
# host iframe, embedded forms can carry hidden context fields (rendered via the
# host_context_params helper) so persist_host_context_from_params re-establishes
# the context on submit. The fallback is restricted to trusted embedded requests.
class OmnyaConnector::EmbeddedContextParamsTest < ActionDispatch::IntegrationTest
  TRUSTED_ORIGIN = "https://host.example.test"
  UNTRUSTED_ORIGIN = "https://evil.example.com"

  test "embedded POST from trusted origin persists context from params" do
    post "/widgets",
      params: { context_user_guid: "param-user", context_tenant_id: 99 },
      headers: { "Origin" => TRUSTED_ORIGIN }

    assert_response :no_content
    assert_equal "param-user", response.headers["X-Omnya-Current-User-Guid"]
    assert_equal 99, response.headers["X-Omnya-Current-Tenant-Id"]

    # The persisted context round-trips through the session on subsequent requests.
    get "/host_context_probe", headers: { "Origin" => TRUSTED_ORIGIN, "Accept" => "application/json" }

    assert_response :success
    assert_equal "param-user", response.parsed_body["user_guid"]
    assert_equal 99, response.parsed_body["tenant_id"]
  end

  test "params are ignored for untrusted origins" do
    post "/widgets",
      params: { context_user_guid: "param-user", context_tenant_id: 99 },
      headers: { "Origin" => UNTRUSTED_ORIGIN }

    assert_response :no_content
    assert_nil response.headers["X-Omnya-Current-User-Guid"]
    assert_nil response.headers["X-Omnya-Current-Tenant-Id"]

    # No context was persisted, so the embedded guard still rejects.
    get "/host_context_probe", headers: { "Origin" => TRUSTED_ORIGIN, "Accept" => "application/json" }

    assert_response :unauthorized
  end

  test "params are ignored for non-embedded requests" do
    post "/widgets", params: { context_user_guid: "param-user", context_tenant_id: 99 }

    assert_response :no_content
    assert_nil response.headers["X-Omnya-Current-User-Guid"]
    assert_nil response.headers["X-Omnya-Current-Tenant-Id"]
  end

  test "malformed param values are ignored" do
    post "/widgets",
      params: { context_user_guid: "", context_tenant_id: "-5" },
      headers: { "Origin" => TRUSTED_ORIGIN }

    assert_response :no_content
    assert_nil response.headers["X-Omnya-Current-User-Guid"]
    assert_nil response.headers["X-Omnya-Current-Tenant-Id"]
  end
end
