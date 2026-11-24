require "test_helper"

# Photo slideshow page generation (no server, no browser)
class SlideshowTest < Minitest::Test
  include CliHelper

  LISTING = {
    "ListingId" => "OC123", "UnparsedAddress" => "85 Sedgewick", "City" => "Irvine", "StateOrProvince" => "CA",
    "ListPrice" => 1_650_000.0, "BedroomsTotal" => 3, "BathroomsTotalInteger" => 3, "LivingArea" => 1712.0,
    "StandardStatus" => "Active"
  }.freeze

  def test_photos_are_sorted_by_order_with_unordered_last
    media = [
      { "MediaURL" => "https://x/c.jpg", "Order" => 2 },
      { "MediaURL" => "https://x/none.jpg" },
      { "MediaURL" => "https://x/a.jpg", "Order" => 0, "ShortDescription" => "Front" },
      { "MediaURL" => "https://x/b.jpg", "Order" => 1, "LongDescription" => "Kitchen " }
    ]
    photos = ResoCli::Slideshow.photos(media)
    assert_equal %w[a b c none], photos.map { |p| File.basename(p["url"], ".jpg") }
    assert_equal ["Front", "Kitchen", "", ""], photos.map { |p| p["caption"] }
  end

  def test_non_photos_are_skipped
    media = [
      { "MediaURL" => "https://x/photo.jpg", "MediaCategory" => "Photo" },
      { "MediaURL" => "https://x/tour", "MediaCategory" => "Virtual Tour" },
      { "MediaURL" => "https://x/video.mp4", "MediaType" => "video/mp4" },
      { "MediaURL" => "https://x/disclosures.pdf" },
      { "MediaURL" => "not-a-url" },
      { "Order" => 1 }
    ]
    assert_equal ["https://x/photo.jpg"], ResoCli::Slideshow.photos(media).map { |p| p["url"] }
    assert_equal [], ResoCli::Slideshow.photos(nil)
  end

  def test_address_and_facts
    assert_equal "85 Sedgewick, Irvine, CA", ResoCli::Slideshow.address(LISTING)
    no_unparsed = { "StreetNumberNumeric" => 12, "StreetName" => "Main", "StreetSuffix" => "St", "City" => "Irvine" }
    assert_equal "12 Main St, Irvine", ResoCli::Slideshow.address(no_unparsed)
    assert_equal ["$1,650,000", "3 bd", "3 ba", "1,712 sq ft", "Active", "MLS # OC123"], ResoCli::Slideshow.facts(LISTING)
  end

  def test_html_contains_header_and_photo_data
    photos = [{ "url" => "https://x/a.jpg", "caption" => "Front" }]
    html = ResoCli::Slideshow.html(LISTING, photos, mls_name: "CRMLS")
    assert_includes html, "<h1>85 Sedgewick, Irvine, CA</h1>"
    assert_includes html, "$1,650,000 · 3 bd · 3 ba · 1,712 sq ft · Active · MLS # OC123 · via CRMLS"
    assert_includes html, '"url":"https://x/a.jpg"'
  end

  def test_html_escapes_listing_text_and_cannot_break_out_of_script
    listing = LISTING.merge("UnparsedAddress" => "<b>1 Evil</b> & Co")
    photos = [{ "url" => "https://x/a.jpg", "caption" => "</script><script>alert(1)</script>" }]
    html = ResoCli::Slideshow.html(listing, photos)
    assert_includes html, "&lt;b&gt;1 Evil&lt;/b&gt; &amp; Co"
    refute_includes html, "</script><script>alert(1)"
  end

  def test_cli_requires_a_listing_id
    result = cli("photos")
    refute result.success?
    assert_match(/Usage: reso_cli photos LISTING_ID/, result.stderr)
  end
end
