---
name: mls
description: Query the active MLS for real estate listings, comparable properties, recent sales and market data via the RESO Web API, show a listing's photos or a full portal-style details page (photos, facts, map, every field), compare listings between two MLS feeds, and save results to CSV/JSON files. Use for questions about homes, listings, prices, sales, agents or offices. Not for adding, switching or removing MLS connections (see mls-setup and mls-use).
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

### Show a listing's photos
```bash
./reso_cli photos OC26210043          # MLS number (ListingId) or ListingKey
```

### Show a listing's full details page
```bash
./reso_cli details OC26210043         # photos, key facts, description, map, and every field
```

## Showing listing photos and details

Two commands open a page about one listing in the user's browser. They share the rules below.

- **Photos** ("show me the photos of that listing", "pictures of 85 Sedgewick"): `./reso_cli photos <ListingId>` opens a full-screen photo slideshow.
- **Details** ("show me the details", "tell me everything about that listing", "open the listing page"): `./reso_cli details <ListingId>` opens a portal-style listing page. Above the fold it shows a photo collage (with a full-screen photo viewer), price, status, beds/baths/sq ft, a key-facts grid, the description, a map and listed-by attribution. Below the fold, "All listing details" lists every field in the record, grouped into sections, with search and toggles for empty fields and raw RESO field names. It respects `InternetAddressDisplayYN` (no street address or map when it's No) and flags listings not approved for internet display.

Prefer `details` when the user wants to learn about a listing. Use `photos` when they only want the pictures. Shared rules:

- **Find the listing's MLS number (`ListingId`).** Usually it's in a result you already showed. If the user means a listing from earlier in the conversation, use that one. If they only give an address, search for it first. If it's unclear which listing they mean, ask.
- **Run the command.** It builds the page and opens it in the user's default browser, and prints the saved path and the photo count (`details` also prints the number of filled-in fields).
- **If `opened` is false** (e.g. there's no desktop browser), give the user the page's path to open themselves.
- **In the Claude desktop app,** if you have a built-in browser or preview tool that can display a local file, you may add `--no-open` and show the page there instead, so it appears next to the conversation.
- **Don't publish these pages** to a hosted or shareable page. MLS listings and photos are licensed content, and the pages should stay on the user's machine. Don't download or describe the photos yourself unless the user asks.
- **Photo links on some MLSs expire** (CRMLS/Trestle links last about an hour). If the user says the photos stopped loading, run the command again.

## Comparing two feeds

Use these when the user wants to check one MLS connection against another, e.g. an aggregator such as CDL against the native MLS feed. Both MLSs must already be set up (see `./reso_cli mls`). The active MLS doesn't change.

- **One listing** ("compare 85 Sedgewick between CDL and CRMLS", "how does this listing differ in the two feeds?"):
  ```bash
  ./reso_cli compare OC26210043 --mls CDL --mls CRMLS
  ```
  This opens a page in the browser. Summary cards show counts of **different**, **only in A**, **only in B**, **same value, different format**, **system fields** (keys, IDs and timestamps each system assigns, so expected to differ) and **same**. Then come both photo strips, and a table of every field that differs. For list fields, the table spells out exactly which values are missing on each side. Summarize the counts and the most notable differences for the user.
- **Many listings** ("compare all active listings in Irvine between CDL and CRMLS", "write a comparison report"):
  ```bash
  ./reso_cli compare-report --mls CDL --mls CRMLS --eq City=Irvine --eq StandardStatus=Active \
    --output ~/analysis/report.md --save-data ~/analysis/report_data
  ```
  Choose the listings with the usual search filters, or with `--ids ID1,ID2` or `--ids-file FILE`. It pulls the listings from both feeds and matches them on `ListingId`. Listings missing from one feed are looked up in the other by MLS number to explain why (e.g. a status change not yet received, with how long it's been; the listing being hidden from internet display; or not being in that feed at all). Then it writes a Markdown report covering the summary, missing listings, status mismatches, the fields that differ most often, list values present in only one feed, and fields filled in by only one feed.
  - Save the report where the user keeps their analysis, if they've said where. Otherwise it goes in the current folder. `--save-data DIR` keeps the raw records from both feeds.
  - `--max N` caps listings per feed (default 2,000). For a broad query, run `count` first and confirm with the user before a very large pull.
  - Afterwards, read the report and summarize the key findings for the user, along with the report's path.

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

- **Stale metadata:** if a field or resource the user expects is missing (e.g. `Property X not found`, or `fields` doesn't list it), the cached metadata may be out of date. Run `./reso_cli refresh` to re-download it, then retry.
- **Busy servers:** reso_cli retries throttled (HTTP 429) or briefly unavailable (502/503/504) requests on its own, and prints "retrying..." on stderr. You don't need to retry yourself. If it still fails after its retries, tell the user the server is busy and suggest trying again later.
- **Auth errors** (`Access denied`, 401/403): suggest `/mls-use` to check the MLSs (the token may have expired) and `/mls-setup` to replace the credentials.
- Field names use RESO Data Dictionary CamelCase (e.g., `ListPrice`, `BedroomsTotal`, not `list_price`)
- **`--filter` and structured flags are mutually exclusive**: When `--filter` is present, all `--eq`/`--ge`/etc. are ignored. Plan your queries accordingly.
- JSON output goes to stdout; format it nicely when presenting to the user (table format preferred).

For detailed RESO field names and common query patterns, see [reference.md](reference.md).
