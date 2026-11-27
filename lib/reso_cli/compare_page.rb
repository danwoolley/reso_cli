require "cgi"
require "json"

module ResoCli
  # HTML page comparing one listing from two feeds, field by field.
  module ComparePage
    ORDER = %i[different only_a only_b format system same].freeze
    BADGE = { different: "b-diff", only_a: "b-only", only_b: "b-only", format: "b-format", system: "b-system", same: "b-same" }.freeze

    module_function

    # Above this many LCS cells (tokens in A × tokens in B), highlight the whole value instead
    MAX_DIFF_CELLS = 250_000
    # Strings this short or shorter are diffed character by character; longer ones word by word
    CHAR_DIFF_MAX = 40

    # For list fields: which items are only on one side
    def list_diff(a, b)
      return nil unless a.is_a?(Array) && b.is_a?(Array)

      la = a.map(&:to_s)
      lb = b.map(&:to_s)
      { only_a: la - lb, only_b: lb - la }
    end

    # Diff of two strings as [[:eq | :del | :add, text], ...], merging runs of the same kind.
    # :del is text only in `a` (the baseline), :add text only in `b`.
    def text_ops(a, b)
      a = a.to_s
      b = b.to_s
      ta, tb = if a.length <= CHAR_DIFF_MAX && b.length <= CHAR_DIFF_MAX
                 [a.chars, b.chars]
               else
                 [a.scan(/\s+|\S+/), b.scan(/\s+|\S+/)]
               end
      return [[:del, a], [:add, b]].reject { |_, t| t.empty? } if ta.size * tb.size > MAX_DIFF_CELLS

      # Longest common subsequence, filled from the end so the walk below goes forward
      n = ta.size
      m = tb.size
      lcs = Array.new(n + 1) { Array.new(m + 1, 0) }
      (n - 1).downto(0) do |i|
        (m - 1).downto(0) do |j|
          lcs[i][j] = ta[i] == tb[j] ? lcs[i + 1][j + 1] + 1 : [lcs[i + 1][j], lcs[i][j + 1]].max
        end
      end

      ops = []
      i = j = 0
      while i < n && j < m
        if ta[i] == tb[j]
          ops << [:eq, ta[i]]
          i += 1
          j += 1
        elsif lcs[i + 1][j] >= lcs[i][j + 1]
          ops << [:del, ta[i]]
          i += 1
        else
          ops << [:add, tb[j]]
          j += 1
        end
      end
      ta[i..].each { |t| ops << [:del, t] }
      tb[j..].each { |t| ops << [:add, t] }

      ops.each_with_object([]) do |(kind, t), out|
        if out.last && out.last[0] == kind
          out.last[1] += t
        else
          out << [kind, t.dup]
        end
      end
    end

    # The baseline (a) and compared (b) cells of a "different" row, with changes marked.
    # Lists: one chip per item, items missing from the other feed in red (−) or green (+).
    # Other values: the changed characters or words wrapped in <del> / <ins>.
    def diff_cells(field, a, b)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      if a.is_a?(Array) && b.is_a?(Array)
        ka = a.map { |x| Compare.loose(x) }
        kb = b.map { |x| Compare.loose(x) }
        chip = lambda do |item, kind|
          sign = { del: "−", add: "+" }[kind]
          %(<span class="chip chip-#{kind}">#{sign ? %(<b>#{sign}</b>) : ''}#{h.(DetailPage.text(field, item))}</span>)
        end
        left = a.each_with_index.map { |x, i| chip.(x, kb.include?(ka[i]) ? :eq : :del) }.join
        right = b.each_with_index.map { |x, i| chip.(x, ka.include?(kb[i]) ? :eq : :add) }.join
        return [%(<div class="chips">#{left}</div>), %(<div class="chips">#{right}</div>)]
      end

      ops = text_ops(DetailPage.text(field, a), DetailPage.text(field, b))
      left = ops.reject { |k, _| k == :add }.map { |k, t| k == :del ? "<del>#{h.(t)}</del>" : h.(t) }.join
      right = ops.reject { |k, _| k == :del }.map { |k, t| k == :add ? "<ins>#{h.(t)}</ins>" : h.(t) }.join
      [left, right]
    end

    # A full page for one listing: header, legend, layout toggle and that listing's diff section
    def html(a_name, a, b_name, b, retrieved_at: Time.now)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      listing = a.empty? ? b : a
      title = Slideshow.address(listing)
      title = "Listing #{listing['ListingId']}" if title.empty?
      rows = Compare.compare(a, b)

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Compare #{h.(listing['ListingId'])} · #{h.(a_name)} vs #{h.(b_name)}</title>
        <style>#{CSS}</style>
        </head>
        <body>
        <div class="wrap">
          <header>
            <div class="kicker">Feed comparison · MLS # #{h.(listing['ListingId'])}</div>
            <h1>#{h.(title)}</h1>
            <p class="sub"><b>#{h.(a_name)}</b> vs <b>#{h.(b_name)}</b> · #{rows.size} fields with a value in either feed · retrieved #{h.(retrieved_at.utc.strftime('%b %-d, %Y, %-I:%M %p UTC'))}</p>
          </header>

          #{legend(a_name, b_name)}
          #{view_toggle}
          #{section(a_name, a, b_name, b)}

          #{footer(a_name, b_name)}
        </div>
        <script>#{JS}</script>
        </body>
        </html>
      HTML
    end

    # What the colours mean, for the whole page
    def legend(a_name, b_name)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      <<~LEGEND
        <div class="legend">
          <span><span class="sw t-del"></span><b>−</b> In #{h.(a_name)} (baseline), missing from #{h.(b_name)}</span>
          <span><span class="sw t-add"></span><b>+</b> In #{h.(b_name)}, not in #{h.(a_name)}</span>
          <span><span class="sw t-fmt"></span> Same value, different format</span>
        </div>
      LEGEND
    end

    # Split / unified switch; applies to every diff table on the page
    def view_toggle
      <<~TOGGLE
        <div class="views-bar">
          <span class="views" role="group" aria-label="Diff layout">
            <button id="view-split" class="view on" aria-pressed="true">Split</button><button id="view-unified" class="view" aria-pressed="false">Unified</button>
          </span>
        </div>
      TOGGLE
    end

    def footer(a_name, b_name)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      <<~FOOTER
        <footer>
          The first feed given with --mls (#{h.(a_name)}) is the baseline: red marks what it has and #{h.(b_name)} lacks, green what #{h.(b_name)} adds.
          "System fields" are keys, IDs and timestamps each system assigns for itself, so they're expected to differ.
          "Same value, different format" ignores case, spacing, punctuation, a URL's http(s)://, list order, and numbers sent as text.
          Generated by reso_cli.
        </footer>
      FOOTER
    end

    # One listing's diff: summary cards, photo strips, filters and the field table.
    # Self-contained, so a page can hold several (each is scoped by the page script).
    def section(a_name, a, b_name, b, id: nil)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      rows = Compare.compare(a, b)
      counts = Compare.summary(rows)
      photos_a = Slideshow.photos(a["Media"])
      photos_b = Slideshow.photos(b["Media"])

      cards = ORDER.map do |st|
        %(<button class="card #{BADGE[st]}" data-show="#{st}"><b>#{counts[st]}</b><span>#{h.(Compare.status_label(st, a_name, b_name))}</span></button>)
      end.join

      sorted = rows.sort_by { |r| [ORDER.index(r[:status]), DetailPage::SECTION_ORDER.index(DetailPage.section_for(r[:field])) || 99, DetailPage.label(r[:field]).downcase] }
      body = sorted.map do |r|
        f = r[:field]
        cell = ->(v) { Compare.empty?(v) ? '<span class="none">—</span>' : DetailPage.html_value(f, v) }
        # Tint and contents of each side: red where the baseline has something the other lacks, green the reverse
        left, right, tint_a, tint_b = case r[:status]
                                      when :different then [*diff_cells(f, r[:a], r[:b]), "t-del", "t-add"]
                                      when :only_a then [cell.(r[:a]), cell.(r[:b]), "t-del", ""]
                                      when :only_b then [cell.(r[:a]), cell.(r[:b]), "", "t-add"]
                                      when :format then [cell.(r[:a]), cell.(r[:b]), "t-fmt", "t-fmt"]
                                      else [cell.(r[:a]), cell.(r[:b]), "", ""]
                                      end
        search = h.("#{DetailPage.label(f)} #{f} #{DetailPage.section_for(f)}".downcase)
        <<~ROW
          <tr data-status="#{r[:status]}" data-search="#{search}">
            <td><div class="label">#{h.(DetailPage.label(f))}</div><code>#{h.(f)}</code><div class="section">#{h.(DetailPage.section_for(f))}</div></td>
            <td class="side side-a #{tint_a}" data-feed="#{h.(a_name)}">#{left}</td>
            <td class="side side-b #{tint_b}" data-feed="#{h.(b_name)}">#{right}</td>
            <td><span class="badge #{BADGE[r[:status]]}">#{h.(Compare.status_label(r[:status], a_name, b_name))}</span></td>
          </tr>
        ROW
      end.join

      thumbs = lambda do |photos|
        return %(<div class="none">No photos</div>) if photos.empty?

        photos.first(8).map { |p| %(<img src="#{h.(p['url'])}" loading="lazy" alt="">) }.join
      end

      <<~SECTION
        <section class="cmp"#{id ? %( id="#{h.(id)}") : ''}>
          <div class="cards">#{cards}</div>

          <div class="photos">
            <div><h3>#{h.(a_name)} · #{photos_a.size} photos</h3><div class="strip">#{thumbs.(photos_a)}</div></div>
            <div><h3>#{h.(b_name)} · #{photos_b.size} photos</h3><div class="strip">#{thumbs.(photos_b)}</div></div>
          </div>

          <div class="controls">
            <input class="filter" type="search" placeholder="Search fields…" aria-label="Search fields">
            <label><input type="checkbox" class="show-same"> Show matching fields (#{counts[:same]})</label>
            <button class="reset link">Show all differences</button>
          </div>

          <table class="diff split">
            <thead><tr><th>Field</th><th>#{h.(a_name)} <span class="base">baseline</span></th><th>#{h.(b_name)}</th><th>Result</th></tr></thead>
            <tbody>#{body}</tbody>
          </table>
          <div class="no-match none" hidden>No fields match.</div>
        </section>
      SECTION
    end

    CSS = <<~'CSS'.freeze
      :root { --ink: #1d2329; --muted: #5d6974; --line: #e3e7eb; --soft: #f5f7f9; --accent: #0a66c2; }
      * { box-sizing: border-box; }
      body { margin: 0; font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--ink); }
      a { color: var(--accent); text-decoration: none; }
      .wrap { max-width: 1280px; margin: 0 auto; padding: 24px; }
      .kicker { color: var(--muted); font-size: 13px; text-transform: uppercase; letter-spacing: .5px; }
      h1 { margin: 4px 0; font-size: 26px; } .sub { color: var(--muted); margin: 0 0 18px; }
      .cards { display: grid; grid-template-columns: repeat(6, 1fr); gap: 10px; }
      .card { text-align: left; border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; background: #fff; cursor: pointer; font: inherit; }
      .card b { display: block; font-size: 26px; } .card span { font-size: 13px; color: var(--muted); }
      .card.active { outline: 2px solid var(--accent); }
      section.cmp { margin-top: 18px; }
      .photos { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 22px 0; }
      .photos h3 { font-size: 14px; margin: 0 0 6px; color: var(--muted); }
      .strip { display: flex; gap: 4px; overflow-x: auto; } .strip img { height: 64px; width: 92px; object-fit: cover; border-radius: 4px; flex: none; }
      .controls { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; margin: 8px 0 12px; font-size: 14px; color: var(--muted); }
      .controls input[type=search] { font: inherit; padding: 8px 12px; border: 1px solid var(--line); border-radius: 8px; min-width: 260px; }
      .link { background: none; border: 0; color: var(--accent); font: inherit; cursor: pointer; }
      table { width: 100%; border-collapse: collapse; font-size: 14px; }
      th { text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: .4px; color: var(--muted); border-bottom: 2px solid var(--line); padding: 8px; position: sticky; top: 0; background: #fff; }
      td { vertical-align: top; padding: 9px 8px; border-bottom: 1px solid var(--line); overflow-wrap: anywhere; }
      td:first-child { width: 24%; } td:nth-child(2), td:nth-child(3) { width: 30%; } td:last-child { width: 16%; }
      .label { font-weight: 600; } code { font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; color: #8a96a1; }
      .section { font-size: 11px; color: var(--muted); }
      .base { font-size: 10px; font-weight: 600; background: var(--soft); border-radius: 999px; padding: 1px 6px; margin-left: 4px; }
      /* GitHub-style diff colours: red = only in the baseline, green = only in the compared feed */
      .t-del { background: #ffebe9; } .t-add { background: #e6ffec; } .t-fmt { background: #f1f5fb; }
      del { background: #ffc1c0; color: #82071e; text-decoration: none; border-radius: 2px; }
      ins { background: #abf2bc; color: #0b5a23; text-decoration: none; border-radius: 2px; }
      .chips { display: flex; flex-wrap: wrap; gap: 4px; }
      .chip { display: inline-block; font-size: 12.5px; padding: 1px 8px; border-radius: 999px; border: 1px solid var(--line); background: #fff; color: #444; }
      .chip b { margin-right: 3px; }
      .chip-del { background: #ffc1c0; border-color: #f5a3a2; color: #82071e; }
      .chip-add { background: #abf2bc; border-color: #8fdca3; color: #0b5a23; }
      .legend { display: flex; flex-wrap: wrap; gap: 18px; font-size: 13px; color: var(--muted); margin: 4px 0 6px; }
      .legend .sw { display: inline-block; width: 14px; height: 14px; border-radius: 3px; vertical-align: -2px; margin-right: 6px; border: 1px solid var(--line); }
      .views-bar { display: flex; justify-content: flex-end; margin: 4px 0 0; }
      .views { display: inline-flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
      .view { font: inherit; font-size: 13px; border: 0; background: #fff; color: var(--muted); padding: 6px 12px; cursor: pointer; }
      .view.on { background: var(--soft); color: var(--ink); font-weight: 600; }
      /* Unified layout: both feeds' values stacked in one column, each labelled with its feed */
      table.unified thead th:nth-child(3) { display: none; }
      table.unified td.side { display: block; width: auto; border-bottom: 0; padding: 6px 8px; }
      table.unified td.side-b { border-bottom: 1px solid var(--line); }
      table.unified td.side::before { content: attr(data-feed); display: block; font-size: 11px; font-weight: 600; color: var(--muted); margin-bottom: 2px; }
      table.unified td.side-a.t-del::before { content: "− " attr(data-feed); color: #82071e; }
      table.unified td.side-b.t-add::before { content: "+ " attr(data-feed); color: #0b5a23; }
      table.unified tr { display: table-row; }
      table.unified td:first-child, table.unified td:last-child { vertical-align: top; }
      .badge { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px; }
      .b-diff { background: #fde8e8; color: #a12a2a; } .b-only { background: #fff1db; color: #8a4b00; }
      .b-format { background: #e8eef7; color: #2d4b73; } .b-system { background: #f0f0f0; color: #555; } .b-same { background: #e3f5e8; color: #17723a; }
      .card.b-diff b { color: #a12a2a; } .card.b-only b { color: #8a4b00; } .card.b-format b { color: #2d4b73; } .card.b-same b { color: #17723a; }
      tr.hide { display: none; }
      .none { color: #9aa5af; }
      footer { margin-top: 24px; font-size: 12px; color: var(--muted); }
      @media (max-width: 900px) { .cards { grid-template-columns: repeat(3, 1fr); } .photos { grid-template-columns: 1fr; } }
      /* Printing / PDF: no interactive controls, keep the diff colours, don't split rows across pages */
      @page { size: letter landscape; margin: 12mm; }
      @media print {
        * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body { font-size: 12px; }
        .wrap { max-width: none; padding: 0; }
        .controls, .views-bar, .exact, .no-match { display: none !important; }
        .card { cursor: default; padding: 8px 10px; } .card b { font-size: 20px; }
        th { position: static; }
        thead { display: table-header-group; }
        tr, .card, .run, .photos { break-inside: avoid; }
        .strip { flex-wrap: wrap; overflow: visible; }
        a { color: inherit; }
      }
    CSS

    JS = <<~'JS'.freeze
      (function () {
        // Each listing's diff section has its own cards, search box and "show matching" switch
        document.querySelectorAll("section.cmp").forEach(sec => {
          const rows = [...sec.querySelectorAll("tbody tr")], filter = sec.querySelector(".filter");
          const showSame = sec.querySelector(".show-same"), noMatch = sec.querySelector(".no-match");
          const cards = sec.querySelectorAll(".card");
          let only = null; // a single status picked from the summary cards
          function apply() {
            const q = filter.value.trim().toLowerCase();
            let shown = 0;
            rows.forEach(r => {
              const st = r.dataset.status;
              let ok = only ? st === only : (st !== "same" || showSame.checked);
              if (q && !r.dataset.search.includes(q)) ok = false;
              r.classList.toggle("hide", !ok);
              if (ok) shown++;
            });
            noMatch.hidden = shown > 0;
            cards.forEach(c => c.classList.toggle("active", c.dataset.show === only));
          }
          cards.forEach(c => c.onclick = () => { only = only === c.dataset.show ? null : c.dataset.show; apply(); });
          sec.querySelector(".reset").onclick = () => { only = null; showSame.checked = false; filter.value = ""; apply(); };
          filter.addEventListener("input", apply);
          showSame.onchange = apply;
          apply();
        });
        // Split / unified layout for every diff table, remembered per browser when storage is available
        const tables = document.querySelectorAll("table.diff");
        function layout(mode) {
          tables.forEach(t => { t.classList.toggle("split", mode === "split"); t.classList.toggle("unified", mode === "unified"); });
          ["split", "unified"].forEach(m => {
            const b = document.getElementById("view-" + m);
            if (!b) return;
            b.classList.toggle("on", m === mode);
            b.setAttribute("aria-pressed", m === mode);
          });
          try { localStorage.setItem("reso-compare-view", mode); } catch (e) {}
        }
        const split = document.getElementById("view-split"), unified = document.getElementById("view-unified");
        if (split) split.onclick = () => layout("split");
        if (unified) unified.onclick = () => layout("unified");
        let saved = null;
        try { saved = localStorage.getItem("reso-compare-view"); } catch (e) {}
        if (saved === "unified") layout("unified");
      })();
    JS
  end
end
