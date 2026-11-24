require "test_helper"
require "date"

# Comparable sales: search criteria, ranking, value range and the page (no server)
class CompsTest < Minitest::Test
  include CliHelper

  C = ResoCli::Comps
  TODAY = Date.new(2026, 11, 24)

  SUBJECT = {
    "ListingId" => "SUBJ", "PropertyType" => "Residential", "PropertySubType" => "Single Family Residence",
    "StandardStatus" => "Active", "ListPrice" => 1_650_000.0, "LivingArea" => 1712.0, "BedroomsTotal" => 3,
    "BathroomsTotalInteger" => 3, "Latitude" => 33.703256, "Longitude" => -117.736416,
    "UnparsedAddress" => "85 Sedgewick", "City" => "Irvine", "StateOrProvince" => "CA"
  }.freeze

  def sale(id, price:, sqft:, beds: 3, lat: 33.7040, lng: -117.7350, closed: "2026-10-15")
    { "ListingId" => id, "StandardStatus" => "Closed", "PropertySubType" => "Single Family Residence",
      "ClosePrice" => price, "ListPrice" => price, "LivingArea" => sqft, "BedroomsTotal" => beds, "BathroomsTotalInteger" => 2,
      "Latitude" => lat, "Longitude" => lng, "CloseDate" => closed, "UnparsedAddress" => "#{id} Main", "City" => "Irvine" }
  end

  def test_criteria
    o = C.criteria(SUBJECT, months: 6, radius: 1, today: TODAY)
    assert_equal({ "StandardStatus" => "Closed", "PropertyType" => "Residential", "PropertySubType" => "Single Family Residence" }, o[:eq])
    assert_equal "2026-05-24", o[:ge]["CloseDate"]
    assert_equal [1284, 2140], [o[:ge]["LivingArea"], o[:le]["LivingArea"]]
    assert_equal [2, 4], [o[:ge]["BedroomsTotal"], o[:le]["BedroomsTotal"]]
    assert_in_delta 33.6888, o[:ge]["Latitude"], 0.001
    assert_in_delta(-117.7538, o[:ge]["Longitude"], 0.001)
  end

  def test_criteria_without_coordinates_falls_back_to_postal_code
    o = C.criteria(SUBJECT.reject { |k, _| %w[Latitude Longitude].include?(k) }.merge("PostalCode" => "92620"), months: 6, radius: 1, today: TODAY)
    assert_equal "92620", o[:eq]["PostalCode"]
    refute o[:ge].key?("Latitude")
  end

  def test_distance
    assert_in_delta 0.0, C.distance_miles(33.7, -117.7, 33.7, -117.7), 0.0001
    assert_in_delta 69.1, C.distance_miles(33.0, -117.0, 34.0, -117.0), 0.2
  end

  def test_rank_prefers_closer_similar_recent_sales_and_skips_bad_records
    candidates = [
      sale("FAR", price: 1_500_000.0, sqft: 1700.0, lat: 33.715, lng: -117.736),   # ~0.8 mi
      sale("NEAR", price: 1_550_000.0, sqft: 1720.0),                              # ~0.1 mi, similar size
      sale("BIG", price: 1_900_000.0, sqft: 2100.0),                               # near but bigger
      sale("OUTSIDE", price: 1_400_000.0, sqft: 1700.0, lat: 33.75, lng: -117.736), # beyond the 1 mi radius
      sale("NOPRICE", price: nil, sqft: 1700.0),
      SUBJECT.merge("ClosePrice" => 1.0, "CloseDate" => "2026-10-01")             # the subject itself
    ]
    ranked = C.rank(SUBJECT, candidates, radius: 1, months: 6, max: 10, today: TODAY)
    assert_equal %w[NEAR BIG FAR], ranked.map { |c| c.record["ListingId"] }
    assert_in_delta 1_550_000.0 / 1720, ranked.first.ppsf, 0.01
    assert_equal 1.3, ranked.first.months_ago
    assert_equal 2, C.rank(SUBJECT, candidates, radius: 1, months: 6, max: 2, today: TODAY).size
  end

  def test_estimate
    comps = [700.0, 750.0, 800.0, 850.0].map { |p| C::Comp.new(record: {}, ppsf: p) }
    est = C.estimate(SUBJECT, comps)
    assert_equal 775.0, est[:median_ppsf]
    assert_equal 737.5, est[:low_ppsf]
    assert_equal 812.5, est[:high_ppsf]
    assert_equal 1_327_000.0, est[:value]
    assert_nil C.estimate(SUBJECT, comps.first(2)), "fewer than 3 comps gives no range"
  end

  def test_page
    comps = C.rank(SUBJECT, [sale("A", price: 1_500_000.0, sqft: 1800.0), sale("B", price: 1_600_000.0, sqft: 1750.0),
                             sale("C", price: 1_450_000.0, sqft: 1690.0)], radius: 1, months: 6, max: 10, today: TODAY)
    html = ResoCli::CompsPage.html(SUBJECT, comps, estimate: C.estimate(SUBJECT, comps), photo_for: { "A" => "https://x/a.jpg" },
                                   mls_name: "CRMLS", months: 6, radius: 1.0)
    assert_includes html, "<h1>85 Sedgewick, Irvine, CA</h1>"
    assert_includes html, "3 closed Single Family Residence sales within 1.0 mi"
    assert_includes html, "Value range from these comps"
    assert_includes html, "not an appraisal"
    assert_includes html, %(<img src="https://x/a.jpg")
    assert_includes html, "tile.openstreetmap.org"
    assert_includes html, '"subject":{"lat":33.703256'
  end

  def test_page_with_too_few_comps
    html = ResoCli::CompsPage.html(SUBJECT, [], estimate: nil, photo_for: {}, mls_name: "CRMLS", months: 12, radius: 2.0, widened: true)
    assert_includes html, "Not enough comps"
    assert_includes html, "No comparable sales found."
    assert_includes html, "The search was widened"
  end

  def test_cli_requires_a_listing_id
    result = cli("comps")
    refute result.success?
    assert_match(/Usage: reso_cli comps LISTING_ID/, result.stderr)
  end
end
