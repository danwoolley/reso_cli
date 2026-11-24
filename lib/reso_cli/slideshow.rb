require "json"
require "cgi"

module ResoCli
  # Builds a self-contained HTML photo slideshow for one listing.
  module Slideshow
    # Media categories that aren't photos (videos, documents, virtual tours)
    NON_PHOTO = /video|document|tour|audio|pdf/i

    module_function

    # Photo entries from a listing's Media, in listing order (by Order; unordered last)
    def photos(media)
      Array(media)
        .select { |m| m.is_a?(Hash) && m["MediaURL"].to_s.match?(%r{\Ahttps?://}i) }
        .reject { |m| [m["MediaCategory"], m["MediaType"]].any? { |v| v.to_s.match?(NON_PHOTO) } }
        .reject { |m| m["MediaURL"].to_s.match?(/\.pdf(\?|\z)/i) }
        .each_with_index
        .sort_by { |m, i| [m["Order"].is_a?(Numeric) ? 0 : 1, m["Order"].to_f, i] }
        .map do |m, _|
          { "url" => m["MediaURL"], "caption" => (m["ShortDescription"] || m["LongDescription"]).to_s.strip }
        end
    end

    def address(listing)
      unparsed = listing["UnparsedAddress"].to_s.strip
      street = if unparsed.empty?
                 [listing["StreetNumber"] || listing["StreetNumberNumeric"], listing["StreetName"], listing["StreetSuffix"]]
                   .compact.map(&:to_s).reject(&:empty?).join(" ")
               else
                 unparsed
               end
      place = [listing["City"], listing["StateOrProvince"]].compact.map(&:to_s).reject(&:empty?).join(", ")
      [street, place].reject(&:empty?).join(", ")
    end

    def facts(listing)
      price = listing["ListPrice"]
      [
        price.is_a?(Numeric) ? "$#{price.round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}" : nil,
        listing["BedroomsTotal"] ? "#{listing['BedroomsTotal']} bd" : nil,
        listing["BathroomsTotalInteger"] ? "#{listing['BathroomsTotalInteger']} ba" : nil,
        listing["LivingArea"].is_a?(Numeric) ? "#{listing['LivingArea'].round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse} sq ft" : nil,
        listing["StandardStatus"],
        listing["ListingId"] ? "MLS # #{listing['ListingId']}" : nil
      ].compact
    end

    def html(listing, photos, mls_name: nil)
      title = address(listing)
      title = "Listing #{listing['ListingId']}" if title.empty?
      data = JSON.generate(photos).gsub("</", "<\\/")
      subtitle = (facts(listing) + [mls_name ? "via #{mls_name}" : nil]).compact.join(" · ")
      h = ->(s) { CGI.escapeHTML(s.to_s) }

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h.(title)} · Photos</title>
        <style>
          :root { color-scheme: dark; }
          * { box-sizing: border-box; }
          body { margin: 0; font: 15px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #111; color: #eee;
                 display: grid; grid-template-rows: auto 1fr auto auto; height: 100vh; }
          header { padding: 12px 20px; border-bottom: 1px solid #2a2a2a; }
          header h1 { margin: 0; font-size: 18px; font-weight: 600; }
          header p { margin: 2px 0 0; color: #aaa; font-size: 13px; }
          main { position: relative; display: flex; align-items: center; justify-content: center; min-height: 0; }
          main img { max-width: 100%; max-height: 100%; object-fit: contain; }
          .nav { position: absolute; top: 50%; transform: translateY(-50%); background: rgba(0,0,0,.5); color: #fff; border: 0;
                 font-size: 32px; width: 52px; height: 72px; cursor: pointer; border-radius: 6px; }
          .nav:hover { background: rgba(0,0,0,.8); }
          #prev { left: 12px; } #next { right: 12px; }
          .info { text-align: center; padding: 8px 20px; color: #ccc; font-size: 13px; min-height: 2.2em; }
          .thumbs { display: flex; gap: 6px; overflow-x: auto; padding: 8px 12px 14px; background: #0b0b0b; }
          .thumbs img { height: 64px; width: 96px; object-fit: cover; opacity: .55; cursor: pointer; border: 2px solid transparent; border-radius: 3px; flex: none; }
          .thumbs img.active { opacity: 1; border-color: #4ea1ff; }
          .empty { color: #aaa; }
        </style>
        </head>
        <body>
        <header>
          <h1>#{h.(title)}</h1>
          <p>#{h.(subtitle)}</p>
        </header>
        <main>
          <button class="nav" id="prev" aria-label="Previous photo">&#8249;</button>
          <img id="photo" alt="">
          <button class="nav" id="next" aria-label="Next photo">&#8250;</button>
        </main>
        <div class="info" id="info"></div>
        <div class="thumbs" id="thumbs"></div>
        <script>
          const photos = #{data};
          const photo = document.getElementById("photo"), info = document.getElementById("info"), thumbs = document.getElementById("thumbs");
          let i = 0;
          function show(n) {
            if (!photos.length) return;
            i = (n + photos.length) % photos.length;
            photo.src = photos[i].url;
            photo.alt = photos[i].caption || ("Photo " + (i + 1));
            info.textContent = (i + 1) + " / " + photos.length + (photos[i].caption ? " · " + photos[i].caption : "");
            [...thumbs.children].forEach((t, k) => t.classList.toggle("active", k === i));
            thumbs.children[i].scrollIntoView({ block: "nearest", inline: "center" });
          }
          photos.forEach((p, k) => {
            const t = document.createElement("img");
            t.src = p.url; t.loading = "lazy"; t.alt = "Thumbnail " + (k + 1);
            t.onclick = () => show(k);
            thumbs.appendChild(t);
          });
          document.getElementById("prev").onclick = () => show(i - 1);
          document.getElementById("next").onclick = () => show(i + 1);
          document.addEventListener("keydown", e => { if (e.key === "ArrowLeft") show(i - 1); if (e.key === "ArrowRight") show(i + 1); });
          photo.onerror = () => { info.textContent = "This photo didn't load. Some MLS photo links expire: run the photos command again for fresh links."; };
          if (photos.length) show(0); else { info.innerHTML = '<span class="empty">This listing has no photos.</span>'; document.querySelectorAll(".nav").forEach(b => b.hidden = true); }
        </script>
        </body>
        </html>
      HTML
    end
  end
end
