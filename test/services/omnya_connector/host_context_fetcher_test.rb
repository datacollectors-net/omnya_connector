require "test_helper"

class OmnyaConnector::HostContextFetcherTest < ActiveSupport::TestCase
  test "raises error when token is blank" do
    error = assert_raises(OmnyaConnector::HostContextFetcher::Error) do
      OmnyaConnector::HostContextFetcher.call(
        token: "",
        context_endpoint: "https://host.example.test/context",
        allowed_origins: [ "https://host.example.test" ]
      )
    end

    assert_equal "missing_token", error.message
  end

  test "raises error when context_endpoint is blank" do
    error = assert_raises(OmnyaConnector::HostContextFetcher::Error) do
      OmnyaConnector::HostContextFetcher.call(
        token: "valid-token",
        context_endpoint: "",
        allowed_origins: [ "https://host.example.test" ]
      )
    end

    assert_equal "missing_context_endpoint", error.message
  end

  test "raises error when endpoint origin is not in allowed list" do
    error = assert_raises(OmnyaConnector::HostContextFetcher::Error) do
      OmnyaConnector::HostContextFetcher.call(
        token: "valid-token",
        context_endpoint: "https://evil.example/context",
        allowed_origins: [ "https://host.example.test" ]
      )
    end

    assert_equal "untrusted_context_endpoint", error.message
  end

  test "raises error for invalid URI" do
    error = assert_raises(OmnyaConnector::HostContextFetcher::Error) do
      OmnyaConnector::HostContextFetcher.call(
        token: "valid-token",
        context_endpoint: "not a valid uri %%%",
        allowed_origins: [ "https://host.example.test" ]
      )
    end

    assert_kind_of OmnyaConnector::HostContextFetcher::Error, error
  end
end
