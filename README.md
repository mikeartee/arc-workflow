# Arc — Personal Engineering Workflow

This is a fork of a fork, forking heck! This version is for Kiro IDE, the one I forked (unofficially, but officially) from, is the Claude Code CLI one from  Seb Kreuger https://github.com/ZunoSmartLabs/zsl-superpowers

## Installation

1. Clone this repo and open it in Kiro
2. Run the following in Kiro's chat to copy skills and steering to your global config:

```
Copy the skills and steering file to global — run: Copy-Item -Recurse -Force .kiro/skills/* $HOME/.kiro/skills/; Copy-Item -Force .kiro/steering/arc-workflow.md $HOME/.kiro/steering/arc-workflow.md
```

Or on macOS/Linux:

```bash
cp -r .kiro/skills/* ~/.kiro/skills/
cp .kiro/steering/arc-workflow.md ~/.kiro/steering/arc-workflow.md
```

That's the entire install. Skills and the workflow steering file are now available globally in every workspace you open.

## Usage

Open any folder in Kiro, then in chat:

```
#arc-workflow I want to build [describe what you want]
```

That's it. The workflow handles setup, alignment, PRD, issues, triage, build, and review automatically.

## Examples

**New project from scratch:**

```
#arc-workflow I want to build a CLI tool that syncs my dotfiles across machines
```

**Add a feature to an existing project:**

```
#arc-workflow I want to add OAuth login to this app
```

**Point it at existing notes or a doc:**

```
#arc-workflow Here's what I'm thinking: [paste notes or drag in a file]
```

**Jump into the middle (you already have a PRD):**

```
#arc-workflow I already have a PRD at #File:docs/prd.md — break it into issues
```

**Use skills directly (skip the full workflow):**

- `/tdd` — TDD a specific issue
- `/triage` — triage issues on your tracker
- `/grill-with-docs` — stress-test a plan against your domain model
- `/to-issues` — break a PRD into vertical slices

## What Happens

1. **Setup** (first time per repo) — writes `docs/agents/` config using your defaults. Automatic, no questions asked.
2. **Grill** — challenges your idea until there's shared understanding. Updates CONTEXT.md inline.
3. **PRD** — synthesizes the grilling into a published PRD issue.
4. **Issues** — breaks the PRD into independently-grabbable vertical slices.
5. **Triage** — labels each slice as AFK (agent-ready) or HITL (needs human), writes agent briefs.
6. **Build** — fans out AFK slices into parallel TDD agents, merges into one integration PR.
7. **Review** — reviews the PR, proposes fixes, waits for your approval.

## Phases

| # | Phase | Skill | Input | Output |
|---|-------|-------|-------|--------|
| 0 | Repo Setup | `setup-arc` | Fresh repo | `docs/agents/` config |
| 1 | Understand | `grill-with-docs` | Your idea/notes | Shared understanding + CONTEXT.md |
| 2 | PRD | `to-prd` | Grilling output | Published PRD issue |
| 3 | Issues | `to-issues` | PRD issue | Vertical slice issues |
| 4 | Triage | `triage` | Slice issues | Labeled + briefed issues |
| 5 | Build | `tdd-parallel` | Triaged AFK slices | Integration PR |
| 6 | Review | `code-review` | Integration PR | Reviewed PR ready to merge |

## Customization Guide

### Adding a phase

1. Open `.kiro/steering/arc-workflow.md` (or `~/.kiro/steering/arc-workflow.md` for global)
2. Add a new `### Phase N — Name` section at the desired position
3. Write the phase body invoking the skill by its `name` front-matter value
4. Update this README

### Removing a phase

1. Delete the `### Phase N — Name` section from the steering file
2. Remove the corresponding entry from this README

### Modifying a skill

1. Edit `.kiro/skills/<name>/SKILL.md` directly
2. Changes take effect on next invocation — no restart needed
3. Propagation to `~/.kiro/skills/` is automatic: the `sync-skills-to-global-auto.kiro.hook` fires at session start from this workspace and copies skills + steering to global. To propagate immediately, manually trigger the `sync-skills-to-global` hook (the `userTriggered` escape hatch) or re-run the install command from the Installation section

### Adding a bundled resource to a skill

1. Create the resource file in `.kiro/skills/<name>/`
2. Add a relative link to it from `SKILL.md`
3. The agent resolves the link on next invocation

### Global vs local skills

- `~/.kiro/skills/` — available in every workspace
- `.kiro/skills/` — workspace-local, overrides global on name collision
- Removing from `.kiro/skills/` does NOT remove from `~/.kiro/skills/`
- The sync runs automatically at session start from this repo (`sync-skills-to-global-auto.kiro.hook`), copying local → global (skills + steering file); the manual `sync-skills-to-global` hook remains as an escape hatch
