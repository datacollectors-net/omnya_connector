require "test_helper"

class OmnyaConnector::EngineTest < ActiveSupport::TestCase
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

  def build_app_with(policy:, host_origins:)
    connector = ActiveSupport::OrderedOptions.new
    connector.host_app_origins = host_origins

    x_config = ActiveSupport::OrderedOptions.new
    x_config.omnya_connector = connector

    config = Struct.new(:content_security_policy, :x).new(policy, x_config)
    Struct.new(:config).new(config)
  end
end
