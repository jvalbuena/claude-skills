---
name: research
description: Research the current state of the codebase into research.md, then clarify a task with the user and write a lean plan to plan.md. Use when starting any non-trivial feature, fix, or refactor — it produces a shared understanding of the code before committing to an approach.
---

# Research & Plan Skill

This skill runs in two phases:

1. **Research** — read the codebase, capture what matters in `research.md`
2. **Plan** — clarify the task with the user, then write a lean, decision-aware plan to `plan.md`

---

## Phase 1 — Research

### What to do

Read the codebase top-down and write `research.md` into the current working directory. Do NOT start Phase 2 until `research.md` is written and confirmed.

### Reading order

1. `CLAUDE.md` (project instructions, module map, env vars, architecture notes) — read this first. It is the authoritative guide.
2. Every file listed in the module map inside `CLAUDE.md`. Read each one fully.
3. Key config files: `pyproject.toml`, `.env` (if present), `requirements.txt` or `uv.lock`, any `docker-compose.yml`.
4. Any file that CLAUDE.md calls out as an entry point (e.g. `app.py`).
5. Files that are likely to be touched by the upcoming task — based on context in the conversation.

If CLAUDE.md does not exist, derive the module map by listing the repo root, reading `README.md` if present, and reading the entry point files.

### What to capture in `research.md`

Structure the file with these sections:

```
# Codebase Research

## Project snapshot
One paragraph: purpose, stack, entry point, deployment model.

## Module map
Table: file | responsibility | key exports or side-effects
(copy and extend from CLAUDE.md if present)

## Data model
Tables/schemas that matter. Primary keys, foreign keys, JSON columns, notable constraints.

## Key decisions & patterns
Bullet list. Each bullet: the decision made, why it exists (if known), and consequences for new work.
Examples: thread model for AI calls, dual-mode DB, CDN-loaded component, auth flow.

## Environment & configuration
Variables that gate behaviour. Which ones must be set for the task at hand.

## Boundaries & gotchas
Things that will break if ignored: stale connection handling, GPU semaphore, WebSocket reconnects, component protocol, etc.

## Files likely relevant to the upcoming task
List files by name. One line each explaining why.
```

Write the file with the Write tool. Be precise and factual — no padding, no speculation.

---

## Phase 2 — Task definition

### What to do

After `research.md` is written, shift to conversation mode. Your goal is to reach a shared, unambiguous definition of what needs to be built, then write it to `plan.md`.

### Step 1 — Ask what the task is

If the user has not stated it yet, ask:

> "Research is done. What do you want to build or fix?"

### Step 2 — Clarify until the task is tight

Ask focused questions until you can answer ALL of these without guessing:

**Functional (what it does)**
- What is the exact user-visible change or new capability?
- What are the inputs and outputs?
- What are the acceptance criteria — how will we know it's done?
- What edge cases must be handled explicitly?

**Non-functional (how it behaves)**
- Performance: any latency or throughput constraints?
- Reliability: does this path need error handling, retries, or fallback?
- Security: does it touch auth, user data, or external services?
- Maintainability: will this be extended? Is it a one-off?
- Observability: does it need logging, tracing, or metrics?

Do not ask all questions at once. Ask the most important unresolved ones first. Two or three per turn is the right cadence. Stop asking when the answers make the implementation unambiguous.

### Step 3 — Write `plan.md`

Once the task is clear, write `plan.md` into the current working directory. Structure:

```
# Plan: <task name>

## Objective
One sentence. What changes and why.

## Scope
### In scope
Bullet list of exactly what will be built.

### Out of scope
Explicit exclusions that prevent scope creep.

## Functional requirements
Numbered list. Each one testable: "Given X, when Y, then Z."

## Non-functional requirements
Bullet list. Each one concrete: latency target, error handling rule, auth check, etc. Omit categories that genuinely do not apply.

## Approach
### Files to change
Table: file | what changes | why

### Files to leave alone
Anything that looks relevant but should NOT be touched, and why.

### Implementation steps
Numbered, ordered, atomic. Each step small enough to verify independently.

### Decisions made
Table: decision | rationale | alternative considered

## Open questions
Anything still unresolved that could change the plan. (Remove section if empty.)
```

### Lean product check

Before finalising `plan.md`, apply these filters:

- **Cut**: any step that adds abstraction, generalisation, or future-proofing not required by the stated task
- **Cut**: error handling for cases that cannot happen given the codebase's invariants
- **Cut**: new files when an existing file already owns that responsibility
- **Flag**: anything that touches more than one concern at once — split it or justify it
- **Flag**: non-functional requirements added "just in case" — each one needs a concrete reason

If the plan passes these filters, write it. If it doesn't, trim and rewrite before writing.

---

## Completion

When both files are written, tell the user:

> "`research.md` and `plan.md` are ready. Review `plan.md` and let me know if anything needs adjusting before I start implementing."

Do not begin implementation unless the user explicitly says to proceed.
