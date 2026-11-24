require "test_helper"

# Turning CLI flags into OData query parameters, using a small fixture metadata file (no server).
class QueryTest < Minitest::Test
  def setup
    @md_dir = Dir.mktmpdir("reso_cli-md")
    md_file = File.join(@md_dir, "metadata.xml")
    FileUtils.cp(File.join(FIXTURES, "metadata.xml"), md_file)
    client = ResoTransport::Client.new(
      endpoint: "https://api.example.com/odata",
      authentication: { access_token: "unused", token_type: "Bearer" },
      md_file: md_file,
      logger: Logger.new(File::NULL)
    )
    @resource = client.resources.fetch("Property")
  end

  def teardown
    FileUtils.remove_entry(@md_dir)
  end

  def params_for(*args)
    options = ResoCli.send(:parse_query_options, ["Property", *args])
    options.delete(:resource)
    ResoCli.send(:build_query, @resource, options).send(:compile_params)
  end

  def test_structured_filters_paging_and_order
    params = params_for("--eq", "City=Irvine", "--eq", "StandardStatus=Active", "--ge", "ListPrice=500000",
                        "--le", "BedroomsTotal=4", "--top", "5", "--skip", "10", "--orderby", "ListPrice desc")
    assert_equal "City eq 'Irvine' and StandardStatus eq 'Active' and ListPrice ge 500000 and BedroomsTotal le 4",
                 params["$filter"]
    assert_equal 5, params["$top"]
    assert_equal 10, params["$skip"]
    assert_equal "ListPrice desc", params["$orderby"]
  end

  def test_booleans_dates_and_decimals
    params = params_for("--eq", "NewConstructionYN=true", "--gt", "ModificationTimestamp=2026-11-01T00:00:00Z",
                        "--lt", "ListPrice=1.5", "--ne", "City=Irvine")
    # Filters are grouped by operator (eq, ne, gt, ge, lt, le), not kept in the order typed
    assert_equal "NewConstructionYN eq true and City ne 'Irvine' and " \
                 "ModificationTimestamp gt 2026-11-01T00:00:00Z and ListPrice lt 1.5", params["$filter"]
  end

  def test_values_with_spaces
    assert_equal "City eq 'Newport Beach'", params_for("--eq", "City=Newport Beach")["$filter"]
  end

  def test_raw_filter_overrides_structured_flags
    params = params_for("--filter", "contains(City,'Irv')", "--eq", "City=Ignored")
    assert_equal "contains(City,'Irv')", params["$filter"]
  end

  def test_select
    assert_equal "ListingKey,City", params_for("--select", "ListingKey,City")["$select"]
  end

  # Regression: "02134" used to become the number 2134, silently breaking ZIP code and ID searches
  def test_leading_zeros_are_kept
    assert_equal "City eq '02134'", params_for("--eq", "City=02134")["$filter"]
    assert_equal "02134", ResoCli.send(:coerce_value, "02134")
  end

  def test_value_coercion
    assert_equal 42, ResoCli.send(:coerce_value, "42")
    assert_equal 0, ResoCli.send(:coerce_value, "0")
    assert_equal 1.5, ResoCli.send(:coerce_value, "1.5")
    assert_equal true, ResoCli.send(:coerce_value, "TRUE")
    assert_equal false, ResoCli.send(:coerce_value, "false")
    assert_equal "Irvine", ResoCli.send(:coerce_value, "Irvine")
  end
end
