# Implementation Plan: Arc Kiro Workflow Personalization

## ⚠️ MANDATORY - READ BEFORE EVERY TASK ⚠️

**YOU MUST FOLLOW THESE RULES FOR EVERY TASK:**

1. **Shell Commands**: Use `controlPwshProcess` ONLY. NEVER use `executePwsh`.
2. **Gap Analysis**: Perform TWO gap analysis passes BEFORE marking any task complete.
3. **Show Your Work**: Gap analysis must be visible in your response.

If you skip any of these, you have violated the protocol.

---

## Overview

This plan converts the partially-converted Arc Skills repo into a fully personalized Kiro workflow.
Every task is a file-authoring or file-editing action — there is no compiled code, no build step, and no runtime.
Tasks are ordered so each one builds on the previous: audit first, then infrastructure, then per-skill customization, then steering, then documentation.

## Development Principles

**IMPORTANT**: Follow these principles strictly during implementation:

1. **Build ugly and working before making it clean**
   - Get the content right first; polish prose later
   - Don't over-engineer markdown structure

2. **If something isn't specified, ask — don't invent**
   - No assumptions about preferred label strings, question lists, or patterns
   - No "improvements" beyond what requirements and design specify

3. **Build exactly what's specified. Nothing more.**
   - No extra bundled resource files beyond those listed
   - No extra sections in skill files

4. **Stop and ask if stuck for 10+ minutes**
   - Ambiguous requirements take priority over guessing

5. **Property tests are not applicable here**
   - This is a markdown-authoring system with no compiled code
   - No property-based test tasks are included

## Non-Requirements (What NOT to Build)

❌ Any compiled code, scripts, or runtime validation tooling
❌ Automated CI/CD pipelines or GitHub Actions
❌ New skills beyond those already in `.kiro/skills/`
❌ Changes to skills not listed in requirements (only tdd, triage, grill-with-docs, setup-arc)
❌ A `docs/agents/` directory in this repo (that is per-repo config, not part of this spec)
❌ Deployment or publishing steps

**System Characteristics:**

✅ Markdown-only skill files and bundled resource files
✅ One steering file update
✅ One sync hook update
✅ One README.md at repo root
✅ All changes take effect on next agent invocation — no restart needed

---

## Tasks

- [x] 1. Run the skill audit and record keep/modify/drop decisions
  - Read every directory under `.kiro/skills/` and collect `name`, `description`, and body summary from each `SKILL.md`
  - For each skill, check whether a matching directory exists under `skills/` (original source); if `skills/` is absent, mark diff as "no source available"
  - Compare front matter and body against the source; classify each as: front-matter-changed / body-changed / unchanged / no-source
  - Check `arc-workflow.md` phase bodies to determine which skills are steering-file-referenced
  - Output a markdown table to the conversation: skill name | description | status (keep/modify/drop) | steering-file-referenced | diff-from-source
  - Confirm the table with the user before proceeding to Task 2
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 2. Smoke-test hot-reload and document the platform guarantee
  - Edit one skill's `SKILL.md` (add a trailing comment), invoke the skill, confirm the change is picked up without an IDE restart, then revert the edit
  - Add a one-line note to `.kiro/skills/setup-arc/SKILL.md` (or a shared note file) confirming hot-reload works as expected
  - _Requirements: 2.1_

- [x] 3. Update the sync hook to remove `git pull`
  - Edit `.kiro/hooks/sync-skills-to-global.json`
  - Change the `command` value from `"git pull && Copy-Item -Recurse -Force .kiro/skills/* $HOME/.kiro/skills/"` to `"Copy-Item -Recurse -Force .kiro/skills/* $HOME/.kiro/skills/"`
  - This makes the hook safe for customized repos that have diverged from Arc upstream
  - _Requirements: 9.4_

- [x] 4. Create `defaults.md` in the setup skill
  - Create `.kiro/skills/setup-arc/defaults.md`
  - Use the format specified in the design: `## Issue tracker`, `## Triage labels`, `## Domain docs`, `## Ship style`, `## Project board` sections
  - Pre-fill with the user's preferred defaults (confirm with user before writing if not already known)
  - _Requirements: 4.1_

