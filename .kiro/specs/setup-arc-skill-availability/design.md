# Setup Arc Skill Availability Bugfix Design

## Overview

The `setup-arc` skill is the Phase 0 configuration skill for the Arc workflow. It is meant to be available in every project the way the published `zsl` plugin's `setup-zsl-superpowers` ("zsl-setup") is. Today it is only reliably present inside the `arc-workflow` source repo, because its single cross-project delivery path is a manual, `userTriggered` sync hook that copies `.kiro/skills/*` into `~/.kiro/skills/`. If that hook was never triggered on a machine — or was last triggered before `setup-arc` existed — every other project fails to resolve `setup-arc`, Phase 0 cannot run it, and the steering pre-flight "Unknown skill reference check" reports it as unresolved.

This design fixes the bug with a targeted, minimal change that mirrors the *effect* of the working `setup-zsl-superpowers` distribution (the skill is simply present everywhere and stays present), using Kiro's native global-skill mechanism (`~/.kiro/skills/`) rather than inventing a new packaging system. The fix has two parts:

1. **Distribution reliability** — remove the dependency on a remembered manual trigger so the current `setup-arc` lands in `~/.kiro/skills/` and stays refreshed.
2. **Branding heading** — correct the leftover `# Setup ZSL Superpowers` H1 in `setup-arc/SKILL.md` to Arc branding.

The fix must not disturb the `arc-workflow` repo's local resolution, the existing manual hook, the unrelated `zsl` plugin, or other Arc skills already present globally.

## Glossary

- **Bug_Condition (C)**: Referencing `setup-arc` from a workspace that is NOT the `arc-workflow` source repo when `setup-arc` is absent from that machine's global skill set — the reference fails to resolve.
- **Property (P)**: For an input satisfying C, the fixed system resolves `setup-arc`, Phase 0 can invoke it, and the steering pre-flight check emits no warning for it.
- **Preservation**: Behavior that must remain identical for inputs that do NOT satisfy C — local resolution inside `arc-workflow`, the manual sync hook, the `zsl` plugin distribution, other already-global Arc skills, and the `setup-arc` frontmatter.
- **Global skill set (G)**: The contents of `~/.kiro/skills/` — skills Kiro resolves in every workspace.
- **Local skill set**: The contents of a workspace's `.kiro/skills/` — workspace-local skills that override global on name collision.
- **resolveSkillReference(name, workspace)**: Kiro's resolution of a skill name against the combined skill set (`.kiro/skills/` + `~/.kiro/skills/`).
- **Pre-flight check**: The "Pre-flight: Unknown skill reference check" defined in `c:\Dev\arc-workflow\.kiro\steering\arc-workflow.md`, which warns when a referenced skill name does not resolve in `.kiro/skills/` or `~/.kiro/skills/`.
- **Sync hook**: `c:\Dev\arc-workflow\.kiro\hooks\sync-skills-to-global.json` — the existing manual, `userTriggered` hook that copies workspace skills and the steering file into `~/.kiro/`.
- **Source-of-truth repo**: The `arc-workflow` repo, where the canonical `.kiro/skills/setup-arc/` lives and from which global copies are derived.

## Bug Details

### Bug Condition

The bug manifests whenever the `setup-arc` skill is referenced (by Phase 0 of the steering file, by the pre-flight check, or directly) from a workspace that is not the `arc-workflow` source repo, on a machine where `setup-arc` has not been synced into `~/.kiro/skills/`. Resolution depends entirely on whether a human previously remembered to run the manual `userTriggered` sync hook from the `arc-workflow` repo, and on whether that run happened after `setup-arc` was created. The delivery mechanism is therefore neither automatic nor reliably current.

**Formal Specification:**

```text
FUNCTION isBugCondition(input)
  INPUT: input of type ProjectContext
         { workspace, globalSkills (contents of ~/.kiro/skills), skillRef }
  OUTPUT: boolean

  RETURN input.skillRef == "setup-arc"
         AND input.workspace IS NOT arc-workflow-source-repo
         AND "setup-arc" NOT IN input.globalSkills
END FUNCTION
```

The companion content defect (the mismatched H1 heading) is not part of the formal `isBugCondition` set above — it manifests on every read of `setup-arc/SKILL.md` regardless of workspace — but it is fixed in the same change and verified deterministically (see Fix Checking and Unit Tests).

### Examples

