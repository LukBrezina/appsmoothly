require "test_helper"

class ProductionTest < ActiveSupport::TestCase
  test "deploy config uses kamal's local registry and includes litestream when backups configured" do
    app = App.new(name: "widget", agent: "claude", prod_server: "prod-1", prod_host: "widget.example.com",
                  s3_bucket: "widget-backups", s3_region: "auto", s3_endpoint: "https://storage.googleapis.com",
                  s3_access_key_id: "GOOG1", s3_secret_access_key: "shh")
    config = YAML.safe_load(Production.deploy_yaml(app))
    assert_equal "widget", config["service"]
    assert_equal "widget", config["image"]
    assert_equal "localhost:5555", config.dig("registry", "server")
    assert_equal ["prod-1"], config["servers"]["web"]
    assert_equal "widget.example.com", config["proxy"]["host"]
    assert_equal "litestream/litestream:0.3", config.dig("accessories", "litestream", "image")
    assert_equal "https://storage.googleapis.com", config.dig("accessories", "litestream", "env", "clear", "LITESTREAM_ENDPOINT")
  end

  test "deploy config omits accessory without backups" do
    app = App.new(name: "widget", agent: "claude", prod_server: "100.64.0.7", prod_host: "widget.example.com")
    config = YAML.safe_load(Production.deploy_yaml(app))
    assert_nil config["accessories"]
    assert_nil config.dig("registry", "username")
  end

  test "behind Caddy (RAF_DOMAIN) the proxy skips ssl, forwards headers, and first deploy pins kamal-proxy to loopback" do
    ENV["RAF_DOMAIN"] = "acme.appsmoothly.com"
    app = App.new(name: "widget", agent: "claude", prod_server: "localhost", prod_host: "acme.appsmoothly.com")
    config = YAML.safe_load(Production.deploy_yaml(app))
    assert_equal false, config["proxy"]["ssl"]
    assert_equal true, config["proxy"]["forward_headers"]
    assert_equal "acme.appsmoothly.com", config["proxy"]["host"]
    assert_includes Production.deploy_command(app), "proxy boot_config set --publish-host-ip 127.0.0.1"
    assert_includes Production.deploy_command(app), "&& bin/kamal setup"
    app.deployed_at = Time.current
    assert_equal "bin/kamal deploy", Production.deploy_command(app)
  ensure
    ENV.delete("RAF_DOMAIN")
  end

  test "provisioned SMTP credential flows into the deploy env" do
    ENV["RAF_SMTP_ADDRESS"] = "smtp.eu.mailgun.org"
    ENV["RAF_SMTP_USER_NAME"] = "app@mail.acme.appsmoothly.com"
    ENV["RAF_SMTP_FROM"] = "app@mail.acme.appsmoothly.com"
    app = App.new(name: "widget", agent: "claude", prod_server: "localhost", prod_host: "acme.appsmoothly.com")
    config = YAML.safe_load(Production.deploy_yaml(app))
    assert_includes config.dig("env", "secret"), "SMTP_PASSWORD"
    assert_equal "smtp.eu.mailgun.org", config.dig("env", "clear", "SMTP_ADDRESS")
    assert_equal "app@mail.acme.appsmoothly.com", config.dig("env", "clear", "SMTP_FROM")
  ensure
    %w[RAF_SMTP_ADDRESS RAF_SMTP_USER_NAME RAF_SMTP_FROM].each { |key| ENV.delete(key) }
  end

  test "without RAF_DOMAIN the proxy terminates ssl itself and setup runs without boot_config" do
    app = App.new(name: "widget", agent: "claude", prod_server: "prod-1", prod_host: "widget.example.com")
    config = YAML.safe_load(Production.deploy_yaml(app))
    assert_equal true, config["proxy"]["ssl"]
    assert_equal "bin/kamal setup", Production.deploy_command(app)
  end
end
