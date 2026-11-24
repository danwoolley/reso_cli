require "test_helper"
require "date"

# Price and status history on the details page
class HistoryTest < Minitest::Test
  H = ResoCli::History

  def tx(time, change_type, field, previous, new_value)
    { "ModificationTimestamp" => time, "ChangeType" => change_type, "FieldName" => field,
      "PreviousValue" => previous, "NewValue" => new_value }
  end

  # The 85 Sedgewick history from CRMLS, plus a sale
  TRANSACTIONS = [
    { "ModificationTimestamp" => "2026-09-30T20:37:18.123+00:00", "ChangeType" => "New Listing", "FieldName" => "StandardStatus", "PreviousValue" => "Other", "NewValue" => "ComingSoon" },
    { "ModificationTimestamp" => "2026-09-30T20:37:18.456+00:00", "ChangeType" => "New Listing", "FieldName" => "ListPrice", "NewValue" => "1670000.00" },
    { "ModificationTimestamp" => "2026-09-30T20:37:18+00:00", "ChangeType" => "New Listing", "FieldName" => "PropertyType", "PreviousValue" => "Other", "NewValue" => "Residential" },
    { "ModificationTimestamp" => "2026-09-30T22:18:50+00:00", "ChangeType" => "Active", "FieldName" => "StandardStatus", "PreviousValue" => "ComingSoon", "NewValue" => "Active" },
    { "ModificationTimestamp" => "2026-10-19T07:51:48+00:00", "ChangeType" => "Price Change", "FieldName" => "ListPrice", "PreviousValue" => "1670000.00", "NewValue" => "1650000.00" },
    { "ModificationTimestamp" => "2026-11-20T10:00:00+00:00", "ChangeType" => "Closed", "FieldName" => "StandardStatus", "PreviousValue" => "Pending", "NewValue" => "Closed" }
  ].freeze

  def test_from_transactions_newest_first
    events = H.from_transactions(TRANSACTIONS)
    assert_equal ["Sold", "Price cut", "Active (was Coming Soon)", "Listed (Coming Soon)"], events.map(&:event)
    assert_equal 1_650_000.0, events[1].price
    assert_equal "-1.2%", events[1].change
    assert_equal 1_670_000.0, events.last.price, "status and price parts of the new listing are one event, even with sub-second differences"
    assert_equal Time.utc(2026, 10, 19, 7, 51, 48), events[1].time
  end

  def test_price_increase
    events = H.from_transactions([TRANSACTIONS[4].merge("PreviousValue" => "1600000.00")])
    assert_equal "Price change", events.first.event
    assert_equal "+3.1%", events.first.change
  end

  def test_from_record_when_feed_has_no_history
    listing = {
      "StandardStatus" => "Active", "ListPrice" => 1_650_000.0, "OriginalListPrice" => 1_670_000.0,
      "OnMarketTimestamp" => DateTime.new(2026, 9, 30, 15, 9, 14), "DerivedPreviousListPrice" => 1_670_000.0,
      "DerivedPriceChangeTimestamp" => "2026-10-19T00:46:48+00:00", "DerivedPreviousStatus" => "ComingSoon",
      "DerivedStatusChangeTimestamp" => "2026-09-30T15:09:14+00:00"
    }
    events = H.from_record(listing)
    assert_equal ["Price cut", "Active (was Coming Soon)", "Listed"], events.map(&:event)
    assert_nil events[1].price, "a status change from the record has no reliable price"
    assert_equal 1_670_000.0, events[2].price
  end

  def test_from_record_sold
    listing = { "StandardStatus" => "Closed", "ClosePrice" => 8_280_000.0, "CloseDate" => "2026-11-23",
                "ListPrice" => 8_980_000.0, "OnMarketDate" => Date.new(2025, 12, 12), "OriginalListPrice" => 9_280_000.0 }
    events = H.from_record(listing)
    assert_equal %w[Sold Listed], events.map(&:event)
    assert_equal 8_280_000.0, events.first.price
  end

  def test_details_page_history_section
    listing = { "ListingId" => "OC1", "StandardStatus" => "Active", "ListPrice" => 1_650_000.0, "PropertyType" => "Residential" }
    history = { events: H.from_transactions(TRANSACTIONS), source: :transactions }
    html = ResoCli::DetailPage.html(listing, [], history: history)
    assert_includes html, "Price &amp; status history"
    assert_includes html, "<td>Oct 19, 2026</td><td>Price cut</td><td>$1,650,000</td>"
    assert_includes html, %(<span class="down">-1.2%</span>)
    assert_includes html, "From this feed&#39;s HistoryTransactional records."

    derived = ResoCli::DetailPage.html(listing, [], history: { events: H.from_transactions(TRANSACTIONS), source: :record })
    assert_includes derived, "This feed has no change history"

    refute_includes ResoCli::DetailPage.html(listing, [], history: { events: [], source: :record }), "Price &amp; status history"
  end

  def test_price_per_sq_ft_uses_close_price_when_sold
    sold = { "StandardStatus" => "Closed", "ClosePrice" => 8_280_000.0, "ListPrice" => 8_980_000.0, "LivingArea" => 5963.0 }
    assert_equal "$1,389", ResoCli::DetailPage.key_facts(sold).to_h["Price/sq ft"]
  end
end
