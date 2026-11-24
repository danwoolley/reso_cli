---
name: mls-setup
description: Add a new MLS RESO Web API connection (name, endpoint, credentials) to reso_cli, from details the user pastes or from a Postman collection.
allowed-tools: Bash(./reso_cli mls), Bash(./reso_cli add *), Bash(./reso_cli postman *), Bash(./reso_cli test), Bash(./reso_cli use *), Bash(./reso_cli remove *)
---

# MLS Setup Skill

Each run adds **one MLS connection** to reso_cli and makes it the active one. Connections are saved by `./reso_cli add` in `~/.config/reso_cli/mls.yml`, outside the repo, with private file permissions.

The person may not be technical. Keep it friendly: ask one short question at a time, accept answers in whatever form they come (a pasted email from the MLS is fine), and never ask them to edit YAML or files.

## Rules for credentials

- **Never read or edit the config file directly.** Use only the `./reso_cli` commands listed in this skill.
- **Never repeat a secret, token or password back** in your replies, not even partly. Refer to them as "your client secret", "your token", and so on.
- If a Postman collection is available, prefer it. `./reso_cli add --from-postman` copies the credentials straight from the file, so the secrets never appear in the conversation.

## Step 1: See what's already set up

Run `./reso_cli mls` and note the existing names, so you can avoid duplicates.

## Step 2: Ask how they received their credentials

Ask: "Did your MLS or data vendor send you a **Postman collection** (a `.json` file), or do you have the **connection details** (an API URL plus a token, or a client ID and secret) to paste here?"

### Path A: Postman collection

1. Ask for the file's location. Expand `~` and turn any relative path into an absolute one, because `./reso_cli` runs from the repo folder.
2. Run `./reso_cli postman "<ABSOLUTE PATH>"`. It lists each usable auth setup in the collection, with its token URL, client ID, scope and the OData endpoints its requests use. It never shows secrets.
3. If there's more than one usable auth setup, ask the user which one to use, using AskUserQuestion with one option per auth. Explain the differences in plain words when the names hint at them (e.g. "IDX & VOW" is public listing data; "BO" is the back-office feed).
4. Ask for a name (see Step 3), then run:
   ```bash
   ./reso_cli add "<NAME>" --from-postman "<ABSOLUTE PATH>" --postman-auth "<AUTH NAME>"
   ```
   The endpoint is taken from the collection. If the collection listed no endpoint, ask for it and add `--endpoint "<URL>"`.

### Path B: Pasted or typed details

Collect these, one at a time. If the user pastes a whole email or note, pick the values out of it yourself, and only ask about anything missing.

1. **API endpoint URL**: the OData service root, e.g. `https://api.example.com/odata`. If they give a request URL like `https://api.example.com/odata/Property?$top=10`, use the part through `/odata`.
2. **Name** (Step 3).
3. **Credentials**, in one of two kinds. Work out which from what they pasted, and ask only if it's unclear:
   - **Bearer token**: a single long access token.
   - **OAuth2 client credentials**: a token URL, client ID and client secret, plus a scope if the MLS specified one. Leave the scope out if none was given; most servers want none.

Then run one of these:

```bash
./reso_cli add "<NAME>" --endpoint "<URL>" --token "<TOKEN>"
./reso_cli add "<NAME>" --endpoint "<URL>" --token-url "<TOKEN URL>" --client-id "<ID>" --client-secret "<SECRET>" [--scope "<SCOPE>"]
```

## Step 3: Choose a name

Suggest a short name based on the MLS or the endpoint's host (e.g. `CRMLS`, `ACTRIS`, `Bright`), and let the user accept it or type their own.

If the name already exists (`./reso_cli add` reports it), ask whether to **replace** that connection (re-run with `--replace`) or use a different name.

## Step 4: Test the connection

Run `./reso_cli test`. It makes a real, authenticated request to the new (now active) MLS.

- **Success**: tell the user that `<NAME>` is set up and active, and how many resources it has (e.g. Property, Member, Office). Mention that they can now ask questions like "show me active listings in <city>", and switch MLSs any time with `/mls-use`.
- **Failure**: explain the error in plain words and suggest a fix:
  - `Access denied: invalid_client` / `invalid_scope` / `unauthorized`, or HTTP 401/403: a credential or scope problem. Double-check the values with the user, or ask the MLS which scope to use. To fix it, re-run the `add` command with `--replace`.
  - `Could not connect`: the URL may be wrong, or the network may be blocking it. Some MLSs only allow approved IP addresses.
  - `Received 404`: the endpoint URL is probably missing or has an extra path segment.
- If the user gives up on this MLS, offer to remove it with `./reso_cli remove "<NAME>"`.