- [x] 5. Customize the setup skill seed templates
  - [x] 5.1 Edit `.kiro/skills/setup-arc/issue-tracker-github.md` to match the user's preferred GitHub issue tracker format
    - _Requirements: 4.3_
  - [x] 5.2 Edit `.kiro/skills/setup-arc/triage-labels.md` to match the user's preferred label strings
    - _Requirements: 4.3_
  - [x] 5.3 Edit `.kiro/skills/setup-arc/ship-style-pr.md` to match the user's preferred PR workflow description
    - _Requirements: 4.3_
  - [x] 5.4 Edit `.kiro/skills/setup-arc/domain.md` to match the user's preferred domain doc layout description
    - _Requirements: 4.3_
  - [x] 5.5 Review `.kiro/skills/setup-arc/issue-tracker-gitlab.md` and `.kiro/skills/setup-arc/issue-tracker-local.md` — edit if the user has preferences for these trackers, or leave as-is if GitLab/local markdown are not used
    - _Requirements: 4.3_
  - [x] 5.6 Review `.kiro/skills/setup-arc/project-board.md` — edit to match the user's preferred project board config format, or leave as-is if project board sync is not used
    - _Requirements: 4.3_

- [x] 6. Update the setup skill SKILL.md for partial re-run UX and freeform issue tracker
  - Edit `.kiro/skills/setup-arc/SKILL.md`
  - Add a "Partial re-run" section to the Process that presents the numbered checklist UI when `docs/agents/` already exists (as specified in the design's Error Handling section)
  - Ensure the checklist asks the user to select which sections to update and re-runs only those
  - Add explicit handling for the "Other" issue tracker option in Section A: when the user selects "Other", prompt for a one-paragraph prose description and write it verbatim to `docs/agents/issue-tracker.md` — no structured parsing
  - _Requirements: 4.2, 4.4_

- [x] 7. Checkpoint — review setup skill changes
  - Ensure all setup skill files are consistent: `defaults.md` format matches design spec, seed templates are edited, SKILL.md partial re-run section is present
  - Ask the user if questions arise before continuing.

- [x] 8. Create `questions.md` in the grill-with-docs skill
  - Create `.kiro/skills/grill-with-docs/questions.md`
  - Use the format from the design: `# Domain Questions` heading followed by a bullet list of domain-specific questions
  - Populate with the user's preferred standing questions (confirm with user if not already known)
  - _Requirements: 5.1_

- [x] 9. Create `config.md` in the grill-with-docs skill
  - Create `.kiro/skills/grill-with-docs/config.md`
  - Use the format from the design: `# Grill Config` heading with `max-questions: N`
  - Set the user's preferred max-questions value (confirm with user if not already known)
  - _Requirements: 5.3_

- [x] 10. Update grill-with-docs SKILL.md for proactive CONTEXT.md scan and inline updates
  - Edit `.kiro/skills/grill-with-docs/SKILL.md`
  - Add a "Session start" step before the first question: read `CONTEXT.md`, scan the user's opening message for conflicting terms, surface any conflicts immediately
  - Add an explicit instruction that `CONTEXT.md` must be updated in the same response turn where a term is resolved — never batched
  - Add a reference to `[questions.md](./questions.md)` and `[config.md](./config.md)` in the supporting-info section
  - [x] 10.1 Add ADR offer timing instruction: ADR offers must be made inline, immediately after the decision is resolved and before moving to the next question — never batched to the end of the session
    - _Requirements: 5.5_
  - _Requirements: 5.2, 5.4_

- [x] 11. Create `patterns.md` in the tdd skill
  - Create `.kiro/skills/tdd/patterns.md`
  - Use the format from the design: `# Preferred Test Patterns` heading with a numbered list of patterns in priority order
  - Populate with the user's preferred patterns (round-trip, invariant, metamorphic, idempotent, or others — confirm with user if not already known)
  - _Requirements: 6.3_

- [x] 12. Update tdd SKILL.md for vertical slicing enforcement, `--no-ship` parsing, and sub-issue definition
  - Edit `.kiro/skills/tdd/SKILL.md`
  - [x] 12.1 Strengthen the vertical slicing enforcement at step 2: add an explicit check that the agent has not written more than one test without a passing implementation; if detected, stop and return to last green state
    - _Requirements: 6.1_
  - [x] 12.2 Add natural language `--no-ship` parsing: document that the agent parses `--no-ship` or `no-ship` from the invocation message string, not just as a literal CLI flag
    - _Requirements: 6.4_
  - [x] 12.3 Add a reference to `[patterns.md](./patterns.md)` in the Planning step so the agent reads it before suggesting tests
    - _Requirements: 6.3_
  - [x] 12.4 Update the container issue refusal pre-flight check with the precise definition: a "sub-issue" is a child issue linked via the issue tracker's native parent-child relationship (not merely mentioned in the body); a sub-issue is "open" when its `state` is `open`; only native open sub-issues trigger the refusal
    - _Requirements: 6.2_
  - [x] 12.5 Add invocation-time validation instruction: when the agent loads this skill, it checks that all relative links in the SKILL.md body resolve to existing files in the skill directory; if any link is broken, surface a `missing-resource` error before executing the skill instructions
    - _Requirements: 2.3_

- [x] 13. Checkpoint — review tdd and grill skill changes
  - Confirm `patterns.md`, `questions.md`, and `config.md` all exist and match the design format
  - Confirm SKILL.md edits for tdd and grill-with-docs are present and internally consistent
  - Ask the user if questions arise before continuing.

- [x] 14. Update triage SKILL.md for hard error on missing AGENT-BRIEF.md and label/board clarifications
  - Edit `.kiro/skills/triage/SKILL.md`
  - [x] 14.1 Add a hard error at the start of step 5 (Apply the outcome): if `AGENT-BRIEF.md` is absent from the skill directory when attempting to post an agent brief, surface a `missing-resource` error and halt — do not post a brief using any fallback
    - _Requirements: 7.2, 7.3_
  - [x] 14.2 Clarify in the "Quick state override" section that the label is applied regardless of whether the user wants an agent brief — the label transition is mandatory, the brief is optional
    - _Requirements: 7.4_
  - [x] 14.3 Clarify in step 6 (Sync the project board) that if the issue is not found on the configured project, the skill logs "issue not in configured project; skipping Status update" and continues — the label change is not rolled back
    - _Requirements: 7.5_
  - [x] 14.4 Add explicit instruction to read triage label strings from `docs/agents/triage-labels.md` and never use the canonical default strings (`needs-triage`, `ready-for-agent`, etc.) when that file exists; if `docs/agents/triage-labels.md` is absent, halt and instruct the user to run `setup-arc`
    - _Requirements: 7.1_

- [x] 15. Update the steering file
  - Edit `.kiro/steering/arc-workflow.md`
  - [x] 15.1 Update the `## Rules` section: add the README reminder rule — "WHEN you edit this steering file (add, remove, or reorder phases), remind the user to update README.md to keep it in sync with the current phase list"
    - _Requirements: 10.2, 8.4_
  - [x] 15.2 Add a global constraint rule: "Never skip a phase unless the user explicitly asks to"
    - _Requirements: 8.4_
  - [x] 15.3 Add documentation of optional phase syntax in a comment or note near the phase headings: phases marked `(optional)` in their heading are skipped during a default run and execute only when the user explicitly requests them by name or number
    - _Requirements: 8.3_
  - [x] 15.4 Verify the inclusion mode table is documented: add a brief comment block at the top of the file (below front matter) explaining the three `inclusion` values (`manual`, `always`, `fileMatch`) and their behavior
    - _Requirements: 3.1, 3.2_
  - [x] 15.5 Add an unknown-skill-ref warning instruction to the `## Rules` section: at the start of each session, before any phase executes, check that all skill names referenced in phase bodies exist in the combined skill set (`.kiro/skills/` + `~/.kiro/skills/`); surface a warning for any unresolved reference and present all warnings together as a pre-flight report before proceeding
    - _Requirements: 8.2_

- [x] 16. Checkpoint — review steering file changes
  - Confirm all four steering file sub-tasks are present and the file is valid markdown with correct front matter
  - Ask the user if questions arise before continuing.

- [x] 17. Create `README.md` at the repo root
  - Create `README.md` following the template from design Property 18
  - [x] 17.1 Write the `# Personal Workflow` title and `## Quick Start` section with the minimum command sequence (6 steps as specified in the design)
    - _Requirements: 10.1, 10.3_
  - [x] 17.2 Write the `## Phases` section with one entry per phase in `arc-workflow.md` (Phase 0 through Phase 6), each including: skill name, input description, output description
    - _Requirements: 10.1_
  - [x] 17.3 Write the `## Customization Guide` section with the four subsections from the design template: Adding a phase, Removing a phase, Modifying a skill, Adding a bundled resource to a skill
    - _Requirements: 10.4_
  - [x] 17.4 Add a note in the Customization Guide about global vs local skills: editing `.kiro/skills/` affects only this workspace; run the sync hook to propagate to `~/.kiro/skills/`; removing from `.kiro/skills/` does not remove from `~/.kiro/skills/`
    - _Requirements: 9.4_

- [x] 18. Final checkpoint — run the audit checklist from the design
  - Verify all 21 skills in `.kiro/skills/` have a keep/modify/drop decision recorded (from Task 1)
  - Verify all skill references in `arc-workflow.md` resolve to a known skill `name`
  - Verify all relative links in all edited `SKILL.md` files resolve to existing files in their skill directory
  - Verify `README.md` covers all phases in `arc-workflow.md`
  - Verify the sync hook no longer contains `git pull`
  - Ensure all tests pass, ask the user if questions arise.

