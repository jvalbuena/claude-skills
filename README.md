# claude-skills

A collection of reusable [Claude Code](https://claude.ai/code) skills — slash commands that encode repeatable workflows into structured prompts.

## What is a skill?

A skill is a directory inside `~/.claude/skills/<name>/` containing a `SKILL.md` file (and optionally reference sub-files). Once installed, Claude Code loads it automatically and exposes it as `/name` in any session.

## Skills in this repo

| Skill | What it does |
|---|---|
| [research](skills/research/) | Reads the codebase into `research.md`, then clarifies a task with you and writes a lean `plan.md` before any implementation begins |
| [langfuse](skills/langfuse/) | Query and modify Langfuse data via the CLI; look up Langfuse docs and SDK usage |

## Installation

```sh
# Clone the repo
git clone https://github.com/YOUR_USERNAME/claude-skills.git
cd claude-skills

chmod +x install.sh

# Install all skills
./install.sh

# Install a specific skill
./install.sh research

# Preview what would be installed
./install.sh --dry-run

# List available skills
./install.sh --list
```

Existing skills are backed up before overwriting (e.g. `~/.claude/skills/research.bak.20260425120000`).

## Using a skill

In any Claude Code session, type the skill name as a slash command:

```
/research
/langfuse
```

Claude will load the skill's instructions and follow them.

## Adding a skill to this repo

1. Create `skills/<your-skill-name>/SKILL.md` with this frontmatter:

```markdown
---
name: your-skill-name
description: One-line description shown in /help and skill lists.
---

# Your Skill Title

Instructions for Claude...
```

2. Optionally add reference files under `skills/<your-skill-name>/references/`.
3. Add a row to the table above.
4. Open a PR.

## Structure

```
skills/
  research/
    SKILL.md
  langfuse/
    SKILL.md
    references/
      cli.md
      instrumentation.md
install.sh
```
