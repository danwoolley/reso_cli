require "test_helper"

# MLS connection management: add / use / remove / mls, storage, and migration.
class ConfigTest < Minitest::Test
  include CliHelper

  def test_no_config_yet
    result = cli("mls")
    assert result.success?
    assert_equal [], result.json
    assert_match(/No MLSs configured yet/, result.stderr)
    refute File.exist?(@config_path), "listing MLSs must not create a config file"
  end

  def test_commands_needing_an_mls_explain_what_to_do
    result = cli("search", "Property", "--top", "1")
    refute result.success?
    assert_match(%r{Run /mls-setup}, result.stderr)
  end

  def test_add_bearer_token
    result = add_bearer("Test MLS", endpoint: "https://api.example.com/odata/")
    out = result.json
    assert_equal "Test MLS", out["added"]
    assert_equal "https://api.example.com/odata", out["endpoint"], "trailing slash is stripped"
    assert_equal "bearer", out["auth"]
    assert out["active"]

    entry = config_data["mls"]["Test MLS"]
    assert_equal({ "access_token" => "secret-token-xyz", "token_type" => "Bearer" }, entry["authentication"])
    assert_equal "Test MLS", config_data["active"]
  end

  def test_add_oauth_defaults_to_no_scope
    result = cli("add", "OAuth MLS", "--endpoint", "https://api.example.com/odata/$metadata",
                 "--token-url", "https://auth.example.com/token", "--client-id", "id1", "--client-secret", "s3cret")
    assert result.success?, result.stderr
    assert_equal "https://api.example.com/odata", result.json["endpoint"], "$metadata suffix is stripped"

    auth = config_data["mls"]["OAuth MLS"]["authentication"]
    assert_equal "https://auth.example.com/token", auth["endpoint"]
    assert_equal "id1", auth["client_id"]
    assert_equal "s3cret", auth["client_secret"]
    assert_equal "", auth["scope"]
  end

  def test_add_oauth_with_scope
    cli("add", "Scoped", "--endpoint", "https://api.example.com/odata", "--token-url", "https://auth.example.com/token",
        "--client-id", "id1", "--client-secret", "s3cret", "--scope", "ODataApi")
    assert_equal "ODataApi", config_data["mls"]["Scoped"]["authentication"]["scope"]
  end

  def test_add_rejects_incomplete_or_invalid_input
    no_creds = cli("add", "X", "--endpoint", "https://api.example.com/odata")
    refute no_creds.success?
    assert_match(/Give credentials/, no_creds.stderr)

    partial = cli("add", "X", "--endpoint", "https://api.example.com/odata", "--token-url", "https://t", "--client-id", "a")
    refute partial.success?
    assert_match(/--client-secret/, partial.stderr)

    bad_url = cli("add", "X", "--endpoint", "api.example.com/odata", "--token", "t")
    refute bad_url.success?
    assert_match(/http/, bad_url.stderr)

    refute File.exist?(@config_path), "failed adds must not write a config"
  end

  def test_duplicate_name_needs_replace
    add_bearer("Dup")
    dup = cli("add", "dup", "--endpoint", "https://other.example.com/odata", "--token", "t2")
    refute dup.success?
    assert_match(/already exists/, dup.stderr)

    replaced = cli("add", "dup", "--endpoint", "https://other.example.com/odata", "--token", "t2", "--replace")
    assert replaced.success?, replaced.stderr
    assert replaced.json["replaced"]
    assert_equal ["dup"], config_data["mls"].keys
    assert_equal "https://other.example.com/odata", config_data["mls"]["dup"]["endpoint"]
  end

  def test_no_activate
    add_bearer("First")
    cli("add", "Second", "--endpoint", "https://api.example.com/odata", "--token", "t", "--no-activate")
    assert_equal "First", config_data["active"]
  end

  def test_mls_lists_without_secrets
    add_bearer("Bearer MLS", token: "super-secret-token")
    cli("add", "OAuth MLS", "--endpoint", "https://api.example.com/odata", "--token-url", "https://auth.example.com/token",
        "--client-id", "id1", "--client-secret", "super-secret-client")

    result = cli("mls")
    assert result.success?
    refute_match(/super-secret/, result.stdout + result.stderr)
    list = result.json
    assert_equal ["Bearer MLS", "OAuth MLS"], list.map { |m| m["name"] }
    assert_equal %w[bearer oauth2], list.map { |m| m["auth"] }
    assert_equal [false, true], list.map { |m| m["active"] }
  end

  def test_use_is_case_insensitive
    add_bearer("CRMLS")
    add_bearer("Other")
    result = cli("use", "crmls")
    assert result.success?, result.stderr
    assert_equal "CRMLS", result.json["active"]
    assert_equal "CRMLS", config_data["active"]

    missing = cli("use", "nope")
    refute missing.success?
    assert_match(/No MLS named 'nope'/, missing.stderr)
  end

  def test_remove_active_mls_picks_another
    add_bearer("A")
    add_bearer("B")
    result = cli("remove", "b")
    assert result.success?, result.stderr
    assert_equal "A", result.json["active"]
    assert_equal ["A"], config_data["mls"].keys

    cli("remove", "A")
    assert_equal({}, config_data["mls"])
    refute config_data.key?("active")
  end

  def test_config_file_is_private
    add_bearer("Private")
    assert_equal 0o600, File.stat(@config_path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(@config_path)).mode & 0o777
    assert_match(/Contains credentials/, File.read(@config_path))
  end

  def test_migrates_multi_mls_legacy_config
    legacy = File.join(@tmpdir, "legacy-mls.yml")
    File.write(legacy, { "active" => "Two", "mls" => {
      "One" => { "endpoint" => "https://one.example.com/odata", "authentication" => { "access_token" => "t1", "token_type" => "Bearer" } },
      "Two" => { "endpoint" => "https://two.example.com/odata", "authentication" => { "access_token" => "t2", "token_type" => "Bearer" } }
    } }.to_yaml)

    result = cli("mls")
    assert result.success?
    assert_match(/Moved your MLS config/, result.stderr)
    assert_equal %w[One Two], result.json.map { |m| m["name"] }
    assert_equal "Two", config_data["active"]
    assert File.exist?(legacy), "migration copies; it never deletes the old file"
  end

  def test_migrates_original_single_mls_legacy_config
    legacy = File.join(@tmpdir, "legacy-mls.yml")
    File.write(legacy, { "endpoint" => "https://one.example.com/odata",
                         "authentication" => { "access_token" => "t1", "token_type" => "Bearer" } }.to_yaml)

    result = cli("mls")
    assert result.success?
    assert_equal [{ "name" => "default", "endpoint" => "https://one.example.com/odata", "auth" => "bearer", "active" => true }],
                 result.json
  end

  def test_existing_config_is_never_overwritten_by_migration
    add_bearer("Current")
    File.write(File.join(@tmpdir, "legacy-mls.yml"), { "mls" => { "Old" => { "endpoint" => "https://old.example.com/odata" } } }.to_yaml)
    assert_equal ["Current"], cli("mls").json.map { |m| m["name"] }
  end
end
