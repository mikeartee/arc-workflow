# Implementation Plan: Hands-Off Mode

## ⚠️ MANDATORY - READ BEFORE EVERY TASK ⚠️

**YOU MUST FOLLOW THESE RULES FOR EVERY TASK:**

1. **Shell Commands**: Use `controlPwshProcess` ONLY. NEVER use `executePwsh`.
2. **Gap Analysis**: Perform TWO gap analysis passes BEFORE marking any task complete.
3. **Show Your Work**: Gap analysis must be visible in your response.

If you skip any of these, you have violated the protocol.

---

## Overview

Hands-off mode is markdown-driven orchestration. There is no compiled code, no
daemon, and no build step. "The orchestrator" is a new Kiro skill
(`.kiro/skills/arc-handsoff/SKILL.md`) plus a toggle-aware addition to the
always-on `arc-workflow.md` steering. The persistent toggle is a repo-local,
gitignored state file (`.arc-hands-off.json`). The skill reads `Repository_State`
through the `gh` CLI, re-derives the current phase on every loop iteration, and
chains the existing phase skills in-session until a stop condition fires, then
posts a single `Hands_Off_Report` to GitHub.

The bulk of the work is authoring one skill file incrementally, then wiring the
steering hook, the gitignore entry, the skill-sync exclusion, and the README
phase list around it.

## Development Principles

**IMPORTANT**: Follow these principles strictly during implementation:

1. **Build ugly and working before making it clean** — get the skill instructions correct first, tighten prose later.
2. **If something isn't specified, ask - don't invent** — no extra dispositions, labels, or phases beyond the design.
3. **Build exactly what's specified. Nothing more.** — no new verifier, no merge capability, no background process.
4. **Stop and ask if stuck for 10+ minutes** — confirm board option IDs and label strings against `docs/agents/` rather than guessing.
5. **Scenario tests are optional for MVP** — sub-tasks marked `*` can be skipped.

## Non-Requirements (What NOT to Build)

❌ Autonomous merge or any push-to-default-branch capability (Requirement 7).
❌ Kiro Web / cloud execution — local single session only (Requirement 4).
❌ Scheduling, cron, or any daemon / background process (ADR-002).
❌ Headless operation without an open, user-started session.
❌ Grill automation — the Grill phase stays human-only (Requirement 3.1).
❌ A new coverage / mutation / independent verifier before the integration PR (ADR-005).
❌ A private progress counter — phase is always re-derived from `Repository_State` (ADR-004).

**System Characteristics:**

✅ A persistent on/off toggle backed by a gitignored local state file.
✅ A `arc-handsoff` skill that detects phase from GitHub state and chains phase skills in-session.
✅ Non-blocking park semantics: park-and-continue for HITL slices, park-and-wait for failures.
✅ A single `Hands_Off_Report` (DID / PARKED / READ & MERGE) posted to the PRD issue.
✅ The existing merge-stop, preserved identically in both modes.

## Context7 MCP Usage

This feature uses **no external code libraries** — it is markdown skill content
plus the `gh` CLI. Context7 is not required.

**Reference instead:**

- `docs/agents/project-board.md` — project node ID, `Status` field ID, option IDs for GraphQL reads.
- `docs/agents/triage-labels.md` — canonical triage label strings.
- `docs/agents/ship-style.md` — the merge-stop / PR conventions reused by Build.
- `docs/agents/issue-tracker.md` — `gh` CLI usage for issues, comments, labels.

Confirm board option IDs and label strings against these files before writing
any `gh api graphql` snippet — do not hardcode guessed IDs.

---

## Tasks

