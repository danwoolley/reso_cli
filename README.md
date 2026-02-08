## Configure your credentials

`cp config/mls.yml.example config/mls.yml`
Then edit config/mls.yml with your MLS endpoint and OAuth credentials.


## Test	

Once that's done, you can test with `./reso_cli resources`
  

## Commands

  - reso_cli resources -- discover what the MLS exposes
  - reso_cli fields RESOURCE [--match PATTERN] -- list/search field names
  - reso_cli search RESOURCE [filters] -- query with structured or raw OData filters
  - reso_cli get RESOURCE KEY -- fetch a single record
  - reso_cli count RESOURCE [filters] -- count matching records


## Skills: .claude/skills/mls/

  - SKILL.md -- tells me when/how to use the CLI, query strategy, and auto-allows the Bash command
  - reference.md -- RESO Data Dictionary field names, OData filter syntax, and common query patterns (comps, active listings, new
  listings, etc.)


## Claude Code

In future conversations, just ask me things like "show me 3-bedroom homes under $500k in [your city]" and the skill will kick in automatically.

