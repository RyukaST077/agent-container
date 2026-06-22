---
name: save-knowledge
description: Save a development trouble (error, build/startup failure, cannot-access, misconfiguration, etc.) as a structured knowledge report under the project's `knowledge/` folder. Auto-fills Context/Problem/Cause/Solution as much as possible from conversation history, git diffs, and related files, asks the user only for what is missing, and writes a searchable Markdown report. Trigger when the user says things like "save this trouble to knowledge", "record this error", "turn this into knowledge", "keep this as a learning", or "write a trouble report".
---

# Purpose

Accumulate **troubles and how they were resolved** as reusable, structured knowledge under the
project's `knowledge/` folder, one file per trouble.

Goals:

- Make "I've seen this error before" instantly retrievable later via **grep / index / tags**
- Preserve the troubleshooting trail, including failed attempts
- **Auto-fill most fields** from conversation context to minimize human input

This skill does **not** handle:

- Generic how-to / design notes (non-troubles) → write those as normal docs
- Storing secrets (tokens, passwords, production connection info) → mask them in Phase 3

---

## Triggers

Invoke this skill when the user says things like:

- "Save this trouble / error to knowledge", "record it", "keep it"
- "Turn this into knowledge", "keep this as a learning"
- "Write a trouble report", "write it to knowledge"
- Right after fixing an error together: "log this for me"

---

## Output

```
<project-root>/knowledge/
  ├── INDEX.md                       ← index of all knowledge (auto-updated)
  └── YYYY-MM-DD-<slug>.md           ← one file per trouble
```

Each file follows the structure of `templates/knowledge-report.md` (YAML frontmatter + 9 sections).
The frontmatter carries tags/category/date, duplicated with the body, so it can be retrieved via
both grep and metadata search.

**Language**: Write the report **body in Japanese** (section content and the Japanese headings in the
template). Keep these in English: error messages / logs / commands / code (verbatim), the search tags
`tech` / `error_type` / `library`, and the `cause_category` value. The filename slug stays English kebab-case.

---

## Flow

```
Phase 0: Identify target trouble  → decide "what to record" from this session's conversation history
Phase 1: Auto-collect context     → gather material from conversation, git, related files
Phase 2: Fill template fields     → auto-fill, then ask only for missing/uncertain fields
Phase 3: Draft & approve          → show full report, confirm secret masking → approve
Phase 4: Save                     → write the file into knowledge/
Phase 5: Update INDEX & report    → append one line to INDEX.md, show the result
```

Do **not** write anything to disk (neither the knowledge file nor INDEX) before approval in Phase 3.

---

## Phase 0: Identify the target trouble

This skill takes **no arguments**. The target is always derived from **this session's
conversation history**.

1. Review the conversation history of the current session, phrase "which trouble to record" in one
   sentence, and confirm with the user:

   ```
   I'll turn the following trouble into knowledge. OK?
     → "<summary of the recently solved/discussed trouble>"
   If you meant a different trouble, tell me what it is.
   ```

2. If several troubles are candidates, list them and let the user pick one.
3. If no trouble is found in the conversation at all, ask: "Tell me the trouble you'd like to record."

> The trouble need not be resolved — it's still worth recording as `status: unresolved` / `workaround`.

---

## Phase 1: Auto-collect context

Gather the material to fill the report **before asking the user**.
See `reference/field-guide.md` for how to fill each field (sources, category list, tagging policy).

Collection actions (scoped to the target trouble):

- **Conversation history**: error messages, attempted steps, the fix that worked, commands run
- **Project info**:
  - `git rev-parse --show-toplevel` / `basename` (Project name)
  - `package.json` / `requirements.txt` / `pyproject.toml` / `go.mod` / `Dockerfile`, etc. (Tech Stack)
- **Changes**:
  - `git diff --name-only` / `git diff` (Changed Files / Before-After)
  - `git log --oneline -5` (related commits)
- **Related files**: `Read` file paths surfaced in stack traces or error messages

> Read-only. Change nothing in Phase 1.

---

## Phase 2: Fill template fields

Fill every `{{...}}` placeholder in `templates/knowledge-report.md`.

How:

