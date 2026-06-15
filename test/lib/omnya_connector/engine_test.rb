require "test_helper"

class OmnyaConnector::EngineTest < ActiveSupport::TestCase
  test "requires force_ssl in production" do
    app = build_app_with(policy: nil, host_origins: [ "https://host.example.test" ], force_ssl: false)
    env = ActiveSupport::StringInquirer.new("production")

    error = assert_raises(RuntimeError) do
      OmnyaConnector::Engine.send(:ensure_https_enforced!, app, env)
    end

    assert_match "HTTPS must be enforced in production", error.message
  end

  test "allows boot when force_ssl is enabled in production" do
    app = build_app_with(policy: nil, host_origins: [ "https://host.example.test" ], force_ssl: true)
    env = ActiveSupport::StringInquirer.new("production")

    assert_nothing_raised do
      OmnyaConnector::Engine.send(:ensure_https_enforced!, app, env)
    end
  end

  test "skips HTTPS enforcement outside production" do
    app = build_app_with(policy: nil, host_origins: [ "https://host.example.test" ], force_ssl: false)
    env = ActiveSupport::StringInquirer.new("development")

    assert_nothing_raised do
      OmnyaConnector::Engine.send(:ensure_https_enforced!, app, env)
    end
  end

  test "content security policy merge is a no-op when policy is nil" do
    app = build_app_with(policy: nil, host_origins: [ "https://host.example.test" ])

    assert_nothing_raised do
      OmnyaConnector::Engine.send(:apply_content_security_policy!, app)
    end
  end

  test "content security policy merges connect-src and frame-ancestors additively" do
    policy = ActionDispatch::ContentSecurityPolicy.new
    policy.connect_src :self, "https://api.example.test"
    policy.frame_ancestors "https://embedder.example.test"

    app = build_app_with(
      policy: policy,
      host_origins: [ "https://host.example.test", "https://api.example.test" ]
    )

    OmnyaConnector::Engine.send(:apply_content_security_policy!, app)

    assert_equal [ "'self'", "https://api.example.test", "https://host.example.test" ], policy.connect_src
    assert_equal [ "https://embedder.example.test", "'self'", "https://host.example.test", "https://api.example.test" ], policy.frame_ancestors
  end

  test "content security policy ensures frame-ancestors includes self even without host origins" do
    policy = ActionDispatch::ContentSecurityPolicy.new
    policy.frame_ancestors "https://embedder.example.test"

    app = build_app_with(policy: policy, host_origins: [])

    OmnyaConnector::Engine.send(:apply_content_security_policy!, app)

    assert_equal [ "https://embedder.example.test", "'self'" ], policy.frame_ancestors
  end

  private

  def build_app_with(policy:, host_origins:, force_ssl: true)
    connector = ActiveSupport::OrderedOptions.new
    connector.host_app_origins = host_origins

    x_config = ActiveSupport::OrderedOptions.new
    x_config.omnya_connector = connector

    config = Struct.new(:content_security_policy, :x, :force_ssl).new(policy, x_config, force_ssl)
    Struct.new(:config).new(config)
  end
end
