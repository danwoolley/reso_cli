# RESO Web API Client CLI + Claude Skills = Claude Code MLS Access! :lobster:

https://github.com/user-attachments/assets/844c8724-7d7d-48fc-9e27-342d0adf474e

Connect to as many MLS RESO Web API servers as you like and switch between them. It has been tested with CRMLS (https://h.api.crmls.org/Reso/OData; the Skills include special notes for it), Bridge Interactive (ACTRIS) and CDL / Lone Wolf.


## Prerequisites

1. **Ruby 3.1+** (tested with 3.4.1)
   - Check with: `ruby --version`
   - Install: [ruby-lang.org/en/documentation/installation](https://www.ruby-lang.org/en/documentation/installation/)
2. **Bundler** — `gem install bundler`
3. **Claude Code** — [claude.com/claude-code](https://claude.com/claude-code) (optional; everything also works from the shell)


## Setup

```bash
git clone https://github.com/danwoolley/reso_cli.git
cd reso_cli
bundle install
```

### Add an MLS

Start Claude Code in the `reso_cli` folder and type:

```text
/mls-setup
```

Claude asks a few simple questions: what to call the MLS, its API address, and your credentials. You can:

- **Point it at a Postman collection** (a `.json` file) if your MLS or data vendor sent you one. Claude reads the settings straight from the file, so your secrets never appear in the chat. This is the easiest and safest option.
- **Paste the connection details**, for example straight from the email your MLS sent. Claude picks out the API URL, then either a bearer token or a client ID and secret (OAuth2).

Claude then tests the connection and tells you whether it worked. Run `/mls-setup` again for each MLS you want to add. The newest one becomes active.

### Switch between MLSs

```text
/mls-use            # pick from a list
/mls-use CRMLS      # or choose by name
```

### Where your credentials are stored

MLS connections are saved in **`~/.config/reso_cli/mls.yml`**. That's in your home folder, outside this repo, so they can't be committed to git by accident, and they stay put if you delete or re-clone the repo. The file can only be read by your user account. To keep it somewhere else, set `RESO_CLI_CONFIG=/path/to/mls.yml`.

You don't need to edit this file. If you want to see its format, look at `config/mls.yml.example`.

A few things to know:

- **Pasted credentials become part of your Claude conversation.** That's normally fine for MLS API keys. If you'd rather keep a secret out of the chat, use a Postman collection, or run `./reso_cli add` yourself in a terminal (see below).
- Claude never prints saved secrets, and this repo's `.claude/settings.json` stops Claude from reading the config file.
- **Bearer tokens often expire** (sometimes daily). If an MLS suddenly stops working, run `/mls-setup` again with a fresh token and choose to replace the existing entry. OAuth2 client credentials renew automatically.

### Upgrading from an older version

Older versions kept credentials in `config/mls.yml` inside the repo. The first time you run any `reso_cli` command, that file is copied to `~/.config/reso_cli/mls.yml` automatically. After that, you can delete `config/mls.yml`.

### Without Claude

You can do everything from the shell:

```bash
# Bearer token
./reso_cli add "My MLS" --endpoint https://api.my-mls.com/odata --token YOUR_TOKEN

# OAuth2 client credentials (add --scope SCOPE only if your MLS requires one)
./reso_cli add "My MLS" --endpoint https://api.my-mls.com/odata \
  --token-url https://auth.my-mls.com/oauth2/token --client-id YOUR_ID --client-secret YOUR_SECRET

# From a Postman collection
./reso_cli postman ~/Downloads/MyMLS.postman_collection.json           # see which auth setups it contains
./reso_cli add "My MLS" --from-postman ~/Downloads/MyMLS.postman_collection.json --postman-auth "AUTH NAME"

./reso_cli test           # check that the active MLS accepts your credentials
./reso_cli mls            # list your MLSs
./reso_cli use "My MLS"   # switch
./reso_cli remove "My MLS"
```


## CLI commands

  - `reso_cli resources` -- discover what the MLS exposes
  - `reso_cli fields RESOURCE [--match PATTERN]` -- list/search field names
  - `reso_cli search RESOURCE [filters]` -- query with structured or raw OData filters
  - `reso_cli get RESOURCE KEY` -- fetch a single record
  - `reso_cli count RESOURCE [filters]` -- count matching records
  - `reso_cli mls` -- list configured MLSs (credentials are never printed)
  - `reso_cli use NAME` -- switch the active MLS
  - `reso_cli add NAME [options]` -- add an MLS connection (`reso_cli add --help` for options)
  - `reso_cli remove NAME` -- remove an MLS connection
  - `reso_cli test` -- make a live, authenticated request to the active MLS
  - `reso_cli postman FILE` -- show the auth setups in a Postman collection (secrets are never printed)


## Skills

In folder .claude/skills:
  - /mls
    - SKILL.md -- tells me when/how to use the CLI, query strategy, and auto-allows the Bash command
    - reference.md -- RESO Data Dictionary field names, OData filter syntax, and common query patterns (comps, active listings, new listings, etc.)
  - /mls-setup
    - SKILL.md -- friendly setup interview; adds a new named MLS from pasted details or a Postman collection, then tests it
  - /mls-use
    - SKILL.md -- switch the active MLS by name or by picking from a list


## Claude Code usage

Run Claude Code in the root project folder, then ask things like:

```text
show me 3-bedroom homes under $500k in [your city]
```
```text
what is the highest recorded sales price in [city] in the past 18 months?
```



danwoolley@gmail.com :goat:
