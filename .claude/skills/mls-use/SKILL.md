---
name: mls-use
description: Switch reso_cli to a previously configured MLS, by name or by picking from a list.
argument-hint: "[MLS name]"
allowed-tools: Bash(./reso_cli mls), Bash(./reso_cli use *), Bash(./reso_cli test)
---

# MLS Use Skill

Switch the MLS that `reso_cli` queries. MLS connections are added with `/mls-setup`. Never read the config file directly, because it contains credentials. Use only the CLI commands below.

## Step 1: List the configured MLSs

```bash
./reso_cli mls
```

This prints each MLS's `name`, `endpoint`, `auth` type, and whether it is `active`. If the list is empty, tell the user to run `/mls-setup` and stop.

## Step 2: Choose the MLS

- **If the user gave a name** (as the skill argument or in their message), match it against the listed names. Matching is case-insensitive, and a clear partial match is fine, e.g. `crm` matches `CRMLS`. If more than one name matches, or none does, fall back to the list below.
- **Otherwise**, ask the user to pick one, using AskUserQuestion with one option per MLS. Each option's label is the MLS name, and its description is the endpoint, plus "(currently active)" for the active one. AskUserQuestion allows at most 4 options. If there are more than 4 MLSs, show them as a numbered list in your message and ask the user to reply with a name or number.

If the chosen MLS is already active, say so and stop.

## Step 3: Switch

```bash
./reso_cli use "<NAME>"
```

## Step 4: Confirm the connection

Run `./reso_cli test`, which makes a real, authenticated request. If it succeeds, tell the user which MLS is now active, along with its endpoint. If it fails, explain the error in plain words and suggest re-running `/mls-setup` to replace that MLS's credentials. Expired bearer tokens are a common cause.

MLS-specific quirks in the `/mls` skill (e.g., the CRMLS notes) apply based on the active endpoint.