- [x] 1. Establish the toggle foundation
  - [x] 1.1 Add the state file to `.gitignore`
    - Add `.arc-hands-off.json` to the repo-root `.gitignore` (create the file if absent)
    - The toggle is machine-local session state; it must never be committed
    - _Requirements: 1.2, 1.4_
  - [x] 1.2 Scaffold the `arc-handsoff` skill and the `/hands-off` command interface
    - Create `.kiro/skills/arc-handsoff/SKILL.md` with frontmatter and overview matching the existing skill convention (single `SKILL.md` per skill folder)
    - Document the toggle states: file present with `{"state": "on"}` = on; file absent or `{"state": "off"}` = off; absent is the default
    - Specify the `/hands-off` interface: no argument → write `{"state": "on"}` then enter the control loop; `/hands-off off` → write `{"state": "off"}` (or delete the file) then stop
    - Note the name is deliberately distinct from Kiro's tool-approval autonomy mode
    - _Requirements: 1.1, 1.2, 1.4, 1.5, 1.6_

- [x] 2. Phase detection from Repository_State
  - [x] 2.1 Add the Repository_State read model to the skill
    - Document the `gh` / `gh api graphql` reads: PRD (`tracking`) issue, its sub-issues and each triage label, open PR whose body contains `Closes #<prd>`, and the grill proxy (non-trivial `CONTEXT.md`)
    - Reference `docs/agents/project-board.md` for the project node ID and `Status` option IDs, and `docs/agents/triage-labels.md` for label strings
    - Treat a `gh` read failure as an ambiguous state (see task 3.2)
    - _Requirements: 2.1_
  - [x] 2.2 Add the state→phase decision table to the skill
    - Encode every row: grill-not-done → stop/park grill; grill done + no PRD → `to-prd`; PRD + no sub-issues → `to-issues`; untriaged sub-issues → `triage`; all triaged + no PR → `tdd-parallel`; open un-reviewed PR → `code-review`; reviewed clean → stop; no/contradictory match → stop/park `phase-detection`
    - State that the next action is re-derived from state each iteration, so completed phases are skipped (idempotent, self-correcting)
    - _Requirements: 2.1, 2.3_
  - [x] 2.3 Write decision-table scenario checks
    - Create `verification/decision-table-scenarios.md` walking each table row and each Error Handling row (ambiguous, no AFK slices, PR already exists, grill missing) against a concrete `Repository_State` fixture with its expected next action
    - Example/scenario based per the design Testing Strategy (no property tests apply)
    - _Requirements: 2.1, 2.3_

- [x] 3. Auto-advance control loop
  - [x] 3.1 Add the grill-first precondition gate to the skill
    - Run once, before the loop: if the grill proxy is absent, park `grill` as "requires the human" (park-and-wait), report, and return — never invoke grill
    - When the gate passes, begin auto-advancement at the PRD phase
    - _Requirements: 3.1, 3.2, 3.3_
  - [x] 3.2 Add the in-session auto-advance loop to the skill
    - On each iteration: read state, detect phase, stop on Review-complete, stop and park on ambiguous state, otherwise invoke the next phase skill in-session with no human prompt
    - Advance strictly in order PRD → Issues → Triage → Build → Review
    - Document that the loop runs in the single session that invoked `/hands-off`; when the session ends the loop ends (no background process, no resume)
    - The orchestrator never blocks on a question; any decision needing the absent human becomes a parked item it declines to make
    - _Requirements: 2.2, 2.3, 2.4, 4.1, 4.2, 4.3, 5.4_
  - [x] 3.3 Write toggle and control-loop scenario checks
    - Create `verification/toggle-and-loop-scenarios.md` verifying default-off with no state file, `/hands-off` writes on, `/hands-off off` writes off, state persists across invocations, and the state file is gitignored and not swept by the skill-sync hook
    - _Requirements: 1.2, 1.4, 1.5, 1.6, 4.2_

- [x] 4. Checkpoint - core orchestration
  - Ensure all scenario checks authored so far pass, ask the user if questions arise.

- [x] 5. Park semantics
  - [x] 5.1 Add park semantics to the skill
    - Define the `Parked_Item` shape (`kind`, `ref`, `reason`, `disposition`) and the two dispositions
    - Park-and-continue: record each skipped HITL (`ready-for-human`) slice with a one-line reason and keep building remaining AFK slices
    - Park-and-wait: on a genuine phase failure (middle phase errored, Build cannot bring an AFK slice to passing, or Review flags a blocker) record the item, stop auto-advancement, and never retry that phase in the same session
    - State the in-memory parked list is the authoritative source for the report; the `ready-for-human` label is the natural HITL park marker (invent no new label)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 6.1, 6.2, 6.3, 6.4_
  - [x] 5.2 Write park-list assembly scenario checks
    - Create `verification/park-list-scenarios.md` for a mixed run (some AFK merged, one HITL skipped, one phase failed) confirming each parked item is captured with the correct `kind`, `disposition`, and one-line reason
    - _Requirements: 5.3, 6.2, 6.3_

