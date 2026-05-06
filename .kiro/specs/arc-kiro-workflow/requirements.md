# Requirements Document

## Introduction

The user wants to build a personalized spin on the Arc Skills workflow for Kiro IDE. The Arc Skills repo (originally built for Claude Code) has been cloned and partially converted to Kiro by placing skills in `.kiro/skills/` and a steering file in `.kiro/steering/arc-workflow.md`. The goal is to go further: customize the individual skills, the orchestrating workflow, and the steering file to match how the user personally works — rather than using the Arc defaults as-is.

This feature covers the full lifecycle of that customization: understanding the existing system, deciding what to keep or change, authoring the custom versions, and wiring them together into a coherent personal workflow.

## Glossary

- **Skill**: A markdown file (with YAML front matter) placed in `.kiro/skills/<name>/SKILL.md` that Kiro loads as a named agent behavior. Equivalent to a Claude Code slash command.
- **Steering file**: A markdown file in `.kiro/steering/` that Kiro injects into the agent's context. Can be `always`, `manual`, or `fileMatch` inclusion. The `arc-workflow.md` steering file orchestrates the end-to-end workflow.
- **Workflow**: The ordered sequence of skill invocations that takes a rough idea from alignment → PRD → issues → triage → build → review. Currently defined in `.kiro/steering/arc-workflow.md`.
- **Personal workflow**: The user's customized version of the Workflow — different phase order, different skills, different defaults, or different rules than the Arc originals.
- **Skill bundle**: The set of skills that together implement a complete Workflow. Currently the Arc bundle lives in `.kiro/skills/`.
- **Phase**: A named step in the Workflow (e.g. "Understand what you're building", "Write the PRD"). Each phase invokes one or more Skills.
- **Agent brief**: A structured comment posted to an issue by the `triage` skill that gives an AFK agent everything it needs to implement the slice without human context.
- **AFK slice**: An issue slice that is fully specified and can be implemented by an agent without human interaction.
- **HITL slice**: An issue slice that requires human judgment, design decisions, or external access.
- **Triage role**: A canonical state-machine label applied to an issue (e.g. `needs-triage`, `ready-for-agent`, `wontfix`).
- **Ship style**: How changes reach the default branch — either via pull request or direct push. Configured per-repo in `docs/agents/ship-style.md`.
- **CONTEXT.md**: A domain glossary file that captures the project's canonical terminology. Read by skills like `grill-with-docs`, `tdd`, and `improve-codebase-architecture`.
- **ADR**: Architecture Decision Record. A short document capturing a hard-to-reverse, surprising, or trade-off-driven decision.

## Requirements

### Requirement 1: Audit the Existing Skill Set

**User Story:** As a developer customizing the Arc workflow, I want to review all converted skills side-by-side with the originals, so that I can decide which to keep, modify, or drop before writing any custom versions.

#### Acceptance Criteria

1. THE Workflow_System SHALL provide a way to compare each skill in `.kiro/skills/` against its source in `skills/` to surface differences introduced during the Kiro conversion.
2. WHEN the user reviews the skill set, THE Workflow_System SHALL present each skill with its name, description, and a summary of what it does, so the user can make an informed keep/modify/drop decision.
3. THE Workflow_System SHALL identify which skills are referenced by the steering file and which are standalone, so the user knows the impact of removing or renaming a skill.

---

### Requirement 2: Customize Individual Skills

**User Story:** As a developer, I want to edit the content of individual skills to match my personal preferences, so that the agent behaves the way I want rather than following Arc defaults.

#### Acceptance Criteria

1. WHEN the user edits a skill file in `.kiro/skills/<name>/SKILL.md`, THE Skill_Loader SHALL pick up the updated content on the next invocation without requiring a restart.
2. THE Skill_System SHALL support adding new bundled resource files (e.g. `deep-modules.md`, `mocking.md`) alongside a `SKILL.md` so that skills can reference supporting documents via relative links.
3. WHEN a skill references a supporting document that does not exist, THE Skill_Loader SHALL surface a clear error rather than silently ignoring the missing file.
4. THE Skill_System SHALL allow the user to disable a skill by removing its directory from `.kiro/skills/`, without affecting other skills that do not depend on it.
5. WHERE the user wants a skill to be available globally across all repos, THE Skill_System SHALL support placing the skill in `~/.kiro/skills/` so it is loaded in every workspace.

