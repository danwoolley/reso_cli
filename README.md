# RESO Web API Client CLI + Claude Skills = Claude Code MLS Access! :lobster:

https://github.com/user-attachments/assets/844c8724-7d7d-48fc-9e27-342d0adf474e

Connect to as many MLS RESO Web API servers as you like, switch between them, and ask Claude about listings in plain English. Open a listing's photos or a full portal-style details page, see comparable sales, compare feeds, and save results to a spreadsheet (CSV) or JSON file.


## Prerequisites

- **macOS or Linux.** On Windows, use [WSL](https://learn.microsoft.com/windows/wsl/install) (Windows Subsystem for Linux) and follow the Linux steps inside it.
- **Claude Code**: [claude.com/claude-code](https://claude.com/claude-code). This is optional; everything also works from the shell.
- **Ruby 3.1 or newer.** You don't need to set this up in advance: `/mls-setup` checks for it and helps you install it. To do it yourself:
  - **macOS:** the built-in Ruby is too old. Install [Homebrew](https://brew.sh), then run `brew install ruby`. You don't need to change your PATH; `./reso_cli` finds Homebrew's Ruby automatically.
  - **Ubuntu/Debian:** `sudo apt install ruby-full`
  - **Other systems:** [ruby-lang.org/en/documentation/installation](https://www.ruby-lang.org/en/documentation/installation/)
  - Version managers (rbenv, rvm, asdf) work too, with any Ruby 3.1 or newer.


## Setup

### 1. Get the code

```bash
git clone https://github.com/danwoolley/reso_cli.git
cd reso_cli
```

### 2. Add an MLS

Start Claude Code in the `reso_cli` folder and type:

```text
/mls-setup
```

The first time, Claude checks that Ruby and reso_cli's gems are installed, and installs whatever's missing, asking you first. Then it asks a few simple questions: what to call the MLS, its API address, and your credentials. You can:

- **Paste the connection details**, for example straight from the email your MLS sent. Claude picks out the API URL, then either an access token or a client ID and secret (OAuth2). This is the usual way.
- **Or point it at a Postman collection** (a `.json` file) if your MLS or data vendor sent one. Claude reads the settings straight from the file, so your secrets never appear in the chat.

Claude then tests the connection and tells you whether it worked. Run `/mls-setup` again for each MLS you want to add. The newest one becomes active.

### Switch, list or remove MLSs

```text
/mls-use                  # pick from a list
/mls-use CRMLS            # or choose by name
/mls-use list             # see your MLSs, which one is active, and when tokens expire
/mls-use check            # check that every MLS is working
/mls-use remove ACTRIS    # remove one (Claude asks you to confirm first)
```

You don't need the slash commands: plain requests like "switch to CRMLS", "which MLS am I using?", "are all my MLSs working?", "add another MLS" or "remove ACTRIS" work too.

### Where your credentials are stored

MLS connections are saved in **`~/.config/reso_cli/mls.yml`**. That's in your home folder, outside this repo, so they can't be committed to git by accident, and they stay put if you delete or re-clone the repo. The file can only be read by your user account. To keep it somewhere else, set `RESO_CLI_CONFIG=/path/to/mls.yml`.

You don't need to edit this file. If you want to see its format, look at `config/mls.yml.example`.

A few things to know:

- **Pasted credentials become part of your Claude conversation.** That's normally fine for MLS API keys. If you'd rather keep a secret out of the chat, use a Postman collection, or run `./reso_cli add` yourself in a terminal (see below).
- Claude never prints saved secrets, and this repo's `.claude/settings.json` stops Claude from reading the config file.
- **Bearer tokens often expire** (sometimes daily). When a token contains its expiry date, as most do, `/mls-use list` (or `./reso_cli mls`) shows when it expires. To replace an expired token, run `/mls-setup` again with a fresh one and choose to replace the existing entry. OAuth2 client credentials renew automatically.
- **Check all your MLSs at once** by asking Claude "are all my MLSs working?" (or running `./reso_cli test --all`). You get one line per MLS, showing whether it works and, if not, why: credentials rejected, token expired, or can't connect.

### Upgrading from an older version

Older versions kept credentials in `config/mls.yml` inside the repo. The first time you run any `reso_cli` command, that file is copied to `~/.config/reso_cli/mls.yml` automatically. After that, you can delete `config/mls.yml`.

### Without Claude

You can do everything from the shell:

```bash
./reso_cli setup          # first time only: installs reso_cli's Ruby gems

# Bearer token
./reso_cli add "My MLS" --endpoint https://api.my-mls.com/odata --token YOUR_TOKEN

# OAuth2 client credentials (add --scope SCOPE only if your MLS requires one)
./reso_cli add "My MLS" --endpoint https://api.my-mls.com/odata \
  --token-url https://auth.my-mls.com/oauth2/token --client-id YOUR_ID --client-secret YOUR_SECRET

# From a Postman collection
./reso_cli postman ~/Downloads/MyMLS.postman_collection.json           # see which auth setups it contains
./reso_cli add "My MLS" --from-postman ~/Downloads/MyMLS.postman_collection.json --postman-auth "AUTH NAME"

./reso_cli test           # check that the active MLS accepts your credentials
./reso_cli test --all     # check every MLS
./reso_cli mls            # list your MLSs
./reso_cli use "My MLS"   # switch
./reso_cli remove "My MLS"
```


## Metadata cache

Every RESO server publishes a metadata document describing its resources (Property, Member, Office, …), fields and data types. `reso_cli` downloads it the first time you use an MLS and caches it, so later commands start quickly. Some servers' metadata is several megabytes, so that first command can take a few seconds.

- **Location:** `~/.cache/mls/`, one file per endpoint, named `metadata-<id>.xml`. The `<id>` is the first 12 characters of a SHA-256 hash of the endpoint URL, so switching MLSs never reuses another server's metadata.
- **No credentials:** the files hold only the server's schema description, so they're safe to delete at any time.
- **Shared by identical endpoints:** two MLS entries with the exact same endpoint URL (for example, two sets of credentials for one server) share a cache file. The URL text must match exactly, so `.../odata` and `.../OData` get separate files.
- **Never expires on its own:** if an MLS adds or changes fields or resources, ask Claude to "refresh the MLS metadata", or run:

  ```bash
  ./reso_cli refresh          # re-download the active MLS's metadata now
  ./reso_cli refresh --all    # clear every MLS's cache; each is downloaded again when next used
  ```

The cache never holds credentials, and `reso_cli resources` and `fields` can be answered from it without contacting the server. So to check that an MLS still accepts your credentials, use `reso_cli test`, which always makes a live, authenticated request.


## CLI commands

  - `reso_cli resources` -- discover what the MLS exposes
  - `reso_cli fields RESOURCE [--match PATTERN]` -- list/search field names
  - `reso_cli search RESOURCE [filters]` -- query with structured or raw OData filters; add `--output FILE` to save results (`.csv` or JSON), `--all` for every page, `--max N` to cap `--all` (default 10,000)
  - `reso_cli get RESOURCE KEY` -- fetch a single record (`--output FILE` to save it)
  - `reso_cli count RESOURCE [filters]` -- count matching records
  - `reso_cli mls` -- list configured MLSs (credentials are never printed)
  - `reso_cli use NAME` -- switch the active MLS
  - `reso_cli add NAME [options]` -- add an MLS connection (`reso_cli add --help` for options)
  - `reso_cli remove NAME` -- remove an MLS connection
  - `reso_cli test [--all]` -- make a live, authenticated request to the active MLS (or every MLS, one result each)
  - `reso_cli refresh [--all]` -- re-download the active MLS's metadata (or clear every cached copy)
  - `reso_cli photos LISTING_ID` -- open a photo slideshow for a listing (`--output FILE.html`, `--no-open`)
  - `reso_cli details LISTING_ID` -- open a full listing details page: photos, key facts, map and every field (`--output FILE.html`, `--no-open`)
  - `reso_cli comps LISTING_ID` -- comparable recent sales with a value range, map and table (`--months`, `--radius`, `--max`, `--output`, `--no-open`)
  - `reso_cli compare LISTING_ID --mls A --mls B` -- compare one listing between two MLS connections, field by field
  - `reso_cli compare-report --mls A --mls B (filters | --ids … | --ids-file FILE)` -- compare many listings and write a Markdown report (`--output`, `--max`, `--save-data`)
  - `reso_cli postman FILE` -- show the auth setups in a Postman collection (secrets are never printed)
  - `reso_cli setup` -- install reso_cli's Ruby gems (first-time setup)

File paths can be relative to the folder you run `reso_cli` from, e.g. `./reso_cli postman MyMLS.json`.


## Skills

In folder .claude/skills:
  - /mls
    - SKILL.md -- tells me when/how to use the CLI, query strategy, and auto-allows the Bash command
    - reference.md -- RESO Data Dictionary field names, OData filter syntax, and common query patterns (comps, active listings, new listings, etc.)
  - /mls-setup
    - SKILL.md -- friendly setup interview; adds a new named MLS from pasted details or a Postman collection, then tests it
  - /mls-use
    - SKILL.md -- list your MLSs (with token expiry), check that they all work, switch the active one, or remove one


## Running tests

```bash
bundle exec rake test
```

The tests run offline in a few seconds. They use a throwaway config file and fake fixtures in `test/fixtures`, so they never touch your MLS connections or contact a server. They cover:

- managing MLS connections: add, use, remove and moving an old config
- Postman import
- how search flags become OData queries
- saving results to JSON and CSV, and fetching every page with `--all`
- health checks, token expiry, metadata refresh, and retrying throttled requests
- photo slideshow pages: photo order, skipping videos and documents, and escaping listing text
- listing details pages: field grouping, labels, value formatting, hidden addresses, and escaping
- price and status history: grouping change records into events, and the fallback built from the listing record
- comparable sales: search criteria, distance, ranking, the value range and the page
- feed comparison: field classification, the comparison page, and the batch report

GitHub Actions runs them on every push and pull request, with Ruby 3.1 and 3.4.


## Claude Code usage

Run Claude Code in the root project folder, then ask things like:

```text
show me 3-bedroom homes under $500k in [your city]
```
```text
what is the highest recorded sales price in [city] in the past 18 months?
```

### Viewing a listing's photos

Ask Claude for a listing's photos in plain words:

```text
show me the photos of that listing
```
```text
show me pictures of 85 Sedgewick in Irvine
```

Claude opens a slideshow of every photo, in order, in your browser. The page has the address, price, beds/baths and MLS number at the top, previous/next arrows (the arrow keys work too) and a strip of thumbnails. The page is saved on your computer (under `~/.cache/mls/photos/`) and isn't published anywhere.

Some MLSs issue photo links that expire after about an hour (CRMLS through Trestle does). If the photos stop loading, ask again and Claude rebuilds the page with fresh links.

From the shell:

```bash
./reso_cli photos OC26210043                        # MLS number or ListingKey; opens your browser
./reso_cli photos OC26210043 --output ~/Desktop/85-sedgewick.html --no-open
```

### Viewing a listing's full details

Ask Claude to show you everything about a listing:

```text
show me the details of that listing
```
```text
open the listing page for 85 Sedgewick
```

Claude opens a listing page in your browser, laid out like the big real estate portals:

- **At the top:** a photo collage (click any photo, or "Show all photos", for a full-screen viewer), the price and status, beds/baths/sq ft and the address. Below those: key facts (type, year built, lot, price per sq ft, HOA, parking, cooling, days on market…), the description, a **price & status history** (listed, price changes with the % change, status changes, sold), a map and who the listing is with. The history comes from the MLS's change-history records when the feed provides them. Otherwise it's pieced together from the listing's own dates and previous price and status, and the page notes that it may be incomplete.
- **Below that, "All listing details":** every field in the MLS record, grouped into sections such as Interior, Exterior & lot, Community & HOA, Location, Schools, Financial & tax, Price & listing history and Agents & offices, with readable labels and formatted values. A search box filters the fields. You can also show the empty fields, or the original RESO field names (handy when comparing feeds or checking data quality).

If the seller asked that the address not be shown online, the street address and map are left out. Listings not approved for internet display are flagged at the top. The map uses OpenStreetMap and needs an internet connection. Like the photo slideshow, the page is saved on your computer (under `~/.cache/mls/details/`) and isn't published anywhere.

From the shell:

```bash
./reso_cli details OC26210043                       # MLS number or ListingKey; opens your browser
./reso_cli details OC26210043 --output ~/Desktop/85-sedgewick.html --no-open
```

### Comparable sales (comps)

Ask Claude what similar homes have sold for:

```text
show me comps for 85 Sedgewick
```
```text
what are similar homes near that listing selling for?
```

Claude opens a page in your browser with:
- **The listing** you asked about.
- **A value range** based on what comparable homes sold for per square foot. This is a rough guide, not an appraisal.
- **A map** with the listing (★) and each comp numbered.
- **A table of the comps:** photo, address, sold date, sold and list price, beds/baths, sq ft, $/sq ft and distance.

Comps are recent closed sales of the same type of home (e.g. single-family vs condo) nearby, with similar size and bedrooms. They're ranked by how similar they are. By default the search covers the last 6 months within 1 mile, and widens automatically if it finds fewer than 3.

From the shell:

```bash
./reso_cli comps OC26210043
./reso_cli comps OC26210043 --months 12 --radius 2 --max 15
```

### Comparing two feeds

If you have two connections that should carry the same listings, for example a data aggregator and the MLS's own feed, reso_cli can compare them.

**One listing, side by side:**

```text
compare listing OC26210043 between CDL and CRMLS
```

This opens a page that lines the two records up field by field. It counts the fields that are **different**, **only in one feed**, the **same value in a different format** (e.g. `949-572-5372` vs `9495725372`), **system fields** (each system's own keys, IDs and timestamps, which are expected to differ) and the **same**. For list fields such as interior features, it shows exactly which values one feed is missing. Both feeds' photos are shown as well.

**Many listings, as a report:**

```text
compare all active listings in Irvine between CDL and CRMLS and save a report to ~/analysis
```

reso_cli pulls the matching listings from both feeds, matches them by MLS number and writes a Markdown report. It covers:
- **missing listings and why:** e.g. a status change that hasn't reached one feed yet (and for how long), a listing hidden from internet display, or a listing absent from that feed altogether
- **status mismatches** between the feeds
- **the fields that differ most often**, with examples
- **list values one feed leaves out**
- **fields only one feed fills in**

From the shell:

```bash
./reso_cli compare OC26210043 --mls CDL --mls CRMLS
./reso_cli compare-report --mls CDL --mls CRMLS --eq City=Irvine --eq StandardStatus=Active \
  --output irvine-report.md --save-data irvine-data
./reso_cli compare-report --mls CDL --mls CRMLS --ids OC26210043,OC26219911    # or --ids-file ids.txt
```

### Saving results to a file

Ask Claude to save any search to a file, in plain words:

```text
save all active listings in Irvine to a spreadsheet
```
```text
export the last 6 months of sales in [city] as JSON
```
```text
save those results to comps.csv
```

- **Spreadsheet or CSV** gives a `.csv` file that opens in Excel, Numbers or Google Sheets: one row per listing, one column per field. Otherwise you get a `.json` file.
- **"All" means every match.** Claude follows every page of results, up to 10,000 records by default. For bigger exports, Claude tells you how many records match and asks before raising the limit.
- **Busy servers are handled.** If the MLS throttles requests (HTTP 429) or is briefly unavailable (502/503/504), reso_cli waits and retries, up to 4 attempts, honoring the server's `Retry-After` header, so a long export doesn't fail halfway through.
- **Files are saved in the folder you started Claude Code in**, unless you name another location. Claude tells you the full path and how many records were saved.
- The file has exactly what the MLS returned. Claude has the CLI write it directly instead of copying results through the chat.

From the shell, add `--output FILE` to `search` or `get` (and `--all` for every page):

```bash
./reso_cli search Property --eq City=Irvine --eq StandardStatus=Active --all --output irvine-active.csv
./reso_cli search Property --eq City=Irvine --top 100 --output irvine.json
./reso_cli get Property 412212140 --output listing.json
```



danwoolley@gmail.com :goat:
