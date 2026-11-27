require "test_helper"

# The MLS comparison report (two MLSs, same query, timings + listing diffs) and copying reports to a Drive folder
class MlsReportTest < Minitest::Test
  include CliHelper

  A = { "ListingId" => "OC1", "UnparsedAddress" => "85 Sedgewick", "City" => "Irvine", "StateOrProvince" => "CA",
        "ListPrice" => 1_650_000, "RoomType" => %w[Kitchen Bedroom], "Media" => [] }.freeze
  B = { "ListingId" => "OC1", "UnparsedAddress" => "85 Sedgewick", "City" => "Irvine", "StateOrProvince" => "CA",
        "ListPrice" => 1_650_000, "RoomType" => %w[Kitchen], "Media" => [] }.freeze
  A2 = { "ListingId" => "OC2", "UnparsedAddress" => "1 Main", "City" => "Irvine", "StateOrProvince" => "CA", "Media" => [] }.freeze

  def runs
    [{ name: "MLS-A", url: "https://a.example.com/odata/Property?%24filter=City%20eq%20%27Irvine%27&%24top=5", ms: 564, count: 2 },
     { name: "MLS-B", url: "https://b.example.com/odata/Property?%24filter=City%20eq%20%27Irvine%27&%24top=5", ms: 954, count: 1 }]
  end

  B2 = A2.merge("ListPrice" => 900_000).freeze

  def report(**opts)
    ResoCli::MlsReport.html(prompt: "Compare MLS-A and MLS-B on five Irvine listings", runs: runs,
                            pairs: [{ id: "OC1", a: A, b: B }, { id: "OC2", a: A2, b: B2 }], **opts)
  end

  def test_report_sections
    html = report
    assert_includes html, "<h1>MLS comparison: MLS-A vs MLS-B</h1>"
    assert_match(%r{Generated .* by reso_cli, <a href="https://github.com/danwoolley/reso_cli">https://github.com/danwoolley/reso_cli</a>}, html)
    assert_includes html, %(<blockquote class="prompt">Compare MLS-A and MLS-B on five Irvine listings</blockquote>)
    assert_includes html, "https://a.example.com/odata/Property?$filter=City eq &#39;Irvine&#39;&amp;$top=5", "the query URL is shown readable"
    assert_includes html, "%24filter=City%20eq%20%27Irvine%27", "and exactly as sent"
    assert_includes html, "<b>564</b> ms round trip"
    assert_includes html, "<b>954</b> ms round trip"
    assert_includes html, "<b>MLS-A</b> was faster by <b>390 ms</b> (41% less time than MLS-B)."
  end

  def test_report_has_a_diff_per_listing
    html = report
    assert_equal 2, html.scan(%(<section class="cmp")).size
    assert_includes html, %(<h3 id="listing-1">1. 85 Sedgewick, Irvine, CA)
    assert_includes html, %(<span class="chip chip-del"><b>−</b>Bedroom</span>), "uses the red/green listing diff"
    assert_includes html, "These are the first 2 listings matching the query that both MLSs have."
    assert_includes html, %(<a href="#listing-2">)
    assert_includes html, %(id="view-unified"), "one layout switch for every diff"
  end

  def test_report_notes_listings_only_the_second_mls_returned
    assert_includes report(extra_b: %w[OC9]), "MLS-B also returned 1 listing that MLS-A didn't: OC9."
  end

  def test_report_notes_skipped_listings
    html = report(skipped: %w[OC7 OC8], wanted: 5)
    assert_includes html, "Skipped 2 listings that MLS-B doesn't have: OC7, OC8."
    assert_includes html, "Only 2 of the 5 listings asked for are in both MLSs."
    refute_includes report(wanted: 2), "Only 2 of the 2"
  end

  def test_report_equal_times
    r = runs
    r[1] = r[1].merge(ms: 564)
    html = ResoCli::MlsReport.html(prompt: "p", runs: r, pairs: [])
    assert_includes html, "Both took the same time."
  end

  def test_report_escapes_text
    html = ResoCli::MlsReport.html(prompt: "<script>x</script>", runs: runs, pairs: [])
    refute_includes html, "<script>x</script>"
  end

  # -- CLI --

  def test_mls_report_needs_two_mls_and_filters
    refute cli("mls-report", "--mls", "A").success?
    add_bearer("A")
    add_bearer("B")
    result = cli("mls-report", "--mls", "A", "--mls", "B")
    refute result.success?
    assert_match(/Add search filters/, result.stderr)
    result = cli("mls-report", "--mls", "A", "--mls", "B", "--eq", "City=Irvine", "--top", "100")
    assert_match(/--top must be between 1 and 25/, result.stderr)
  end

  def test_drive_folder_setting_and_copy
    drive = File.join(@tmpdir, "Drive", "MLS Reports")
    refute cli("copy-report").success?, "no reports yet"

    report = File.join(@tmpdir, "cache", "mls-reports", "mls-report-A-vs-B.html")
    FileUtils.mkdir_p(File.dirname(report))
    File.write(report, "<html>report</html>")

    result = cli("copy-report")
    refute result.success?
    assert_match(/No Drive folder set/, result.stderr)

    result = cli("settings", "drive-folder", drive)
    refute result.success?, "the parent folder must exist"
    FileUtils.mkdir_p(File.dirname(drive))
    result = cli("settings", "drive-folder", drive)
    assert result.success?, result.stderr
    assert result.json["created"]
    assert_match(/isn't inside Google Drive for desktop/, result.json["note"])
    assert_equal drive, cli("settings").json["drive_folder"]

    no_pdf = cli("copy-report")
    refute no_pdf.success?, "only the PDF is copied by default, and this report has none"
    assert_match(/This report has no PDF/, no_pdf.stderr)

    html_only = cli("copy-report", "--html-only")
    assert html_only.success?, html_only.stderr
    copied = html_only.json["copied"].map { |c| c["to"] }
    assert_equal [File.join(drive, "mls-report-A-vs-B.html")], copied
    refute_includes html_only.stdout, "<html>", "the report's contents are never printed"
    assert_equal "<html>report</html>", File.read(copied.first)

    # With a PDF beside the report, only the PDF is copied; --with-html adds the HTML
    File.write(report.sub(".html", ".pdf"), "%PDF-1.4 fake")
    pdf = cli("copy-report")
    assert_equal ["mls-report-A-vs-B.pdf"], pdf.json["copied"].map { |c| File.basename(c["to"]) }
    again = cli("copy-report", report)
    assert_equal ["mls-report-A-vs-B-2.pdf"], again.json["copied"].map { |c| File.basename(c["to"]) }, "an existing copy isn't overwritten"
    both = cli("copy-report", "--with-html")
    assert_equal %w[mls-report-A-vs-B-2.html mls-report-A-vs-B-3.pdf], both.json["copied"].map { |c| File.basename(c["to"]) }
  end

  # -- PDF export --

  def fake_chrome
    path = File.join(@tmpdir, "fake-chrome")
    File.write(path, <<~SH)
      #!/bin/sh
      for a in "$@"; do
        case "$a" in --print-to-pdf=*) out="${a#--print-to-pdf=}";; file://*) src="$a";; esac
      done
      printf '%%PDF-1.4 %s' "$src" > "$out"
    SH
    File.chmod(0o755, path)
    path
  end

  def test_print_pdf_uses_the_browser_and_cleans_up
    html = File.join(@tmpdir, "my report.html")
    File.write(html, %(<img src="x.jpg" loading="lazy">))
    pdf = File.join(@tmpdir, "my report.pdf")
    with_env("RESO_CLI_CHROME" => fake_chrome) do
      assert_equal pdf, ResoCli.print_pdf(html, pdf)
    end
    assert_match(%r{\A%PDF-1\.4 file://.*/my%20report\.print\.html\z}, File.read(pdf), "prints a copy, with spaces escaped in its URL")
    refute File.exist?(File.join(@tmpdir, "my report.print.html")), "the temporary copy is removed"
  end

  def test_print_pdf_without_a_browser
    html = File.join(@tmpdir, "r.html")
    File.write(html, "<p>x</p>")
    with_env("RESO_CLI_CHROME" => File.join(@tmpdir, "missing")) do
      assert_nil ResoCli.chrome_path
      assert_nil ResoCli.print_pdf(html, File.join(@tmpdir, "r.pdf"))
    end
  end

  def test_print_styles_hide_controls
    css = ResoCli::ComparePage::CSS
    assert_includes css, "@media print"
    assert_includes css, ".controls, .views-bar, .exact, .no-match { display: none !important; }"
    assert_includes ResoCli::MlsReport::CSS, ".listing { break-before: page;"
  end

  private

  def with_env(vars)
    saved = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end
end
