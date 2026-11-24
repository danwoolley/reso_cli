require "test_helper"

# Remarks, photos and virtual tours are left out of printed search/get results unless asked for.
class ProtectedTest < Minitest::Test
  def test_recognizes_protected_fields
    %w[PublicRemarks PrivateRemarks SyndicationRemarks Media MediaURL OriginalMediaUrl MediaHTML
       X_MediaStream VirtualTourURLBranded VirtualTourURLUnbranded].each do |name|
      assert ResoCli.protected_field?(name), "#{name} should be protected"
    end
  end

  def test_leaves_facts_alone
    %w[ListPrice ClosePrice CloseDate City BedroomsTotal PhotosCount MediaKey MediaType ListingId].each do |name|
      refute ResoCli.protected_field?(name), "#{name} should not be protected"
    end
  end

  def test_without_protected_drops_fields_and_names_them
    records = [
      { "ListingId" => "A1", "ListPrice" => 1_000_000, "PublicRemarks" => "Lovely home", "Media" => [{ "MediaURL" => "x" }] },
      { "ListingId" => "A2", "ListPrice" => 900_000, "VirtualTourURLUnbranded" => "https://tour" }
    ]
    cleaned, omitted = ResoCli.without_protected(records)

    assert_equal [{ "ListingId" => "A1", "ListPrice" => 1_000_000 }, { "ListingId" => "A2", "ListPrice" => 900_000 }], cleaned
    assert_equal %w[Media PublicRemarks VirtualTourURLUnbranded], omitted
    assert_equal "Lovely home", records.first["PublicRemarks"], "the original records are not modified"
  end

  def test_without_protected_with_nothing_to_drop
    cleaned, omitted = ResoCli.without_protected([{ "ClosePrice" => 1, "CloseDate" => "2026-11-01" }])
    assert_equal [{ "ClosePrice" => 1, "CloseDate" => "2026-11-01" }], cleaned
    assert_empty omitted
  end

  def test_include_protected_flag_is_parsed
    options = ResoCli.send(:parse_query_options, ["Property", "--include-protected", "--top", "1"])
    assert options[:include_protected]
    refute ResoCli.send(:parse_query_options, ["Property", "--top", "1"])[:include_protected]
  end
end