- [x] 6. Merge-stop preservation and the report
  - [x] 6.1 Document merge-stop preservation in the skill
    - State the orchestrator adds no merge or push capability: shipping is delegated entirely to `tdd-parallel` per `docs/agents/ship-style.md`, which opens the single integration PR with `Closes #<prd>` and stops
    - The orchestrator only reads PR state to advance to Review; it leaves the PR unmerged, never calls `git merge`, and never pushes to the default branch — identically whether the mode is on or off
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - [x] 6.2 Add Hands_Off_Report assembly, template, and posting to the skill
    - Produce one report whenever auto-advancement stops (Review complete, phase failure, grill gate, or ambiguous state)
    - Render DID (completed AFK slices + integration PR contents), PARKED (each HITL slice and each failed phase with a one-line reason), and READ & MERGE (the integration PR link); empty sections state "None"
    - Post as a comment on the PRD issue, falling back to the integration PR body if the PRD issue cannot be resolved
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_
  - [x] 6.3 Write report-rendering and merge-stop regression checks
    - Create `verification/report-and-merge-stop-scenarios.md` confirming the DID / PARKED / READ & MERGE sections render correctly and post to the PRD issue, and confirming the skill introduces no `git merge` or push-to-default capability and leaves the PR unmerged in both modes
    - _Requirements: 7.2, 7.3, 7.4, 8.2, 8.3, 8.4, 8.5_

- [x] 7. Checkpoint - park and report
  - Ensure all scenario checks pass, ask the user if questions arise.

- [x] 8. Wire hands-off mode into the workflow
  - [x] 8.1 Add the toggle-aware phase-gating hook to `arc-workflow.md`
    - Update `.kiro/steering/arc-workflow.md` so that when the mode is off the flow waits for the human between phases (today's behavior), and when on it hands control to the `arc-handsoff` orchestrator
    - Add `arc-handsoff` so it resolves in the pre-flight unknown-skill-reference check
    - _Requirements: 1.3, 2.2_
  - [x] 8.2 Verify the skill-sync hook excludes the state file
    - Inspect `.kiro/hooks/sync-skills-to-global*.json` and confirm it copies only `.kiro/skills/*` and `arc-workflow.md`, leaving the repo-root `.arc-hands-off.json` untouched; adjust the exclusion only if the state file would be swept
    - _Requirements: 1.2_
  - [x] 8.3 Update README.md phase list
    - Update `README.md` to reference hands-off mode and the `/hands-off` command, keeping it in sync with the steering phase list per the `arc-workflow.md` maintenance rule
    - _Requirements: 1.1_

- [x] 9. Final checkpoint - Ensure everything is wired
  - Confirm the skill, steering hook, gitignore entry, skill-sync exclusion, and README are consistent; ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP.
- This feature has no executable runtime, so verification is example/scenario based (guided walkthroughs against the `gh` CLI and fixture issues), not property-based — consistent with the design Testing Strategy, which intentionally omits a Correctness Properties section.
- Most tasks edit the single `arc-handsoff/SKILL.md`, so the dependency graph serializes them across waves to avoid write conflicts.
- Each task references granular requirements clauses for traceability.
- Checkpoints ensure incremental validation.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2"] },
    { "id": 3, "tasks": ["3.1", "2.3"] },
    { "id": 4, "tasks": ["3.2", "3.3"] },
    { "id": 5, "tasks": ["5.1"] },
    { "id": 6, "tasks": ["6.1", "5.2"] },
    { "id": 7, "tasks": ["6.2"] },
    { "id": 8, "tasks": ["8.1", "8.2", "8.3", "6.3"] }
  ]
}
```
