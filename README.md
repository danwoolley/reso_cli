# RESO Web API Client CLI + Claude Skills = Claude Code MLS Access! :lobster:

https://github.com/user-attachments/assets/844c8724-7d7d-48fc-9e27-342d0adf474e

This has been tested so far on the CRMLS RESO Server at https://h.api.crmls.org/Reso/OData and special notes have been added to the Skills for that MLS.


## Prerequisites

1. **Ruby 3.1+** (tested with 3.4.1)
   - Check with: `ruby --version`
   - Install: [ruby-lang.org/en/documentation/installation](https://www.ruby-lang.org/en/documentation/installation/)
2. **Bundler** — `gem install bundler`
3. **Install dependencies** — `bundle install`


## Have Claude configure your MLS RESO access and credentials

Start Claude Code in the root folder of this project, then prompt it with:

```text
/mls-setup
```

Answer the questions.


## Manually configure your MLS RESO access and credentials

```bash
cp config/mls.yml.example config/mls.yml
```

Then edit config/mls.yml with your MLS endpoint and OAuth credentials.


## Test	your MLS RESO connection

Once that's done, you can test with:

```bash
./reso_cli resources
```

You should see a list of resources available on your MLS.


## CLI commands

  - `reso_cli resources` -- discover what the MLS exposes
  - `reso_cli fields RESOURCE [--match PATTERN]` -- list/search field names
  - `reso_cli search RESOURCE [filters]` -- query with structured or raw OData filters
  - `reso_cli get RESOURCE KEY` -- fetch a single record
  - `reso_cli count RESOURCE [filters]` -- count matching records


## Skills

In folder .claude/skills:
  - /mls
    - SKILL.md -- tells me when/how to use the CLI, query strategy, and auto-allows the Bash command
    - reference.md -- RESO Data Dictionary field names, OData filter syntax, and common query patterns (comps, active listings, new listings, etc.)
  - /mls-setup
    - SKILL.md -- the initial setup interview


## Claude Code

Run Claude Code in the root project folder, then ask things like:

```text
show me 3-bedroom homes under $500k in [your city]
```
```text
what is the highest recorded sales price in [city] in the past 18 months?
```



danwoolley@gmail.com :goat:
