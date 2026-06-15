# Decision-Table Scenario Checks

## Purpose

This document verifies the state→phase decision table in
`.kiro/skills/arc-handsoff/SKILL.md` by walking each table row, and each Error
Handling row from `design.md`, against a concrete `Repository_State` fixture and
confirming the orchestrator selects the expected next action.

These are example/scenario-based walkthroughs, not property tests. Per the
design Testing Strategy, this feature is markdown-driven orchestration with no
executable runtime, so there is no pure function to assert a universal property
over. Each scenario is a guided walkthrough: given the fixture as the freshly
re-derived `Repository_State`, the orchestrator classifies it against exactly
one decision-table row and takes that row's single next action.

## How to read a scenario

Each scenario provides:

- **Fixture** — a concrete `Repository_State` record as the orchestrator would
  assemble it from the `gh` reads on one loop iteration.
- **Matched row** — the single decision-table row the fixture satisfies.
- **Expected next action** — the action the orchestrator MUST take.

The `Repository_State` shape follows the conceptual record in `SKILL.md`:
`grillProxyPresent`, `prdIssue` (or `null`), `subIssues` (each with its triage
`label`), and `integrationPr` (or `null`).

## Decision-table row scenarios

### DT-1: No grill proxy and no PRD issue → stop, park grill

Fresh repo with no alignment artifact and no PRD issue. The grill proxy is
absent, so the precondition is not met.

```json
{
  "grillProxyPresent": false,
  "prdIssue": null,
  "subIssues": [],
  "integrationPr": null
}
```

- **Matched row** — "No `CONTEXT.md` (or trivially empty) and no PRD issue" →
  Grill not done.
- **Expected next action** — **Stop** auto-advancement and park a `grill`
  item with the reason "requires the human" (Requirement 3.2). The orchestrator
  never invokes the Grill phase.

### DT-2: Grill proxy present, no PRD issue → invoke `to-prd`

Alignment is done (a non-trivial `CONTEXT.md` exists) but no PRD `tracking`
issue has been created yet.

```json
{
  "grillProxyPresent": true,
  "prdIssue": null,
  "subIssues": [],
  "integrationPr": null
}
```

- **Matched row** — "Grill proxy present, no PRD issue exists" → Ready to start.
- **Expected next action** — Invoke `to-prd` to begin at the PRD phase
  (Requirement 3.3).

### DT-3: PRD issue exists, no sub-issues → invoke `to-issues`

The PRD `tracking` issue exists but has not been broken into slice sub-issues.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [],
  "integrationPr": null
}
```

- **Matched row** — "PRD issue exists, has no sub-issues" → PRD done.
- **Expected next action** — Invoke `to-issues`.

### DT-4: Sub-issues exist but one or more untriaged → invoke `triage`

Slice sub-issues exist, but at least one still carries `needs-triage` (or
`needs-info`, or no triage label), so triage is incomplete.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 122, "label": "needs-triage" }
  ],
  "integrationPr": null
}
```

- **Matched row** — "Sub-issues exist, one or more still untriaged" →
  Issues done.
- **Expected next action** — Invoke `triage`.

### DT-5: Every sub-issue triaged, no open PR → invoke `tdd-parallel`

Every slice carries a triage label (`ready-for-agent` or `ready-for-human`) and
no integration PR is open yet, so Build has not run.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 122, "label": "ready-for-agent" },
    { "number": 142, "label": "ready-for-human" }
  ],
  "integrationPr": null
}
```

- **Matched row** — "Every sub-issue triaged, no open integration PR" →
  Triage done.
- **Expected next action** — Invoke `tdd-parallel` (Build).

### DT-6: Open integration PR, not yet reviewed → invoke `code-review`

Build has shipped: an integration PR is open and has not been reviewed
(`reviewed: false`, no review decision).

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 122, "label": "ready-for-agent" }
  ],
  "integrationPr": { "number": 130, "state": "open", "reviewed": false }
}
```

- **Matched row** — "Open integration PR exists, not yet reviewed" → Build done.
- **Expected next action** — Invoke `code-review` (Review).

### DT-7: Integration PR reviewed clean → stop auto-advancement

Review has completed and the integration PR is reviewed clean
(`reviewed: true`). This is the terminal success row.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 122, "label": "ready-for-agent" }
  ],
  "integrationPr": { "number": 130, "state": "open", "reviewed": true }
}
```

- **Matched row** — "Integration PR reviewed clean (Review completed)" →
  Review done.
- **Expected next action** — **Stop** auto-advancement (Requirement 2.4). The
  orchestrator produces the `Hands_Off_Report` and leaves the PR unmerged.

### DT-8: No single row matches → stop, park phase-detection

The signals contradict each other: sub-issues still need triage, yet an
integration PR is already open whose `Closes` set does not match those slices.
No single row matches.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 122, "label": "needs-triage" }
  ],
  "integrationPr": { "number": 130, "state": "open", "reviewed": false }
}
```

