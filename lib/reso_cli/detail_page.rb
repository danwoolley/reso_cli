require "json"
require "cgi"
require "time"
require "date"

module ResoCli
  # Builds a self-contained, portal-style listing detail page: photos, key facts,
  # description and map above the fold; every field in the listing record below it.
  module DetailPage
    # Which section a field belongs to. First match wins, so order matters.
    SECTION_RULES = [
      ["Agents & offices",        /Agent|Office|Team|Showing|LockBox|Lockbox|Owner|AttributionContact|SignOnProperty|Occupant|ListAOR/],
      ["Source & system",         /\A(Originating|SourceSystem|Derived|RawMls|CId|CLIP|Universal|EntityEvent|RecordSignature|HumanModified|Id\z)|Key(Numeric)?\z|ModificationTimestamp|Photos|Media|Documents|\AInternet|IDX|VOW|Syndicat|Permission|Replication/],
      ["Schools",                 /School/],
      ["Community & HOA",         /Association|Community|Senior|Pets|CommonInterest|Amenit/],
      ["Financial & tax",         /Tax|Assessment|Fee(?!t)|Financ|Income|Expense|Rent|Insurance|Mortgage|Assum/],
      ["Price & listing history", /Price|Close|ListingContract|ListingTerms|ListingAgreement|ListingService|SpecialListing|Possession|Disclosure|Concession|Contingen|DaysOnMarket|Status|MajorChange|OnMarket|Activation|StartShowing|OriginalEntry|Expiration|Withdrawn|Cancel|OffMarket|PurchaseContract|Compensation|BuyerAgency|DualOrVariable|LeaseConsidered|LandLease/],
      ["Interior",                /Bedroom|Bathroom|Room|LivingArea|BuildingArea|AboveGrade|BelowGrade|Interior|Floor|Appliance|Fireplace|Heating|Cooling|Laundry|Basement|Attic|Window|Door|Accessibility|Levels|Stories|EntryLevel|EntryLocation|CommonWalls|Furnished|Security|MainLevel/],
      ["Exterior & lot",          /Lot|Exterior|Roof|Construction|Foundation|Pool|Spa|Fenc|Patio|Porch|View|Waterfront|Garage|Parking|Carport|Driveway|Structure|Architectural|YearBuilt|PropertyCondition|Builder|Horse|Vegetation|Topography|Frontage|Road|Attached|Covered|Elevation/],
      ["Utilities & energy",      /Utilit|Water|Sewer|Electric|Gas|Green|Solar|Power|Irrigation/],
      ["Location",                /Address|Street|City|County|State|Postal|Country|Latitude|Longitude|Directions|Subdivision|MLSArea|Zoning|Parcel|CrossStreet|Township|Map|Unit/],
      ["Property",                /PropertyType|PropertySubType|NumberOfUnits|Ownership|Business/],
      ["Remarks",                 /Remarks|Description/]
    ].freeze

    SECTION_ORDER = [
      "Interior", "Exterior & lot", "Property", "Community & HOA", "Utilities & energy", "Location", "Schools",
      "Financial & tax", "Price & listing history", "Agents & offices", "Remarks", "Other", "Source & system"
    ].freeze

    LABELS = {
      "ListingId" => "MLS #", "ListPrice" => "List price", "StandardStatus" => "Status", "MlsStatus" => "MLS status",
      "BedroomsTotal" => "Bedrooms", "BathroomsTotalInteger" => "Bathrooms", "LivingArea" => "Living area",
      "UnparsedAddress" => "Address", "PublicRemarks" => "Description", "YearBuilt" => "Year built",
      "LotSizeSquareFeet" => "Lot size (sq ft)", "LotSizeAcres" => "Lot size (acres)", "MLSAreaMajor" => "MLS area"
    }.freeze

    # Fields that hold money (unless they're really counts, percentages or frequencies)
    MONEY  = /Price|Amount\z|Fee(?!t)|Tax(?!Lot|Year|Block|Book|Map|Legal|Tract|Status|Exemption)|Assessment|Expense|Income|Rent(?!al)|Compensation/
    NOT_MONEY = /Percent|Frequency|Count|Year|Includes|Timestamp|Date|Type|YN\z|Change(?!Amount)|Source|Units?\z|Paid|Calculation/

    module_function

    def section_for(field)
      SECTION_RULES.each { |name, rule| return name if field.match?(rule) }
      "Other"
    end

    def label(field)
      return LABELS[field] if LABELS.key?(field)

      yes_no = field.end_with?("YN") # e.g. CoolingYN -> "Cooling?", so it doesn't clash with Cooling
      words = field.sub(/YN\z/, "").split(/(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/)
      words = words.each_with_index.map do |w, i|
        next w if w.match?(/\A[A-Z0-9]{2,}\z/) # acronyms: MLS, HOA, AOR, URL

        i.zero? ? w.capitalize : w.downcase
      end
      words.join(" ") + (yes_no ? "?" : "")
    end

    def empty?(value) = value.nil? || value == "" || value == [] || value == {}

    def commas(n) = n.to_s.reverse.scan(/\d{1,3}/).join(",").reverse

    def money(n)
      whole = n.round
      sign = n.negative? ? "-" : ""
      (n - n.truncate).abs < 0.005 ? "#{sign}$#{commas(whole.abs)}" : format("%s$%s.%02d", sign, commas(n.abs.truncate), ((n.abs - n.abs.truncate) * 100).round)
    end

    def number(field, n)
      return money(n) if field.match?(MONEY) && !field.match?(NOT_MONEY)
      return "#{n}%" if field.match?(/Percent/)
      return "#{commas(n.round)} sq ft" if field.match?(/SquareFeet\z|LivingArea\z|BuildingArea\z|AboveGradeFinishedArea\z|BelowGradeFinishedArea\z/)
      return "#{n.round(2)} acres" if field.match?(/Acres\z/)
      return n.to_s if field.match?(/Latitude|Longitude/)

      n = n.to_i if n.is_a?(Float) && n == n.to_i
      # Thousands separators only for quantities; IDs, keys and codes stay as-is
      quantity = field.match?(/Area|Feet|Size|Count|NumberOf|Total|Units|Spaces/) && !field.match?(/Id\z|Key|Numeric\z/)
      quantity && n.is_a?(Integer) && n.abs >= 1_000 ? commas(n) : n.to_s
    end

    def timestamp(str)
      t = Time.iso8601(str)
      t.utc.strftime("%b %-d, %Y, %-I:%M %p UTC")
    rescue ArgumentError
      str
    end

    def date(str)
      Time.strptime(str, "%Y-%m-%d").strftime("%b %-d, %Y")
    rescue ArgumentError
      str
    end

    # Plain-text form of a value (used for search and in tests)
    def text(field, value)
      case value
      when nil then "—"
      when true then "Yes"
      when false then "No"
      when Numeric then number(field, value)
      when Array then value.map { |v| v.is_a?(Hash) ? JSON.generate(v) : spaced(text(field, v)) }.join(", ")
      when Hash then JSON.generate(value)
      # reso_transport turns Edm.DateTimeOffset / Edm.Date values into Ruby objects
      when DateTime, Time then value.to_time.utc.strftime("%b %-d, %Y, %-I:%M %p UTC")
      when Date then value.strftime("%b %-d, %Y")
      when /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/ then timestamp(value)
      when /\A\d{4}-\d{2}-\d{2}\z/ then date(value)
      else value.to_s
      end
    end

    # Lookup values in lists sometimes arrive as run-together words ("CashToNewLoan"); space them out
    def spaced(str)
      return str unless str.match?(/\A[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\z/)

      str.gsub(/(?<=[a-z0-9])(?=[A-Z])/, " ")
    end

    # HTML form of a value: like text, but links URLs and emails
    def html_value(field, value)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      if value.is_a?(String) && value.match?(%r{\Ahttps?://\S+\z}i)
        %(<a href="#{h.(value)}" target="_blank" rel="noopener noreferrer">#{h.(value)}</a>)
      elsif value.is_a?(String) && value.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
        %(<a href="mailto:#{h.(value)}">#{h.(value)}</a>)
      else
        h.(text(field, value))
      end
    end

    # Fields grouped into sections, in display order: { section => [[field, value], ...] }
    def sections(listing)
      grouped = Hash.new { |hash, k| hash[k] = [] }
      listing.each do |field, value|
        next if field == "Media" || field.start_with?("@odata")

        grouped[section_for(field)] << [field, value]
      end
      SECTION_ORDER.filter_map do |name|
        fields = grouped[name]
        next if fields.empty?

        [name, fields.sort_by { |f, _| label(f).downcase }]
      end.to_h
    end

    # Short facts for the grid above the fold, skipping anything not in the record
    def key_facts(l)
      facts = []
      add = ->(label, value) { facts << [label, value] unless empty?(value) }
      add.("Type", [l["PropertySubType"], l["PropertyType"]].compact.first)
      add.("Year built", l["YearBuilt"]&.to_s)
      lot = if l["LotSizeSquareFeet"].is_a?(Numeric) && l["LotSizeSquareFeet"].positive?
              "#{commas(l['LotSizeSquareFeet'].round)} sq ft lot"
            elsif l["LotSizeAcres"].is_a?(Numeric) && l["LotSizeAcres"].positive?
              "#{l['LotSizeAcres'].round(2)} acre lot"
            end
      add.("Lot", lot)
      if l["ListPrice"].is_a?(Numeric) && l["LivingArea"].is_a?(Numeric) && l["LivingArea"].positive?
        add.("Price/sq ft", money((l["ListPrice"] / l["LivingArea"]).round))
      end
      if l["AssociationFee"].is_a?(Numeric) && l["AssociationFee"].positive?
        add.("HOA", [money(l["AssociationFee"]), l["AssociationFeeFrequency"]&.downcase].compact.join(" "))
      elsif l["AssociationYN"] == false
        add.("HOA", "None")
      end
      parking = if l["GarageSpaces"].is_a?(Numeric) && l["GarageSpaces"].positive?
                  "#{number('GarageSpaces', l['GarageSpaces'])}-car garage"
                elsif l["ParkingTotal"].is_a?(Numeric) && l["ParkingTotal"].positive?
                  "#{number('ParkingTotal', l['ParkingTotal'])} spaces"
                end
      add.("Parking", parking)
      add.("Cooling", Array(l["Cooling"]).reject { |c| c.to_s.match?(/\Anone\z/i) }.join(", "))
      add.("Heating", Array(l["Heating"]).reject { |c| c.to_s.match?(/\Anone\z/i) }.join(", "))
      add.("Stories", l["StoriesTotal"]&.to_s || l["Stories"]&.to_s)
      add.("Days on market", l["DaysOnMarket"]&.to_s)
      add.("Pool", "Private pool") if l["PoolPrivateYN"] == true
      add.("View", Array(l["View"]).reject { |c| c.to_s.match?(/\Anone\z/i) }.join(", "))
      facts
    end

    def address_hidden?(l) = l["InternetAddressDisplayYN"] == false

    def coordinates(l)
      lat = l["Latitude"]
      lng = l["Longitude"]
      return nil unless lat.is_a?(Numeric) && lng.is_a?(Numeric) && !(lat.zero? && lng.zero?)

      [lat, lng]
    end

    # OpenStreetMap's own embeddable map (no API key; tiles load from openstreetmap.org)
    def map_embed_url(lat, lng)
      d_lat = 0.004
      d_lng = 0.006
      bbox = [lng - d_lng, lat - d_lat, lng + d_lng, lat + d_lat].map { |v| format("%.6f", v) }.join(",")
      "https://www.openstreetmap.org/export/embed.html?bbox=#{CGI.escape(bbox)}&layer=mapnik&marker=#{format('%.6f', lat)}%2C#{format('%.6f', lng)}"
    end

    def headline_price(l)
      if l["StandardStatus"].to_s.match?(/closed/i) && l["ClosePrice"].is_a?(Numeric)
        ["Sold #{money(l['ClosePrice'])}", l["CloseDate"] ? "on #{text('CloseDate', l['CloseDate'])}" : nil]
      elsif l["ListPrice"].is_a?(Numeric)
        lease = l["PropertyType"].to_s.match?(/lease/i)
        [money(l["ListPrice"]) + (lease ? "/mo" : ""), nil]
      else
        ["Price not available", nil]
      end
    end

    def status_class(status)
      case status.to_s
      when /active|coming/i then "s-active"
      when /pending|contract/i then "s-pending"
      when /closed|sold/i then "s-closed"
      else "s-other"
      end
    end

    def html(listing, photos, mls_name: nil, retrieved_at: Time.now)
      l = listing
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      hide_address = address_hidden?(l)
      full_address = Slideshow.address(l)
      place = [l["City"], l["StateOrProvince"], l["PostalCode"]].compact.map(&:to_s).reject(&:empty?).join(", ")
      title = hide_address ? (place.empty? ? "Listing #{l['ListingId']}" : place) : (full_address.empty? ? "Listing #{l['ListingId']}" : full_address)
      price, price_note = headline_price(l)
      stats = [
        l["BedroomsTotal"] ? ["#{l['BedroomsTotal']}", "beds"] : nil,
        l["BathroomsTotalInteger"] ? ["#{l['BathroomsTotalInteger']}", "baths"] : nil,
        l["LivingArea"].is_a?(Numeric) ? [commas(l["LivingArea"].round), "sq ft"] : nil
      ].compact
      coords = hide_address ? nil : coordinates(l)
      map_query = CGI.escape(hide_address ? place : full_address)
      agent = [l["ListAgentFullName"], l["ListOfficeName"]].compact.map(&:to_s).reject(&:empty?)
      agent_contact = [l["ListAgentOfficePhone"] || l["ListOfficePhone"], l["ListAgentEmail"]].compact.map(&:to_s).reject(&:empty?)
      groups = sections(l)
      total = groups.values.sum(&:size)
      filled = groups.values.flatten(1).count { |_, v| !empty?(v) }

      gallery = gallery_html(photos, h)
      facts_html = key_facts(l).map { |k, v| %(<div class="fact"><div class="fact-label">#{h.(k)}</div><div class="fact-value">#{h.(v)}</div></div>) }.join
      details_html = groups.map do |name, fields|
        rows = fields.map do |field, value|
          blank = empty?(value)
          search = h.("#{label(field)} #{field} #{blank ? '' : text(field, value)}".downcase)
          %(<div class="row#{blank ? ' blank' : ''}" data-search="#{search}"><dt>#{h.(label(field))}<code>#{h.(field)}</code></dt><dd>#{blank ? '<span class="none">—</span>' : html_value(field, value)}</dd></div>)
        end.join
        count = fields.count { |_, v| !empty?(v) }
        %(<details class="section" open><summary>#{h.(name)} <span class="count">#{count}</span></summary><dl>#{rows}</dl></details>)
      end.join

      map_html = if coords
                   %(<iframe id="map" title="Map" src="#{h.(map_embed_url(*coords))}"></iframe>)
                 else
                   %(<div class="map-missing">#{hide_address ? 'The seller asked that the address not be shown online.' : 'No map coordinates in this listing.'}</div>)
                 end

      notices = []
      notices << "This listing is not approved for public internet display (InternetEntireListingDisplayYN = No)." if l["InternetEntireListingDisplayYN"] == false
      notices << "The seller asked that the street address not be shown online, so it and the map are hidden." if hide_address

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h.(title)} · #{h.(price)}</title>
        <style>#{CSS}</style>
        </head>
        <body>
        #{notices.map { |n| %(<div class="notice">#{h.(n)}</div>) }.join}
        <div class="wrap">
          #{gallery}
          <div class="top">
            <div class="main">
              <div class="headline">
                <span class="status #{status_class(l['StandardStatus'])}">#{h.(l['StandardStatus'] || 'Unknown')}</span>
                <div class="price">#{h.(price)}#{price_note ? %( <span class="price-note">#{h.(price_note)}</span>) : ''}</div>
                <div class="stats">#{stats.map { |n, u| %(<span><b>#{h.(n)}</b> #{h.(u)}</span>) }.join}</div>
                <h1>#{h.(title)}</h1>
                <div class="sub">#{h.(['MLS # ' + l['ListingId'].to_s, mls_name ? "via #{mls_name}" : nil].compact.join(' · '))}</div>
              </div>
              #{facts_html.empty? ? '' : %(<div class="facts">#{facts_html}</div>)}
              #{empty?(l['PublicRemarks']) ? '' : %(<section class="about"><h2>About this home</h2><p id="remarks" class="clamp">#{h.(l['PublicRemarks'])}</p><button id="more" class="link-btn" hidden>Show more</button></section>)}
            </div>
            <aside class="side">
              <div class="card map-card">
                #{map_html}
                <div class="map-links"><a href="https://www.google.com/maps/search/?api=1&amp;query=#{map_query}" target="_blank" rel="noopener noreferrer">Google Maps</a> · <a href="https://www.openstreetmap.org/search?query=#{map_query}" target="_blank" rel="noopener noreferrer">OpenStreetMap</a></div>
              </div>
              #{agent.empty? ? '' : %(<div class="card agent"><div class="agent-label">Listed by</div><div class="agent-name">#{h.(agent.join(', '))}</div>#{agent_contact.map { |c| %(<div class="agent-contact">#{html_value(c.include?('@') ? 'Email' : 'Phone', c)}</div>) }.join}</div>)}
            </aside>
          </div>

          <section class="all">
            <div class="all-head">
              <h2>All listing details</h2>
              <div class="controls">
                <input id="filter" type="search" placeholder="Search #{filled} fields…" aria-label="Search fields">
                <label><input type="checkbox" id="show-empty"> Show empty fields (#{total - filled})</label>
                <label><input type="checkbox" id="show-names"> Show RESO field names</label>
              </div>
            </div>
            <div id="no-match" class="none" hidden>No fields match your search.</div>
            <div class="sections">#{details_html}</div>
          </section>

          <footer>
            Source: #{h.(mls_name || 'MLS')} via RESO Web API · Retrieved #{h.(retrieved_at.utc.strftime('%b %-d, %Y, %-I:%M %p UTC'))} ·
            Information deemed reliable but not guaranteed. Generated by reso_cli.
          </footer>
        </div>

        <div id="lightbox" class="lightbox" hidden>
          <button class="lb-close" aria-label="Close">&times;</button>
          <button class="lb-nav lb-prev" aria-label="Previous photo">&#8249;</button>
          <img id="lb-img" alt="">
          <button class="lb-nav lb-next" aria-label="Next photo">&#8250;</button>
          <div id="lb-info" class="lb-info"></div>
        </div>

        <script>const PHOTOS = #{JSON.generate(photos).gsub('</', '<\\/')};</script>
        <script>#{JS}</script>
        </body>
        </html>
      HTML
    end

    def gallery_html(photos, h)
      return %(<div class="gallery none-photos">No photos for this listing</div>) if photos.empty?

      tiles = photos.first(5).each_with_index.map do |p, i|
        %(<img class="tile t#{i}" src="#{h.(p['url'])}" alt="#{h.(p['caption'].to_s.empty? ? "Photo #{i + 1}" : p['caption'])}" data-index="#{i}" #{i.zero? ? '' : 'loading="lazy"'}>)
      end.join
      layout = photos.size >= 5 ? "g5" : "g1"
      %(<div class="gallery #{layout}">#{tiles}<button class="all-photos" data-index="0">Show all #{photos.size} photos</button></div>)
    end

    CSS = <<~'CSS'.freeze
      :root { --ink: #1d2329; --muted: #5d6974; --line: #e3e7eb; --bg: #ffffff; --soft: #f5f7f9; --accent: #0a66c2; }
      * { box-sizing: border-box; }
      body { margin: 0; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--ink); background: var(--bg); }
      a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
      .notice { background: #fff4e5; border-bottom: 1px solid #f3d19e; color: #7a4b00; padding: 10px 24px; font-size: 14px; }
      .wrap { max-width: 1200px; margin: 0 auto; padding: 20px 24px 40px; }
      .gallery { position: relative; border-radius: 14px; overflow: hidden; background: var(--soft); }
      .gallery img { width: 100%; height: 100%; object-fit: cover; display: block; cursor: zoom-in; }
      .gallery.g5 { display: grid; grid-template-columns: 2fr 1fr 1fr; grid-template-rows: 240px 240px; gap: 6px; }
      .gallery.g5 .t0 { grid-row: 1 / span 2; }
      .gallery.g1 { height: 480px; } .gallery.g1 img:not(.t0) { display: none; }
      .gallery.none-photos { height: 200px; display: flex; align-items: center; justify-content: center; color: var(--muted); }
      .all-photos { position: absolute; right: 14px; bottom: 14px; background: #fff; border: 1px solid var(--line); border-radius: 8px; padding: 8px 14px; font: 600 14px inherit; cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,.15); }
      .top { display: grid; grid-template-columns: minmax(0, 1fr) 360px; gap: 32px; margin-top: 24px; }
      .headline h1 { font-size: 20px; font-weight: 500; margin: 6px 0 2px; }
      .price { font-size: 36px; font-weight: 700; letter-spacing: -0.5px; margin-top: 8px; }
      .price-note { font-size: 16px; font-weight: 400; color: var(--muted); }
      .stats { display: flex; gap: 18px; font-size: 18px; margin-top: 2px; } .stats b { font-weight: 700; }
      .sub { color: var(--muted); font-size: 14px; }
      .status { display: inline-block; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .5px; padding: 3px 9px; border-radius: 999px; }
      .s-active { background: #e3f5e8; color: #17723a; } .s-pending { background: #fff1db; color: #9a5b00; }
      .s-closed { background: #ececec; color: #444; } .s-other { background: #e8eef7; color: #2d4b73; }
      .facts { display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: 10px; margin: 24px 0; }
      .fact { background: var(--soft); border-radius: 10px; padding: 12px 14px; }
      .fact-label { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .4px; }
      .fact-value { font-weight: 600; margin-top: 2px; }
      h2 { font-size: 22px; margin: 0 0 10px; }
      .about p { white-space: pre-line; margin: 0; }
      .clamp { display: -webkit-box; -webkit-line-clamp: 6; -webkit-box-orient: vertical; overflow: hidden; }
      .link-btn { background: none; border: 0; color: var(--accent); font: 600 15px inherit; padding: 6px 0; cursor: pointer; }
      .card { border: 1px solid var(--line); border-radius: 12px; overflow: hidden; margin-bottom: 16px; }
      #map { display: block; width: 100%; height: 280px; border: 0; } .map-missing { height: 140px; display: flex; align-items: center; justify-content: center; text-align: center; padding: 16px; color: var(--muted); background: var(--soft); font-size: 14px; }
      .map-links { padding: 10px 14px; font-size: 14px; border-top: 1px solid var(--line); }
      .agent { padding: 16px; } .agent-label { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .4px; }
      .agent-name { font-weight: 600; margin: 2px 0 6px; } .agent-contact { font-size: 14px; }
      .all { margin-top: 48px; border-top: 1px solid var(--line); padding-top: 28px; }
      .all-head { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 12px; }
      .controls { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; font-size: 14px; color: var(--muted); }
      .controls input[type=search] { font: inherit; padding: 8px 12px; border: 1px solid var(--line); border-radius: 8px; min-width: 240px; }
      .sections { columns: 2 420px; column-gap: 24px; }
      .section { break-inside: avoid; border: 1px solid var(--line); border-radius: 12px; margin: 0 0 20px; padding: 4px 16px 10px; }
      .section summary { cursor: pointer; font-weight: 700; font-size: 17px; padding: 10px 0 6px; }
      .count { font-weight: 500; font-size: 13px; color: var(--muted); background: var(--soft); border-radius: 999px; padding: 1px 8px; margin-left: 4px; }
      dl { margin: 0; } .row { display: grid; grid-template-columns: 44% 56%; gap: 12px; padding: 7px 0; border-top: 1px solid var(--soft); font-size: 14px; }
      dt { color: var(--muted); } dd { margin: 0; overflow-wrap: anywhere; }
      dt code { display: none; font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; color: #8a96a1; }
      body.names dt code { display: block; }
      .row.blank { display: none; } body.empties .row.blank { display: grid; }
      .row.filtered { display: none !important; } .section.hidden { display: none; }
      .none { color: #9aa5af; }
      footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid var(--line); font-size: 12px; color: var(--muted); }
      .lightbox { position: fixed; inset: 0; background: rgba(10,12,14,.94); z-index: 2000; display: flex; align-items: center; justify-content: center; }
      .lightbox[hidden] { display: none; }
      .lightbox img { max-width: 92vw; max-height: 84vh; object-fit: contain; }
      .lb-nav, .lb-close { position: absolute; background: rgba(255,255,255,.12); color: #fff; border: 0; cursor: pointer; border-radius: 8px; }
      .lb-nav { top: 50%; transform: translateY(-50%); font-size: 34px; width: 54px; height: 74px; } .lb-prev { left: 16px; } .lb-next { right: 16px; }
      .lb-close { top: 14px; right: 16px; font-size: 30px; width: 46px; height: 46px; }
      .lb-info { position: absolute; bottom: 16px; left: 0; right: 0; text-align: center; color: #ddd; font-size: 14px; }
      @media (max-width: 900px) {
        .top { grid-template-columns: 1fr; }
        .gallery.g5 { grid-template-columns: 1fr 1fr; grid-template-rows: 260px 120px 120px; } .gallery.g5 .t0 { grid-column: 1 / span 2; grid-row: auto; }
        .gallery.g5 .t3, .gallery.g5 .t4 { display: none; }
      }
    CSS

    JS = <<~'JS'.freeze
      (function () {
        // Lightbox slideshow
        const lb = document.getElementById("lightbox"), img = document.getElementById("lb-img"), info = document.getElementById("lb-info");
        let i = 0;
        function show(n) {
          if (!PHOTOS.length) return;
          i = (n + PHOTOS.length) % PHOTOS.length;
          img.src = PHOTOS[i].url;
          info.textContent = (i + 1) + " / " + PHOTOS.length + (PHOTOS[i].caption ? " · " + PHOTOS[i].caption : "");
        }
        function open(n) { lb.hidden = false; show(n); }
        document.querySelectorAll(".gallery [data-index]").forEach(el => el.addEventListener("click", () => open(+el.dataset.index)));
        lb.querySelector(".lb-close").onclick = () => { lb.hidden = true; };
        lb.querySelector(".lb-prev").onclick = () => show(i - 1);
        lb.querySelector(".lb-next").onclick = () => show(i + 1);
        lb.addEventListener("click", e => { if (e.target === lb) lb.hidden = true; });
        document.addEventListener("keydown", e => {
          if (lb.hidden) return;
          if (e.key === "Escape") lb.hidden = true;
          if (e.key === "ArrowLeft") show(i - 1);
          if (e.key === "ArrowRight") show(i + 1);
        });
        img.onerror = () => { info.textContent = "This photo didn't load. Some MLS photo links expire: run the details command again for fresh links."; };

        // Description: show more / less
        const remarks = document.getElementById("remarks"), more = document.getElementById("more");
        if (remarks && more && remarks.scrollHeight > remarks.clientHeight + 4) {
          more.hidden = false;
          more.onclick = () => { const c = remarks.classList.toggle("clamp"); more.textContent = c ? "Show more" : "Show less"; };
        }

        // All details: search, empty fields, field names
        const filter = document.getElementById("filter"), noMatch = document.getElementById("no-match");
        function applyFilter() {
          const q = filter.value.trim().toLowerCase();
          let any = false;
          document.querySelectorAll(".section").forEach(sec => {
            let visible = 0;
            sec.querySelectorAll(".row").forEach(row => {
              const hit = !q || row.dataset.search.includes(q);
              row.classList.toggle("filtered", !hit);
              const shown = hit && (!row.classList.contains("blank") || document.body.classList.contains("empties"));
              if (shown) visible++;
            });
            sec.classList.toggle("hidden", visible === 0);
            if (q && visible) sec.open = true;
            if (visible) any = true;
          });
          noMatch.hidden = any;
        }
        filter.addEventListener("input", applyFilter);
        document.getElementById("show-empty").onchange = e => { document.body.classList.toggle("empties", e.target.checked); applyFilter(); };
        document.getElementById("show-names").onchange = e => document.body.classList.toggle("names", e.target.checked);
        applyFilter();

      })();
    JS
  end
end
