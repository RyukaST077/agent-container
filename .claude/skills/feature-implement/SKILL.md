---
name: "feature-implement"
description: "Execute the implementation plan by processing and executing all tasks defined in tasks.md"
argument-hint: "Optional implementation guidance or task filter"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/implement.md"
user-invocable: true
disable-model-invocation: false
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before implementation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_implement` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    
    Wait for the result of the hook command before proceeding to the Outline.
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Execution Strategy: Opus Orchestrator + Sonnet Implementers

This command runs with **Opus as the orchestrator** and delegates the actual
file-writing implementation to **Sonnet subagents** to maximize token efficiency.

**Role split**:
- **Opus (you, the orchestrator)**: parse tasks.md, build the execution graph,
  dispatch work to subagents, review their output, make accept/reject decisions,
  mark tasks `[X]`, and report. Do **not** write implementation code directly
  unless a task is trivial (≤ a few lines) or a subagent has failed twice.
- **Sonnet implementer subagents**: receive one task (or one parallel batch),
  write/edit the code, and return a concise report of what changed.

**Dispatch protocol** — for each task (or parallel batch) spawn a subagent via the
Agent tool with `subagent_type: "claude"` and `model: "sonnet"`. The prompt MUST be
self-contained and include:
  - The task ID(s) and exact description from tasks.md
  - The precise file path(s) to create or modify
  - Relevant excerpts from plan.md / data-model.md / contracts / constitution
    (paste the needed lines — do not assume the subagent has read them)
  - Acceptance criteria: what "done" means, expected tests, coding conventions
  - An instruction to return a SHORT structured report (files changed, summary,
    test/lint results, any deviations) — not the full file contents

**Parallel execution**:
  - Tasks marked `[P]` whose file sets do **not** overlap MAY be dispatched as
    multiple Sonnet subagents in a single message (concurrent).
  - Tasks touching the same files, or with sequential dependencies, MUST be
    dispatched one at a time in dependency order.
  - Never parallelize across a phase boundary that requires validation first.

**Review loop (Opus checks)**:
  - After each subagent returns, Opus reviews the reported diff/result against the
    acceptance criteria and the spec.
  - If it passes: mark the task `[X]` in tasks.md and continue.
  - If it passes but deviates from spec.md / plan.md (the subagent reported a
    deviation, or Opus finds one and accepts it as the better outcome): mark the
    task `[X]` AND record it in the run's **deviation log** (task ID, what changed
    vs. spec/plan, why accepted). Accepting a deviation means the documents must
    be amended — reconciliation is enforced in the completion gate (step 9).
  - If it fails: send corrective feedback to the same subagent (or respawn) with
    the specific problem. After 2 failed attempts, Opus fixes it directly.
  - Opus reads files only as needed to verify — keep verification reads targeted.

## Outline

1. Run the check-prerequisites script from repo root with `--json --require-tasks --include-tasks` and parse FEATURE_DIR and AVAILABLE_DOCS list. Prefer the project script `.specify/scripts/bash/check-prerequisites.sh` if it exists; otherwise fall back to the copy bundled with this skill at `scripts/check-prerequisites.sh` (relative to this SKILL.md), which keeps the skill self-contained. (Both still resolve per-project state — `.specify/feature.json` — via the project's `.specify/` directory.) All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
     - Completed items: Lines matching `- [X]` or `- [x]`
     - Incomplete items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Completed | Incomplete | Status |
     |-----------|-------|-----------|------------|--------|
     | ux.md     | 12    | 12        | 0          | ✓ PASS |
     | test.md   | 8     | 5         | 3          | ✗ FAIL |
     | security.md | 6   | 6         | 0          | ✓ PASS |
     ```

   - Calculate overall status:
     - **PASS**: All checklists have 0 incomplete items
     - **FAIL**: One or more checklists have incomplete items

   - **If any checklist is incomplete**:
     - Display the table with incomplete item counts
     - **STOP** and ask: "Some checklists are incomplete. Do you want to proceed with implementation anyway? (yes/no)"
     - Wait for user response before continuing
     - If user says "no" or "wait" or "stop", halt execution
     - If user says "yes" or "proceed" or "continue", proceed to step 3

   - **If all checklists are complete**:
     - Display the table showing all checklists passed
     - Automatically proceed to step 3

3. Load and analyze the implementation context:
   - **REQUIRED**: Read tasks.md for the complete task list and execution plan
   - **REQUIRED**: Read plan.md for tech stack, architecture, and file structure
   - **IF EXISTS**: Read data-model.md for entities and relationships
   - **IF EXISTS**: Read contracts/ for API specifications and test requirements
   - **IF EXISTS**: Read research.md for technical decisions and constraints
   - **IF EXISTS**: Read .specify/memory/constitution.md for governance constraints
   - **IF EXISTS**: Read quickstart.md for integration scenarios

