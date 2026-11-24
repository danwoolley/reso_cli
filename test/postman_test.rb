require "test_helper"

# Reading MLS auth settings from a Postman collection export.
class PostmanTest < Minitest::Test
  include CliHelper

  COLLECTION = File.join(FIXTURES, "postman_collection.json")

  def collection = ResoCli::Postman.new(COLLECTION)

  def test_finds_auth_setups_and_drops_duplicates
    names = collection.auths.map(&:name)
    # The collection-level auth repeats the "Public" folder's, so only the folder is kept
    assert_equal ["Public", "Back Office", "Token", "Broken"], names
  end

  def test_usable_and_unusable_auths
    by_name = collection.auths.to_h { |a| [a.name, a] }
    assert by_name["Public"].usable?
    assert by_name["Token"].usable?
    refute by_name["Broken"].usable?, "an empty {{variable}} secret is not usable"
  end

  def test_resolves_collection_variables
    bo = collection.find_auth("back office")
    assert_equal "resolved-secret-123", bo.authentication["client_secret"]
    assert_equal "api.read", bo.authentication["scope"]
  end

  def test_oauth_and_bearer_authentication_formats
    assert_equal({ "endpoint" => "https://auth.example.com/oauth2/token", "client_id" => "public-client",
                   "client_secret" => "public-secret", "scope" => "" },
                 collection.find_auth("Public").authentication)
    assert_equal({ "access_token" => "static-token-abc", "token_type" => "Bearer" },
                 collection.find_auth("Token").authentication)
  end

  def test_endpoints_come_from_requests_with_most_common_spelling
    # Two requests use /OData and one uses /odata: one endpoint, most common spelling
    assert_equal ["https://api.example.com/v2/OData"], collection.find_auth("Public").endpoints
    assert_equal ["https://token.example.com/reso/odata"], collection.find_auth("Token").endpoints
  end

  def test_find_auth_without_name_requires_a_single_usable_option
    assert_nil collection.find_auth, "several usable auths: the user has to choose"
  end

  def test_summary_never_includes_secrets
    output = collection.auths.map(&:summary).to_json
    refute_match(/public-secret|resolved-secret|static-token/, output)
    assert_match(/public-client/, output)
  end

  def test_cli_postman_command_hides_secrets
    result = cli("postman", COLLECTION)
    assert result.success?, result.stderr
    refute_match(/public-secret|resolved-secret|static-token/, result.stdout)
    assert_equal "Example MLS", result.json["collection"]
  end

  def test_cli_postman_resolves_paths_relative_to_where_it_was_run
    FileUtils.cp(COLLECTION, File.join(@tmpdir, "mine.json"))
    result = cli("postman", "mine.json") # RESO_CLI_PWD is @tmpdir
    assert result.success?, result.stderr
  end

  def test_cli_add_from_postman
    ambiguous = cli("add", "X", "--from-postman", COLLECTION)
    refute ambiguous.success?
    assert_match(/--postman-auth/, ambiguous.stderr)

    result = cli("add", "Example BO", "--from-postman", COLLECTION, "--postman-auth", "Back Office")
    assert result.success?, result.stderr
    refute_match(/resolved-secret/, result.stdout)
    assert_equal "https://bo.example.com/odata", result.json["endpoint"]
    assert_equal "resolved-secret-123", config_data["mls"]["Example BO"]["authentication"]["client_secret"]
  end

  def test_cli_add_from_postman_rejects_unusable_auth
    result = cli("add", "X", "--from-postman", COLLECTION, "--postman-auth", "Broken")
    refute result.success?
    assert_match(/missing credentials/, result.stderr)
  end
end
