# Park-List Assembly Scenario Checks

## Purpose

This document verifies the park semantics in
`.kiro/skills/arc-handsoff/SKILL.md` by walking concrete mixed runs and
confirming that every exception is captured as a `Parked_Item` with the correct
`kind`, `disposition`, and one-line `reason`. A mixed run is the realistic case
the design calls out: some AFK slices build and merge, one HITL slice is
skipped, and one phase fails.

These are example/scenario-based walkthroughs, not property tests. Per the
design Testing Strategy, this feature is markdown-driven orchestration with no
executable runtime, so there is no pure function to assert a universal property
over. Each scenario is a guided walkthrough: given a triaged set of slices and a
run outcome, the in-memory `parked` list the orchestrator assembles MUST contain
exactly the parked items shown, each with the field values shown.

## How to read a scenario

Each scenario provides:

- **Triaged slices** — the sub-issues and their triage labels as Build sees
  them, so it is clear which are AFK (`ready-for-agent`) and which are HITL
  (`ready-for-human`).
- **Run outcome** — what happens as the orchestrator advances: which AFK slices
  merge, which HITL slice is skipped, and which phase fails.
- **Resulting parked list** — the authoritative in-memory `parked` list when the
  run stops, rendered as an array of `Parked_Item` records.
- **Assertions** — the `kind`, `disposition`, and one-line `reason` each parked
  item MUST carry.

The `Parked_Item` shape follows the record in `SKILL.md`: `kind` (one of
`hitl-slice`, `afk-incomplete`, `phase-failure`, `review-blocker`,
`decision-deferred`), `ref` (an issue reference `#N` for slice-level items or a
phase name for phase-level items), `reason` (a single line), and `disposition`
(`park-and-continue` or `park-and-wait`).

## Scenario PL-1: AFK merged, HITL skipped, Build cannot finish one AFK slice

A run where Build does most of the automatable work, skips the one human-only
slice, and then genuinely cannot bring one AFK slice to a passing state. This is
the primary mixed run and covers the park-and-continue HITL path (Requirement
5.3) and the park-and-wait `afk-incomplete` path (Requirement 6.2) in one
walkthrough.

### Triaged slices

```json
[
  { "number": 121, "label": "ready-for-agent" },
  { "number": 122, "label": "ready-for-agent" },
  { "number": 123, "label": "ready-for-agent" },
  { "number": 142, "label": "ready-for-human" }
]
```

### Run outcome

- Every slice is triaged and no integration PR is open, so detection invokes
  `tdd-parallel` (Build).