---

### Requirement 3: Customize the Workflow Steering File

**User Story:** As a developer, I want to edit the orchestrating steering file to change the phase order, rules, and defaults, so that the workflow matches how I personally move from idea to shipped code.

#### Acceptance Criteria

1. THE Steering_File SHALL be editable as plain markdown so the user can reorder phases, add new phases, or remove phases without touching any code.
2. WHEN the user changes the `inclusion` front-matter field in `.kiro/steering/arc-workflow.md` from `manual` to `always`, THE Steering_Loader SHALL inject the workflow into every agent session automatically.
3. THE Steering_File SHALL reference skills by their `name` front-matter value so that renaming a skill directory requires only updating the steering file reference, not the skill itself.
4. WHEN the user adds a new phase to the Steering_File, THE Workflow_System SHALL execute that phase in the position it appears in the file, preserving the declared order.
5. IF the user removes a phase from the Steering_File, THEN THE Workflow_System SHALL skip that phase without erroring, provided no later phase declares a hard dependency on it.

---

### Requirement 4: Personalize the Setup Skill

**User Story:** As a developer, I want to customize the `setup-arc` skill to reflect my preferred defaults (issue tracker, ship style, label vocabulary), so that new repos are configured the way I work without re-answering the same questions every time.

#### Acceptance Criteria

1. THE Setup_Skill SHALL allow the user to hard-code default answers for any of the five setup sections (issue tracker, triage labels, domain docs, ship style, project board) so those sections are skipped or pre-filled during setup.
2. WHEN the user runs the Setup_Skill on a repo that already has `docs/agents/` populated, THE Setup_Skill SHALL detect the existing configuration and offer to update specific sections rather than re-running the full setup.
3. THE Setup_Skill SHALL write `docs/agents/` files using the user's customized templates rather than the seed templates, so the output matches the user's preferred format.
4. IF the user's preferred issue tracker is not GitHub, GitLab, or local markdown, THEN THE Setup_Skill SHALL accept a freeform prose description and record it in `docs/agents/issue-tracker.md` without requiring a code change to the skill.

---

### Requirement 5: Personalize the Grilling Skills

**User Story:** As a developer, I want to customize the `grill-me` and `grill-with-docs` skills to ask the questions I care about and skip the ones I don't, so that alignment sessions are faster and more relevant to my projects.

#### Acceptance Criteria

1. THE Grill_Skill SHALL allow the user to add a list of domain-specific questions or prompts that are always included in the grilling session for a given repo.
2. WHEN the user invokes `grill-with-docs`, THE Grill_Skill SHALL read `CONTEXT.md` and surface any terms that conflict with the user's current language before asking new questions.
3. THE Grill_Skill SHALL allow the user to configure the maximum number of questions per session so that grilling does not become exhausting for small changes.
4. WHEN a grilling session resolves a new term, THE Grill_Skill SHALL update `CONTEXT.md` immediately rather than batching updates to the end of the session.
5. THE Grill_Skill SHALL offer to create an ADR only when all three conditions are met: the decision is hard to reverse, surprising without context, and the result of a real trade-off.

---

### Requirement 6: Personalize the TDD Skill

**User Story:** As a developer, I want to customize the `tdd` skill to enforce my preferred testing patterns and red-green-refactor discipline, so that the agent writes tests the way I would write them.

#### Acceptance Criteria

1. THE TDD_Skill SHALL enforce vertical slicing (one test → one implementation → repeat) and refuse to write all tests before any implementation.
2. WHEN the user invokes `tdd` against a container issue (one with open sub-issues), THE TDD_Skill SHALL refuse and instruct the user to run `to-issues` first.
3. THE TDD_Skill SHALL allow the user to configure which test patterns are preferred (e.g. round-trip, invariant, metamorphic) via a bundled resource file so the agent prioritizes those patterns when suggesting tests.
4. WHEN the `--no-ship` flag is passed, THE TDD_Skill SHALL stop after the final refactor commit and report the branch name, last commit SHA, and a one-paragraph summary without pushing or opening a PR.
5. THE TDD_Skill SHALL read `docs/agents/ship-style.md` before shipping and follow the configured ship style exactly.
6. IF `docs/agents/ship-style.md` does not exist, THEN THE TDD_Skill SHALL halt and instruct the user to run the Setup_Skill before continuing.

