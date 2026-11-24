require "test_helper"
require "date"

# Listing detail page: field grouping, labels, value formatting and page content (no server, no browser)
class DetailPageTest < Minitest::Test
  include CliHelper

  D = ResoCli::DetailPage

  LISTING = {
    "ListingId" => "OC123", "ListingKey" => "1191750288", "StandardStatus" => "Active", "PropertyType" => "Residential",
    "PropertySubType" => "Single Family Residence", "UnparsedAddress" => "85 Sedgewick", "City" => "Irvine",
    "StateOrProvince" => "CA", "PostalCode" => "92620", "Latitude" => 33.703256, "Longitude" => -117.736416,
    "ListPrice" => 1_650_000.0, "OriginalListPrice" => 1_670_000.0, "BedroomsTotal" => 3, "BathroomsTotalInteger" => 3,
    "LivingArea" => 1712.0, "LotSizeSquareFeet" => 3000.0, "YearBuilt" => 2013, "AssociationFee" => 152.0,
    "AssociationFeeFrequency" => "Monthly", "GarageSpaces" => 2.0, "Cooling" => ["Central Air"], "CoolingYN" => true,
    "PoolPrivateYN" => false, "DaysOnMarket" => 45, "PublicRemarks" => "Welcome home.",
    "ListAgentFullName" => "Joe Yan", "ListOfficeName" => "Gold Orange Realty", "ListAgentEmail" => "joe@example.com",
    "ListAgentURL" => "https://example.com/joe", "ElementarySchool" => "Stonegate", "Appliances" => nil,
    "OnMarketTimestamp" => DateTime.new(2026, 9, 30, 15, 9, 14), "ListingContractDate" => Date.new(2026, 9, 25),
    "RecordSignature" => 1_361_463_392, "Media" => [{ "MediaURL" => "https://x/1.jpg" }]
  }.freeze

  PHOTOS = [{ "url" => "https://x/1.jpg", "caption" => "" }].freeze

  def page(listing = LISTING, photos = PHOTOS) = D.html(listing, photos, mls_name: "CRMLS")

  # -- grouping and labels --

  def test_fields_are_grouped_into_sections
    {
      "BedroomsTotal" => "Interior", "Cooling" => "Interior", "LotSizeSquareFeet" => "Exterior & lot",
      "PoolPrivateYN" => "Exterior & lot", "AssociationFee" => "Community & HOA", "ElementarySchool" => "Schools",
      "ListPrice" => "Price & listing history", "ListAgentFullName" => "Agents & offices", "City" => "Location",
      "ListingKey" => "Source & system", "PublicRemarks" => "Remarks", "SomethingUnusual" => "Other"
    }.each { |field, section| assert_equal section, D.section_for(field), field }
  end

  def test_labels
    assert_equal "Bathrooms", D.label("BathroomsTotalInteger")
    assert_equal "Living area", D.label("LivingArea")
    assert_equal "Association fee frequency", D.label("AssociationFeeFrequency")
    assert_equal "MLS area", D.label("MLSAreaMajor")
    assert_equal "List agent AOR", D.label("ListAgentAOR")
    assert_equal "Cooling?", D.label("CoolingYN"), "yes/no flags don't clash with their companion field"
  end

  # -- value formatting --

  def test_value_formatting
    assert_equal "$1,650,000", D.text("ListPrice", 1_650_000.0)
    assert_equal "$152.50", D.text("AssociationFee", 152.5)
    assert_equal "Monthly", D.text("AssociationFeeFrequency", "Monthly")
    assert_equal "1,712 sq ft", D.text("LivingArea", 1712.0)
    assert_equal "0.07 acres", D.text("LotSizeAcres", 0.0689)
    assert_equal "-1.2%", D.text("DerivedPriceChangePercentage", -1.2)
    assert_equal "2013", D.text("YearBuilt", 2013)
    assert_equal "2,100", D.text("NumberOfUnitsInCommunity", 2100)
    assert_equal "1361463392", D.text("RecordSignature", 1_361_463_392), "IDs get no thousands separators"
    assert_equal "Yes", D.text("CoolingYN", true)
    assert_equal "No", D.text("PoolPrivateYN", false)
    assert_equal "Central Air, Evaporative", D.text("Cooling", ["Central Air", "Evaporative"])
    assert_equal "Cash, Cash To New Loan, FHA", D.text("ListingTerms", %w[Cash CashToNewLoan FHA])
    assert_equal "McDonald", D.text("ListAgentLastName", "McDonald"), "single values are left as-is"
    assert_equal "Sep 30, 2026, 3:09 PM UTC", D.text("OnMarketTimestamp", DateTime.new(2026, 9, 30, 15, 9, 14))
    assert_equal "Sep 30, 2026, 3:09 PM UTC", D.text("OnMarketTimestamp", "2026-09-30T15:09:14+00:00")
    assert_equal "Sep 25, 2026", D.text("ListingContractDate", Date.new(2026, 9, 25))
    assert_equal "Sep 25, 2026", D.text("ListingContractDate", "2026-09-25")
  end

  def test_key_facts
    facts = D.key_facts(LISTING).to_h
    assert_equal "Single Family Residence", facts["Type"]
    assert_equal "2013", facts["Year built"]
    assert_equal "3,000 sq ft lot", facts["Lot"]
    assert_equal "$964", facts["Price/sq ft"]
    assert_equal "$152 monthly", facts["HOA"]
    assert_equal "2-car garage", facts["Parking"]
    assert_equal "Central Air", facts["Cooling"]
    refute facts.key?("Heating"), "facts missing from the record are left out"
  end

  # -- the page --

  def test_page_shows_headline_photos_map_and_agent
    html = page
    assert_includes html, "<h1>85 Sedgewick, Irvine, CA</h1>"
    assert_includes html, ">$1,650,000<"
    assert_includes html, "<b>1,712</b> sq ft"
    assert_includes html, "openstreetmap.org/export/embed.html"
    assert_includes html, "Joe Yan, Gold Orange Realty"
    assert_includes html, %(<a href="mailto:joe@example.com">)
    assert_includes html, "Show all 1 photos"
    assert_includes html, "Welcome home."
  end

  def test_every_field_appears_below_the_fold_except_media
    html = page
    LISTING.each_key do |field|
      next if field == "Media"

      assert_includes html, "<code>#{field}</code>", "#{field} should be listed in All listing details"
    end
    refute_includes html, "<code>Media</code>"
    assert_match(/<div class="row blank"[^>]*><dt>Appliances<code>Appliances<\/code>/, html, "empty fields are present but hidden by default")
  end

  def test_hidden_address_hides_street_and_map
    html = page(LISTING.merge("InternetAddressDisplayYN" => false))
    assert_includes html, "<h1>Irvine, CA, 92620</h1>"
    refute_includes html, "openstreetmap.org/export/embed.html"
    assert_includes html, "asked that the street address not be shown online"
  end

  def test_not_for_internet_display_notice
    assert_includes page(LISTING.merge("InternetEntireListingDisplayYN" => false)), "not approved for public internet display"
  end

  def test_lease_and_sold_prices
    assert_includes page(LISTING.merge("PropertyType" => "Residential Lease", "ListPrice" => 3800.0)), ">$3,800/mo<"
    sold = page(LISTING.merge("StandardStatus" => "Closed", "ClosePrice" => 1_600_000.0, "CloseDate" => "2026-11-01"))
    assert_includes sold, "Sold $1,600,000"
    assert_includes sold, "on Nov 1, 2026"
  end

  def test_no_photos_and_no_coordinates
    html = page(LISTING.reject { |k, _| %w[Latitude Longitude].include?(k) }, [])
    assert_includes html, "No photos for this listing"
    assert_includes html, "No map coordinates in this listing."
  end

  def test_listing_text_is_escaped
    html = page(LISTING.merge("PublicRemarks" => "<script>alert(1)</script>", "ListAgentURL" => "javascript:alert(1)"))
    refute_includes html, "<script>alert(1)</script>"
    refute_includes html, %(href="javascript:)
  end

  def test_cli_requires_a_listing_id
    result = cli("details")
    refute result.success?
    assert_match(/Usage: reso_cli details LISTING_ID/, result.stderr)
  end
end
