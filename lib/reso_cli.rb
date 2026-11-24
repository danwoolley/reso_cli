require "reso_transport"
require "json"
require "yaml"
require "fileutils"
require "logger"
require "digest"
require "optparse"
require_relative "reso_cli/postman"

module ResoCli
  APP_ROOT           = File.expand_path("../..", __FILE__)
  # Where MLS configs lived before they moved out of the repo; migrated automatically
  LEGACY_CONFIG_PATH = File.join(APP_ROOT, "config", "mls.yml")
  CACHE_DIR          = File.expand_path("~/.cache/mls")
  CONFIG_HEADER      = <<~YAML
    # reso_cli MLS connections. Contains credentials: don't commit or share this file.
    # Managed by `reso_cli add / use / remove` (or /mls-setup and /mls-use in Claude Code).
  YAML

  class << self
    def run(args)
      command = args.shift

      case command
      when "resources" then cmd_resources(args)
      when "fields"    then cmd_fields(args)
      when "search"    then cmd_search(args)
      when "get"       then cmd_get(args)
      when "count"     then cmd_count(args)
      when "mls"       then cmd_mls(args)
      when "use"       then cmd_use(args)
      when "add"       then cmd_add(args)
      when "remove"    then cmd_remove(args)
      when "test"      then cmd_test(args)
      when "postman"   then cmd_postman(args)
      when "help", nil, "-h", "--help" then cmd_help
      else
        abort "Unknown command: #{command}. Run 'reso_cli help' for usage."
      end
    rescue ResoTransport::AccessDenied => e
      abort "Error: #{e.message}"
    rescue ResoTransport::RequestError => e
      abort "Error: #{e.message}"
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
      abort "Error: Could not connect to #{@config&.dig(:endpoint) || 'the MLS server'} (#{e.message}).\n" \
            "Check the URL and your network/VPN. Some MLSs only accept connections from approved IP addresses."
    rescue => e
      abort "Error: #{e.class}: #{e.message}"
    end

    private

    # -- Config storage --
    #
    # MLS connections live outside the repo (so credentials can't be committed):
    #   $RESO_CLI_CONFIG, or $XDG_CONFIG_HOME/reso_cli/mls.yml, or ~/.config/reso_cli/mls.yml
    # Format: { "active" => NAME, "mls" => { NAME => { "endpoint" => ..., "authentication" => {...} } } }

    def config_path
      @config_path ||= begin
        base = ENV["XDG_CONFIG_HOME"].to_s.empty? ? "~/.config" : ENV["XDG_CONFIG_HOME"]
        File.expand_path(ENV["RESO_CLI_CONFIG"].to_s.empty? ? File.join(base, "reso_cli", "mls.yml") : ENV["RESO_CLI_CONFIG"])
      end
    end

    # Settings for the active MLS (endpoint, authentication, localizations, ...)
    def config
      @config ||= begin
        name = active_mls_name
        entry = mls_entries[name]
        abort "Active MLS '#{name}' is not defined. Run 'reso_cli mls' to list MLSs." unless entry
        symbolize(entry)
      end
    end

    # Parsed config file; a missing or empty file means "no MLSs yet"
    def config_file
      @config_file ||= begin
        migrate_legacy_config
        data = File.exist?(config_path) ? (YAML.load_file(config_path) || {}) : {}
        abort "Invalid config in #{config_path}: expected a mapping" unless data.is_a?(Hash)
        data["mls"] ||= {}
        data
      end
    end

    def save_config(data)
      dir = File.dirname(config_path)
      FileUtils.mkdir_p(dir, mode: 0o700)
      tmp = "#{config_path}.tmp-#{Process.pid}"
      File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |f|
        f.write(CONFIG_HEADER + "\n" + data.to_yaml.delete_prefix("---\n"))
      end
      File.rename(tmp, config_path)
      @config_file = nil
      @config = nil
    end

    # Move a config from the old in-repo location (config/mls.yml) to config_path.
    # Handles both the multi-MLS format and the original single-MLS format.
    def migrate_legacy_config
      return if File.exist?(config_path) || !File.exist?(LEGACY_CONFIG_PATH)

      legacy = YAML.load_file(LEGACY_CONFIG_PATH)
      return unless legacy.is_a?(Hash) && !legacy.empty?

      data = if legacy["mls"].is_a?(Hash)
               legacy
             elsif legacy["endpoint"]
               { "active" => "default", "mls" => { "default" => legacy } }
             end
      return unless data

      save_config(data)
      warn "Moved your MLS config from #{LEGACY_CONFIG_PATH} to #{config_path}.\n" \
           "You can delete #{LEGACY_CONFIG_PATH}; it's no longer used and contains credentials."
    end

    def mls_entries(require_any: true)
      entries = config_file["mls"]
      abort "No MLSs configured yet. Run /mls-setup in Claude Code (or 'reso_cli add') to add one." if require_any && entries.empty?
      entries
    end

    def active_mls_name
      name = config_file["active"]
      return name if name && mls_entries.key?(name)
      return mls_entries.keys.first if mls_entries.size == 1
      abort "No active MLS set. Choose one with 'reso_cli use NAME' (see 'reso_cli mls')."
    end

    def find_mls_name(query)
      names = mls_entries(require_any: false).keys
      names.find { |n| n == query } || names.find { |n| n.casecmp?(query) }
    end

    def symbolize(obj)
      case obj
      when Hash  then obj.to_h { |k, v| [k.to_sym, symbolize(v)] }
      when Array then obj.map { |v| symbolize(v) }
      else obj
      end
    end

    # One metadata cache file per endpoint, so switching MLS configs
    # never reuses another server's metadata.
    def metadata_cache_path
      key = Digest::SHA256.hexdigest(config[:endpoint].to_s)[0, 12]
      File.join(CACHE_DIR, "metadata-#{key}.xml")
    end

    def client
      @client ||= begin
        FileUtils.mkdir_p(CACHE_DIR)

        null_logger = Logger.new(File::NULL)

        ResoTransport::Client.new(
          endpoint: config[:endpoint],
          authentication: config[:authentication],
          md_file: metadata_cache_path,
          use_replication_endpoint: config.fetch(:use_replication_endpoint, false),
          logger: null_logger
        )
      end
    end

    def resolve_resource(name)
      resource = client.resources[name]
      unless resource
        available = client.resources.keys.join(", ")
        abort "Resource '#{name}' not found. Available: #{available}"
      end

      if resource.localizations.any?
        loc = config.dig(:localizations, name.to_sym)
        if loc
          resource.localization(loc)
        else
          abort "Resource '#{name}' requires a localization.\n" \
                "Available: #{resource.localizations.keys.join(', ')}\n" \
                "Set it for this MLS in #{config_path}:\n  localizations:\n    #{name}: <choice>"
        end
      end

      resource
    end

    # -- Commands --

    def auth_type(entry)
      (entry["authentication"] || {}).key?("access_token") ? "bearer" : "oauth2"
    end

    # List configured MLSs (never prints credentials)
    def cmd_mls(_args)
      entries = mls_entries(require_any: false)
      warn "No MLSs configured yet. Run /mls-setup in Claude Code (or 'reso_cli add') to add one." if entries.empty?
      active = entries.empty? ? nil : active_mls_name_or_nil
      output = entries.map do |name, entry|
        { name: name, endpoint: entry["endpoint"], auth: auth_type(entry), active: name == active }
      end
      puts JSON.pretty_generate(output)
    end

    def active_mls_name_or_nil
      name = config_file["active"]
      return name if name && config_file["mls"].key?(name)
      config_file["mls"].size == 1 ? config_file["mls"].keys.first : nil
    end

    # Set the active MLS by name (case-insensitive)
    def cmd_use(args)
      query = args.join(" ").strip
      abort "Usage: reso_cli use NAME (see 'reso_cli mls')" if query.empty?

      name = find_mls_name(query)
      abort "No MLS named '#{query}'. Available: #{mls_entries.keys.join(', ')}" unless name

      data = config_file
      data["active"] = name
      save_config(data)
      puts JSON.pretty_generate(active: name, endpoint: data["mls"][name]["endpoint"])
    end

    # Add (or replace) an MLS connection and make it active.
    # Credentials come from flags or from a Postman collection; they're never printed.
    def cmd_add(args)
      opts = { scope: "", activate: true }
      parser = OptionParser.new do |o|
        o.banner = "Usage: reso_cli add NAME --endpoint URL (--token TOKEN | --token-url URL --client-id ID --client-secret SECRET [--scope SCOPE])\n" \
                   "       reso_cli add NAME --from-postman FILE [--postman-auth AUTH_NAME] [--endpoint URL]"
        o.on("--endpoint URL", "OData service root, e.g. https://api.example.com/odata") { |v| opts[:endpoint] = v }
        o.on("--token TOKEN", "Static bearer token") { |v| opts[:token] = v }
        o.on("--token-url URL", "OAuth2 token endpoint") { |v| opts[:token_url] = v }
        o.on("--client-id ID", "OAuth2 client ID") { |v| opts[:client_id] = v }
        o.on("--client-secret SECRET", "OAuth2 client secret") { |v| opts[:client_secret] = v }
        o.on("--scope SCOPE", "OAuth2 scope (default: none)") { |v| opts[:scope] = v }
        o.on("--from-postman FILE", "Read auth settings from a Postman collection") { |v| opts[:postman] = v }
        o.on("--postman-auth NAME", "Which auth in the collection to use (see 'reso_cli postman FILE')") { |v| opts[:postman_auth] = v }
        o.on("--replace", "Replace an existing MLS with the same name") { opts[:replace] = true }
        o.on("--no-activate", "Don't make the new MLS active") { opts[:activate] = false }
      end
      rest = parser.parse(args)
      name = rest.join(" ").strip
      abort parser.banner if name.empty?

      authentication = nil
      if opts[:postman]
        collection = Postman.new(opts[:postman])
        auth = collection.find_auth(opts[:postman_auth])
        unless auth
          names = collection.auths.select(&:usable?).map(&:name)
          abort "Choose which auth to use with --postman-auth. Options: #{names.join(', ')}" if names.any?
          abort "No usable OAuth2 or bearer-token settings found in #{collection.path}"
        end
        abort "The '#{auth.name}' auth in the collection is missing credentials" unless auth.usable?
        authentication = auth.authentication
        authentication["scope"] = opts[:scope] if opts[:scope] != "" && auth.oauth2?
        opts[:endpoint] ||= auth.endpoints.first
      elsif opts[:token]
        authentication = { "access_token" => opts[:token].strip, "token_type" => "Bearer" }
      elsif opts[:token_url] || opts[:client_id] || opts[:client_secret]
        missing = %i[token_url client_id client_secret].reject { |k| opts[k].to_s.strip != "" }
        abort "Missing for OAuth2: #{missing.map { |k| "--#{k.to_s.tr('_', '-')}" }.join(', ')}" if missing.any?
        authentication = {
          "endpoint" => opts[:token_url].strip,
          "client_id" => opts[:client_id].strip,
          "client_secret" => opts[:client_secret].strip,
          "scope" => opts[:scope].strip
        }
      else
        abort "Give credentials: --token, or --token-url/--client-id/--client-secret, or --from-postman FILE"
      end

      endpoint = opts[:endpoint].to_s.strip.sub(%r{/\$metadata\z}i, "").sub(%r{/+\z}, "")
      abort "Missing --endpoint (the OData service root URL)" if endpoint.empty?
      abort "Endpoint must start with http:// or https://" unless endpoint.match?(%r{\Ahttps?://}i)

      data = config_file
      existing = data["mls"].keys.find { |n| n.casecmp?(name) }
      if existing && !opts[:replace]
        abort "An MLS named '#{existing}' already exists. Use --replace to overwrite it, or choose another name."
      end
      data["mls"].delete(existing) if existing

      data["mls"][name] = { "endpoint" => endpoint, "authentication" => authentication }
      data["active"] = name if opts[:activate] || data["active"].nil?
      save_config(data)

      puts JSON.pretty_generate(
        added: name, endpoint: endpoint, auth: auth_type(data["mls"][name]),
        active: data["active"] == name, replaced: !existing.nil?, config: config_path
      )
    end

    def cmd_remove(args)
      query = args.join(" ").strip
      abort "Usage: reso_cli remove NAME (see 'reso_cli mls')" if query.empty?

      name = find_mls_name(query)
      abort "No MLS named '#{query}'. Available: #{mls_entries(require_any: false).keys.join(', ')}" unless name

      data = config_file
      data["mls"].delete(name)
      data["active"] = data["mls"].keys.first if data["active"] == name
      data.delete("active") if data["active"].nil?
      save_config(data)
      puts JSON.pretty_generate(removed: name, active: data["active"])
    end

    # Check that the active MLS accepts our credentials (always makes a live, authenticated request)
    def cmd_test(_args)
      name = active_mls_name
      response = client.connection.get("") { |req| req.headers["Accept"] = "application/json" }
      if [401, 403].include?(response.status)
        abort "Error: #{name} rejected the credentials (HTTP #{response.status}). Check them and run /mls-setup again to replace this MLS."
      end

      resources = client.resources
      puts JSON.pretty_generate(
        mls: name, endpoint: config[:endpoint], ok: true,
        http_status: response.status, resources: resources.keys
      )
    end

    # Show the auth settings in a Postman collection (never prints secrets)
    def cmd_postman(args)
      path = args.first
      abort "Usage: reso_cli postman FILE" unless path

      collection = Postman.new(path)
      puts JSON.pretty_generate(collection: collection.collection_name, auths: collection.auths.map(&:summary))
    end

    def cmd_resources(_args)
      resources = client.resources
      output = resources.map do |name, resource|
        entry = { name: name }
        entry[:localizations] = resource.localizations.keys if resource.localizations.any?
        entry
      end
      puts JSON.pretty_generate(output)
    end

    def cmd_fields(args)
      resource_name = args.shift
      abort "Usage: reso_cli fields RESOURCE [--match PATTERN]" unless resource_name

      pattern = nil
      if args[0] == "--match" && args[1]
        pattern = Regexp.new(args[1], Regexp::IGNORECASE)
      end

      resource = resolve_resource(resource_name)
      fields = resource.properties.map do |prop|
        { name: prop.name, type: prop.data_type }
      end

      fields.select! { |f| f[:name].match?(pattern) } if pattern

      puts JSON.pretty_generate(fields)
    end

    def cmd_search(args)
      options = parse_query_options(args)
      resource_name = options.delete(:resource)
      abort "Usage: reso_cli search RESOURCE [options]" unless resource_name

      resource = resolve_resource(resource_name)
      query = build_query(resource, options)

      results = query.results
      output = { count: results.length, results: results }
      output[:next_link] = query.next_link if query.next_link

      puts JSON.pretty_generate(output)
    end

    def cmd_get(args)
      resource_name = args.shift
      key = args.shift
      abort "Usage: reso_cli get RESOURCE KEY [--select FIELD1,FIELD2]" unless resource_name && key

      select_fields = nil
      if args[0] == "--select" && args[1]
        select_fields = args[1]
      end

      resource = resolve_resource(resource_name)

      url = "#{resource.url}('#{key}')"
      url += "?$select=#{select_fields}" if select_fields

      response = client.connection.get(url) do |req|
        req.headers["Accept"] = "application/json"
      end

      unless response.success?
        abort "Error: Received #{response.status} for #{resource_name}('#{key}')"
      end

      parsed = JSON.parse(response.body)
      resource.entity_type.parse(parsed)

      puts JSON.pretty_generate(parsed)
    end

    def cmd_count(args)
      options = parse_query_options(args)
      resource_name = options.delete(:resource)
      abort "Usage: reso_cli count RESOURCE [options]" unless resource_name

      resource = resolve_resource(resource_name)
      query = build_query(resource, options)

      total = query.count
      puts JSON.generate({ count: total })
    end

    def cmd_help
      puts <<~HELP
        reso_cli - Query the local MLS via RESO Web API

        Usage: reso_cli COMMAND [options]

        Commands:
          resources                     List available resources
          fields RESOURCE               List fields for a resource
          search RESOURCE [options]     Search records
          get RESOURCE KEY              Get a single record by key
          count RESOURCE [options]      Count matching records
          mls                           List configured MLSs (marks the active one)
          use NAME                      Switch the active MLS
          add NAME [options]            Add an MLS connection (run 'reso_cli add --help')
          remove NAME                   Remove an MLS connection
          test                          Check that the active MLS accepts your credentials
          postman FILE                  Show the MLS auth settings in a Postman collection
          help                          Show this help

        Search/Count Options:
          --eq FIELD=VALUE              Equality filter (repeatable)
          --ne FIELD=VALUE              Not-equal filter (repeatable)
          --gt FIELD=VALUE              Greater-than filter (repeatable)
          --ge FIELD=VALUE              Greater-or-equal filter (repeatable)
          --lt FIELD=VALUE              Less-than filter (repeatable)
          --le FIELD=VALUE              Less-or-equal filter (repeatable)
          --filter ODATA_EXPR           Raw OData $filter (overrides structured filters)
          --select FIELD1,FIELD2        Fields to return
          --expand ASSOC1,ASSOC2        Associations to expand
          --orderby "FIELD [desc]"      Sort order
          --top N                       Limit results
          --skip N                      Skip N results

        Fields Options:
          --match PATTERN               Regex to filter field names

        Get Options:
          --select FIELD1,FIELD2        Fields to return

        Config: ~/.config/reso_cli/mls.yml (override with RESO_CLI_CONFIG)

        Examples:
          reso_cli resources
          reso_cli fields Property
          reso_cli fields Property --match "List|Price"
          reso_cli search Property --eq City=Austin --ge ListPrice=500000 --top 10
          reso_cli search Property --filter "City eq 'Austin' and ListPrice ge 500000" --top 10
          reso_cli search Property --select ListingKey,City,ListPrice,BedroomsTotal --top 5
          reso_cli get Property 12345
          reso_cli get Property 12345 --select ListingKey,City,ListPrice
          reso_cli count Property --eq City=Austin
      HELP
    end

    # -- Query building --

    def build_query(resource, options)
      query = resource.query

      if options[:filter]
        query = query.set_query_params("$filter" => options[:filter])
      else
        options[:eq]&.each { |f, v| query = query.eq(f.to_sym => v) }
        options[:ne]&.each { |f, v| query = query.ne(f.to_sym => v) }
        options[:gt]&.each { |f, v| query = query.gt(f.to_sym => v) }
        options[:ge]&.each { |f, v| query = query.ge(f.to_sym => v) }
        options[:lt]&.each { |f, v| query = query.lt(f.to_sym => v) }
        options[:le]&.each { |f, v| query = query.le(f.to_sym => v) }
      end

      query = query.limit(options[:top]) if options[:top]
      query = query.offset(options[:skip]) if options[:skip]
      query = query.select(*options[:select]) if options[:select]
      query = query.expand(*options[:expand]) if options[:expand]

      if options[:orderby]
        parts = options[:orderby].split
        query = query.order(parts[0], parts[1]&.to_sym)
      end

      query
    end

    def parse_query_options(args)
      options = { eq: {}, ne: {}, gt: {}, ge: {}, lt: {}, le: {} }

      # First non-flag arg is the resource name
      options[:resource] = args.shift unless args.first&.start_with?("--")

      i = 0
      while i < args.length
        arg = args[i]
        val = args[i + 1]

        case arg
        when "--eq", "--ne", "--gt", "--ge", "--lt", "--le"
          abort "Missing value for #{arg}" unless val
          field, fval = val.split("=", 2)
          abort "Invalid format for #{arg}: expected FIELD=VALUE, got '#{val}'" unless fval
          op = arg.delete_prefix("--").to_sym
          options[op][field] = coerce_value(fval)
          i += 2
        when "--filter"
          abort "Missing value for --filter" unless val
          options[:filter] = val
          i += 2
        when "--select"
          abort "Missing value for --select" unless val
          options[:select] = val.split(",")
          i += 2
        when "--expand"
          abort "Missing value for --expand" unless val
          options[:expand] = val.split(",")
          i += 2
        when "--orderby"
          abort "Missing value for --orderby" unless val
          options[:orderby] = val
          i += 2
        when "--top"
          abort "Missing value for --top" unless val
          options[:top] = val.to_i
          i += 2
        when "--skip"
          abort "Missing value for --skip" unless val
          options[:skip] = val.to_i
          i += 2
        else
          abort "Unknown option: #{arg}. Run 'reso_cli help' for usage."
        end
      end

      options
    end

    def coerce_value(value)
      case value
      when /\A\d+\z/        then value.to_i
      when /\A\d+\.\d+\z/   then value.to_f
      when /\Atrue\z/i       then true
      when /\Afalse\z/i      then false
      else value
      end
    end
  end
end
