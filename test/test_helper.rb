require "minitest/autorun"
require "open3"
require "json"
require "yaml"
require "tmpdir"
require "rbconfig"

APP_ROOT = File.expand_path("..", __dir__)
FIXTURES = File.join(__dir__, "fixtures")

# Never touch the user's real config or a real in-repo config/mls.yml
ENV["RESO_CLI_LEGACY_CONFIG"] = File.join(Dir.tmpdir, "reso_cli-test-no-legacy-#{Process.pid}.yml")

require "reso_cli"

# Runs the real CLI (bin/reso_cli) in a subprocess against a throwaway config file.
module CliHelper
  Result = Struct.new(:stdout, :stderr, :status) do
    def success? = status.success?
    def json = JSON.parse(stdout)
  end

  def setup
    super
    @tmpdir = Dir.mktmpdir("reso_cli-test")
    @config_path = File.join(@tmpdir, "config", "mls.yml")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    super
  end

  def cli(*args, env: {})
    env = {
      "RESO_CLI_CONFIG" => @config_path,
      "RESO_CLI_LEGACY_CONFIG" => File.join(@tmpdir, "legacy-mls.yml"),
      "RESO_CLI_PWD" => @tmpdir
    }.merge(env)
    out, err, status = Open3.capture3(env, RbConfig.ruby, File.join(APP_ROOT, "bin", "reso_cli"), *args.map(&:to_s))
    Result.new(out, err, status)
  end

  def config_data = YAML.load_file(@config_path)

  def add_bearer(name, endpoint: "https://api.example.com/odata", token: "secret-token-xyz")
    result = cli("add", name, "--endpoint", endpoint, "--token", token)
    assert result.success?, result.stderr
    result
  end
end
