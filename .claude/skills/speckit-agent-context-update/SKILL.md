---
name: speckit-agent-context-update
description: Refresh the managed Spec Kit section in the coding agent context file
compatibility: Works standalone; uses .specify/ configuration and scripts when present
metadata:
  author: github-spec-kit
  source: agent-context:commands/speckit.agent-context.update.md
user-invocable: true
disable-model-invocation: false
---

# Update Coding Agent Context

Refresh the managed Spec Kit section inside the active coding agent's context/instruction file (e.g. `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`) so it points at the current feature's implementation plan.

## User Input

```text
$ARGUMENTS
```

If `$ARGUMENTS` contains a path, treat it as `plan_path`.

## Resolution

Resolve the following, in order, before touching any file:

1. **Context file**:
   1. If `.specify/extensions/agent-context/agent-context-config.yml` exists, read its `context_file` value and use it. If the value is empty, report "nothing to do" and stop successfully.
   2. Otherwise use the agent default for this session: `CLAUDE.md` at the project root. If the file does not exist, it will be created in the Execution step.
2. **Markers**: `context_markers.start` / `context_markers.end` from the same config when present; otherwise the defaults `<!-- SPECKIT START -->` and `<!-- SPECKIT END -->`.
3. **Plan path** (first match wins):
   1. Explicit `plan_path` from `$ARGUMENTS`.
   2. `.specify/feature.json` → `feature_directory` + `/plan.md`, if that file exists.
   3. The most recently modified `specs/*/plan.md`.

   If none is found, report "no plan found — run `/speckit-plan` first" and stop successfully (do not create a plan).

## Execution

1. **Preferred fast path**: if the agent-context extension script exists, run it and skip step 2:
   - Bash: `.specify/extensions/agent-context/scripts/bash/update-agent-context.sh [plan_path]`
   - PowerShell: `.specify/extensions/agent-context/scripts/powershell/update-agent-context.ps1 [plan_path]`
2. **Otherwise perform the update directly**:
   - Build the managed block (using the resolved markers in place of the defaults when the config overrides them):

     ```markdown
     <!-- SPECKIT START -->
     ## Active Spec Kit Feature

     - Implementation plan: `specs/<feature>/plan.md`
     <!-- SPECKIT END -->
     ```

   - Use the **project-relative** path for the plan reference (e.g. `specs/003-user-auth/plan.md`), not an absolute path.
   - If the context file already contains both markers, replace the content between them (keep the markers themselves).
   - If the file exists but contains no markers, append the block to the end of the file, separated by one blank line.
   - If the file does not exist, create it containing only the block.
   - Do not modify anything outside the managed block.

## Completion Report

Report to the user:

- The context file that was updated (or created).
- The plan path written into the managed block.
- Whether the block was replaced, appended, or the file was newly created — or why nothing was done (empty `context_file`, or no plan found).

## Done When

- [ ] Context file and markers resolved (config first, agent default otherwise)
- [ ] Managed block points at the resolved plan path (replaced/appended/created), or a "nothing to do" case was reported
- [ ] Completion reported with context file path and plan path
