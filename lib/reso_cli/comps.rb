require "date"
require "time"

module ResoCli
  # Comparable sales ("comps"): recent closed sales near a listing with similar size and bedrooms,
  # ranked by similarity, plus a rough price-per-sq-ft value range. Not an appraisal.
  module Comps
    Comp = Struct.new(:record, :distance, :ppsf, :months_ago, :score, keyword_init: true)

    module_function

    def number(value) = value.is_a?(Numeric) ? value.to_f : nil

    def coordinates(listing)
      lat = number(listing["Latitude"])
      lng = number(listing["Longitude"])
      lat && lng && !(lat.zero? && lng.zero?) ? [lat, lng] : nil
    end

    # Great-circle distance in miles
    def distance_miles(lat1, lng1, lat2, lng2)
      rad = Math::PI / 180
      dlat = (lat2 - lat1) * rad
      dlng = (lng2 - lng1) * rad
      a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlng / 2)**2
      3958.8 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    # Latitude/longitude box that contains a circle of radius_miles
    def box(lat, lng, radius_miles)
      dlat = radius_miles / 69.0
      dlng = radius_miles / (69.172 * Math.cos(lat * Math::PI / 180)).abs
      [lat - dlat, lat + dlat, lng - dlng, lng + dlng].map { |v| v.round(6) }
    end

    # Search options (as for reso_cli search) for closed sales similar to the subject
    def criteria(subject, months:, radius:, today: Date.today)
      options = { eq: {}, ne: {}, gt: {}, ge: {}, lt: {}, le: {} }
      options[:eq]["StandardStatus"] = "Closed"
      options[:eq]["PropertyType"] = subject["PropertyType"] if subject["PropertyType"]
      # Same kind of home: single-family homes and condos sell for very different amounts per sq ft
      options[:eq]["PropertySubType"] = subject["PropertySubType"] unless Compare.empty?(subject["PropertySubType"])
      options[:ge]["CloseDate"] = (today << months).iso8601

      if (coords = coordinates(subject))
        lat_min, lat_max, lng_min, lng_max = box(*coords, radius)
        options[:ge]["Latitude"] = lat_min
        options[:le]["Latitude"] = lat_max
        options[:ge]["Longitude"] = lng_min
        options[:le]["Longitude"] = lng_max
      elsif subject["PostalCode"]
        options[:eq]["PostalCode"] = subject["PostalCode"].to_s
      elsif subject["City"]
        options[:eq]["City"] = subject["City"].to_s
      end

      if (area = number(subject["LivingArea"])) && area.positive?
        options[:ge]["LivingArea"] = (area * 0.75).round
        options[:le]["LivingArea"] = (area * 1.25).round
      end
      if (beds = number(subject["BedroomsTotal"]))
        options[:ge]["BedroomsTotal"] = [beds.to_i - 1, 0].max
        options[:le]["BedroomsTotal"] = beds.to_i + 1
      end
      options
    end

    def close_time(record)
      value = record["CloseDate"]
      case value
      when Date then value
      when Time, DateTime then value.to_date
      when String then Date.parse(value)
      end
    rescue ArgumentError
      nil
    end

    # Score candidates (lower = more similar) and return the best `max`, most similar first
    def rank(subject, candidates, radius:, months:, max:, today: Date.today)
      coords = coordinates(subject)
      area = number(subject["LivingArea"])
      beds = number(subject["BedroomsTotal"])
      comps = candidates.filter_map do |c|
        next if c["ListingId"].to_s == subject["ListingId"].to_s

        price = number(c["ClosePrice"])
        sqft = number(c["LivingArea"])
        closed = close_time(c)
        next unless price&.positive? && sqft&.positive? && closed

        c_coords = coordinates(c)
        distance = coords && c_coords ? distance_miles(*coords, *c_coords) : nil
        next if distance && distance > radius

        months_ago = ((today - closed).to_f / 30.44).round(1)
        score = 0.0
        score += distance / radius if distance
        score += 2.0 * (sqft - area).abs / area if area&.positive?
        score += 0.5 * (number(c["BedroomsTotal"]).to_f - beds).abs if beds
        score += 0.5 * months_ago / months
        Comp.new(record: c, distance: distance, ppsf: price / sqft, months_ago: months_ago, score: score.round(3))
      end
      comps.sort_by(&:score).first(max)
    end

    def percentile(sorted, p)
      return nil if sorted.empty?

      rank = (sorted.size - 1) * p
      lower = sorted[rank.floor]
      upper = sorted[rank.ceil]
      lower + (upper - lower) * (rank - rank.floor)
    end

    # Median and middle-half price per sq ft, and what that implies for the subject's size
    def estimate(subject, comps)
      ppsf = comps.map(&:ppsf).sort
      return nil if ppsf.size < 3

      result = { median_ppsf: percentile(ppsf, 0.5), low_ppsf: percentile(ppsf, 0.25), high_ppsf: percentile(ppsf, 0.75) }
      if (area = number(subject["LivingArea"])) && area.positive?
        result[:value] = (result[:median_ppsf] * area).round(-3)
        result[:low] = (result[:low_ppsf] * area).round(-3)
        result[:high] = (result[:high_ppsf] * area).round(-3)
      end
      result
    end
  end
end
