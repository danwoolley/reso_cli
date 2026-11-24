require "test_helper"

# Health checks (test --all), token expiry, metadata refresh, and retrying throttled requests.
class HealthTest < Minitest::Test
  include CliHelper

  # -- token expiry --

  def test_mls_shows_bearer_token_expiry
    add_bearer("Fresh", token: jwt_expiring_at(Time.now + 3 * 3600 + 120))
    add_bearer("Stale", token: jwt_expiring_at(Time.now - 60))
    add_bearer("Opaque", token: "not-a-jwt")

    list = cli("mls").json.to_h { |m| [m["name"], m] }
    refute list["Fresh"]["token_expired"]
    assert_match(/\A3h \d+m\z/, list["Fresh"]["token_expires_in"])
    assert list["Stale"]["token_expired"]
    refute list["Stale"].key?("token_expires_in")
    refute list["Opaque"].key?("token_expires"), "tokens that aren't JWTs have no known expiry"
  end

  def test_expired_token_hint
    entry = { "authentication" => { "access_token" => jwt_expiring_at(Time.now - 60) } }
    message = ResoCli.send(:with_expiry_hint, "credentials rejected (HTTP 401)", entry)
    assert_match(/bearer token expired at .*replace it with \/mls-setup/, message)

    fresh = { "authentication" => { "access_token" => jwt_expiring_at(Time.now + 600) } }
    assert_equal "x", ResoCli.send(:with_expiry_hint, "x", fresh)
  end

  def test_human_duration
    assert_equal "5m", ResoCli.send(:human_duration, 5 * 60 + 30)
    assert_equal "2h 5m", ResoCli.send(:human_duration, 2 * 3600 + 5 * 60)
    assert_equal "3d 4h", ResoCli.send(:human_duration, 76 * 3600)
  end

  # -- test --all --

  def test_test_all_reports_each_mls_and_fails_if_any_fail
    # Nothing listens on port 9 locally, so both connections fail fast and offline
    add_bearer("Down One", endpoint: "http://127.0.0.1:9/odata")
    add_bearer("Down Two", endpoint: "http://127.0.0.1:9/other/odata")

    result = cli("test", "--all")
    refute result.success?, "exit status is non-zero when any MLS fails"
    results = result.json
    assert_equal ["Down One", "Down Two"], results.map { |r| r["name"] }
    results.each do |r|
      refute r["ok"]
      assert_match(/could not connect/, r["error"])
    end
    assert_equal [false, true], results.map { |r| r["active"] }
  end

  # -- refresh --

  def test_refresh_all_clears_the_cache
    cache = File.join(@tmpdir, "cache")
    FileUtils.mkdir_p(cache)
    %w[metadata-aaa.xml metadata-bbb.xml keep.txt].each { |f| File.write(File.join(cache, f), "x") }

    result = cli("refresh", "--all")
    assert result.success?, result.stderr
    assert_equal 2, result.json["deleted"]
    assert_equal ["keep.txt"], Dir.children(cache)
  end

  # -- retries --

  class RetryTest < Minitest::Test
    def setup
      @waits = []
      ResoCli.send(:sleeper=, ->(s) { @waits << s })
    end

    def teardown
      ResoCli.send(:sleeper=, nil)
    end

    def error(status, headers = {})
      ResoTransport::RequestError.new(nil, { status: status, response_headers: headers }, "Property")
    end

    def retrying(&block)
      result = nil
      _out, @stderr = capture_io { result = ResoCli.send(:with_retries, &block) }
      result
    end

    def test_retries_throttled_requests_with_backoff
      calls = 0
      result = retrying do
        calls += 1
        raise error(429) if calls < 3
        :ok
      end
      assert_equal :ok, result
      assert_equal [1, 2], @waits
      assert_match(/busy \(HTTP 429\)/, @stderr)
    end

    def test_honors_retry_after
      calls = 0
      retrying do
        calls += 1
        raise error(503, "Retry-After" => "7") if calls == 1
        :ok
      end
      assert_equal [7], @waits
    end

    def test_caps_long_waits
      calls = 0
      retrying do
        calls += 1
        raise error(429, "retry-after" => "3600") if calls == 1
        :ok
      end
      assert_equal [60], @waits
    end

    def test_gives_up_after_max_attempts
      calls = 0
      assert_raises(ResoTransport::RequestError) do
        retrying do
          calls += 1
          raise error(429)
        end
      end
      assert_equal 4, calls
      assert_equal [1, 2, 4], @waits
    end

    def test_does_not_retry_other_errors
      calls = 0
      assert_raises(ResoTransport::RequestError) do
        retrying do
          calls += 1
          raise error(400)
        end
      end
      assert_equal 1, calls
      assert_empty @waits
    end
  end
end
