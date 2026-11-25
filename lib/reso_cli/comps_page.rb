require "cgi"
require "json"

module ResoCli
  # HTML page for comparable sales: subject, value range, map with pins, and a ranked table.
  module CompsPage
    module_function

    # detail_for maps a ListingId to the href of that listing's details page, when one was built
    def html(subject, comps, estimate:, photo_for:, mls_name:, months:, radius:, widened: false, retrieved_at: Time.now,
             detail_for: {})
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      # Wrap inner HTML in a link to the listing's details page (opens in a new tab), if there is one
      link = lambda do |id, inner, cls = nil|
        href = detail_for[id.to_s]
        next inner unless href

        %(<a href="#{h.(href)}" target="_blank"#{cls ? %( class="#{cls}") : ''} title="Open the listing details">#{inner}</a>)
      end
      money = ->(n) { n ? DetailPage.money(n) : "—" }
      lease = subject["PropertyType"].to_s.match?(/lease/i)
      per = lease ? "/mo" : ""
      address = Slideshow.address(subject)
      address = "Listing #{subject['ListingId']}" if address.empty?
      subject_photo = photo_for[subject["ListingId"].to_s]
      price, price_note = DetailPage.headline_price(subject)
      facts = [
        subject["BedroomsTotal"] ? "#{subject['BedroomsTotal']} bd" : nil,
        subject["BathroomsTotalInteger"] ? "#{subject['BathroomsTotalInteger']} ba" : nil,
        subject["LivingArea"].is_a?(Numeric) ? "#{DetailPage.commas(subject['LivingArea'].round)} sq ft" : nil,
        subject["PropertySubType"]
      ].compact.join(" · ")

      kind = [subject["PropertySubType"], subject["PropertyType"]].map(&:to_s).find { |k| !k.empty? } || "similar"
      coords = Comps.coordinates(subject)
      pins = comps.each_with_index.filter_map do |c, i|
        cc = Comps.coordinates(c.record)
        next unless cc

        { lat: cc[0], lng: cc[1], n: i + 1, label: "#{i + 1}. #{Slideshow.address(c.record)} · #{money.(c.record['ClosePrice'])}#{per}" }
      end
      map_data = { subject: coords ? { lat: coords[0], lng: coords[1], label: "Subject: #{address}" } : nil, pins: pins }

      rows = comps.each_with_index.map do |c, i|
        r = c.record
        photo = photo_for[r["ListingId"].to_s]
        img = photo ? %(<img src="#{h.(photo)}" alt="" loading="lazy">) : %(<div class="noimg"></div>)
        closed = Comps.close_time(r)
        <<~ROW
          <tr>
            <td class="n">#{i + 1}</td>
            <td class="thumb">#{link.(r['ListingId'], img)}</td>
            <td><div class="addr">#{link.(r['ListingId'], h.(Slideshow.address(r)), 'detail-link')}</div><div class="muted">MLS # #{h.(r['ListingId'])}#{r['PropertySubType'] ? " · #{h.(r['PropertySubType'])}" : ''}</div></td>
            <td>#{h.(closed ? closed.strftime('%b %-d, %Y') : '—')}<div class="muted">#{c.months_ago} mo ago</div></td>
            <td class="num"><b>#{h.(money.(r['ClosePrice']))}#{per}</b>#{r['ListPrice'].is_a?(Numeric) ? %(<div class="muted">list #{h.(money.(r['ListPrice']))}</div>) : ''}</td>
            <td class="num">#{h.(r['BedroomsTotal'] || '—')} / #{h.(r['BathroomsTotalInteger'] || '—')}</td>
            <td class="num">#{h.(DetailPage.commas(r['LivingArea'].to_f.round))}</td>
            <td class="num"><b>#{h.(money.(c.ppsf.round))}</b></td>
            <td class="num">#{c.distance ? format('%.2f mi', c.distance) : '—'}</td>
          </tr>
        ROW
      end.join

      estimate_html = if estimate && estimate[:value]
                        <<~EST
                          <div class="estimate">
                            <div class="est-label">Value range from these comps</div>
                            <div class="est-value">#{h.(money.(estimate[:low]))}#{per} – #{h.(money.(estimate[:high]))}#{per}</div>
                            <div class="muted">Midpoint #{h.(money.(estimate[:value]))}#{per} · median #{h.(money.(estimate[:median_ppsf].round))}/sq ft (middle half #{h.(money.(estimate[:low_ppsf].round))}–#{h.(money.(estimate[:high_ppsf].round))}) × #{h.(DetailPage.commas(subject['LivingArea'].to_f.round))} sq ft</div>
                            <div class="disclaimer">A rough price-per-square-foot range, not an appraisal. It doesn't account for condition, lot, views, upgrades or market changes.</div>
                          </div>
                        EST
                      elsif comps.size < 3
                        %(<div class="estimate"><div class="est-label">Not enough comps</div><div class="muted">Fewer than 3 similar sales found, so no value range is shown. Try a larger radius (--radius) or longer period (--months).</div></div>)
                      else
                        ""
                      end

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Comps · #{h.(address)}</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
        <style>#{CSS}</style>
        </head>
        <body>
        <div class="wrap">
          <div class="kicker">Comparable sales</div>
          <div class="top">
            <div class="subject">
              #{subject_photo ? %(<img src="#{h.(subject_photo)}" alt="">) : ''}
              <div>
                <h1>#{link.(subject['ListingId'], h.(address), 'detail-link')}</h1>
                <div class="subject-price">#{h.(price)}#{price_note ? %( <span class="muted">#{h.(price_note)}</span>) : ''} <span class="pill">#{h.(subject['StandardStatus'])}</span></div>
                <div class="muted">#{h.(facts)}</div>
                <div class="muted">MLS # #{h.(subject['ListingId'])} · via #{h.(mls_name)}</div>
              </div>
            </div>
            #{estimate_html}
          </div>
          <p class="criteria">#{comps.size} closed #{h.(kind)} sales within #{h.(radius)} mi, sold in the last #{h.(months)} months, with similar size (±25%) and bedrooms (±1), ranked by similarity (distance, size, bedrooms, how recent).#{widened ? ' <b>The search was widened</b> because the first pass found fewer than 3.' : ''}#{detail_for.any? ? ' Click an address or photo to open that listing’s details.' : ''}</p>
          #{coords || pins.any? ? '<div id="map"></div>' : ''}
          <table>
            <thead><tr><th>#</th><th></th><th>Address</th><th>Sold</th><th class="num">Price</th><th class="num">Bd / Ba</th><th class="num">Sq ft</th><th class="num">$/sq ft</th><th class="num">Distance</th></tr></thead>
            <tbody>#{rows.empty? ? '<tr><td colspan="9" class="muted">No comparable sales found.</td></tr>' : rows}</tbody>
          </table>
          <footer>Source: #{h.(mls_name)} via RESO Web API · Retrieved #{h.(retrieved_at.utc.strftime('%b %-d, %Y, %-I:%M %p UTC'))} · Information deemed reliable but not guaranteed. Generated by reso_cli.</footer>
        </div>
        <script>const MAP = #{JSON.generate(map_data).gsub('</', '<\\/')};</script>
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
        <script>#{JS}</script>
        </body>
        </html>
      HTML
    end

    CSS = <<~'CSS'.freeze
      :root { --ink: #1d2329; --muted: #5d6974; --line: #e3e7eb; --soft: #f5f7f9; --accent: #0a66c2; }
      * { box-sizing: border-box; }
      body { margin: 0; font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--ink); }
      .wrap { max-width: 1200px; margin: 0 auto; padding: 24px; }
      .kicker { color: var(--muted); font-size: 13px; text-transform: uppercase; letter-spacing: .5px; }
      .top { display: grid; grid-template-columns: 1fr 420px; gap: 24px; margin: 8px 0 12px; align-items: stretch; }
      .subject { display: flex; gap: 16px; align-items: center; }
      .subject img { width: 200px; height: 140px; object-fit: cover; border-radius: 10px; }
      h1 { font-size: 24px; margin: 0 0 4px; }
      .subject-price { font-size: 22px; font-weight: 700; }
      .pill { font-size: 12px; font-weight: 700; text-transform: uppercase; background: var(--soft); border-radius: 999px; padding: 2px 8px; vertical-align: middle; }
      .muted { color: var(--muted); font-size: 13px; }
      .estimate { background: #f0f6fd; border: 1px solid #d4e5f7; border-radius: 12px; padding: 16px 18px; }
      .est-label { font-size: 12px; text-transform: uppercase; letter-spacing: .4px; color: var(--muted); }
      .est-value { font-size: 26px; font-weight: 700; margin: 2px 0 4px; }
      .disclaimer { font-size: 12px; color: var(--muted); margin-top: 8px; }
      .criteria { color: var(--muted); font-size: 14px; }
      #map { height: 380px; border-radius: 12px; border: 1px solid var(--line); margin: 8px 0 20px; }
      table { width: 100%; border-collapse: collapse; }
      th { text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: .4px; color: var(--muted); border-bottom: 2px solid var(--line); padding: 8px 6px; }
      td { padding: 8px 6px; border-bottom: 1px solid var(--line); vertical-align: middle; }
      .num { text-align: right; white-space: nowrap; }
      td.n { font-weight: 700; color: var(--accent); width: 28px; }
      .thumb img, .noimg { width: 96px; height: 64px; object-fit: cover; border-radius: 6px; display: block; background: var(--soft); }
      .addr { font-weight: 600; }
      a.detail-link { color: inherit; text-decoration: none; }
      a.detail-link:hover { color: #1a5fb4; text-decoration: underline; }
      footer { margin-top: 24px; font-size: 12px; color: var(--muted); }
      .pin { background: var(--accent); color: #fff; border: 2px solid #fff; border-radius: 50%; width: 24px; height: 24px; line-height: 20px; text-align: center; font: 700 12px sans-serif; box-shadow: 0 1px 4px rgba(0,0,0,.4); }
      .pin.subject { background: #d4382c; width: 28px; height: 28px; line-height: 24px; font-size: 14px; }
      @media (max-width: 900px) { .top { grid-template-columns: 1fr; } .subject img { width: 140px; height: 100px; } }
    CSS

    JS = <<~'JS'.freeze
      (function () {
        const el = document.getElementById("map");
        if (!el) return;
        if (!window.L) { el.outerHTML = '<p class="muted">The map couldn\'t load (no internet connection?).</p>'; return; }
        const map = L.map(el, { scrollWheelZoom: false });
        // Esri's World Street Map tiles. The page is opened as a local file, so the browser sends no
        // Referer, and OpenStreetMap's and CARTO's tile servers refuse such requests; Esri's don't.
        L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}", {
          maxZoom: 19,
          attribution: 'Tiles &copy; <a href="https://www.esri.com">Esri</a> &mdash; Source: Esri, HERE, Garmin, USGS, NGA, EPA, USDA, NPS'
        }).addTo(map);
        const icon = (text, cls) => L.divIcon({ className: "", html: '<div class="pin ' + cls + '">' + text + '</div>', iconSize: [28, 28], iconAnchor: [14, 14] });
        const points = [];
        MAP.pins.forEach(p => { L.marker([p.lat, p.lng], { icon: icon(p.n, "") }).addTo(map).bindTooltip(p.label); points.push([p.lat, p.lng]); });
        if (MAP.subject) { L.marker([MAP.subject.lat, MAP.subject.lng], { icon: icon("★", "subject"), zIndexOffset: 1000 }).addTo(map).bindTooltip(MAP.subject.label); points.push([MAP.subject.lat, MAP.subject.lng]); }
        if (points.length === 1) map.setView(points[0], 15); else map.fitBounds(points, { padding: [30, 30] });
      })();
    JS
  end
end
