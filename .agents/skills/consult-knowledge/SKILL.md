---
name: consult-knowledge
description: When a development trouble occurs (error, build/startup failure, cannot-access, misconfiguration, dependency/version conflict, test failure, etc.), search the project's `knowledge/` folder for past trouble reports and reuse their confirmed solutions before troubleshooting from scratch. Auto-extracts search terms (error type, tech, library, keywords) from the current trouble, greps the saved reports, surfaces the most relevant ones, and applies the recorded fix. Trigger PROACTIVELY whenever you hit a trouble, and also when the user says things like "have we seen this before?", "check the knowledge folder", "search past troubles", or "is there a known fix for this?".
---

# Purpose

Reuse **previously recorded troubles and their resolutions** (saved by the `save-knowledge`
skill under `knowledge/`) so that a trouble we have already solved once is fixed instantly
instead of re-investigated from zero.

This skill is the **read/consult counterpart** of `save-knowledge`:

- `save-knowledge` → writes a trouble report into `knowledge/`
- `consult-knowledge` → searches `knowledge/` and applies the recorded fix

It reads the same files (`knowledge/INDEX.md` + `knowledge/YYYY-MM-DD-<slug>.md`) and the same
structure as `templates/knowledge-report.md` (YAML frontmatter + 9 Japanese sections).

This skill does **not**:

- Modify or create knowledge files → that's `save-knowledge`'s job
- Replace your own judgement → a past fix is a *strong hint*, not a guarantee it applies here

---

## Triggers

Invoke this skill **proactively, without being asked**, the moment you encounter a trouble while
working, for example:

- A command, build, install, or test **fails** (non-zero exit, stack trace, error log)
- A server / dev server **won't start** or a port is in use
- "cannot access" / 4xx-5xx / timeout / connection refused
- A misconfiguration, dependency/version conflict, or permission/auth error appears

Also invoke when the user explicitly asks:

- "Have we hit this before?", "Is this a known issue?", "Check the knowledge folder"
- "Search past troubles for this error", "Is there a recorded fix?"

> **When to skip**: trivial, self-evident errors you can fix in one step (e.g. an obvious typo you
> just introduced) don't need a knowledge lookup. Use this skill when the trouble is non-trivial,
> unfamiliar, or you're about to spend real time investigating.

> **One-shot, non-blocking**: consult once per distinct trouble. If `knowledge/` is missing/empty or
> nothing matches, say so in one line and continue troubleshooting normally — never block on it.

---

## Flow

```
Phase 0: Frame the trouble    → state in one sentence what just went wrong
Phase 1: Extract search terms → pull error_type / tech / library / keywords from the trouble
Phase 2: Search knowledge/    → run the search script (or grep) and rank candidates
Phase 3: Read & judge         → read top matches, decide which actually apply
Phase 4: Apply & report       → reuse the recorded fix, or report "no match" and proceed
```

---

## Phase 0: Frame the trouble

Phrase, in one sentence, what went wrong — the symptom plus the technology/target.
Example: "Vite dev server fails to start because the port is already in use."

Derive this from the current session: the failing command, its error output, the stack trace, and
what we were doing when it broke.

---

## Phase 1: Extract search terms

From the trouble, pull a handful of high-signal terms that match the tagging vocabulary used by
`save-knowledge` (see `../save-knowledge/reference/field-guide.md`). Aim for 3–6 terms across:

- **Error Type** — the literal error token if any: `EADDRINUSE`, `ModuleNotFoundError`, `403`,
  `timeout`, `ECONNREFUSED`, exception class names.
- **Tech** — language / framework / tool: `node`, `vite`, `docker`, `python`, `go`.
- **Library** — the specific package involved: `react`, `fastapi`, `prisma`, `pnpm`.
- **Keywords** — the symptom in plain words (English and/or Japanese): `port conflict`,
  `ポート競合`, `peer dependency`.

Prefer the **verbatim error token** — it's the highest-signal match against saved frontmatter
`error_type` tags and the `## 問題 > エラーメッセージ` code blocks.

---

## Phase 2: Search knowledge/

Run the helper script with the extracted terms (it handles "folder missing / empty / no match"
gracefully and ranks files by how many distinct terms they hit):

```
bash .agents/skills/consult-knowledge/scripts/search-knowledge.sh "<term1>" "<term2>" "<term3>"
```

Interpreting its output:

- It prints one block per matching file, **best match first**, with `SCORE=<distinct>/<total>`,
  `HITS=<total matches>`, the path, and the matched term/line for each hit.
- If it prints `NO_KNOWLEDGE_DIR` / `NO_KNOWLEDGE_FILES` / `NO_MATCH` on stderr → there's nothing to
  reuse. Go straight to Phase 4 (report "no match" and proceed).

Fallback if the script can't run:

```
grep -ril "<error token>" knowledge/        # find files mentioning the error
grep -ri  "<keyword>"     knowledge/INDEX.md # scan the index by keyword/tag
```

---

## Phase 3: Read & judge

1. read the top 1–3 candidate files (highest `SCORE` first).
2. For each, check it genuinely matches the **current** trouble — compare:
   - `## 問題` (期待/実際の挙動・エラーメッセージ) vs. what we're seeing now
   - `## 背景` (技術スタック・環境) vs. our context
   - `status` in frontmatter — `resolved` is directly reusable; `workaround` / `unresolved` is a
     partial lead, flag that.
3. Discard false positives (same token, different root cause). A high `HITS` count on an unrelated
   file is still a miss — judge by content, not score alone.

---

## Phase 4: Apply & report

**If a relevant report is found**, tell the user concisely before acting:

```
📚 Found a past knowledge entry for this trouble:
   knowledge/<file>.md — "<Title>"  (status: <resolved|workaround|unresolved>)

Recorded cause: <確定した原因 in one line>
Recorded fix:   <最終的な修正 in one line>

I'll apply this fix to the current situation.
```

Then apply the recorded **最終的な修正 / 再発防止** to the current trouble, adapting paths/values to
the present context. Verify it actually resolved the trouble (re-run the failing command, etc.)
before declaring success — a past fix is a strong hint, not a guarantee.

**If nothing relevant is found**, say so in one line and continue troubleshooting normally:

```
📭 No matching entry in knowledge/ for this trouble. Proceeding to investigate.
```

After you solve a *new, unrecorded* trouble this way, **offer to save it** so next time it's a hit:

```
This looks new. Want me to record it with the save-knowledge skill?
```

---

## Edge cases

- **`knowledge/` doesn't exist / is empty** → the script reports it; mention once and move on. Don't
  create the folder (that's `save-knowledge`).
- **Many candidates** → read by `SCORE` order, cap at the top ~3 unless they're all near-misses.
- **Match is `status: unresolved` / `workaround`** → surface it as a *lead* and prior attempts to
  avoid, not as a solved fix. The recorded "試したこと（失敗した試行）" tells you what NOT to repeat.
- **Applied fix doesn't work** → don't force it; fall back to normal investigation, and note the
  divergence (it may be worth updating that knowledge entry afterward).
- **Multiple distinct troubles at once** → consult per distinct trouble, not one blended search.

---

## Mindset

- **Look before you dig**: on a non-trivial trouble, a 1-second grep of past reports can save a long
  investigation. Make consulting the reflex.
- **Content over score**: ranking finds candidates; *you* confirm relevance by reading the report.
- **A hint, not gospel**: adapt the recorded fix to the current context and verify it worked.
- **Close the loop**: a new trouble solved → offer `save-knowledge` so the next occurrence is a hit.
- **Never block**: missing folder / no match is normal early on — report briefly and keep working.
