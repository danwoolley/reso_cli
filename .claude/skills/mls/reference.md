# RESO Data Dictionary - Common Fields Reference

## MLS-Specific Notes

- **`$select` not supported** — Never use `--select`; this MLS returns 400. Full records are always returned.
- **Enum fields** (typed `OData.Models.*`) — City, StandardStatus, PropertySubType, StreetSuffix, StreetDirPrefix, etc. MUST use structured `--eq`/`--ne` flags. They cause 400 errors in raw `--filter` OData expressions.
- **`ListingKeyNumeric`** — Use this instead of `ListingKey` (which is null on this MLS).
- **`StreetNumberNumeric`** — Use this instead of `StreetNumber` (which is null on this MLS).
- **No `UnparsedAddress`** — Build addresses from `StreetNumberNumeric`, `StreetName`, `StreetSuffix`.

## Property Resource - Key Fields

### Identification
- `ListingKeyNumeric` - Unique identifier for the listing (use this, not ListingKey)
- `ListingId` - MLS number
- `StandardStatus` - Standardized status (Active, Pending, Closed, etc.) **[ENUM — use --eq only]**

### Pricing
- `ListPrice` - Current list price
- `OriginalListPrice` - Original list price
- `ClosePrice` - Final sale price (for closed listings)
- `PreviousListPrice` - Previous list price

### Location
- `City` - City name **[ENUM — use --eq only]**
- `StateOrProvince` - State/province code (e.g., "CA")
- `PostalCode` - ZIP/postal code
- `CountyOrParish` - County name
- `StreetNumberNumeric` - Street number (integer; use this, not StreetNumber)
- `StreetName` - Street name (string)
- `StreetSuffix` - Street suffix (Place, Ave, Dr, etc.) **[ENUM]**
- `StreetDirPrefix` / `StreetDirSuffix` - Directional **[ENUM]**
- `SubdivisionName` - Subdivision or neighborhood name
- `MLSAreaMajor` - MLS area code/name (e.g., "639 - Monrovia") **[ENUM]**

### Property Characteristics
- `PropertyType` - Type (Residential, Commercial, Land, etc.) **[ENUM]**
- `PropertySubType` - Subtype (Single Family Residence, Condominium, Townhouse, etc.) **[ENUM]**
- `BedroomsTotal` - Total bedrooms
- `BathroomsTotalInteger` - Total bathrooms (integer)
- `BathroomsFull` - Full bathrooms
- `BathroomsHalf` - Half bathrooms
- `LivingArea` - Living area in square feet
- `LotSizeArea` - Lot size
- `LotSizeUnits` - Lot size units
- `YearBuilt` - Year built
- `Stories` - Number of stories
- `GarageSpaces` - Number of garage spaces
- `PoolPrivateYN` - Has private pool (boolean)

### Dates
- `ListingContractDate` - Date listed
- `CloseDate` - Date closed/sold
- `OnMarketDate` - Date placed on market
- `ModificationTimestamp` - Last modified timestamp
- `OriginalEntryTimestamp` - First entered timestamp
- `DaysOnMarket` - Days on market
- `CumulativeDaysOnMarket` - Cumulative days on market

### Description
- `PublicRemarks` - Public listing description
- `PrivateRemarks` - Agent-only remarks (may not be accessible)
- `Directions` - Directions to property

### Agent/Office
- `ListAgentKey` - Listing agent key
- `ListAgentFullName` - Listing agent name
- `ListOfficeName` - Listing office name
- `BuyerAgentFullName` - Buyer agent name (closed listings)
- `BuyerOfficeName` - Buyer office name (closed listings)

### Financial
- `TaxAnnualAmount` - Annual taxes
- `TaxAssessedValue` - Tax assessed value
- `AssociationFee` - HOA fee amount
- `AssociationFeeFrequency` - HOA fee frequency

## OData Filter Syntax

### Comparison Operators
- `eq` - equals: `City eq 'Austin'`
- `ne` - not equals: `City ne 'Houston'`
- `gt` - greater than: `ListPrice gt 500000`
- `ge` - greater than or equal: `BedroomsTotal ge 3`
- `lt` - less than: `ListPrice lt 1000000`
- `le` - less than or equal: `DaysOnMarket le 30`

### Logical Operators
- `and` - both conditions: `City eq 'Austin' and ListPrice gt 500000`
- `or` - either condition: `City eq 'Austin' or City eq 'Houston'`
- `not` - negation: `not City eq 'Houston'`

### String Functions
- `contains(Field,'text')` - field contains text
- `startswith(Field,'text')` - field starts with text
- `endswith(Field,'text')` - field ends with text

### Grouping
Use parentheses for complex logic:
```
City eq 'Austin' and (BedroomsTotal ge 3 or BathroomsTotalInteger ge 2)
```

## Common Query Patterns

All examples use the CLI at `./reso_cli`. No `--select` (unsupported). Extract fields from JSON output.

### Active listings in a city
```bash
reso_cli search Property --eq StandardStatus=Active --eq "City=Newport Beach" --top 10 --orderby "ListPrice desc"
```

### Recently sold (comps)
```bash
reso_cli search Property --eq StandardStatus=Closed --eq "City=Newport Beach" \
  --ge ClosePrice=400000 --le ClosePrice=600000 \
  --ge BedroomsTotal=3 --le BedroomsTotal=4 \
  --top 10 --orderby "CloseDate desc"
```

### Price range search
```bash
reso_cli search Property --eq StandardStatus=Active \
  --ge ListPrice=500000 --le ListPrice=750000 \
  --eq "City=Newport Beach" --ge BedroomsTotal=3 --top 10 --orderby "ListPrice desc"
```

### Listings with keyword in remarks (raw filter for string function)
```bash
reso_cli search Property --eq "City=Newport Beach" --eq StandardStatus=Active \
  --filter "contains(PublicRemarks,'pool')" --top 10
```
Note: --filter overrides structured filters for non-enum fields. Enum fields (City, StandardStatus) MUST stay in --eq flags — but they will be IGNORED when --filter is present. This is a known limitation; for keyword searches, rely on --filter alone for the non-enum conditions and accept that enum filters won't apply.

### Count listings in an area
```bash
reso_cli count Property --eq StandardStatus=Active --eq "City=Newport Beach"
```

### Key fields to extract from results
When presenting results to the user, extract and format these fields:
- `ListingKeyNumeric`, `ListPrice` (or `ClosePrice`), `StreetNumberNumeric`, `StreetName`, `StreetSuffix`, `City`
- `BedroomsTotal`, `BathroomsTotalInteger`, `LivingArea`, `YearBuilt`, `PropertySubType`
- `DaysOnMarket`, `PublicRemarks` (for detail views)

## Other Resources

The MLS may also expose these resources (run `reso_cli resources` to confirm):
- **Member** - Agent roster (ListAgentKey, MemberFullName, MemberEmail, etc.)
- **Office** - Brokerage offices (OfficeName, OfficePhone, etc.)
- **OpenHouse** - Scheduled open houses (OpenHouseDate, OpenHouseStartTime, etc.)
- **Media** - Photos and documents linked to listings
