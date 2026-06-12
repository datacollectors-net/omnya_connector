require "test_helper"

class OmnyaConnector::OriginMatcherTest < ActiveSupport::TestCase
  test "matches exact origin" do
    assert OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://host.example.com",
      [ "https://host.example.com" ]
    )
  end

  test "matches exact origin after default-port normalization" do
    assert OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://host.example.com:443",
      [ "https://host.example.com" ]
    )
  end

  test "rejects exact origin when non-default port differs" do
    assert_not OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://host.example.com:8443",
      [ "https://host.example.com" ]
    )
  end

  test "matches wildcard subdomain" do
    assert OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://tenant-a.omnya-app.com",
      [ "https://*.omnya-app.com" ]
    )
  end

  test "matches wildcard deep subdomain" do
    assert OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://region-a.tenant-a.omnya-app.com",
      [ "https://*.omnya-app.com" ]
    )
  end

  test "rejects wildcard apex domain" do
    assert_not OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://omnya-app.com",
      [ "https://*.omnya-app.com" ]
    )
  end

  test "rejects wildcard lookalike suffix" do
    assert_not OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://tenant-a.omnya-app.com.evil.example",
      [ "https://*.omnya-app.com" ]
    )
  end

  test "matches wildcard when explicit wildcard port matches" do
    assert OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://tenant-a.omnya-app.com:3443",
      [ "https://*.omnya-app.com:3443" ]
    )
  end

  test "rejects wildcard when explicit wildcard port differs" do
    assert_not OmnyaConnector::OriginMatcher.origin_allowed?(
      "https://tenant-a.omnya-app.com",
      [ "https://*.omnya-app.com:3443" ]
    )
  end

  test "rejects blank origin" do
    assert_not OmnyaConnector::OriginMatcher.origin_allowed?(
      "",
      [ "https://host.example.com" ]
    )
  end

  test "rejects invalid origin" do
    assert_not OmnyaConnector::OriginMatcher.origin_allowed?(
      "not a valid origin",
      [ "https://host.example.com" ]
    )
  end
end