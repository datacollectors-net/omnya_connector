require "test_helper"

class TrModule::ConfigurationTest < ActiveSupport::TestCase
  setup do
    TrModule.reset_configuration!
  end

  teardown do
    TrModule.reset_configuration!
  end

  test "parses comma separated origins" do
    env = ActiveSupport::StringInquirer.new("test")

    TrModule.configure do |c|
      c.module_key = "module-posts"
      c.host_app_origins = "https://host-a.example, https://host-b.example"
    end

    config = TrModule.configuration.build(env)

    assert_equal "module-posts", config[:module_key]
    assert_equal [ "https://host-a.example", "https://host-b.example" ], config[:host_app_origins]
    assert_equal "https://host-a.example", config[:primary_host_origin]
  end

  test "adds test fallback origin when none configured" do
    env = ActiveSupport::StringInquirer.new("test")

    TrModule.configure do |c|
      c.module_key = "module-posts"
      c.host_app_origins = ""
    end

    config = TrModule.configuration.build(env)

    assert_equal [ "https://host.example.test" ], config[:host_app_origins]
  end

  test "adds development default origins in development" do
    env = ActiveSupport::StringInquirer.new("development")

    TrModule.configure do |c|
      c.module_key = "module-posts"
      c.host_app_origins = "https://custom.example"
    end

    config = TrModule.configuration.build(env)

    assert_includes config[:host_app_origins], "https://custom.example"
    assert_includes config[:host_app_origins], "https://localhost:3020"
  end

  test "sets autonomous defaults in development" do
    env = ActiveSupport::StringInquirer.new("development")

    config = TrModule.configuration.build(env)

    assert_equal "dev-user-guid-1", config[:autonomous_user_guid]
    assert_equal 1, config[:autonomous_tenant_id]
  end

  test "autonomous values are nil in production" do
    env = ActiveSupport::StringInquirer.new("test")

    config = TrModule.configuration.build(env)

    assert_nil config[:autonomous_user_guid]
    assert_nil config[:autonomous_tenant_id]
  end

  test "DSL values override ENV fallback" do
    env = ActiveSupport::StringInquirer.new("test")

    TrModule.configure do |c|
      c.module_key = "dsl-key"
      c.host_app_origins = "https://dsl.example"
    end

    config = TrModule.configuration.build(env)

    assert_equal "dsl-key", config[:module_key]
    assert_equal [ "https://dsl.example" ], config[:host_app_origins]
  end

  test "rejects wildcard origins in production" do
    env = ActiveSupport::StringInquirer.new("production")

    TrModule.configure do |c|
      c.module_key = "module-posts"
      c.host_app_origins = "https://*.example.com"
      c.host_app_origins_explicitly_set = true
    end

    error = assert_raises(RuntimeError) do
      TrModule.configuration.build(env)
    end

    assert_match "cannot include wildcard", error.message
  end

  test "requires host origins to be explicitly set in production" do
    env = ActiveSupport::StringInquirer.new("production")

    TrModule.configure do |c|
      c.module_key = "module-posts"
      c.host_app_origins = "https://app.example.com"
      c.host_app_origins_explicitly_set = false
    end

    error = assert_raises(RuntimeError) do
      TrModule.configuration.build(env)
    end

    assert_match "must be explicitly set", error.message
  end

  test "requires module key in production" do
    env = ActiveSupport::StringInquirer.new("production")

    TrModule.configure do |c|
      c.module_key = ""
      c.host_app_origins = "https://app.example.com"
      c.host_app_origins_explicitly_set = true
    end

    error = assert_raises(RuntimeError) do
      TrModule.configuration.build(env)
    end

    assert_match "MODULE_KEY must be present", error.message
  end

  test "rejects http origins in production" do
    env = ActiveSupport::StringInquirer.new("production")

    TrModule.configure do |c|
      c.module_key = "module-posts"
      c.host_app_origins = "http://localhost:3000"
      c.host_app_origins_explicitly_set = true
    end

    error = assert_raises(RuntimeError) do
      TrModule.configuration.build(env)
    end

    assert_match "must use https", error.message
  end

  test "configure_session_store defaults to true" do
    config = TrModule.configuration.build(ActiveSupport::StringInquirer.new("test"))

    assert config[:configure_session_store]
  end

  test "allow_trusted_origin_csrf_bypass defaults based on environment" do
    test_config = TrModule.configuration.build(ActiveSupport::StringInquirer.new("test"))
    assert_equal false, test_config[:allow_trusted_origin_csrf_bypass]
  end
end
