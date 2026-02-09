# RESO Web API Client CLI + Claude Skills = Claude Code MLS Access! :lobster:

This has been tested so far on the CRMLS RESO Server at https://h.api.crmls.org/Reso/OData and special notes have been added to the Skills for that MLS.


## Configure your credentials

```bash
cp config/mls.yml.example config/mls.yml
```

Then edit config/mls.yml with your MLS endpoint and OAuth credentials.


## Test	

Once that's done, you can test with:

```bash
./reso_cli resources
```
  

## Commands

  - `reso_cli resources` -- discover what the MLS exposes
  - `reso_cli fields RESOURCE [--match PATTERN]` -- list/search field names
  - `reso_cli search RESOURCE [filters]` -- query with structured or raw OData filters
  - `reso_cli get RESOURCE KEY` -- fetch a single record
  - `reso_cli count RESOURCE [filters]` -- count matching records


## Skills

In folder .claude/skills/mls:

  - SKILL.md -- tells me when/how to use the CLI, query strategy, and auto-allows the Bash command
  - reference.md -- RESO Data Dictionary field names, OData filter syntax, and common query patterns (comps, active listings, new
  listings, etc.)


## Claude Code

Run CC in the project folder, then ask things like:

```text
show me 3-bedroom homes under $500k in [your city]
```
```text
what is the highest recorded sales price in [city] in the past 18 months?
```



danwoolley@gmail.com :goat:
