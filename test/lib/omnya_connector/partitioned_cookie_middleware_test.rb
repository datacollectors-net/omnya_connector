require "test_helper"

class OmnyaConnector::PartitionedCookieMiddlewareTest < ActiveSupport::TestCase
  test "engine inserts middleware before ActionDispatch::Cookies when session store is configured" do
    stack = Rails.application.middleware.map(&:klass)

    assert_includes stack, OmnyaConnector::PartitionedCookieMiddleware
    assert_operator stack.index(OmnyaConnector::PartitionedCookieMiddleware), :<, stack.index(ActionDispatch::Cookies)
  end

  test "adds Partitioned attribute to the session cookie" do
    _status, headers, _body = call_with("#{session_key}=abc123; path=/; HttpOnly; SameSite=None")

    assert_equal "#{session_key}=abc123; path=/; HttpOnly; SameSite=None; Partitioned", headers["Set-Cookie"]
  end

  test "leaves non-session cookies untouched" do
    _status, headers, _body = call_with(
      [ "#{session_key}=abc123; path=/; HttpOnly; SameSite=None", "other_cookie=value; path=/" ]
    )

    assert_equal(
      "#{session_key}=abc123; path=/; HttpOnly; SameSite=None; Partitioned\nother_cookie=value; path=/",
      headers["Set-Cookie"]
    )
  end

  test "does not add a second Partitioned attribute" do
    _status, headers, _body = call_with("#{session_key}=abc123; path=/; HttpOnly; SameSite=None; Partitioned")

    assert_equal "#{session_key}=abc123; path=/; HttpOnly; SameSite=None; Partitioned", headers["Set-Cookie"]
  end

  test "is a no-op without Set-Cookie header" do
    _status, headers, _body = call_with(nil)

    assert_nil headers["Set-Cookie"]
  end

  private

  def session_key
    Rails.application.config.session_options[:key]
  end

  def call_with(set_cookie_value)
    inner = lambda do |_env|
      [ 200, { "Set-Cookie" => set_cookie_value }, [] ]
    end

    OmnyaConnector::PartitionedCookieMiddleware.new(inner).call({})
  end
end
