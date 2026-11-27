require "cgi"

module ResoCli
  # HTML report comparing two MLS connections on the same query: the exact request each one
  # got, how long each took, and a red/green diff of every listing returned.
  module MlsReport
    PROJECT_URL = "https://github.com/danwoolley/reso_cli".freeze

    module_function

    # prompt:  the request in the user's words (shown as asked)
    # runs:    [{ name:, url:, ms:, count: }, { ... }] — baseline first
    # pairs:   [{ id:, a: record, b: record }] in the baseline's order: listings both MLSs have
    # extra_b: MLS numbers the second feed returned that the baseline didn't
    # skipped: baseline MLS numbers left out because the second MLS doesn't have them
    # wanted:  how many listings were asked for
    def html(prompt:, runs:, pairs:, extra_b: [], skipped: [], wanted: nil, generated_at: Time.now)
      h = ->(s) { CGI.escapeHTML(s.to_s) }
      a_run, b_run = runs
      a_name = a_run[:name]
      b_name = b_run[:name]
      title = "MLS comparison: #{a_name} vs #{b_name}"

      run_cards = runs.each_with_index.map do |r, i|
        <<~RUN
          <div class="run">
            <div class="run-head"><b>#{h.(r[:name])}</b>#{i.zero? ? ' <span class="base">baseline</span>' : ''}</div>
            <div class="ms"><b>#{h.(DetailPage.commas(r[:ms]))}</b> ms round trip</div>
            <div class="muted">#{h.(r[:count])} listing#{r[:count] == 1 ? '' : 's'} returned</div>
            <div class="url-label">Query</div>
            <code class="url">#{h.(readable_url(r[:url]))}</code>
            <details class="exact"><summary>Exact URL as sent</summary><code class="url">#{h.(r[:url])}</code></details>
          </div>
        RUN
      end.join

      diff = (a_run[:ms] - b_run[:ms]).abs
      speed = if diff.zero?
                "Both took the same time."
              else
                faster, slower = a_run[:ms] < b_run[:ms] ? [a_run, b_run] : [b_run, a_run]
                pct = slower[:ms].zero? ? 0 : (diff * 100.0 / slower[:ms]).round
                "<b>#{h.(faster[:name])}</b> was faster by <b>#{h.(DetailPage.commas(diff))} ms</b> (#{pct}% less time than #{h.(slower[:name])})."
              end
      max = [a_run[:ms], b_run[:ms], 1].max
      bars = runs.map do |r|
        width = (r[:ms] * 100.0 / max).round(1)
        %(<div class="bar-row"><span class="bar-name">#{h.(r[:name])}</span><span class="bar"><span style="width:#{width}%"></span></span><span class="bar-ms">#{h.(DetailPage.commas(r[:ms]))} ms</span></div>)
      end.join

      toc = pairs.each_with_index.map do |p, i|
        %(<li><a href="#listing-#{i + 1}">#{h.(address(p[:a], p[:id]))}</a> <span class="muted">MLS # #{h.(p[:id])}</span></li>)
      end.join

      sections = pairs.each_with_index.map do |p, i|
        <<~LISTING
          <div class="listing">
            <h3 id="listing-#{i + 1}">#{i + 1}. #{h.(address(p[:a], p[:id]))} <span class="muted">MLS # #{h.(p[:id])}</span></h3>
            #{ComparePage.section(a_name, p[:a], b_name, p[:b])}
          </div>
        LISTING
      end.join

      notes = []
      notes << "These are the first #{pairs.size} listings matching the query that both MLSs have." if pairs.any?
      if skipped.any?
        notes << "Skipped #{skipped.size} listing#{skipped.size == 1 ? '' : 's'} that #{h.(b_name)} doesn't have: #{h.(skipped.join(', '))}."
      end
      if wanted && pairs.size < wanted
        notes << "Only #{pairs.size} of the #{wanted} listings asked for are in both MLSs."
      end
      if extra_b.any?
        notes << "#{h.(b_name)} also returned #{extra_b.size} listing#{extra_b.size == 1 ? '' : 's'} that #{h.(a_name)} didn't: #{h.(extra_b.join(', '))}."
      end
      extra = notes.empty? ? "" : %(<p class="muted">#{notes.join(' ')}</p>)

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h.(title)}</title>
        <style>#{ComparePage::CSS}#{CSS}</style>
        </head>
        <body>
        <div class="wrap">
          <header>
            <div class="kicker">MLS comparison report</div>
            <h1>#{h.(title)}</h1>
            <p class="sub">Generated #{h.(generated_at.utc.strftime('%b %-d, %Y, %-I:%M %p UTC'))} by reso_cli, <a href="#{PROJECT_URL}">#{PROJECT_URL}</a></p>
          </header>

          <h2>Prompt</h2>
          <blockquote class="prompt">#{h.(prompt)}</blockquote>

          <h2>Queries</h2>
          <div class="runs">#{run_cards}</div>

          <h2>Speed</h2>
          <p class="speed">#{speed}</p>
          <div class="bars">#{bars}</div>
          <p class="muted">Round trip = the time from sending the query to receiving the full response, measured on this computer after signing in, so sign-in and metadata downloads aren't counted. One run per feed; timings vary from run to run.</p>

          <h2>Listing diffs</h2>
          #{extra}
          <ol class="toc">#{toc}</ol>
          #{ComparePage.legend(a_name, b_name)}
          #{ComparePage.view_toggle}
          #{sections}

          #{ComparePage.footer(a_name, b_name)}
        </div>
        <script>#{ComparePage::JS}</script>
        </body>
        </html>
      HTML
    end

    # The query URL with its percent-encoding undone ($filter, quotes, spaces), for reading
    def readable_url(url)
      CGI.unescape(url.to_s.gsub("+", "%2B")).gsub("%2B", "+")
    rescue ArgumentError
      url.to_s
    end

    def address(listing, id)
      a = Slideshow.address(listing)
      a.empty? ? "Listing #{id}" : a
    end

    CSS = <<~'CSS'.freeze
      h2 { font-size: 19px; margin: 28px 0 10px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
      .prompt { margin: 0; padding: 12px 16px; background: var(--soft); border-left: 4px solid var(--accent); border-radius: 0 8px 8px 0; font-size: 16px; }
      .runs { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
      .run { border: 1px solid var(--line); border-radius: 12px; padding: 14px 16px; min-width: 0; }
      .run-head { font-size: 17px; margin-bottom: 4px; }
      .ms b { font-size: 26px; }
      .url-label { margin-top: 10px; font-size: 11px; text-transform: uppercase; letter-spacing: .4px; color: var(--muted); }
      code.url { display: block; margin-top: 4px; padding: 8px 10px; background: var(--soft); border-radius: 6px; font-size: 12px; color: var(--ink); overflow-wrap: anywhere; white-space: pre-wrap; }
      .exact { margin-top: 6px; font-size: 12px; color: var(--muted); } .exact summary { cursor: pointer; }
      .muted { color: var(--muted); font-size: 13px; }
      .speed { font-size: 16px; margin: 4px 0 10px; }
      .bars { display: grid; gap: 6px; max-width: 720px; margin-bottom: 8px; }
      .bar-row { display: grid; grid-template-columns: 110px 1fr 90px; gap: 10px; align-items: center; font-size: 14px; }
      .bar { background: var(--soft); border-radius: 4px; height: 14px; overflow: hidden; }
      .bar span { display: block; height: 100%; background: var(--accent); border-radius: 4px; }
      .bar-ms { text-align: right; font-variant-numeric: tabular-nums; }
      .toc { margin: 6px 0 16px; padding-left: 22px; } .toc li { margin: 3px 0; }
      .listing { margin-top: 30px; padding-top: 6px; border-top: 2px solid var(--line); }
      .listing h3 { font-size: 18px; margin: 10px 0 0; scroll-margin-top: 12px; }
      @media (max-width: 900px) { .runs { grid-template-columns: 1fr; } }
      @media print {
        .listing { break-before: page; border-top: 0; margin-top: 0; }
        .toc a { color: inherit; }
        .bar span { background: #0a66c2; }
      }
    CSS
  end
end
