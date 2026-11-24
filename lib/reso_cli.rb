require "reso_transport"
require "json"
require "yaml"
require "fileutils"
require "logger"
require "digest"

module ResoCli
  CONFIG_PATH = File.join(File.expand_path("../..", __FILE__), "config", "mls.yml")
  CACHE_DIR   = File.expand_path("~/.cache/mls")

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
      when "help", nil, "-h", "--help" then cmd_help
      else
        abort "Unknown command: #{command}. Run 'reso_cli help' for usage."
      end
    rescue ResoTransport::AccessDenied => e
      abort "Error: #{e.message}"
    rescue ResoTransport::RequestError => e
      abort "Error: #{e.message}"
    rescue => e
      abort "Error: #{e.class}: #{e.message}"
    end

    private

    # Settings for the active MLS (endpoint, authentication, localizations, ...)
    def config
      @config ||= begin
        name = active_mls_name
        entry = mls_entries[name]
        abort "Active MLS '#{name}' is not defined in #{CONFIG_PATH}. Run 'reso_cli mls' to list MLSs." unless entry
        symbolize(entry)
      end
    end

    # Raw contents of config/mls.yml. The file is checked in empty, so treat
    # empty/blank as "no MLSs configured".
    def config_file
      @config_file ||= begin
        abort "Config not found at #{CONFIG_PATH}. Run /mls-setup in Claude Code to add an MLS." unless File.exist?(CONFIG_PATH)
        data = YAML.load_file(CONFIG_PATH) || {}
        abort "Invalid config in #{CONFIG_PATH}: expected a mapping" unless data.is_a?(Hash)
        data
      end
    end

    def mls_entries
      entries = config_file["mls"] || {}
      abort "No MLSs configured in #{CONFIG_PATH}. Run /mls-setup in Claude Code to add one." if entries.empty?
      entries
    end

    def active_mls_name
      name = config_file["active"]
      return name if name
      return mls_entries.keys.first if mls_entries.size == 1
      abort "No active MLS set. Choose one with 'reso_cli use NAME' (see 'reso_cli mls')."
    end

    def find_mls_name(query)
      names = mls_entries.keys
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
                "Set in #{CONFIG_PATH}:\n  localizations:\n    #{name}: <choice>"
        end
      end

      resource
    end

    # -- Commands --

    # List configured MLSs (never prints credentials)
    def cmd_mls(_args)
      active = config_file["active"] || (mls_entries.size == 1 ? mls_entries.keys.first : nil)
      output = mls_entries.map do |name, entry|
        auth = entry["authentication"] || {}
        {
          name: name,
          endpoint: entry["endpoint"],
          auth: auth.key?("access_token") ? "bearer" : "oauth2",
          active: name == active
        }
      end
      puts JSON.pretty_generate(output)
    end

    # Set the active MLS by name (case-insensitive)
    def cmd_use(args)
      query = args.join(" ").strip
      abort "Usage: reso_cli use NAME (see 'reso_cli mls')" if query.empty?

      name = find_mls_name(query)
      abort "No MLS named '#{query}'. Available: #{mls_entries.keys.join(', ')}" unless name

      # Rewrite only the top-level `active:` line so comments/formatting survive.
      text = File.read(CONFIG_PATH)
      line = "active: #{name.to_json}"
      text = if text.match?(/^active:.*$/)
               text.sub(/^active:.*$/, line)
             else
               "#{line}\n#{text}"
             end
      File.write(CONFIG_PATH, text)
      puts JSON.pretty_generate(active: name, endpoint: mls_entries[name]["endpoint"])
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

        Config: config/mls.yml (one entry per MLS under `mls:`; `active:` picks one)

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