- **Phase 0 in another project (buggy):** Open an unrelated repo on a machine where the sync hook never ran. Start `#arc-workflow`. Expected: Phase 0 invokes `setup-arc`. Actual: `setup-arc` does not resolve; Phase 0 cannot run setup.
- **Pre-flight warning (buggy):** In that same project, the steering pre-flight check collects `setup-arc` from the Phase 0 body, finds no `setup-arc` directory in `.kiro/skills/` or `~/.kiro/skills/`, and surfaces an "unresolved skill reference" warning.
- **Stale sync (buggy):** The sync hook was last triggered before `setup-arc` was created. `~/.kiro/skills/` contains `tdd`, `triage`, `diagnose`, etc., but no `setup-arc`. Other projects still cannot see it.
- **Inside arc-workflow (NOT buggy — must stay working):** Open the `arc-workflow` repo itself. `setup-arc` resolves from local `.kiro/skills/setup-arc/`. This is the `¬C` case to preserve.
- **zsl-setup in another project (NOT buggy — reference behavior):** `setup-zsl-superpowers` resolves everywhere because the `zsl` plugin ships it through the Claude marketplace install. This is the working behavior whose *effect* we mirror.
- **Branding heading (secondary defect):** Reading `setup-arc/SKILL.md` shows the H1 `# Setup ZSL Superpowers`, inconsistent with the renamed `setup-arc` skill. Expected: `# Setup Arc`.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**

- Inside the `arc-workflow` source repo, `setup-arc` MUST continue to resolve via the local `.kiro/skills/setup-arc/` directory exactly as today (Req 3.1).
- The manual `sync-skills-to-global` hook MUST continue to copy workspace skills and the `arc-workflow` steering file into `~/.kiro/`, preserving the existing manual escape hatch (Req 3.2).
- The `zsl` plugin and its marketplace MUST continue to distribute `setup-zsl-superpowers` and the other engineering skills, completely untouched (Req 3.3).
- Other Arc skills already present in the global skill set (for example `tdd`, `triage`, `diagnose`) MUST continue to resolve from other projects as before (Req 3.4).
- The `setup-arc` skill's frontmatter `name` (`setup-arc`) and `description` MUST remain byte-for-byte identical; only the internal H1 heading changes (Req 3.5).
- The `setup-arc` skill's scaffolding behavior (issue tracker, triage labels, domain docs, ship style, optional project board) MUST remain unchanged (Req 3.6).

**Scope:**

All inputs where `isBugCondition` is false MUST be completely unaffected by this fix. This includes:

- Any reference resolved from inside the `arc-workflow` repo.
- Any reference to a skill other than `setup-arc`.
- Any reference resolved against a global skill set that already contains `setup-arc`.
- The `zsl-skills` repo and its `.claude-plugin` manifests, which this fix does not edit.

The actual expected correct behavior for buggy inputs is defined in the Correctness Properties section (Property 1). This section focuses on what must NOT change.

## Hypothesized Root Cause

Based on the bug analysis, the most likely causes are, in order of confidence:

1. **Manual, forgettable delivery (primary).** `setup-arc`'s only cross-project path is `sync-skills-to-global.json` with `when.type == "userTriggered"`. Nothing runs it automatically, so global availability hinges on a human remembering to trigger it from the `arc-workflow` repo. This is the direct analogue of the `zsl` gap: `setup-zsl-superpowers` is *always present* once the plugin is installed, whereas `setup-arc` is present only after a remembered manual action.

2. **Staleness of a prior sync.** Even when the hook was triggered, it may have run before `setup-arc` was created. `Copy-Item -Recurse -Force .kiro/skills/*` copies whatever existed at trigger time, so an old run leaves `~/.kiro/skills/` populated with other Arc skills but missing `setup-arc` — which exactly matches the observed symptom (other Arc skills resolve, `setup-arc` does not).

3. **Mechanism mismatch with the reference.** The working reference (`setup-zsl-superpowers`) is delivered by a Claude Code plugin marketplace (`zsl-skills/.claude-plugin/`). That mechanism does not feed Kiro's `~/.kiro/skills/` resolution and is not how `arc-workflow` (a Kiro-native repo) distributes. The correct Kiro analogue of "globally installed plugin skill" is "present in `~/.kiro/skills/`", so the fix targets that mechanism rather than adding a Claude marketplace.

4. **Incomplete rename (secondary, independent).** The H1 `# Setup ZSL Superpowers` in `setup-arc/SKILL.md` is leftover from the ZSL→Arc rename. It does not cause the resolution failure but is a correctness defect to fix in the same change.

