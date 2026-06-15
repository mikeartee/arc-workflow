# Report-Rendering and Merge-Stop Scenario Checks

## Purpose

This document verifies two things in `.kiro/skills/arc-handsoff/SKILL.md`: that
the `Hands_Off_Report` renders its DID / PARKED / READ & MERGE sections
correctly and posts to the PRD issue (with a fallback to the integration PR
body), and that the orchestrator preserves the existing merge-stop — it
introduces no `git merge` or push-to-default capability and leaves the
integration PR unmerged in both modes.

These are example/scenario-based walkthroughs, not property tests. Per the
design Testing Strategy, this feature is markdown-driven orchestration with no
executable runtime, so there is no pure function to assert a universal property
over. Each scenario is a guided walkthrough: given a run that stopped for a
named reason plus its in-memory parked list, the orchestrator renders the report
from the exact template in `SKILL.md` and posts it to the prescribed target.

## How to read a scenario

Each report-rendering scenario provides:

- **Run outcome** — why the run stopped and what it produced: the completed AFK
  slices, the integration PR (or none), and the in-memory `parked` list.
- **Rendered report** — the markdown the orchestrator MUST produce, filled from
  the run's results and the parked list against the template in `SKILL.md`.
- **Assertions** — the section-level rules the rendered report MUST satisfy.

Each merge-stop scenario provides:

- **Given** — the run state at the point shipping happens.
- **Action** — what the orchestrator does with the integration PR.
- **Expected** — the merge-stop behavior the orchestrator MUST preserve.

The report template, the `None` rule for empty sections, and the posting
commands all follow the "The Hands_Off_Report" section of `SKILL.md`.

## Report-rendering scenarios

### RR-1: All three sections filled — mixed run stopped at a Review blocker

A run where Build merged the AFK slices and opened the integration PR, one HITL
slice was skipped, and Review then flagged a blocker that stopped the run. Every
section has content, so this is the fully-populated rendering (Requirements 8.2,
8.3, 8.4).

#### Run outcome

- AFK slices #121 and #122 reached passing and merged into the integration
  branch.
- HITL slice #142 was skipped and recorded as a `park-and-continue` item.
- `tdd-parallel` opened integration PR #130 (`https://github.com/mikeartee/arc-workflow/pull/130`)
  with `Closes #120`.
- `code-review` flagged a blocker, recorded as a `park-and-wait`
  `review-blocker` item; the run stopped.

The in-memory `parked` list:

```json
[
  {
    "kind": "hitl-slice",
    "ref": "#142",
    "reason": "Requires manual OAuth app registration before implementation",
    "disposition": "park-and-continue"
  },
  {
    "kind": "review-blocker",
    "ref": "review",
    "reason": "Review flagged a SQL-injection risk in the query builder slice",
    "disposition": "park-and-wait"
  }
]
```

#### Rendered report

```markdown
## Hands-Off Report

Run stopped: phase failure
Stopped at: 2025-01-15T19:42:00Z

### DID

Integration PR: https://github.com/mikeartee/arc-workflow/pull/130

Completed AFK slices (merged into the integration branch):

- #121 — Add token bucket to the rate limiter
- #122 — Wire the rate limiter into the request middleware

### PARKED

- [HITL] #142 — OAuth login slice — Requires manual OAuth app registration before implementation
- [FAILED: review] — Review flagged a SQL-injection risk in the query builder slice

### READ & MERGE

- Review and merge: https://github.com/mikeartee/arc-workflow/pull/130
- Nothing reached the default branch; the merge is yours.
```

#### Assertions

- **DID** lists the completed AFK slices #121 and #122 and shows the integration
  PR URL (Requirement 8.2). The completed slices are the DID contents, not
  parked items.
- **PARKED** renders one bullet per parked item from the in-memory list: the
  skipped HITL slice (`[HITL]` prefix) and the failed phase (`[FAILED: review]`
  prefix), each with its one-line reason (Requirement 8.3).
- **READ & MERGE** carries the integration PR link plus the reminder that
  nothing reached the default branch (Requirement 8.4).
- The header, `Run stopped:` / `Stopped at:` lines, and the three `###` section
  headings match the template in `SKILL.md` exactly.

### RR-2: Empty PARKED renders "None" — clean Review-complete run

