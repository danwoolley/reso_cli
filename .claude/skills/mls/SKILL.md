---
name: mls
description: Query the local MLS for real estate listings, comparable properties, recent sales, and market data via the RESO Web API.
allowed-tools: Bash(./reso_cli *)
---

# MLS Query Skill

You have access to the local MLS (Multiple Listing Service) via a CLI tool that queries a RESO Web API server.

## CLI Location

```
./reso_cli
```

## Commands

### List available resources
```bash
./reso_cli resources
```

### List fields for a resource
```bash
./reso_cli fields Property
./reso_cli fields Property --match "Price|List"
```

### Search records with structured filters
```bash
./reso_cli search Property \
  --eq "City=Newport Beach" \
  --eq StandardStatus=Active \
  --ge ListPrice=500000 \
  --le ListPrice=1000000 \
  --ge BedroomsTotal=3 \
  --top 10 \
  --orderby "ListPrice desc"
```
Note: Quote values containing spaces (e.g., `--eq "City=Newport Beach"`).

### Get a single listing by key
```bash
./reso_cli get Property 412212140
```

### Count matching records
```bash
./reso_cli count Property --eq "City=Newport Beach" --eq StandardStatus=Active
```

### Save results to a file
```bash
./reso_cli search Property --eq "City=Irvine" --eq StandardStatus=Active --all --output irvine-active.csv
./reso_cli search Property --eq "City=Irvine" --top 100 --output irvine.json
./reso_cli get Property 412212140 --output listing.json
```

## Saving and exporting results

When the user asks to save, export or download results, or wants them "in a spreadsheet", "in Excel" or "as a file":

- **Re-run the query with `--output FILE`. Never write the results file yourself**, e.g. with the Write tool or by copying results from earlier output. The CLI writes the server's exact data, which never has to pass through the conversation.
- **Pick the format from the request.** Spreadsheet, Excel or CSV means a `.csv` file (one row per listing, one column per field). Otherwise use `.json`. Choose a descriptive file name (e.g. `irvine-active-2026-11-24.csv`) unless the user gave one. Relative paths are saved in the folder Claude Code is running in.
- **Use `--all` when they want every match** ("all active listings in Irvine"). Without it, only the first page is saved. `--all` stops at 10,000 records by default. Before a very large export, run `count` first, tell the user how many records match, and raise the limit with `--max N` if they confirm.
- **Use `--select`** to limit the columns when the user only wants certain fields, which makes the spreadsheet easier to read. Skip this on servers that don't support `$select` (see the CRMLS notes).
- **Afterwards, report** the full path of the saved file, how many records were saved, and any `note` from the output (e.g. that more matches exist).

## Query Strategy

When the user asks about real estate listings:

1. **First run**: Call `reso_cli resources` to discover what resources the MLS exposes.
2. **Discover fields**: Call `reso_cli fields RESOURCE --match PATTERN` to find relevant field names.
3. **Query**: Use `reso_cli search` with structured filters (`--eq`, `--ge`, etc.) and `--top` to limit results.
4. **Always use --top**: Limit results to avoid overwhelming output. Start with 5-10 results.
5. **Iterate**: If the user needs more detail on a specific listing, use `reso_cli get` with its key.

## Important Notes

- Field names use RESO Data Dictionary CamelCase (e.g., `ListPrice`, `BedroomsTotal`, not `list_price`)
- **`--filter` and structured flags are mutually exclusive**: When `--filter` is present, all `--eq`/`--ge`/etc. are ignored. Plan your queries accordingly.
- JSON output goes to stdout; format it nicely when presenting to the user (table format preferred).

## CRMLS-Specific Notes (h.api.crmls.org)

The following quirks apply **only** when the active MLS endpoint (see `./reso_cli mls`) is `https://h.api.crmls.org/Reso/OData` (CRMLS / SoCal MLS). Other MLS servers may not have these limitations.

- **Do NOT use `--select`** — CRMLS returns 400 if `$select` is included. Full records are always returned; extract the fields you need from the JSON output.
- **Do NOT use `--filter` for enum fields** — Fields typed as `OData.Models.*` enums (City, StandardStatus, PropertySubType, etc.) cause 400 errors in raw `$filter` expressions. Always use structured `--eq`/`--ne` for these fields instead.
- Use `--filter` ONLY for string functions (`contains()`, `startswith()`) or complex OR logic on non-enum fields.
- Use `ListingKeyNumeric` (not `ListingKey`) — CRMLS populates `ListingKeyNumeric` only; `ListingKey` is null.
- Use `StreetNumberNumeric` (not `StreetNumber`) — `StreetNumber` is null on CRMLS.
- **No `UnparsedAddress`** — Build addresses from `StreetNumberNumeric`, `StreetName`, `StreetSuffix`.

For detailed RESO field names and common query patterns, see [reference.md](reference.md).
