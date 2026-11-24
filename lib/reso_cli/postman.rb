require "json"

module ResoCli
  # Reads MLS connection settings (auth + OData endpoint) out of a Postman
  # collection export, so users can set up an MLS from the collection their
  # vendor sent instead of copying credentials by hand.
  class Postman
    # One auth configuration found in the collection (collection-level or on a folder/request)
    Auth = Struct.new(:name, :type, :settings, :endpoints, keyword_init: true) do
      def oauth2? = type == "oauth2"
      def bearer? = type == "bearer"

      def token_url = settings["accessTokenUrl"] || settings["authUrl"]

      def usable?
        if oauth2?
          [token_url, settings["clientId"], settings["clientSecret"]].all? { |v| present?(v) }
        elsif bearer?
          present?(settings["token"])
        else
          false
        end
      end

      # Auth settings in reso_cli's config format
      def authentication
        if bearer?
          { "access_token" => settings["token"], "token_type" => "Bearer" }
        else
          auth = {
            "endpoint" => token_url,
            "client_id" => settings["clientId"],
            "client_secret" => settings["clientSecret"],
            "scope" => settings["scope"].to_s
          }
          grant = settings["grant_type"].to_s
          if grant == "password_credentials" || grant == "password"
            auth["grant_type"] = "password"
            auth["username"] = settings["username"]
            auth["password"] = settings["password"]
          end
          auth
        end
      end

      # Safe to print: no secrets or tokens
      def summary
        {
          name: name,
          type: type,
          usable: usable?,
          token_url: oauth2? ? token_url : nil,
          client_id: oauth2? ? settings["clientId"] : nil,
          scope: oauth2? ? settings["scope"].to_s : nil,
          endpoints: endpoints
        }.compact
      end

      private

      def present?(value) = value.is_a?(String) && !value.strip.empty? && !value.match?(/\{\{.*\}\}/)
    end

    attr_reader :path

    def initialize(path)
      @path = File.expand_path(path)
      abort "Postman collection not found: #{@path}" unless File.exist?(@path)
      @data = JSON.parse(File.read(@path))
      abort "Not a Postman collection: #{@path}" unless @data.is_a?(Hash) && @data["item"].is_a?(Array)
      @variables = (@data["variable"] || []).to_h { |v| [v["key"], v["value"]] }
    rescue JSON::ParserError => e
      abort "Could not read Postman collection #{@path}: #{e.message}"
    end

    def collection_name = @data.dig("info", "name")

    def auths
      @auths ||= begin
        found = []
        add_auth(found, "(collection)", @data["auth"], @data["item"])
        walk(@data["item"], [], found)
        # Drop repeats (e.g. collection-level auth copied onto a folder), keeping the most specific
        found.reverse.uniq { |a| [a.type, a.authentication] }.reverse
      end
    end

    # Pick an auth by name (case-insensitive). Without a name, use the only usable one.
    def find_auth(name = nil)
      usable = auths.select(&:usable?)
      if name
        auths.find { |a| a.name.casecmp?(name) } ||
          auths.find { |a| a.name.split("/").last.casecmp?(name) }
      elsif usable.size == 1
        usable.first
      end
    end

    private

    def walk(items, path, found)
      items.each do |item|
        item_path = path + [item["name"].to_s]
        add_auth(found, item_path.join("/"), item["auth"], item["item"] || [item])
        add_auth(found, item_path.join("/"), item.dig("request", "auth"), [item]) if item["request"]
        walk(item["item"], item_path, found) if item["item"]
      end
    end

    def add_auth(found, name, auth, items)
      return unless auth.is_a?(Hash) && %w[oauth2 bearer].include?(auth["type"])

      settings = (auth[auth["type"]] || []).to_h { |kv| [kv["key"], resolve(kv["value"])] }
      found << Auth.new(name: name, type: auth["type"], settings: settings, endpoints: service_roots(items))
    end

    # Replace {{variable}} references with collection variable values when they're set
    def resolve(value)
      return value unless value.is_a?(String)

      value.gsub(/\{\{([^}]+)\}\}/) do |ref|
        v = @variables[Regexp.last_match(1)]
        v.is_a?(String) && !v.empty? ? v : ref
      end
    end

    # OData service roots used by the requests under an item, most common first
    def service_roots(items)
      urls = []
      collect_urls(items, urls)
      roots = urls.filter_map { |u| u[%r{\Ahttps?://[^?#]*?/odata}i] }
      # Group case variants (/odata vs /OData) and keep each group's most common spelling
      roots.group_by(&:downcase).values
           .sort_by { |group| -group.size }
           .map { |group| group.tally.max_by { |_, n| n }.first }
    end

    def collect_urls(items, urls)
      items.each do |item|
        if (req = item["request"])
          url = req["url"].is_a?(Hash) ? req["url"]["raw"] : req["url"]
          urls << resolve(url.to_s)
        end
        collect_urls(item["item"], urls) if item["item"]
      end
    end
  end
end
