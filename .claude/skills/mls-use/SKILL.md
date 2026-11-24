---
name: mls-use
description: List, switch or remove the user's configured MLS connections in reso_cli. Use for requests like "switch to CRMLS", "use my other MLS", "which MLS am I using?", "what MLSs do I have set up?", or "remove ACTRIS". To add an MLS or replace its credentials, use mls-setup instead.
argument-hint: "[MLS name] | list | remove [MLS name]"
allowed-tools: Bash(./reso_cli mls), Bash(./reso_cli use *), Bash(./reso_cli remove *), Bash(./reso_cli test)
---

# MLS Use Skill

Manage which MLS `reso_cli` queries: list the configured MLSs, switch the active one, or remove one. MLS connections are added with `/mls-setup`. Never read the config file directly, because it contains credentials. Use only the CLI commands below.

## Step 1: List the configured MLSs

```bash
./reso_cli mls
```

This prints each MLS's `name`, `endpoint`, `auth` type, and whether it is `active`. It never shows credentials. If the list is empty, tell the user to run `/mls-setup` and stop.

## Step 2: Work out what the user wants

From the skill argument or their message:

- **List / "which one am I using?"**: show the MLSs as a short table (name, endpoint, auth type) and say which one is active. Stop there, unless they also asked to switch.
- **Remove** (e.g. "remove ACTRIS", `/mls-use remove ACTRIS`): go to **Remove an MLS**.
- **Switch**, either with a name (e.g. `/mls-use CRMLS`, "switch to crmls") or with no argument at all: go to **Switch MLS**.

## Switch MLS

1. **Choose the MLS.**
   - If the user gave a name, match it against the listed names. Matching is case-insensitive, and a clear partial match is fine, e.g. `crm` matches `CRMLS`. If more than one name matches, or none does, ask using the list below.
   - Otherwise, ask the user to pick one, using AskUserQuestion with one option per MLS. Each option's label is the MLS name, and its description is the endpoint, plus "(currently active)" for the active one. AskUserQuestion allows at most 4 options. If there are more than 4 MLSs, show them as a numbered list in your message and ask the user to reply with a name or number.
   - If the chosen MLS is already active, say so and stop.
2. **Switch:** `./reso_cli use "<NAME>"`
3. **Confirm the connection:** run `./reso_cli test`, which makes a real, authenticated request. If it succeeds, tell the user which MLS is now active, along with its endpoint. If it fails, explain the error in plain words and suggest running `/mls-setup` to replace that MLS's credentials. Expired bearer tokens are a common cause.

MLS-specific quirks in the `/mls` skill (e.g., the CRMLS notes) apply based on the active endpoint.

## Remove an MLS

1. **Match the name** the same way as for switching. If it's unclear which MLS they mean, ask.
2. **Confirm first.** Removing deletes that MLS's saved credentials, and getting them back means entering them again with `/mls-setup`. Ask, e.g. with AskUserQuestion: "Remove <NAME> (<endpoint>)? Its saved credentials will be deleted." Only continue if they confirm.
3. **Remove:** `./reso_cli remove "<NAME>"`. The output shows the new active MLS, if any.
4. **Report:** say which MLS was removed. If it was the active one, say which MLS is active now, or that none are left and they can add one with `/mls-setup`.
