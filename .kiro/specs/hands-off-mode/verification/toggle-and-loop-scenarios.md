# Toggle and Control-Loop Scenario Checks

## Purpose

This document verifies the persistent toggle mechanism and the single-session
control-loop lifecycle described in `design.md` (sections "The toggle
mechanism" and "The auto-advance control loop", plus ADR-001 and ADR-002)
against concrete fixtures, confirming that the `/hands-off` command and the
`.arc-hands-off.json` state file behave as the requirements specify.

These are example/scenario-based walkthroughs, not property tests. Per the
design Testing Strategy, this feature is markdown-driven orchestration with no
executable runtime, so there is no pure function to assert a universal property
over. Each scenario is a guided walkthrough: given a concrete starting state of
the repo-root state file, performing the named action produces the expected
file state or loop behavior.

## How to read a scenario

Each scenario provides:

- **Given** — the starting state of `.arc-hands-off.json` at the repository
  root (present with contents, or absent).
- **Action** — the `/hands-off` invocation or session event being exercised.
- **Expected** — the file state or loop behavior the orchestrator MUST produce.

The state file is the persistent representation of the toggle (Requirement 1):
present with `{"state": "on"}` means on; absent, or present with
`{"state": "off"}`, means off; absent is the default.

## Toggle behavior scenarios

### TG-1: Default-off when no state file exists

A repo that has never seen the command has no `.arc-hands-off.json`. The
orchestrator treats an absent file as off, so no setup is required for the
default.

- **Given** — `.arc-hands-off.json` is absent.
- **Action** — the workflow starts and reads the mode.
- **Expected** — the mode resolves to **off** (Requirement 1.4). The
  workflow requires the human to invoke each phase manually (Requirement 1.3);
  no control loop runs.

### TG-2: `/hands-off` (no argument) writes on

Invoking the command with no argument turns the mode on and enters the control
loop in the same session.

- **Given** — `.arc-hands-off.json` is absent (or contains `{"state": "off"}`).
- **Action** — the human invokes `/hands-off` with no argument.
- **Expected** — the orchestrator writes the file with contents
  `{"state": "on"}`, then begins the grill-first gate and, if it passes, the
  auto-advance loop (Requirement 1.5).

```json
{
  "state": "on"
}
```

### TG-3: `/hands-off off` writes off

Invoking the command with the argument `off` turns the mode off and does
nothing else — it runs no loop.

- **Given** — `.arc-hands-off.json` contains `{"state": "on"}`.
- **Action** — the human invokes `/hands-off off`.
- **Expected** — the orchestrator records the off state by writing
  `{"state": "off"}` or by deleting the file (both resolve to off), then stops
  without entering the loop (Requirement 1.6).

```json
{
  "state": "off"
}
```

### TG-4: State persists across invocations

The state lives on disk, so it survives between separate workflow invocations
until the command changes it. The mode is not re-derived or reset on each run.

- **Given** — `.arc-hands-off.json` contains `{"state": "on"}` from a prior
  `/hands-off` invocation.
- **Action** — a later, separate workflow invocation reads the mode without any
  intervening `/hands-off off`.
- **Expected** — the mode still resolves to **on** (Requirement 1.2). Only a
  subsequent `/hands-off off` changes it back to off.

## State-file isolation scenarios

### IS-1: State file is gitignored

The toggle is machine-local, per-checkout session state, not shared
configuration (ADR-001), so it must never be committed.

- **Given** — the repo-root `.gitignore` contains a `.arc-hands-off.json` entry.
- **Action** — the file is created by `/hands-off` and the working tree is
  inspected for version-control status.
- **Expected** — `.arc-hands-off.json` is ignored by Git and never appears as a
  tracked or staged change (Requirements 1.2, 1.4).

### IS-2: State file is not swept by the skill-sync hook

The skill-sync hook copies skills and the workflow steering to the global
`~/.kiro/` location. The state file lives at the repository root, outside the
hook's copy scope, so it is left untouched.

- **Given** — the skill-sync hook command copies only `.kiro/skills/*` and
  `.kiro/steering/arc-workflow.md`.
- **Action** — the hook runs while `.arc-hands-off.json` exists at the
  repository root.
- **Expected** — the hook copies the skills and `arc-workflow.md` only; the
  repo-root `.arc-hands-off.json` is neither matched nor copied, so the
  machine-local toggle never leaks into the global Kiro configuration
  (Requirement 1.2).

## Control-loop lifecycle scenario

### LL-1: When the session ends, the loop ends

The auto-advance loop runs entirely within the single Kiro session that invoked
`/hands-off`. There is no background process, daemon, or resume (ADR-002).

- **Given** — `/hands-off` is on and the auto-advance loop is mid-run inside an
  open local session.
- **Action** — the session ends (the user closes it, or the machine is shut
  down).
- **Expected** — auto-advancement stops with the session; no work continues in
  the background (Requirement 4.2). The on-disk `{"state": "on"}` persists, so a
  later `/hands-off` in a new session simply re-derives the phase from
  `Repository_State` and continues from wherever the work actually is — it does
  not resume a saved loop position.

## Coverage summary

| Scenario | Behavior verified | Requirement |
| --- | --- | --- |
| TG-1 | Default-off when no state file exists | 1.4 |
| TG-2 | `/hands-off` writes `{"state": "on"}` and enters the loop | 1.5 |
| TG-3 | `/hands-off off` writes `{"state": "off"}` (or deletes) and stops | 1.6 |
| TG-4 | State persists across invocations | 1.2 |
| IS-1 | State file is gitignored, never committed | 1.2, 1.4 |
| IS-2 | State file is not swept by the skill-sync hook | 1.2 |
| LL-1 | Session end ends the loop; no background resume | 4.2 |

Every clause in scope is covered: default-off (1.4), the two `/hands-off`
write behaviors (1.5, 1.6), persistence across invocations (1.2), gitignore and
skill-sync isolation of the state file (1.2, 1.4), and the session-bound loop
lifecycle (4.2).

_Requirements: 1.2, 1.4, 1.5, 1.6, 4.2_
