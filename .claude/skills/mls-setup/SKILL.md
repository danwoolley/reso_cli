---
name: mls-setup
description: Set up reso_cli by configuring your MLS API credentials and endpoint.
allowed-tools: Write(config/mls.yml), Read(config/mls.yml), Read(config/mls.yml.example), Bash(./reso_cli resources)
---

# MLS Setup Skill

Guide the user through configuring `reso_cli` to connect to their MLS RESO Web API server.

## Step 1: Check for existing config

Read `config/mls.yml`. If it already exists and contains real credentials (not the example placeholders), warn the user:

> You already have a `config/mls.yml`. Do you want to overwrite it?

Only proceed if they confirm. If the file doesn't exist or contains only example placeholders, continue.

## Step 2: Collect MLS details

Ask the user for the following, one question at a time:

1. **API endpoint URL** — The OData service root (e.g., `https://h.api.crmls.org/Reso/OData`)
2. **Auth method** — Ask: "Does your MLS use **OAuth2 client credentials** or a **static bearer token**?"
3. Based on their answer:
   - **OAuth2**: Ask for:
     - Token endpoint URL (e.g., `https://ids.crmls.org/connect/token`)
     - Client ID
     - Client secret
     - Scope (optional — default to empty string `''` if they skip)
   - **Bearer token**: Ask for:
     - The access token value

## Step 3: Write config/mls.yml

Write the config file using the exact structure below. Do NOT include commented-out blocks or alternative configs — write only the variant that matches the user's auth method.

### OAuth2 variant

```yaml
endpoint: <ENDPOINT>
authentication:
  endpoint: <TOKEN_ENDPOINT>
  client_id: <CLIENT_ID>
  client_secret: <CLIENT_SECRET>
  scope: '<SCOPE>'
```

### Bearer token variant

```yaml
endpoint: <ENDPOINT>
authentication:
  access_token: <ACCESS_TOKEN>
  token_type: Bearer
```

## Step 4: Verify the connection

Run:

```bash
./reso_cli resources
```

If it succeeds (prints a list of resources), tell the user setup is complete.

If it fails, help troubleshoot:
- Check the endpoint URL for typos or missing path segments
- Check that credentials are correct
- Check for network/firewall issues
- Offer to re-run setup with corrected values
