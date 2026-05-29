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
end