- **Matched row** — "State matches no row, or matches more than one row in a
  contradictory way" → Ambiguous.
- **Expected next action** — **Stop** and park a `phase-detection` item with the
  reason "ambiguous state". The orchestrator does not guess.

## Error Handling row scenarios

### EH-1: Ambiguous state → stop, park phase-detection

This is the Error Handling counterpart to DT-8, framed from the design's
"Ambiguous state (cannot determine phase)" row. The orchestrator's default
posture while the human is away is to stop safely and park, never guess.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "needs-triage" }
  ],
  "integrationPr": { "number": 130, "state": "open", "reviewed": false }
}
```

- **Expected next action** — **Stop** auto-advancement and park a
  `phase-detection` item (`disposition: park-and-wait`) with a one-line reason
  describing the contradictory signals (Requirement 5.4).

A `gh` read failure (network error, authentication failure, or API error) is
treated the same way: the orchestrator cannot determine the phase, so it stops
and parks `phase-detection` with the read failure as the reason.

### EH-2: No AFK slices exist → park HITL slices, no PR, stop

Every slice is `ready-for-human`, so Build has nothing to fan out.
`tdd-parallel` reports zero AFK work and opens no integration PR.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 141, "label": "ready-for-human" },
    { "number": 142, "label": "ready-for-human" }
  ],
  "integrationPr": null
}
```

- **Matched row** — "Every sub-issue triaged, no open integration PR" → Triage
  done → Invoke `tdd-parallel`.
- **Expected next action** — Build runs but finds no AFK slices. The
  orchestrator records each `ready-for-human` slice as a `park-and-continue`
  `hitl-slice` item, notes that no integration PR could be opened, and stops
  with a report whose READ & MERGE section has no PR link.

### EH-3: Integration PR already exists → skip Build, invoke `code-review`

An integration PR already exists when the loop starts (for example, opened by a
prior run or externally). Detection is idempotent: it lands on the Review row
and Build is not re-run.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 122, "label": "ready-for-agent" }
  ],
  "integrationPr": { "number": 130, "state": "open", "reviewed": false }
}
```

- **Matched row** — "Open integration PR exists, not yet reviewed" → Build done.
- **Expected next action** — Invoke `code-review`. The orchestrator never opens
  a second PR or re-runs `tdd-parallel`.

### EH-4: Grill has not happened → stop, park grill

The precondition gate runs once before the loop. The grill proxy is absent (no
non-trivial `CONTEXT.md` and no PRD issue), so the gate stops before the loop
begins. This is the gate-level counterpart to DT-1.

```json
{
  "grillProxyPresent": false,
  "prdIssue": null,
  "subIssues": [],
  "integrationPr": null
}
```

- **Expected next action** — **Stop** before entering the loop and park a
  `grill` item (`disposition: park-and-wait`) with the reason "requires the
  human" (Requirements 3.1, 3.2). The proxy is conservative: when in doubt it
  reads as "grill not done" so the run stops rather than automate alignment.

## Coverage summary

| Scenario | Decision-table / Error Handling row | Expected next action |
| --- | --- | --- |
| DT-1 | No grill proxy and no PRD issue | Stop — park `grill` |
| DT-2 | Grill proxy present, no PRD issue | Invoke `to-prd` |
| DT-3 | PRD issue exists, no sub-issues | Invoke `to-issues` |
| DT-4 | Sub-issues exist, one or more untriaged | Invoke `triage` |
| DT-5 | Every sub-issue triaged, no open PR | Invoke `tdd-parallel` |
| DT-6 | Open integration PR, not yet reviewed | Invoke `code-review` |
| DT-7 | Integration PR reviewed clean | Stop auto-advancement |
| DT-8 | No single row matches (contradictory) | Stop — park `phase-detection` |
| EH-1 | Ambiguous state / read failure | Stop — park `phase-detection` |
| EH-2 | No AFK slices exist | Build finds none — park HITL, no PR, stop |
| EH-3 | Integration PR already exists | Skip Build — invoke `code-review` |
| EH-4 | Grill has not happened | Stop — park `grill` (gate) |

Every decision-table row (DT-1 through DT-8) and every Error Handling row
(ambiguous, no AFK slices, PR already exists, grill missing) is covered with a
concrete `Repository_State` fixture and its expected next action.

_Requirements: 2.1, 2.3_