## Distribution Mechanism Decision

Requirement 2.4 deliberately left the delivery mechanism open. Two options were evaluated.

**Option A — Make the global `~/.kiro/skills/` delivery reliable (recommended).**

Keep Kiro's native global-skill mechanism and remove the manual-trigger dependency. Concretely: add a repo-scoped, run-once-per-session, idempotent auto-refresh hook that copies `.kiro/skills/*` (and the steering file) into `~/.kiro/` whenever the user is working in the `arc-workflow` repo, and perform a one-time refresh now so `setup-arc` lands immediately. The existing manual hook stays as an escape hatch.

- **Pros:** This is exactly how Kiro makes a skill global, so it directly mirrors the *effect* of the installed `zsl` plugin (skill present everywhere, stays present). Edits to Arc skills only ever happen inside `arc-workflow` (the source of truth), so an auto-refresh scoped to that repo fires in the same session as any edit — propagation can no longer go stale or be forgotten. Minimal change, PowerShell already in place (Windows), and it preserves 3.1–3.4 cleanly because it only writes into `~/.kiro/skills/` from the canonical repo.
- **Cons:** `Copy-Item -Force` overwrites global copies on each refresh — intended, since the repo is the documented source of truth (local → global), and identical to the existing manual hook's behavior. Still requires opening `arc-workflow` once after the fix (acceptable: even the `zsl` plugin requires a one-time `plugin install` per machine).

**Option B — Package the Arc skills as a plugin + marketplace manifest.**

Mirror `zsl-skills` literally by authoring `.claude-plugin/plugin.json` + `marketplace.json` for the Arc skills.

- **Cons:** `arc-workflow` is a Kiro-native repo; the Claude `.claude-plugin` marketplace is a Claude Code CLI feature that does not feed Kiro's `~/.kiro/skills/` resolution — the very resolution the steering pre-flight check (Req 2.3) depends on. So this would not fix the observed Kiro symptom. A true "Kiro Power" packaging is a much heavier lift (manifest, versioning, publishing on every change) and is overkill for a personal, single-user, Windows workflow repo. High ongoing effort, poor fit.

**Decision: Option A.** It most directly mirrors the working `setup-zsl-superpowers` behavior (always-present global skill) with the least ongoing manual effort, uses the mechanism the pre-flight check actually reads, and keeps the blast radius inside `~/.kiro/skills/` so all preservation requirements hold.

## Correctness Properties

Property 1: Bug Condition - setup-arc resolves in other projects

_For any_ input where the bug condition holds (isBugCondition returns true) — `setup-arc` is referenced from a workspace other than the `arc-workflow` source repo on a machine where `setup-arc` is absent from `~/.kiro/skills/` — the fixed system SHALL, after the auto-refresh has run from the `arc-workflow` repo, place `setup-arc` into `~/.kiro/skills/` so that `resolveSkillReference("setup-arc", workspace)` succeeds, Phase 0 can invoke the skill, and the steering pre-flight check emits no warning for `setup-arc`.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation - non-buggy behavior unchanged

_For any_ input where the bug condition does NOT hold (isBugCondition returns false) — a reference resolved inside the `arc-workflow` repo, a reference to any skill other than `setup-arc`, or any reference where `~/.kiro/skills/` already contains `setup-arc` — the fixed system SHALL produce the same result as the original system, preserving local `arc-workflow` resolution, the manual sync hook, the untouched `zsl` plugin distribution, the resolution of other already-global Arc skills, and the `setup-arc` frontmatter (`name` and `description`).

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

Assuming the root-cause analysis is correct, the fix has three concrete changes plus a one-time refresh action.

**Change 1 — Correct the branding heading (secondary defect, Req 2.5).**

**File:** `c:\Dev\arc-workflow\.kiro\skills\setup-arc\SKILL.md`

- Replace the H1 `# Setup ZSL Superpowers` with `# Setup Arc`.
- Do NOT touch the frontmatter `name: setup-arc` or `description:` (Req 3.5). Only the H1 line changes.

**Change 2 — Add an automatic, idempotent global-refresh hook (primary fix, Req 2.1, 2.4).**

**File (new):** `c:\Dev\arc-workflow\.kiro\hooks\sync-skills-to-global-auto.kiro.hook`