A clean run that advanced through Build and Review with no skipped HITL slices
and no failures. Review completed clean, so the run stopped on the terminal
success row. There are no parked items, so the PARKED section renders the single
line `None` rather than being omitted (Requirement 8.3).

#### Run outcome

- AFK slices #121 and #122 merged into the integration branch.
- `tdd-parallel` opened integration PR #130; `code-review` reviewed it clean.
- The in-memory `parked` list is empty: `[]`.

#### Rendered report

```markdown
## Hands-Off Report

Run stopped: Review complete
Stopped at: 2025-01-15T20:05:00Z

### DID

Integration PR: https://github.com/mikeartee/arc-workflow/pull/130

Completed AFK slices (merged into the integration branch):

- #121 — Add token bucket to the rate limiter
- #122 — Wire the rate limiter into the request middleware

### PARKED

None

### READ & MERGE

- Review and merge: https://github.com/mikeartee/arc-workflow/pull/130
- Nothing reached the default branch; the merge is yours.
```

#### Assertions

- With no parked items, **PARKED** is replaced by the single line `None`, never
  omitted — the human can tell "nothing parked" from "report truncated"
  (Requirement 8.3).
- **DID** and **READ & MERGE** are still fully populated, so a `None` in one
  section does not affect the others (Requirements 8.2, 8.4).
- `Run stopped: Review complete` records the clean exit.

### RR-3: Empty DID renders "None" — grill-gate stop before Build

A run where the grill-first precondition gate found no alignment, parked `grill`,
and returned before the loop ever started. Nothing ran and no PR was opened, so
DID renders `None` with `Integration PR: none opened`, and READ & MERGE has no
PR link. PARKED carries the single grill item (Requirements 8.2, 8.3).

#### Run outcome

- The grill proxy was absent (no non-trivial `CONTEXT.md`, no PRD issue), so the
  gate stopped before the loop and parked `grill` (`park-and-wait`).
- No phases ran; no AFK slices completed; no integration PR was opened.

The in-memory `parked` list:

```json
[
  {
    "kind": "phase-failure",
    "ref": "grill",
    "reason": "Grill has not reached shared understanding; alignment needs the human",
    "disposition": "park-and-wait"
  }
]
```

#### Rendered report

```markdown
## Hands-Off Report

Run stopped: grill gate
Stopped at: 2025-01-15T18:10:00Z

### DID

Integration PR: none opened

Completed AFK slices (merged into the integration branch):

None

### PARKED

- [FAILED: grill] — Grill has not reached shared understanding; alignment needs the human

### READ & MERGE

None
```

#### Assertions

- **DID** shows `Integration PR: none opened` and renders the completed-slices
  list as `None`, because nothing ran (Requirement 8.2).
- **PARKED** carries the single grill item, proving the grill-gate stop is
  reported, not silently dropped (Requirement 8.3).
- **READ & MERGE** renders `None`: with no integration PR there is no link to
  show, and the section is still present rather than omitted (Requirement 8.4).

## Report-posting scenarios

### PP-1: Posted as a comment on the PRD issue (primary)

The PRD issue is the primary target because it is stable across the whole run
and exists even when no PR was opened.

- **Given** — a rendered report and a resolvable PRD `tracking` issue `#120`.
- **Action** — the orchestrator writes the rendered markdown to a temporary file
  and posts it as a comment on the PRD issue.
- **Expected** — the report is posted via
  `gh issue comment 120 --body-file hands-off-report.md`, using `--body-file`
  (not `--body`) so the multi-line report, code spans, and bullet lists survive
  shell quoting intact (Requirement 8.5).

### PP-2: Fallback to the integration PR body

When the PRD issue cannot be resolved — no `tracking` issue was found, or the
comment post fails — and an integration PR exists, the report falls back to the
PR body.

- **Given** — a rendered report, an unresolvable PRD issue, and an open
  integration PR `#130`.
- **Action** — the orchestrator writes the report into the integration PR body.
- **Expected** — the report is written via
  `gh pr edit 130 --body-file hands-off-report.md` (Requirement 8.5). The
  fallback applies only because an integration PR exists.

### PP-3: Neither target resolvable — surface in-session