---

### Requirement 7: Personalize the Triage Skill

**User Story:** As a developer, I want to customize the `triage` skill to use my label vocabulary and agent brief format, so that triaged issues are immediately actionable for my workflow.

#### Acceptance Criteria

1. THE Triage_Skill SHALL read triage label strings from `docs/agents/triage-labels.md` and use those strings when applying labels, never the canonical defaults.
2. WHEN the user moves an issue to `ready-for-agent`, THE Triage_Skill SHALL post an agent brief comment using the format defined in the bundled `AGENT-BRIEF.md` resource file.
3. THE Triage_Skill SHALL allow the user to customize the agent brief format by editing the bundled `AGENT-BRIEF.md` file without modifying the skill's core logic.
4. WHEN the user invokes triage with a quick override (e.g. "move #42 to ready-for-agent"), THE Triage_Skill SHALL apply the role directly without running a grilling session, but SHALL ask whether the user wants to write an agent brief.
5. IF `docs/agents/project-board.md` exists, THEN THE Triage_Skill SHALL sync the issue's project board Status after every label change, treating the label as the source of truth and the board sync as best-effort.

---

### Requirement 8: Add or Remove Phases from the Personal Workflow

**User Story:** As a developer, I want to add phases that don't exist in the Arc defaults (e.g. a "spike" phase before the PRD, or a "demo" phase after shipping), so that the workflow reflects my actual process.

#### Acceptance Criteria

1. THE Workflow_System SHALL allow the user to insert a new phase at any position in the Steering_File by adding a new `### Phase N` section with a description and skill invocation.
2. WHEN a new phase references a skill that does not exist in `.kiro/skills/`, THE Workflow_System SHALL surface a warning to the user rather than silently skipping the phase.
3. THE Workflow_System SHALL allow the user to mark a phase as optional by adding `(optional)` to the phase heading, so the agent skips it unless the user explicitly requests it.
4. THE Steering_File SHALL support a `## Rules` section where the user can declare global constraints that apply across all phases (e.g. "never skip Phase 1", "always confirm before publishing to the issue tracker").

---

### Requirement 9: Manage Global vs. Per-Repo Skills

**User Story:** As a developer working across multiple repos, I want to control which skills are global (available everywhere) and which are repo-specific, so that I don't pollute every workspace with skills that only make sense in one context.

#### Acceptance Criteria

1. THE Skill_System SHALL load skills from `~/.kiro/skills/` as global skills available in every workspace.
2. THE Skill_System SHALL load skills from `.kiro/skills/` as workspace-local skills that override global skills of the same name.
3. WHEN a workspace-local skill and a global skill share the same `name` front-matter value, THE Skill_Loader SHALL prefer the workspace-local version.
4. THE Skill_System SHALL allow the user to maintain a personal fork of the Arc skill bundle in `~/.kiro/skills/` so that customizations persist across all repos without needing to copy files into each workspace.

---

### Requirement 10: Document the Personal Workflow

**User Story:** As a developer, I want a single reference document that describes my personal workflow end-to-end, so that I (and any collaborator) can understand how to use it without reading every skill file.

#### Acceptance Criteria

1. THE Workflow_System SHALL produce a `README.md` (or equivalent) that lists every phase in the Personal_Workflow, the skill invoked at each phase, and the expected inputs and outputs.
2. WHEN the user updates the Steering_File, THE Workflow_System SHALL remind the user to update the reference document so it stays in sync.
3. THE Reference_Document SHALL include a "Quick start" section that shows the minimum commands needed to go from a blank repo to a triaged set of issues.
4. THE Reference_Document SHALL include a "Customization guide" section that explains how to add, remove, or modify skills and phases.