- Use the `.kiro.hook` schema already used by the repo's other automatic hooks (`enabled`, `name`, `description`, `version`, `when`, `then`), matching `kiro-recall-session-start.kiro.hook`.
- Trigger: fires automatically at session start (the repo's automatic hooks use `when.type == "promptSubmit"`), and runs once per session.
- Action: `runCommand` executing the same PowerShell copy the manual hook uses, so behavior is identical and Windows-correct:

  ```text
  Copy-Item -Recurse -Force .kiro/skills/* $HOME/.kiro/skills/; Copy-Item -Force .kiro/steering/arc-workflow.md $HOME/.kiro/steering/arc-workflow.md
  ```

- Because this hook lives in the `arc-workflow` repo, it only ever fires while the user is working in the source-of-truth repo. Any edit to an Arc skill is therefore propagated to `~/.kiro/skills/` in the same session, eliminating the staleness/forgetting failure mode while never writing from non-source workspaces.
- Idempotency: copying is overwrite-with-force of identical content on repeat runs; running it more than once is harmless.

**Change 3 — Keep the existing manual hook as an escape hatch (Req 3.2).**

**File:** `c:\Dev\arc-workflow\.kiro\hooks\sync-skills-to-global.json`

- No change. The manual `userTriggered` hook is preserved verbatim so the documented manual workflow (and the README install instructions) keep working.

**One-time action — Refresh the global skill set now (Req 2.1).**

- After Change 1 and Change 2 are in place, run the sync once from the `arc-workflow` repo (the new auto hook will do this at next session start, or the user can trigger the manual hook immediately). This copies the corrected `setup-arc` into `~/.kiro/skills/setup-arc/`, making it resolvable in all other projects right away.

### Explicitly Out of Scope (preserves 3.3)

- No edits to `c:\Dev\zsl-skills\.claude-plugin\plugin.json` or `marketplace.json`.
- No new `.claude-plugin` manifest or Kiro Power packaging for `arc-workflow` (Option B rejected).
- No changes to any skill's scaffolding logic (preserves 3.6).

## Testing Strategy

### Validation Approach

The strategy follows the two-phase bug-condition method: first surface counterexamples that demonstrate the bug on the UNFIXED state (so the root cause is confirmed), then verify the fix resolves the bug for all buggy inputs and preserves behavior for all non-buggy inputs. Because the artifacts here are skill files, hooks, and steering — not application code — "tests" are concrete, scriptable checks of file presence, resolution, frontmatter equality, and pre-flight warning output, run on Windows PowerShell.

### Exploratory Bug Condition Checking

**Goal:** Surface counterexamples that demonstrate the bug BEFORE implementing the fix, confirming the root cause (manual/stale delivery into `~/.kiro/skills/`). If these do not fail on the unfixed state, the root-cause hypothesis is refuted and must be revised.

**Test Plan:** Simulate a clean machine state for the global skill set (a global skills directory with the other Arc skills but no `setup-arc`, mimicking a stale prior sync), then attempt to resolve `setup-arc` as a non-`arc-workflow` workspace would. Run against the UNFIXED repo.

**Test Cases:**

1. **Missing-from-global Test:** With `~/.kiro/skills/` lacking a `setup-arc` directory, assert resolution of `setup-arc` from a non-arc workspace fails (will fail on unfixed code — i.e. the skill is unresolved).
2. **Phase 0 Invocation Test:** Simulate the steering Phase 0 attempting to invoke `setup-arc` in such a workspace; assert it cannot run setup (will fail on unfixed code).
3. **Pre-flight Warning Test:** Run the steering "Unknown skill reference check" logic against the collected phase skill names with `setup-arc` absent from both skill sets; assert a warning is surfaced for `setup-arc` (will fail/warn on unfixed code).
4. **Stale-sync Edge Case:** Populate global skills with `tdd`/`triage`/`diagnose` but not `setup-arc`; assert those resolve while `setup-arc` does not (reproduces the exact reported asymmetry).

**Expected Counterexamples:**

- `setup-arc` unresolved from any non-`arc-workflow` workspace whenever `~/.kiro/skills/setup-arc/` is absent.
- Pre-flight check emits an unresolved-reference warning for `setup-arc`.
- Possible causes confirmed: manual-only trigger, stale prior sync, mechanism mismatch with the Claude plugin marketplace.

### Fix Checking

**Goal:** Verify that for all inputs where the bug condition holds, the fixed system produces the expected behavior (Property 1).

**Pseudocode:**

```text
FOR ALL input WHERE isBugCondition(input) DO
  runAutoRefreshFrom(arc-workflow-repo)        // Change 2 / one-time action
  ASSERT "setup-arc" IN globalSkills(~/.kiro/skills)
  ASSERT resolveSkillReference("setup-arc", input.workspace) == RESOLVED
  ASSERT phase0CanInvoke("setup-arc", input.workspace) == TRUE
  ASSERT preflightWarnings(input.workspace) DOES NOT CONTAIN "setup-arc"
END FOR
```

**Verification on Windows:**

- After running the refresh from `arc-workflow`, confirm `Test-Path $HOME/.kiro/skills/setup-arc/SKILL.md` is `True`.
- Open a different workspace (any folder other than `arc-workflow`) WITHOUT re-running a manual sync; reference `#arc-workflow` and confirm the pre-flight check passes silently and Phase 0 can invoke `setup-arc`.
- Confirm the copied `SKILL.md` shows the corrected `# Setup Arc` H1.

### Preservation Checking

**Goal:** Verify that for all inputs where the bug condition does NOT hold, the fixed system produces the same result as the original system (Property 2).

**Pseudocode:**

```text
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT resolve_fixed(input) == resolve_original(input)
END FOR
```

**Testing Approach:** Property-based testing is recommended for preservation because the non-buggy input space is large (every other skill name, every workspace, both states of the global set) and PBT generates many cases automatically, catching edge cases manual checks miss and giving strong confidence that behavior is unchanged for all `¬C` inputs.

**Test Plan:** Observe the UNFIXED behavior for each non-buggy input class first, then assert the fixed behavior is identical.

**Test Cases:**

1. **Local arc-workflow Preservation (3.1):** From inside `arc-workflow`, observe `setup-arc` resolves locally on unfixed code; assert it still resolves locally (and from the local copy) after the fix.
2. **Manual Hook Preservation (3.2):** Confirm `sync-skills-to-global.json` is byte-for-byte unchanged and still performs the copy when triggered.
3. **zsl Plugin Preservation (3.3):** Confirm `zsl-skills/.claude-plugin/plugin.json` and `marketplace.json` are unmodified and `setup-zsl-superpowers` still distributes via the marketplace.
4. **Other Global Skills Preservation (3.4):** Confirm `tdd`, `triage`, `diagnose` still resolve from other projects exactly as before.
5. **Frontmatter Preservation (3.5):** Diff `setup-arc/SKILL.md` frontmatter before/after; assert `name` and `description` are identical and only the H1 line changed.
6. **Scaffolding Preservation (3.6):** Confirm the skill body (Process sections, templates, bundled resource links) is unchanged apart from the H1.

### Unit Tests

- **Heading fix:** Assert `setup-arc/SKILL.md` contains `# Setup Arc` and does NOT contain `# Setup ZSL Superpowers`.
- **Frontmatter integrity:** Assert frontmatter `name: setup-arc` and the full `description` string are unchanged.
- **Auto-hook schema:** Assert `sync-skills-to-global-auto.kiro.hook` is valid JSON, has `enabled: true`, a `when` trigger, and a `then.runCommand` whose command matches the manual hook's copy command.
- **Manual-hook untouched:** Assert `sync-skills-to-global.json` is identical to its pre-fix content.

### Property-Based Tests

- **Resolution after refresh (Property 1):** Generate arbitrary non-`arc-workflow` workspace names; after the refresh, assert `setup-arc` resolves for every one.
- **Preservation across skill names (Property 2):** Generate arbitrary skill names from the existing Arc set plus `setup-zsl-superpowers`; assert resolution outcome is identical before and after the fix for every name except where C made `setup-arc` fail.
- **Idempotent refresh:** Generate N repeated refresh runs; assert the resulting `~/.kiro/skills/setup-arc/` content is identical regardless of N (no duplication, no corruption).

### Integration Tests

- **End-to-end other-project flow:** On a machine state where global skills lack `setup-arc`, run the refresh from `arc-workflow`, then open a separate project and run `#arc-workflow`; assert Phase 0 detects an unconfigured repo, invokes `setup-arc`, and the pre-flight report shows no `setup-arc` warning.
- **Steering pre-flight pass:** In a non-`arc-workflow` project after refresh, assert the pre-flight check proceeds silently (no unresolved references) per its "proceed silently" rule.
- **Edit-then-propagate:** Make a trivial edit to a skill inside `arc-workflow`, let the auto-refresh fire at next session start, and assert the change appears in `~/.kiro/skills/` without a manual trigger — confirming the staleness failure mode is closed.
