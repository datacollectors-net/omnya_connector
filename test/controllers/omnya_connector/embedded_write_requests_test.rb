require "test_helper"

# Integration tests for CSRF bypass of embedded write actions.
#
# These tests enable real CSRF enforcement (disabled by default in test env)
# plus the trusted-origin bypass, then verify that trusted-origin write
# requests succeed while untrusted or unrecognised requests are rejected.
class OmnyaConnector::EmbeddedWriteRequestsTest < ActionDispatch::IntegrationTest
  include EmbeddedCsrfTestHelper

  TRUSTED_ORIGIN  = "https://host.example.test"
  TRUSTED_REFERER = "https://host.example.test/some/page"
  UNTRUSTED_ORIGIN  = "https://evil.example.com"
  UNTRUSTED_REFERER = "https://evil.example.com/some/page"

  # ── DELETE with trusted Origin header ──────────────────────────────────────

  test "DELETE from trusted Origin succeeds without CSRF token" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: { "Origin" => TRUSTED_ORIGIN }
      assert_response :no_content
    end
  end

  test "embedded requests do not use autonomous fallback values" do
    with_autonomous_values("autonomous-user", 456, "America/New_York", "en-US") do
      with_embedded_csrf_enforcement do
        delete widget_url(1), headers: { "Origin" => TRUSTED_ORIGIN }
        assert_response :no_content
        assert_nil response.headers["X-Omnya-Current-User-Guid"]
        assert_nil response.headers["X-Omnya-Current-Tenant-Id"]
        assert_nil response.headers["X-Omnya-Current-User-Time-Zone"]
        assert_nil response.headers["X-Omnya-Current-User-Language"]
      end
    end
  end

  test "non-embedded requests can still use autonomous fallback values" do
    with_autonomous_values("autonomous-user", 456, "America/New_York", "en-US") do
      delete widget_url(1)
      assert_response :no_content
      assert_equal "autonomous-user", response.headers["X-Omnya-Current-User-Guid"]
      assert_equal 456, response.headers["X-Omnya-Current-Tenant-Id"]
      assert_equal "America/New_York", response.headers["X-Omnya-Current-User-Time-Zone"]
      assert_equal "en-US", response.headers["X-Omnya-Current-User-Language"]
    end
  end

  # ── DELETE with no Origin but trusted Referer ───────────────────────────────

  test "DELETE with no Origin but trusted Referer succeeds without CSRF token" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: { "Referer" => TRUSTED_REFERER }
      assert_response :no_content
    end
  end

  # ── DELETE with Origin: null (sandboxed iframe) and trusted Referer ─────────

  test "DELETE with Origin null but trusted Referer succeeds without CSRF token" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: { "Origin" => "null", "Referer" => TRUSTED_REFERER }
      assert_response :no_content
    end
  end

  # ── DELETE with untrusted Origin is rejected ────────────────────────────────

  test "DELETE from untrusted Origin is rejected with 422" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: { "Origin" => UNTRUSTED_ORIGIN }
      assert_response :unprocessable_content
    end
  end

  # ── DELETE with untrusted Referer and no Origin is rejected ─────────────────

  test "DELETE with untrusted Referer and no Origin is rejected with 422" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: { "Referer" => UNTRUSTED_REFERER }
      assert_response :unprocessable_content
    end
  end

  # ── DELETE with no origin signals at all is rejected ───────────────────────

  test "DELETE with no Origin or Referer is rejected with 422" do
    with_embedded_csrf_enforcement do
      delete widget_url(1)
      assert_response :unprocessable_content
    end
  end

  # ── POST (create) with trusted Origin ──────────────────────────────────────

  test "POST from trusted Origin succeeds without CSRF token" do
    with_embedded_csrf_enforcement do
      post widgets_url, headers: { "Origin" => TRUSTED_ORIGIN }
      assert_response :no_content
    end
  end

  # ── Bypass flag off: even trusted origin is rejected ───────────────────────

  test "DELETE from trusted Origin is rejected when bypass flag is disabled" do
    # Override: forgery protection on, bypass OFF.
    original_forgery = ActionController::Base.allow_forgery_protection
    original_bypass  = Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass

    ActionController::Base.allow_forgery_protection = true
    Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = false

    delete widget_url(1), headers: { "Origin" => TRUSTED_ORIGIN }
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery
    Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = original_bypass
  end

  # ── X-Omnya-Embedded-Host-Origin header bypass (Check 2) ───────────────────
  #
  # When the module's Stimulus controller is embedded in a trusted host, it injects
  # X-Omnya-Embedded-Host-Origin with the postMessage-established host origin on every
  # Turbo/fetch request. The module's own requests carry Origin == module base URL
  # (non-actionable for cross-origin trust), so the server falls back to this header.

  MODULE_BASE_URL = "http://www.example.com"

  test "DELETE with trusted X-Omnya-Embedded-Host-Origin and module-origin Origin succeeds" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: {
        "Origin" => MODULE_BASE_URL,
        "X-Omnya-Embedded-Host-Origin" => TRUSTED_ORIGIN
      }
      assert_response :no_content
    end
  end

  test "DELETE from wildcard-trusted origin succeeds without CSRF token" do
    with_host_app_origins([ "https://*.omnya-app.com" ]) do
      with_embedded_csrf_enforcement do
        delete widget_url(1), headers: { "Origin" => "https://tenant-a.omnya-app.com" }
        assert_response :no_content
      end
    end
  end

  test "DELETE from lookalike origin is rejected when wildcard trusted origin configured" do
    with_host_app_origins([ "https://*.omnya-app.com" ]) do
      with_embedded_csrf_enforcement do
        delete widget_url(1), headers: { "Origin" => "https://tenant-a.omnya-app.com.evil.example" }
        assert_response :unprocessable_content
      end
    end
  end

  test "POST with trusted X-Omnya-Embedded-Host-Origin and module-origin Origin succeeds" do
    with_embedded_csrf_enforcement do
      post widgets_url, headers: {
        "Origin" => MODULE_BASE_URL,
        "X-Omnya-Embedded-Host-Origin" => TRUSTED_ORIGIN
      }
      assert_response :no_content
    end
  end

  test "DELETE with untrusted X-Omnya-Embedded-Host-Origin is rejected with 422" do
    with_embedded_csrf_enforcement do
      delete widget_url(1), headers: {
        "Origin" => MODULE_BASE_URL,
        "X-Omnya-Embedded-Host-Origin" => UNTRUSTED_ORIGIN
      }
      assert_response :unprocessable_content
    end
  end

  test "DELETE with trusted X-Omnya-Embedded-Host-Origin is rejected when bypass flag is disabled" do
    original_forgery = ActionController::Base.allow_forgery_protection
    original_bypass  = Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass

    ActionController::Base.allow_forgery_protection = true
    Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = false

    delete widget_url(1), headers: {
      "Origin" => MODULE_BASE_URL,
      "X-Omnya-Embedded-Host-Origin" => TRUSTED_ORIGIN
    }
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery
    Rails.application.config.x.omnya_connector.allow_trusted_origin_csrf_bypass = original_bypass
  end

  private

  def widget_url(id)
    "/widgets/#{id}"
  end

  def widgets_url
    "/widgets"
  end

  def with_autonomous_values(user_guid, tenant_id, user_time_zone = nil, user_language = nil)
    original_user_guid = Rails.application.config.x.omnya_connector.autonomous_user_guid
    original_tenant_id = Rails.application.config.x.omnya_connector.autonomous_tenant_id
    original_user_time_zone = Rails.application.config.x.omnya_connector.autonomous_user_time_zone
    original_user_language = Rails.application.config.x.omnya_connector.autonomous_user_language

    Rails.application.config.x.omnya_connector.autonomous_user_guid = user_guid
    Rails.application.config.x.omnya_connector.autonomous_tenant_id = tenant_id
    Rails.application.config.x.omnya_connector.autonomous_user_time_zone = user_time_zone
    Rails.application.config.x.omnya_connector.autonomous_user_language = user_language

    yield
  ensure
    Rails.application.config.x.omnya_connector.autonomous_user_guid = original_user_guid
    Rails.application.config.x.omnya_connector.autonomous_tenant_id = original_tenant_id
    Rails.application.config.x.omnya_connector.autonomous_user_time_zone = original_user_time_zone
    Rails.application.config.x.omnya_connector.autonomous_user_language = original_user_language
  end

  def with_host_app_origins(origins)
    original_origins = Rails.application.config.x.omnya_connector.host_app_origins
    Rails.application.config.x.omnya_connector.host_app_origins = origins
    yield
  ensure
    Rails.application.config.x.omnya_connector.host_app_origins = original_origins
  end
end
