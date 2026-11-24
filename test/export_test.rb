require "test_helper"
require "csv"

# Saving results to files (--output) and fetching every page (--all / --max), without a server.
class ExportTest < Minitest::Test
  # Stands in for a ResoTransport query: a first page plus @odata.nextLink pages
  class FakeQuery
    FakeResource = Struct.new(:pages) do
      def get_next_link_results(link) = pages.fetch(link)
      def parse(values) = values
    end

    attr_reader :next_link, :resource

    def initialize(first_page, first_link, later_pages)
      @first_page = first_page
      @next_link = first_link
      @resource = FakeResource.new(later_pages)
    end

    def results = @first_page.dup
    def handle_response(page) = page
  end

  def setup
    @dir = Dir.mktmpdir("reso_cli-export")
    @old_pwd = ENV["RESO_CLI_PWD"]
    ENV["RESO_CLI_PWD"] = @dir
  end

  def teardown
    ENV["RESO_CLI_PWD"] = @old_pwd
    FileUtils.remove_entry(@dir)
  end

  def three_page_query
    FakeQuery.new(
      [{ "Id" => 1 }, { "Id" => 2 }], "page2",
      { "page2" => { "value" => [{ "Id" => 3 }, { "Id" => 4 }], "@odata.nextLink" => "page3" },
        "page3" => { "value" => [{ "Id" => 5 }] } }
    )
  end

  def fetch(query, **opts)
    capture_io { @fetched = ResoCli.send(:fetch_results, query, **opts) }
    @fetched
  end

  def test_first_page_only_by_default
    result = fetch(three_page_query)
    assert_equal [1, 2], result[:records].map { |r| r["Id"] }
    assert_equal "page2", result[:next_link]
    refute result[:hit_max]
  end

  def test_all_follows_every_page
    result = fetch(three_page_query, all: true, max: 100)
    assert_equal [1, 2, 3, 4, 5], result[:records].map { |r| r["Id"] }
    assert_nil result[:next_link]
    refute result[:hit_max]
  end

  def test_all_stops_at_max
    result = fetch(three_page_query, all: true, max: 3)
    assert_equal [1, 2, 3], result[:records].map { |r| r["Id"] }
    assert result[:hit_max]
  end

  def test_json_output
    path = ResoCli.send(:write_records, "out/listings.json", [{ "Id" => 1, "City" => "Irvine" }])
    assert_equal File.join(@dir, "out", "listings.json"), path, "relative to where reso_cli was run; folders created"
    assert_equal [{ "Id" => 1, "City" => "Irvine" }], JSON.parse(File.read(path))
  end

  def test_csv_output
    records = [
      { "Id" => 1, "City" => "Irvine", "Media" => [{ "MediaURL" => "https://x/1.jpg" }] },
      { "Id" => 2, "ListPrice" => 1_500_000.0, "City" => "Costa Mesa, CA" }
    ]
    path = ResoCli.send(:write_records, "listings.CSV", records)
    rows = CSV.read(path)
    assert_equal %w[Id City Media ListPrice], rows[0], "union of fields, in first-seen order"
    assert_equal ["1", "Irvine", '[{"MediaURL":"https://x/1.jpg"}]', nil], rows[1], "nested data as JSON text; missing fields blank"
    assert_equal ["2", "Costa Mesa, CA", nil, "1500000.0"], rows[2]
  end

  def test_save_summary_notes
    more = ResoCli.send(:save_summary, "a.json", { records: [{}], next_link: "x", hit_max: false, max: 10 })
    assert_equal "json", more[:format]
    assert_match(/--all/, more[:note])

    capped = ResoCli.send(:save_summary, "b.csv", { records: [{}], next_link: "x", hit_max: true, max: 10 })
    assert_equal "csv", capped[:format]
    assert_match(/--max limit of 10/, capped[:note])

    done = ResoCli.send(:save_summary, "c.json", { records: [{}], next_link: nil, hit_max: false, max: 10 })
    assert_nil done[:note]
  end

  def test_option_parsing
    options = ResoCli.send(:parse_query_options, %w[Property --all --max 500 --output x.csv --top 50])
    assert_equal true, options[:all]
    assert_equal 500, options[:max]
    assert_equal "x.csv", options[:output]
    assert_equal 50, options[:top]
  end
end