A grill-gate stop with no PRD issue and no integration PR leaves no GitHub
target for the come-back artifact.

- **Given** — a rendered report, no resolvable PRD issue, and no integration PR
  (for example, the RR-3 grill-gate stop).
- **Action** — the orchestrator has no GitHub target to post to.
- **Expected** — the orchestrator surfaces the report in-session as its final
  message, so the run is never left without a come-back artifact (Requirement
  8.5).

## Merge-stop regression scenarios

### MS-1: Shipping is delegated to tdd-parallel; the orchestrator only reads the PR

The orchestrator adds no merge or push capability of its own. Shipping is done
entirely by Build, and the orchestrator's only interaction with the resulting PR
is to read it.

- **Given** — Build has completed its automatable AFK slices in a hands-off run.
- **Action** — `tdd-parallel` pushes the integration branch and opens the single
  integration PR with `Closes #<prd>`, then stops per `docs/agents/ship-style.md`
  (Requirement 7.1). The orchestrator advances to Review.
- **Expected** — the orchestrator only **reads** the open PR and its
  `reviewDecision` as part of `Repository_State` to decide whether to advance to
  Review. It leaves the integration PR **unmerged** (Requirement 7.2), never
  calls `git merge`, and never pushes to the `Default_Branch` (Requirement 7.3).
  No step in the orchestrator path moves code onto the default branch.

### MS-2: No merge/push capability introduced anywhere in the skill

A static check of the skill itself: hands-off mode must introduce no new merge
or push-to-default capability beyond the read-only `gh` reads it uses for phase
detection.

- **Given** — the full `arc-handsoff/SKILL.md`.
- **Action** — inspect every command the skill prescribes.
- **Expected** — the skill issues only read-only `gh` / `gh api graphql` reads
  for `Repository_State`, the report-posting commands (`gh issue comment` and
  `gh pr edit --body-file`), and delegation to phase skills. It contains no
  `git merge`, no `git push` to the `Default_Branch`, and no PR-merge command
  (`gh pr merge`). The merge-stop is a hard boundary the orchestrator reads up to
  but never crosses (Requirements 7.2, 7.3).

### MS-3: Merge-stop applies identically whether the mode is on or off

Because the orchestrator reuses the same `tdd-parallel` → `ship-style` path a
manual run uses, the merge-stop is mode-independent.

- **Given** — the same feature shipped twice: once with `/hands-off` on (the
  orchestrator pulls the trigger to start Build) and once with the mode off (the
  human invokes Build manually).
- **Action** — Build opens the integration PR in each run.
- **Expected** — in both runs the integration PR is left unmerged for the human
  to review and merge; nothing reaches the default branch (Requirement 7.4). The
  only difference between the two modes is who starts Build, and that difference
  ends at the opened PR — from the PR onward the behavior is identical, and the
  `Hands_Off_Report`'s READ & MERGE section points to the PR so the merge stays a
  deliberate human action.

## Coverage summary

| Scenario | Behavior verified | Requirement |
| --- | --- | --- |
| RR-1 | DID / PARKED / READ & MERGE all filled | 8.2, 8.3, 8.4 |
| RR-2 | Empty PARKED renders `None`; others filled | 8.2, 8.3, 8.4 |
| RR-3 | Empty DID and READ & MERGE render `None`; grill item parked | 8.2, 8.3, 8.4 |
| PP-1 | Posted as a comment on the PRD issue (primary) | 8.5 |
| PP-2 | Fallback to the integration PR body | 8.5 |
| PP-3 | Neither target resolvable — surface in-session | 8.5 |
| MS-1 | Shipping delegated to tdd-parallel; orchestrator only reads PR | 7.2, 7.3 |
| MS-2 | No merge/push capability introduced in the skill | 7.2, 7.3 |
| MS-3 | Merge-stop identical whether the mode is on or off | 7.4 |

Every clause in scope is covered: the three report sections rendered both filled
and empty (`None`), report posting to the PRD issue with its PR-body fallback
(8.2, 8.3, 8.4, 8.5), and the merge-stop preserved with no `git merge` or
push-to-default and the PR left unmerged in both modes (7.2, 7.3, 7.4).

_Requirements: 7.2, 7.3, 7.4, 8.2, 8.3, 8.4, 8.5_