4. **Project Setup Verification**:
   - **REQUIRED**: Create/verify ignore files based on actual project setup:

   **Detection & Creation Logic**:
   - Check if the following command succeeds to determine if the repository is a git repo (create/verify .gitignore if so):

     ```sh
     git rev-parse --git-dir 2>/dev/null
     ```

   - Check if Dockerfile* exists or Docker in plan.md → create/verify .dockerignore
   - Check if .eslintrc* exists → create/verify .eslintignore
   - Check if eslint.config.* exists → ensure the config's `ignores` entries cover required patterns
   - Check if .prettierrc* exists → create/verify .prettierignore
   - Check if .npmrc or package.json exists → create/verify .npmignore (if publishing)
   - Check if terraform files (*.tf) exist → create/verify .terraformignore
   - Check if .helmignore needed (helm charts present) → create/verify .helmignore

   **If ignore file already exists**: Verify it contains essential patterns, append missing critical patterns only
   **If ignore file missing**: Create with full pattern set for detected technology

   **Common Patterns by Technology** (from plan.md tech stack):
   - **Node.js/JavaScript/TypeScript**: `node_modules/`, `dist/`, `build/`, `*.log`, `.env*`
   - **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `dist/`, `*.egg-info/`
   - **Java**: `target/`, `*.class`, `*.jar`, `.gradle/`, `build/`
   - **C#/.NET**: `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`
   - **Go**: `*.exe`, `*.test`, `vendor/`, `*.out`
   - **Ruby**: `.bundle/`, `log/`, `tmp/`, `*.gem`, `vendor/bundle/`
   - **PHP**: `vendor/`, `*.log`, `*.cache`, `*.env`
   - **Rust**: `target/`, `debug/`, `release/`, `*.rs.bk`, `*.rlib`, `*.prof*`, `.idea/`, `*.log`, `.env*`
   - **Kotlin**: `build/`, `out/`, `.gradle/`, `.idea/`, `*.class`, `*.jar`, `*.iml`, `*.log`, `.env*`
   - **C++**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.so`, `*.a`, `*.exe`, `*.dll`, `.idea/`, `*.log`, `.env*`
   - **C**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.a`, `*.so`, `*.exe`, `*.dll`, `autom4te.cache/`, `config.status`, `config.log`, `.idea/`, `*.log`, `.env*`
   - **Swift**: `.build/`, `DerivedData/`, `*.swiftpm/`, `Packages/`
   - **R**: `.Rproj.user/`, `.Rhistory`, `.RData`, `.Ruserdata`, `*.Rproj`, `packrat/`, `renv/`
   - **Universal**: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/`

   **Tool-Specific Patterns**:
   - **Docker**: `node_modules/`, `.git/`, `Dockerfile*`, `.dockerignore`, `*.log*`, `.env*`, `coverage/`
   - **ESLint**: `node_modules/`, `dist/`, `build/`, `coverage/`, `*.min.js`
   - **Prettier**: `node_modules/`, `dist/`, `build/`, `coverage/`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - **Terraform**: `.terraform/`, `*.tfstate*`, `*.tfvars`, `.terraform.lock.hcl`
   - **Kubernetes/k8s**: `*.secret.yaml`, `secrets/`, `.kube/`, `kubeconfig*`, `*.key`, `*.crt`

5. Parse tasks.md structure and extract:
   - **Task phases** (as generated by `/feature-tasks`): Setup, Foundational (blocking prerequisites), one phase per user story (P1, P2, P3... in priority order), Polish & Cross-Cutting Concerns, and Final Verification (E2E) — always the last phase
   - **Task dependencies**: Sequential vs parallel execution rules (Foundational blocks all user stories; user story phases are independent of each other unless stated)
   - **Task details**: ID, description, file paths, parallel markers [P], story labels [US1], [US2], ...
   - **Execution flow**: Order and dependency requirements from the Dependencies & Execution Order section

6. Execute implementation by delegating to Sonnet subagents (see Execution Strategy):
   - **Phase-by-phase execution**: Complete and validate each phase before the next
   - **Dispatch per task/batch**: Spawn Sonnet implementer subagents; do not implement directly
   - **Respect dependencies**: Sequential tasks dispatched in order; `[P]` non-conflicting tasks dispatched concurrently as multiple subagents
   - **File-based coordination**: Tasks affecting the same files run sequentially (never in the same parallel batch)
   - **Story-by-story delivery**: Complete Setup, then Foundational (blocks everything), then user story phases in priority order (P1 first = MVP); validate each story's independent test criteria at its checkpoint before moving on
   - **Tests before code (when present)**: If a story phase includes test tasks, dispatch them before that story's implementation tasks and confirm they fail first
   - **Validation checkpoints**: Opus reviews each subagent's output before proceeding

7. Implementation execution rules (mirrors the phase structure `/feature-tasks` generates):
   - **Setup first (Phase 1)**: Initialize project structure, dependencies, configuration
   - **Foundational next (Phase 2)**: Blocking prerequisites (schema/migrations, auth framework, routing, base models, error handling) — MUST be complete before any user story work begins
   - **User story phases (Phase 3+)**: Implement each story as an independently testable increment, in priority order (P1 → P2 → P3). Within a story: tests (if requested) → models → services → endpoints/UI → integration
   - **Polish**: Cross-cutting concerns — cleanup, performance, docs, additional unit tests (if requested)
   - **Final Verification (ALWAYS the last phase)**: Execute the E2E verification tasks from tasks.md. For UI features this means running the Playwright screen tests (`e2e/*.spec.ts`) that cover each user story's primary acceptance scenario against the running app, then running the full suite and confirming all pass. For non-UI projects, run the equivalent end-to-end execution check. Do NOT report completion while any verification task fails

8. Progress tracking and error handling:
   - Report progress after each completed task
   - Halt execution if any non-parallel task fails
   - For parallel tasks [P], continue with successful tasks, report failed ones
   - Provide clear error messages with context for debugging
   - Suggest next steps if implementation cannot proceed
   - **IMPORTANT** For completed tasks, make sure to mark the task off as [X] in the tasks file.
   - **Opus review gate**: Mark a task `[X]` only after Opus has reviewed the subagent's output against acceptance criteria; on failure, send feedback and re-dispatch (Opus fixes directly after 2 failed attempts)

9. Completion validation:
   - Verify all required tasks are completed
   - Check that implemented features match the original specification
   - **Spec reconciliation gate (spec-driven development)** — the spec stays the
     source of truth:
     - For every entry in the deviation log, amend `spec.md` (and `plan.md`,
       `data-model.md`, `contracts/` where affected) in FEATURE_DIR so the
       documents describe the behavior actually accepted — BEFORE reporting
       completion or updating the backlog.
     - If an accepted deviation changes project-level design described under
       `docs/` (e.g., `docs/01_Project_Design/05_Feature_List.md`, the relevant
       files under `docs/02_Detailed_Design/**`, interface definitions), update
       those sections too, keeping IDs (FNC/SCR/IF/BAT) and traceability intact.
     - Never leave the code as the only record of a change: either amend the
       documents (accepted deviation) or fix the code back to the spec
       (rejected deviation).
     - If the deviation log is empty, state so explicitly in the completion report.
   - Validate that tests pass and coverage meets requirements
   - Confirm the Final Verification phase passed: all Playwright E2E screen tests (or the non-UI equivalent end-to-end check) ran against the real app and succeeded
   - Confirm the implementation follows the technical plan
   - Opus performs the final cross-task consistency check before reporting completion
   - If `specs/backlog.md` exists and this feature has a row there, mark the unit's **Implement** column done (only after all tasks are completed and marked `[X]`)

Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/feature-tasks` first to regenerate the task list.

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_implement`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_implement` key.
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue to the Completion Report.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Mandatory hook** (`optional: false`) — **You MUST emit `EXECUTE_COMMAND:` for each mandatory hook**:
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```

## Completion Report

Report final status with summary of completed work, including the deviation log
(or an explicit "no deviations") and any spec/docs amendments made by the
reconciliation gate.

## Done When

- [ ] All tasks in tasks.md completed and marked `[X]`, phase by phase (Setup → Foundational → User Stories in priority order → Polish → Final Verification)
- [ ] Each task was implemented by a Sonnet subagent and reviewed/accepted by Opus (or fixed directly after repeated subagent failure)
- [ ] Final Verification phase executed and passing: Playwright E2E screen tests for each user story's primary acceptance scenario (or the non-UI equivalent end-to-end check)
- [ ] Implementation validated against specification, plan, and test coverage
- [ ] Deviation reconciliation passed: every accepted deviation is reflected in `spec.md` (and plan.md / data-model.md / contracts/ where affected), and `docs/` design files updated when project-level design was impacted — or the deviation log is empty and reported as such
- [ ] Backlog updated: the unit's **Implement** column marked done in `specs/backlog.md` (if the backlog exists and has a row for this feature)
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with summary of completed work
