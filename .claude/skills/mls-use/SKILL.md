---
name: mls-use
description: Switch reso_cli to a previously configured MLS, by name or by picking from a list.
argument-hint: "[MLS name]"
allowed-tools: Bash(./reso_cli mls), Bash(./reso_cli use *), Bash(./reso_cli resources)
---

# MLS Use Skill

Switch the active MLS that `reso_cli` queries. The MLSs are defined in `config/mls.yml` (added with `/mls-setup`). Don't read `config/mls.yml` directly, because it contains credentials. Use the CLI commands below instead.

## Step 1: List the configured MLSs

```bash
./reso_cli mls
```

This prints each MLS's `name`, `endpoint`, `auth` type, and whether it is `active`. If no MLSs are configured, tell the user to run `/mls-setup` and stop.

## Step 2: Choose the MLS

- **If the user gave a name** (as the skill argument or in their message), match it against the listed names. Matching is case-insensitive, and a clear partial match is fine, e.g. `crm` matches `CRMLS`. If more than one name matches, or none does, fall back to the list below.
- **Otherwise**, ask the user to pick one, using AskUserQuestion with one option per MLS. Each option's label is the MLS name, and its description is the endpoint, plus "(currently active)" for the active one. AskUserQuestion allows at most 4 options. If there are more than 4 MLSs, show them as a numbered list in your message and ask the user to reply with a name or number.

If the chosen MLS is already active, say so and stop.

## Step 3: Switch

```bash
./reso_cli use "<NAME>"
```

## Step 4: Confirm the connection

Run `./reso_cli resources`. If it succeeds, tell the user which MLS is now active, along with its endpoint. If it fails, show the error and suggest re-running `/mls-setup` to fix that MLS's credentials.

MLS-specific quirks in the `/mls` skill (e.g., the CRMLS notes) apply based on the active endpoint.
