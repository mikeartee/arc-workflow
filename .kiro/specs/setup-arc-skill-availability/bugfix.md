# Bugfix Requirements Document

## Introduction

The `setup-arc` skill is the first-run configuration skill for the Arc engineering workflow. It is meant to be available in every project so the workflow's Phase 0 ("Repo setup") and the `arc-workflow` steering file's pre-flight skill-reference check can resolve and invoke it. In practice, `setup-arc` is only reliably present inside the `arc-workflow` source repo itself, while the comparable skill from the published `zsl` plugin — `setup-zsl-superpowers` (the user calls this "zsl-setup") — is globally available in every project because it ships through the plugin marketplace.

The user's symptom: "in other projects, set-arc isn't set up as a skill, and zsl-setup is." When working in any project other than the `arc-workflow` repo, the Arc workflow cannot find `setup-arc`, Phase 0 cannot run it, and the steering pre-flight check reports it as an unresolved skill reference.

Root cause context (for analysis only; the fix is decided in design):

- `setup-zsl-superpowers` (working reference) is registered in the `zsl` plugin manifest (`zsl-skills/.claude-plugin/plugin.json`) and the marketplace (`marketplace.json`, plugin `zsl` v0.10.0). Because it ships through the marketplace, it is globally available everywhere.
- `setup-arc` (broken) is defined only locally at `arc-workflow/.kiro/skills/setup-arc/SKILL.md` and is not registered in any plugin manifest. Its only path to other projects is the manual, `userTriggered` hook `arc-workflow/.kiro/hooks/sync-skills-to-global.json`, which copies `.kiro/skills/*` and the steering file into `~/.kiro`. If that hook has not been triggered on a machine (or was last triggered before `setup-arc` existed), other projects never see the skill.
- A secondary defect from an incomplete rename: `setup-arc/SKILL.md` still carries the internal H1 heading `# Setup ZSL Superpowers` instead of Arc branding.

Bug condition (informal): the bug occurs for any workspace that is **not** the `arc-workflow` source repo when `setup-arc` has not been synced into that environment's global skill set. The non-buggy case to preserve is the `arc-workflow` repo itself (where the local skill always resolves) and the unrelated, working distribution of the `zsl` plugin skills.

Reproduction:

1. Open a project that is not the `arc-workflow` source repo on a machine where the global sync hook has not been run (or was run before `setup-arc` existed).
2. Start the Arc workflow via the `arc-workflow` steering file (or otherwise reference the `setup-arc` skill).
3. Observe that `setup-arc` cannot be resolved, while `setup-zsl-superpowers` (zsl-setup) resolves normally.

The fix must make `setup-arc` reliably available in other projects the way `setup-zsl-superpowers` is, while preserving the existing manual sync hook behavior and the unrelated `zsl` plugin distribution.

## Bug Analysis

### Current Behavior (Defect)

What currently happens when the bug is triggered (a project other than the `arc-workflow` source repo, where `setup-arc` has not been synced into the global skill set):

1.1 WHEN a user works in a project other than the `arc-workflow` source repo AND the manual `sync-skills-to-global` hook has not been triggered on that machine THEN the system does not make the `setup-arc` skill available or discoverable in that project.

1.2 WHEN the `arc-workflow` steering file's Phase 0 attempts to invoke the `setup-arc` skill in such a project THEN the system cannot resolve `setup-arc` and Phase 0 cannot run setup.

1.3 WHEN the steering "Pre-flight: Unknown skill reference check" runs in such a project THEN the system reports `setup-arc` as an unresolved skill reference and surfaces a warning.

1.4 WHEN the global sync hook was last triggered before `setup-arc` existed THEN the system leaves `setup-arc` missing from `~/.kiro/skills` and other projects still cannot see it.

1.5 WHEN `setup-arc/SKILL.md` is read THEN the system shows an internal H1 heading `# Setup ZSL Superpowers` that does not match the renamed `setup-arc` skill.

### Expected Behavior (Correct)

What should happen instead, for the same conditions above:

2.1 WHEN a user works in any project other than the `arc-workflow` source repo THEN the system SHALL make `setup-arc` available and discoverable in the same way `setup-zsl-superpowers` is, without requiring a manual per-machine sync step.

2.2 WHEN the `arc-workflow` steering file's Phase 0 invokes the `setup-arc` skill in such a project THEN the system SHALL resolve and run the `setup-arc` skill.

2.3 WHEN the steering "Pre-flight: Unknown skill reference check" runs in such a project THEN the system SHALL resolve `setup-arc` successfully and emit no warning for it.

2.4 WHEN the distribution mechanism delivers Arc skills THEN the system SHALL deliver the current `setup-arc` skill to other projects without depending on whether a manual hook was previously triggered.

2.5 WHEN `setup-arc/SKILL.md` is read THEN the system SHALL show an internal H1 heading consistent with the `setup-arc` / Arc branding.

### Unchanged Behavior (Regression Prevention)

Existing behavior that must be preserved for inputs that do not trigger the bug:

3.1 WHEN a user works in the `arc-workflow` source repo itself THEN the system SHALL CONTINUE TO make `setup-arc` available via the local `.kiro/skills/setup-arc` directory as it does today.

3.2 WHEN the manual `sync-skills-to-global` hook is triggered THEN the system SHALL CONTINUE TO copy workspace skills and the `arc-workflow` steering file into `~/.kiro` as it does today, preserving the existing manual escape hatch.

3.3 WHEN the `zsl` plugin and its marketplace distribute `setup-zsl-superpowers` and the other engineering skills THEN the system SHALL CONTINUE TO make those skills globally available, unchanged.

3.4 WHEN other Arc skills already present in the global skill set (for example `tdd`, `triage`, `diagnose`) are referenced from another project THEN the system SHALL CONTINUE TO resolve them as before.

3.5 WHEN the `setup-arc` skill's frontmatter `name` and `description` are read THEN the system SHALL CONTINUE TO expose the same skill name (`setup-arc`) and description, with only the mismatched internal heading changing.

3.6 WHEN the `setup-arc` skill runs THEN the system SHALL CONTINUE TO perform its existing scaffolding behavior for issue tracker, triage labels, domain docs, ship style, and the optional project board.
