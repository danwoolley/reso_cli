require "test_helper"
require "date"

# Comparing listings between two feeds: field classification, the comparison page, and the batch report
class CompareTest < Minitest::Test
  include CliHelper

  C = ResoCli::Compare

  A = {
    "ListingId" => "OC1", "ListingKey" => "130720028185138196627", "StandardStatus" => "Active", "City" => "Irvine",
    "UnparsedAddress" => "85 Sedgewick", "StateOrProvince" => "CA", "ListPrice" => 1_650_000.0,
    "InteriorFeatures" => ["Walk-In Closet(s)"], "Latitude" => 33.703246, "ListOfficePhone" => "9495725372",
    "ListAgentURL" => "http://www.example.com", "TaxLot" => 25, "OnMarketDate" => Date.new(2026, 9, 30),
    "ModificationTimestamp" => "2026-11-14T19:13:21+00:00", "DerivedLotSizeAcres" => 0.07, "Appliances" => nil,
    "Media" => [{ "MediaURL" => "https://a/1.jpg" }]
  }.freeze

  B = {
    "ListingId" => "OC1", "ListingKey" => "1191750288", "StandardStatus" => "Active", "City" => "Irvine",
    "UnparsedAddress" => "85 Sedgewick", "StateOrProvince" => "CA", "ListPrice" => 1_650_000,
    "InteriorFeatures" => ["AllBedroomsUp", "Walk-In Closet(s)"], "Latitude" => 33.703256,
    "ListOfficePhone" => "949-572-5372", "ListAgentURL" => "www.example.com", "TaxLot" => "25",
    "OnMarketDate" => "2026-09-30", "ModificationTimestamp" => "2026-11-14T19:11:14+00:00",
    "ShowingInstructions" => "Call first", "Appliances" => [],
    "Media" => [{ "MediaURL" => "https://b/1.jpg" }, { "MediaURL" => "https://b/2.jpg" }]
  }.freeze

  def statuses = C.compare(A, B).to_h { |r| [r[:field], r[:status]] }

  # -- field classification --

  def test_classification
    st = statuses
    assert_equal :same, st["ListPrice"], "1650000.0 and 1650000 are the same number"
    assert_equal :same, st["OnMarketDate"], "a Date object and the same date as text are the same"
    assert_equal :same, st["City"]
    assert_equal :different, st["InteriorFeatures"]
    assert_equal :different, st["Latitude"], "numbers are compared exactly, never rounded"
    assert_equal :format, st["ListOfficePhone"], "phone punctuation is a format difference"
    assert_equal :format, st["ListAgentURL"], "http:// prefix is a format difference"
    assert_equal :format, st["TaxLot"], "a number sent as text is a format difference"
    assert_equal :system, st["ListingKey"], "each system assigns its own keys"
    assert_equal :system, st["ModificationTimestamp"]
    assert_equal :only_a, st["DerivedLotSizeAcres"]
    assert_equal :only_b, st["ShowingInstructions"]
    refute st.key?("Appliances"), "fields empty in both feeds are skipped"
    refute st.key?("Media"), "photos are compared separately"
  end

  def test_summary_counts_every_status
    counts = C.summary(C.compare(A, B))
    assert_equal %i[different format only_a only_b system same].sort, counts.keys.sort
    assert_equal C.compare(A, B).size, counts.values.sum
  end

  def test_list_diff
    diff = ResoCli::ComparePage.list_diff(%w[Cash Conventional], %w[Cash CashToNewLoan Conventional])
    assert_equal({ only_a: [], only_b: ["CashToNewLoan"] }, diff)
    assert_nil ResoCli::ComparePage.list_diff("a", ["a"])
  end

  # -- comparison page --

  def test_compare_page
    html = ResoCli::ComparePage.html("CDL", A, "CRMLS", B)
    assert_includes html, "<h1>85 Sedgewick, Irvine, CA</h1>"
    assert_includes html, "only in CRMLS: AllBedroomsUp"
    assert_includes html, "CDL · 1 photos"
    assert_includes html, "CRMLS · 2 photos"
    assert_includes html, %(data-status="format")
    assert_includes html, %(data-status="system")
  end

  def test_compare_page_escapes_listing_text
    html = ResoCli::ComparePage.html("CDL", A.merge("City" => "<script>x</script>"), "CRMLS", B)
    refute_includes html, "<script>x</script>"
  end

  def test_compare_cli_requires_two_mls
    result = cli("compare", "OC1", "--mls", "CDL")
    refute result.success?
    assert_match(/exactly two MLSs/, result.stderr)
  end

  def test_compare_report_cli_requires_a_selection
    add_bearer("One")
    add_bearer("Two")
    result = cli("compare-report", "--mls", "One", "--mls", "Two")
    refute result.success?
    assert_match(/Say which listings to compare/, result.stderr)
  end

  # -- batch report --

  def listing(id, extra = {})
    { "ListingId" => id, "UnparsedAddress" => "#{id} Main St", "City" => "Irvine", "StateOrProvince" => "CA",
      "StandardStatus" => "Active", "RoomType" => %w[Bedroom Kitchen], "ModificationTimestamp" => "2026-11-24T10:00:00Z" }.merge(extra)
  end

  def report
    pulled_a = Time.utc(2026, 11, 24, 18, 0, 0)
    pulled_b = Time.utc(2026, 11, 24, 18, 0, 5)
    a_records = [
      listing("M1"), listing("M2", "StandardStatus" => "Pending"), listing("STALE"),
      listing("M3", "RoomType" => %w[Bedroom])
    ]
    b_records = [
      listing("M1"), listing("M2"), listing("HIDDEN", "InternetEntireListingDisplayYN" => false),
      listing("GONE"), listing("M3", "RoomType" => %w[Bedroom Kitchen PrimaryBedroom])
    ]
    ResoCli::CompareReport.build(
      a_name: "CDL", b_name: "CRMLS", a_records: a_records, b_records: b_records,
      lookups_in_b: { "STALE" => listing("STALE", "StandardStatus" => "Canceled", "ModificationTimestamp" => "2026-11-24T17:00:00Z") },
      lookups_in_a: { "HIDDEN" => nil, "GONE" => nil },
      meta: { generated_at: pulled_b, a_pulled_at: pulled_a, b_pulled_at: pulled_b, a_endpoint: "https://a", b_endpoint: "https://b",
              selection: "test", filters: { "City" => "Irvine", "StandardStatus" => "Active" }, max: 100, capped: false,
              requested_ids: %w[M1 M2 M3 STALE HIDDEN GONE MISSING] }
    )
  end

  def test_report_summary_and_missing_listings
    md = report
    assert_includes md, "| Listings returned | 4 | 5 |"
    assert_includes md, "| Only in this feed | 1 | 2 |"
    assert_includes md, "StandardStatus is \"Canceled\" in CRMLS"
    assert_includes md, "≥ 60 min", "a change made in CRMLS at 17:00 still wasn't in CDL at its 18:00 pull"
    assert_includes md, "Not approved for internet display (InternetEntireListingDisplayYN = No); CDL doesn't include these"
    assert_includes md, "Not in CDL at all"
    assert_includes md, "**Not found in either feed (1):** MISSING"
  end

  def test_report_status_mismatches_and_field_stats
    md = report
    assert_includes md, "## Status mismatches among matched listings (1)"
    assert_match(/\| M2 \|.*\| Pending \|.*\| Active \|/, md)
    assert_match(/\| `RoomType` \| 1 of 3 \|/, md)
    assert_match(/\| `RoomType` \| Kitchen \| CRMLS \| 1 \|/, md)
    assert_match(/\| `RoomType` \| PrimaryBedroom \| CRMLS \| 1 \|/, md)
  end

  def test_missing_reason_with_several_values_for_a_filter
    filters = { "StandardStatus" => %w[Active Pending] }
    pending = listing("P1", "StandardStatus" => "Pending")
    reason = ResoCli::CompareReport.missing_reason(listing("P1"), pending, "CRMLS", filters, nil)
    refute_match(/StandardStatus is/, reason[:reason].to_s, "Pending is one of the values asked for")

    closed = listing("P1", "StandardStatus" => "Closed")
    reason = ResoCli::CompareReport.missing_reason(listing("P1"), closed, "CRMLS", filters, nil)
    assert_includes reason[:reason], "StandardStatus is \"Closed\" in CRMLS"
  end
end