- `tdd-parallel` filters the `ready-for-human` slice (#142) out of its fan-out
  and builds only the AFK slices. The orchestrator records #142 as a skipped
  HITL slice and keeps going (Requirements 5.1, 5.2).
- AFK slices #121 and #122 reach passing and merge into the integration branch.
- AFK slice #123 cannot be brought to a passing state. The orchestrator records
  it as an `afk-incomplete` parked item, stops auto-advancement, and does not
  retry Build in this session (Requirements 6.2, 6.4).

### Resulting parked list

```json
[
  {
    "kind": "hitl-slice",
    "ref": "#142",
    "reason": "Requires manual OAuth app registration before implementation",
    "disposition": "park-and-continue"
  },
  {
    "kind": "afk-incomplete",
    "ref": "#123",
    "reason": "Tests for the rate-limiter slice still fail after the build attempt",
    "disposition": "park-and-wait"
  }
]
```

### Assertions

- The HITL slice #142 is captured with `kind` `hitl-slice`, `disposition`
  `park-and-continue`, and a one-line reason explaining why it needs a human.
  Parking it did not stop the run; #121 and #122 still built and merged
  (Requirements 5.1, 5.2, 5.3).
- The unfinished AFK slice #123 is captured with `kind` `afk-incomplete`, `ref`
  the slice issue `#123`, and a one-line reason for why Build could not finish
  it (Requirement 6.2). Its `disposition` is `park-and-wait`: recording it
  stopped auto-advancement, and Build is not retried this session (Requirement
  6.4).
- The completed AFK slices #121 and #122 are **not** parked — they are the DID
  contents, not exceptions.

## Scenario PL-2: AFK merged, HITL skipped, Review flags a blocker

A run where Build succeeds entirely — the AFK slices merge and the integration
PR opens — the one HITL slice is skipped, and the failure surfaces later, in
Review. Because a `park-and-wait` failure stops the run, a Build failure and a
Review blocker cannot both occur in the same run; this scenario is the
counterpart to PL-1 that exercises the `review-blocker` path (Requirement 6.3).

### Triaged slices

```json
[
  { "number": 121, "label": "ready-for-agent" },
  { "number": 122, "label": "ready-for-agent" },
  { "number": 142, "label": "ready-for-human" }
]
```

### Run outcome

- Build runs: #142 is skipped as a HITL slice and recorded; #121 and #122 reach
  passing and merge. `tdd-parallel` opens the single integration PR #130 with
  `Closes #120` and stops, preserving the merge-stop.
- Detection lands on the "open integration PR, not yet reviewed" row and invokes
  `code-review` (Review).
- `code-review` flags a blocking issue. The orchestrator records a
  `review-blocker` parked item, stops auto-advancement, and does not apply the
  fix autonomously (Requirement 6.3).

### Resulting parked list

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

### Assertions

- The HITL slice #142 is captured with `kind` `hitl-slice`, `disposition`
  `park-and-continue`, and a one-line reason — identical handling to PL-1, and
  again it did not stop the run (Requirements 5.1, 5.2, 5.3).
- The review finding is captured with `kind` `review-blocker`, `ref` the phase
  name `review`, a one-line reason describing the blocker, and `disposition`
  `park-and-wait` (Requirement 6.3). Recording it stopped auto-advancement; the
  orchestrator did not fix the finding itself.
- The completed AFK slices #121 and #122 and the integration PR #130 are the DID
  contents, not parked items.

## Field-shape assertions across both scenarios

Across PL-1 and PL-2, every assembled `Parked_Item` satisfies the shape rules
from `SKILL.md`:

- **`kind`** is drawn only from the fixed set `hitl-slice`, `afk-incomplete`,
  `phase-failure`, `review-blocker`, `decision-deferred`. No new kind is
  invented for any exception.
- **`disposition`** is exactly one of `park-and-continue` or `park-and-wait`,
  and it matches the kind's behavior: HITL slices continue the run; an
  `afk-incomplete` slice or a `review-blocker` stops it.
- **`reason`** is a single line in every item, suitable for one bullet in the
  `PARKED` section of the `Hands_Off_Report` (Requirements 5.3, 6.2, 6.3).
- **`ref`** is an issue reference (`#N`) for slice-level items (`hitl-slice`,
  `afk-incomplete`) and a phase name for phase-level items (`review-blocker`
  uses `review`).
- The in-memory `parked` list is the authoritative source for the report; no new
  GitHub label is added beyond the `ready-for-human` marker the HITL slice
  already carries.

## Coverage summary

| Scenario | Parked item | kind | disposition | Requirement |
| --- | --- | --- | --- | --- |
| PL-1 | HITL slice #142 skipped | `hitl-slice` | `park-and-continue` | 5.3 |
| PL-1 | AFK slice #123 unfinished | `afk-incomplete` | `park-and-wait` | 6.2 |
| PL-2 | HITL slice #142 skipped | `hitl-slice` | `park-and-continue` | 5.3 |
| PL-2 | Review blocker | `review-blocker` | `park-and-wait` | 6.3 |

Both mixed runs confirm that every parked item is captured with the correct
`kind`, `disposition`, and one-line `reason`, that park-and-continue HITL slices
never stop the run while park-and-wait failures do, and that completed AFK slices
are reported as DID contents rather than parked.

_Requirements: 5.3, 6.2, 6.3_
