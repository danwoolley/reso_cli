require "date"
require "time"

module ResoCli
  # Field-by-field comparison of the same listing from two feeds (e.g. an aggregator vs. the native MLS).
  module Compare
    # Fields each system stamps for itself (keys, IDs, signatures, its own modification time).
    # Differences here are expected, so they're reported as "system", not as discrepancies.
    SYSTEM_FIELD = /Key(Numeric)?\z|\AId\z|\ACId|Signature|EntityEvent|Replication|\AModificationTimestamp\z|\ASourceSystem/

    STATUSES = {
      different: "Different",
      format: "Same value, different format",
      only_a: "Only in %{a}",
      only_b: "Only in %{b}",
      system: "System field (expected to differ)",
      same: "Same"
    }.freeze

    module_function

    def empty?(value) = value.nil? || value == "" || value == [] || value == {}

    # Canonical form used for strict equality
    def normalize(value)
      case value
      when nil then nil
      when DateTime, Time then value.to_time.utc.iso8601
      when Date then value.iso8601
      when Float then value == value.to_i ? value.to_i : value
      when Array then value.map { |v| normalize(v) }
      when Hash then value.transform_values { |v| normalize(v) }
      when /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
        begin
          Time.iso8601(value).utc.iso8601
        rescue ArgumentError
          value
        end
      when String then value.strip
      else value
      end
    end

    # Looser form: ignores case, spacing, punctuation (e.g. phone dashes), a URL's http(s)://,
    # list order, and numbers sent as text. Numbers are compared exactly, never rounded.
    def loose(value)
      v = normalize(value)
      case v
      when Array then v.map { |x| loose(x) }.sort_by(&:to_s)
      when Numeric then loose_number(v)
      when String
        if v.match?(/\A-?\d+(\.\d+)?\z/)
          loose_number(v.to_f)
        else
          v.sub(%r{\Ahttps?://}i, "").downcase.gsub(/[^a-z0-9]/, "")
        end
      else v
      end
    end

    def loose_number(n)
      f = n.to_f
      f == f.to_i ? f.to_i.to_s : f.to_s
    end

    def status(field, a, b)
      return :both_empty if empty?(a) && empty?(b)
      return :only_b if empty?(a)
      return :only_a if empty?(b)
      return :same if normalize(a) == normalize(b)
      return :system if field.match?(SYSTEM_FIELD)
      return :format if loose(a) == loose(b)

      :different
    end

    # One row per field present in either record (Media and @odata annotations excluded)
    def compare(a, b)
      fields = (a.keys | b.keys).reject { |f| f == "Media" || f.start_with?("@odata") }
      fields.filter_map do |field|
        st = status(field, a[field], b[field])
        next if st == :both_empty

        { field: field, status: st, a: a[field], b: b[field] }
      end
    end

    def summary(rows)
      counts = STATUSES.keys.to_h { |k| [k, 0] }
      rows.each { |r| counts[r[:status]] += 1 }
      counts
    end

    def status_label(status, a_name, b_name) = format(STATUSES.fetch(status), a: a_name, b: b_name)
  end
end
