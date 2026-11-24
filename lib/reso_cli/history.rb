require "date"
require "time"

module ResoCli
  # Price and status history for a listing, Zillow-style: newest event first.
  # Uses the HistoryTransactional resource when the feed has it; otherwise builds
  # a shorter history from the listing record's own price/status/date fields.
  module History
    Event = Struct.new(:time, :event, :price, :change, keyword_init: true)

    STATUS_NAMES = {
      "ActiveUnderContract" => "Active Under Contract", "ComingSoon" => "Coming Soon"
    }.freeze

    module_function

    def time_of(value)
      case value
      when DateTime, Time then value.to_time.utc
      when Date then Time.utc(value.year, value.month, value.day)
      when /\A\d{4}-\d{2}-\d{2}\z/ then Time.utc(*value.split("-").map(&:to_i))
      when String then Time.iso8601(value).utc
      end&.then { |t| Time.at(t.to_i).utc } # whole seconds, so parts of one change group together
    rescue ArgumentError
      nil
    end

    def number(value)
      Float(value.to_s)
    rescue ArgumentError
      nil
    end

    def status_name(value) = STATUS_NAMES.fetch(value.to_s, DetailPage.spaced(value.to_s))

    def percent(from, to)
      return nil unless from && to && from.positive?

      pct = ((to - from) / from * 100).round(1)
      "#{pct.positive? ? '+' : ''}#{pct}%"
    end

    # Events from HistoryTransactional records (one record per changed field)
    def from_transactions(records)
      relevant = records.select { |r| %w[StandardStatus ListPrice ClosePrice].include?(r["FieldName"].to_s) }
      relevant.group_by { |r| [time_of(r["ModificationTimestamp"]), r["ChangeType"].to_s] }.filter_map do |(time, change_type), group|
        next unless time

        by_field = group.to_h { |r| [r["FieldName"], r] }
        status = by_field["StandardStatus"]
        price = by_field["ListPrice"]
        close = by_field["ClosePrice"]
        new_price = number(price&.dig("NewValue"))
        old_price = number(price&.dig("PreviousValue"))

        if change_type.match?(/new listing/i)
          Event.new(time: time, event: "Listed#{status ? " (#{status_name(status['NewValue'])})" : ''}", price: new_price)
        elsif price && !status
          Event.new(time: time, event: "Price #{new_price && old_price && new_price < old_price ? 'cut' : 'change'}",
                    price: new_price, change: percent(old_price, new_price))
        elsif status
          to = status_name(status["NewValue"])
          from = status["PreviousValue"].to_s.empty? || status["PreviousValue"] == "Other" ? nil : status_name(status["PreviousValue"])
          label = to.match?(/closed/i) ? "Sold" : to
          label = "#{label} (was #{from})" if from && !to.match?(/closed/i)
          Event.new(time: time, event: label, price: number(close&.dig("NewValue")) || new_price)
        elsif close
          Event.new(time: time, event: "Sold", price: number(close["NewValue"]))
        end
      end.then { |events| newest_first(events) }
    end

    # Newest first; at the same moment, "Listed" goes below the change that followed it
    def newest_first(events) = events.sort_by { |e| [-e.time.to_f, e.event.start_with?("Listed") ? 1 : 0] }

    # A shorter history from the listing record itself, for feeds without HistoryTransactional
    def from_record(l)
      events = []
      listed_at = time_of(l["OnMarketTimestamp"] || l["OnMarketDate"] || l["ListingContractDate"])
      original = number(l["OriginalListPrice"])
      events << Event.new(time: listed_at, event: "Listed", price: original || number(l["ListPrice"])) if listed_at

      price_changed = time_of(l["PriceChangeTimestamp"] || l["DerivedPriceChangeTimestamp"])
      previous = number(l["PreviousListPrice"] || l["DerivedPreviousListPrice"])
      current = number(l["ListPrice"])
      if price_changed && previous && current && previous != current
        events << Event.new(time: price_changed, event: "Price #{current < previous ? 'cut' : 'change'}", price: current, change: percent(previous, current))
      end

      status_changed = time_of(l["StatusChangeTimestamp"] || l["DerivedStatusChangeTimestamp"])
      previous_status = l["PreviousStandardStatus"] || l["DerivedPreviousStatus"]
      status = l["StandardStatus"].to_s
      closed = time_of(l["CloseDate"])
      if closed && status.match?(/closed/i)
        events << Event.new(time: closed, event: "Sold", price: number(l["ClosePrice"]))
      elsif status_changed && !previous_status.to_s.empty? && previous_status.to_s != status
        # No price: the record only has today's price, not the price at the time of the status change
        events << Event.new(time: status_changed, event: "#{status_name(status)} (was #{status_name(previous_status)})")
      end

      newest_first(events.uniq { |e| [e.time, e.event] })
    end
  end
end
