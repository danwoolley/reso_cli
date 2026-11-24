---
name: mls-setup
description: Add a new MLS RESO Web API server (name, endpoint, credentials) to reso_cli's config/mls.yml.
allowed-tools: Read(config/mls.yml), Edit(config/mls.yml), Write(config/mls.yml), Read(config/mls.yml.example), Bash(./reso_cli resources), Bash(./reso_cli mls), Bash(./reso_cli use *), Bash(git update-index --skip-worktree config/mls.yml)
---

# MLS Setup Skill

Each time this skill runs, it adds **one new MLS** to `config/mls.yml`. The file can hold many MLSs; the top-level `active:` key picks which one `reso_cli` uses. Existing MLS entries must be preserved exactly.

## File format

```yaml
active: <NAME>

mls:
  <NAME>:
    endpoint: <ENDPOINT>
    authentication:
      ...
  <OTHER NAME>:
    ...
```

`config/mls.yml` is checked into git as an empty file. It may be empty (0 bytes) when you start.

## Step 1: Read the existing config

Read `config/mls.yml` and note the names already defined under `mls:`. Don't repeat any credentials from it back to the user.

## Step 2: Collect the MLS details

Ask the user for the following, one question at a time:

1. **API endpoint URL**: the OData service root (e.g., `https://h.api.crmls.org/Reso/OData`).
2. **MLS name**: a short name for this MLS (e.g., `CRMLS`, `ACTRIS`, `CDL`). Suggest one based on the endpoint's host if it's obvious. If the name already exists in `mls:` (case-insensitive match), ask whether to replace that entry or choose a different name.
3. **Auth method**: ask "Does your MLS use **OAuth2 client credentials** or a **static bearer token**?"
4. Then, based on the answer:
   - **OAuth2**: ask for the token endpoint URL (e.g., `https://ids.crmls.org/connect/token`), client ID, client secret, and scope (optional; use `''` if skipped).
   - **Bearer token**: ask for the access token value.

## Step 3: Add the entry to config/mls.yml

- **If the file is empty** (or has no `mls:` key), Write it as:
  ```yaml
  active: <NAME>

  mls:
    <ENTRY>
  ```
- **Otherwise**, use Edit to append the new entry under `mls:` (or replace the entry with the same name if the user chose to replace it). Leave all other entries and comments untouched. Then set the new MLS as active with `./reso_cli use "<NAME>"`.

Indent the entry two spaces under `mls:`. Quote the name if it contains YAML-special characters (`:`, `#`, leading/trailing spaces, etc.). Write only the auth variant that matches the user's answer:

### OAuth2 entry

```yaml
  <NAME>:
    endpoint: <ENDPOINT>
    authentication:
      endpoint: <TOKEN_ENDPOINT>
      client_id: <CLIENT_ID>
      client_secret: <CLIENT_SECRET>
      scope: '<SCOPE>'
```

### Bearer token entry

```yaml
  <NAME>:
    endpoint: <ENDPOINT>
    authentication:
      access_token: <ACCESS_TOKEN>
      token_type: Bearer
```

## Step 4: Keep credentials out of git

Run:

```bash
git update-index --skip-worktree config/mls.yml
```

This stops git from picking up the local credentials in `config/mls.yml`, which is checked in as an empty file. Running it again is harmless.

## Step 5: Verify the connection

Run:

```bash
./reso_cli resources
```

If it succeeds and prints a list of resources, tell the user that `<NAME>` is added and now active. Also mention they can switch MLSs with `/mls-use`.

If it fails, help troubleshoot:
- Check the endpoint URL for typos or missing path segments.
- Check that the credentials are correct.
- Check for network or firewall issues.
- A stale metadata cache is not the cause: each endpoint has its own cache file in `~/.cache/mls/`.
- Offer to fix the entry with corrected values.
