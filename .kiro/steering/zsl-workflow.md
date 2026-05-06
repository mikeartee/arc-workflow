---
inclusion: manual
---

# ZSL Agentic Engineering Workflow

You are guiding the user through the ZSL end-to-end engineering workflow. The user has given you notes, a project scope, or a rough idea. Your job is to walk them through each phase in order — one at a time, waiting for their input before moving to the next.

Never dump the whole plan at once. Move through the phases conversationally.

## The Flow

### Phase 0 — Repo setup (first time only)

Check whether `docs/agents/` exists in the current repo. If it does not, the repo has not been configured yet.

Tell the user: "This repo hasn't been set up for the ZSL workflow yet. I'll run the setup first — this only needs to happen once."

Then invoke the `setup-zsl-skills` skill. Walk the user through all five sections (issue tracker, triage labels, domain docs, ship style, project board). Do not proceed to Phase 1 until setup is complete.

If `docs/agents/` already exists, skip this phase entirely.

---

### Phase 1 — Understand what you're building

Invoke the `grill-with-docs` skill.

Tell the user: "Let's make sure we're aligned on what you're building before writing a single line of code. I'm going to ask you questions one at a time — answer as much or as little as you like."

Use the notes or scope the user provided as the starting context. Grill them until you have a clear, shared understanding of:
- The problem being solved
- Who it's for
- What success looks like
- Key constraints or decisions already made

Update `CONTEXT.md` and offer ADRs inline as decisions crystallise.

Do not proceed to Phase 2 until the user says they're happy with the understanding.

---

### Phase 2 — Write the PRD

Invoke the `to-prd` skill.

Tell the user: "Great. I'll now turn everything we've discussed into a PRD and publish it to your issue tracker."

Synthesise the grilling session into a PRD. Do NOT re-interview the user — just write it from what you know. Show the user the draft before publishing. Let them edit. Then publish.

Do not proceed to Phase 3 until the PRD is published and the user confirms.

---

### Phase 3 — Break it into issues

Invoke the `to-issues` skill, pointing it at the PRD just created.

Tell the user: "Now I'll break the PRD into independently-grabbable vertical slices. Each slice will be a separate issue."

Present the proposed breakdown. Quiz the user on granularity and dependencies. Iterate until they approve. Then publish the issues and link them as sub-issues of the PRD.

Do not proceed to Phase 4 until the user approves the breakdown and issues are published.

---

### Phase 4 — Triage the slices

Invoke the `triage` skill for each child issue.

Tell the user: "I'll now triage each slice — deciding whether it's ready for an agent to pick up autonomously (AFK) or needs a human (HITL), and writing an agent brief for each AFK slice."

Work through each child issue. For each one: recommend a category and state, write an agent brief if moving to `ready-for-agent`, and apply the label. Sync the project board if configured.

Do not proceed to Phase 5 until all slices are triaged.

---

### Phase 5 — Build

Invoke the `tdd-parallel` skill, pointing it at the PRD issue.

Tell the user: "All AFK slices are ready. I'll now fan them out into parallel TDD sub-agents — each one working in its own worktree, committing locally. When they're all done I'll merge the branches in wave order and open a single integration PR."

Run the full tdd-parallel flow. Handle escalations by relaying them to the user. Halt with a structured RCA on any failure.

Do not proceed to Phase 6 until the integration PR is open.

---

### Phase 6 — Review and ship

Invoke the `code-review` skill on the integration PR branch.

Tell the user: "The integration PR is open. Let me review it before you merge."

Present findings grouped by severity. Propose a fix plan. Wait for approval before applying any fixes. Once the review is clean, tell the user the PR is ready to merge.

---

## Rules

- Always tell the user which phase you're in and what's happening next.
- Never skip a phase unless the user explicitly asks to.
- If the user pastes notes or a scope at the start, treat that as the input to Phase 1.
- If the user says "just build it" or similar, still run Phase 1 — alignment is non-negotiable.
- If the user wants to jump into the middle of the flow (e.g. they already have a PRD), start from the appropriate phase and check prerequisites exist.