1. **Confirm auto-fillable fields first** using material from Phase 1.
2. Ask the user **once, in a single batch**, only for fields that can't be filled or that you're
   unsure about (don't drip-feed questions).
   - Especially confirm: **Confirmed Cause** / **Final Fix** / **Verification results** / **Prevention**.
   - Use `AskUserQuestion` or a concise bullet list.
3. For anything still unknown, put `N/A` or `Unknown (needs confirmation)` (**no blanks, no guessing
   stated as fact**).
4. Assign tags (Tech / Error Type / Library / Keywords) and `cause_category`.
   - Pick `cause_category` from the list in field-guide.
   - `status` is one of `resolved` / `workaround` / `unresolved`.
5. Derive the filename slug (English kebab-case) from the Title.
6. Write all filled-in content in **Japanese** (keep error messages/commands/code verbatim, and
   tag values / `cause_category` in English — see field-guide).

---

## Phase 3: Draft & approve

1. Show the **full filled report** on screen (Markdown).
2. Also show the proposed save path: `knowledge/YYYY-MM-DD-<slug>.md`.
3. **Secret check** (important): before showing, scan Error Message / commands / Before-After for
   tokens, passwords, API keys, production hostnames, or PII, and mask them (e.g. `***`).
   Tell the user what was masked.
4. Ask for approval:

   | User response   | Next action                        |
   | --------------- | ---------------------------------- |
   | "OK", "save it" | Go to Phase 4                      |
   | "change this"   | Apply the edit and re-show Phase 3 |
   | "cancel"        | Exit without writing anything      |

---

## Phase 4: Save

1. Generate the save path deterministically (handles `knowledge/` creation, date prefix, collisions):

   ```
   bash .claude/skills/save-knowledge/scripts/new-knowledge.sh "<slug>"
   ```

   - It prints `knowledge/YYYY-MM-DD-<slug>.md` to stdout. Use that as the save path.
   - If the script can't run, create `knowledge/` manually and build the filename with `date +%F`.

2. `Write` the final content (all `{{...}}` replaced with real values) to that path.
   - Verify the YAML frontmatter is intact (two `---` lines, valid array syntax).

---

## Phase 5: Update INDEX & report

1. Update `knowledge/INDEX.md` (create if absent). Append one line per knowledge, **at the top
   (newest first)**:

   ```
   - [YYYY-MM-DD] [<Title>](./YYYY-MM-DD-<slug>.md) — `<cause_category>` / tags: tech, error_type …
   ```

   INDEX.md template (when creating new):

   ```markdown
   # Knowledge Index

   Index of development troubles and resolutions (newest first).
   Search: `grep -ri "<keyword>" knowledge/`

   ## Entries

   - [2026-05-29] [<Title>](./2026-05-29-<slug>.md) — `Category` / tags: …
   ```

2. Completion message:

   ```
   ✅ Knowledge saved.

   📄 knowledge/YYYY-MM-DD-<slug>.md
   🏷  category: <cause_category> / status: <status>
   🔎 tags: <key tags>
   📚 Updated INDEX.md.

   Search: grep -ri "<keyword>" knowledge/
   ```

3. Offer the commit only if the user wants it (never auto-commit):

   ```
   git add knowledge/ && git commit -m "docs(knowledge): add <Title>"
   ```

---

## Edge cases

- **Can't identify the trouble** → always confirm in Phase 0. Don't fabricate one.
- **Cause unconfirmed** → save with `Confirmed Cause: Unconfirmed` / `status: unresolved`. Can be
  appended later.
- **Secrets present** → must mask in Phase 3. Never store raw tokens/passwords.
- **A near-duplicate already exists** → check with `grep -ri`; if found, ask "append to existing
  [...] or create new?".
- **knowledge/ is gitignored** → check `git check-ignore knowledge/`; if the user wants to commit,
  advise revising the ignore rule.
- **Huge error message** → trim to key lines + head/tail of the stack trace (full text can go in a
  collapsed code block).

---

## Mindset

- **Collect before asking**: auto-fill what you can from conversation/git/files; ask humans only the gaps.
- **Keep the trail of failures**: writing wrong hypotheses / attempts into Suspected Cause / Attempts
  is what creates value later.
- **No blanks**: unknown → `N/A` or `Unknown (needs confirmation)`. But **never state a guess as fact**.
- **Don't write before approval**: no `Write` / INDEX update until Phase 3 passes.
- **Don't leak secrets**: always mask tokens/keys/production connection info before saving.
- **Searchability first**: choose Title/Summary/tags by "what would future-me search for?".
- **Record in Japanese**: fill the report body in Japanese; keep verbatim logs/commands/code and
  English tag values untouched.
