---
name: arc-handsoff
description: Persistent on/off toggle that lets the Arc orchestrator auto-advance through the mechanical middle phases (PRD, Issues, Triage, Build, Review) while you are away from the keyboard. Use when the user wants to run the workflow unattended for a short window, says "hands off", or invokes "/hands-off".
argument-hint: "off — to turn the mode off (no argument turns it on)"
---

# Hands-Off Mode

Hands-off mode is a persistent on/off toggle for the Arc engineering pipeline, engaged via the `/hands-off` command. When off, the workflow behaves as it does today: the human invokes each phase manually and acts as the scheduler between phases. When on, the orchestrator reads repository and board state to determine the current phase and auto-advances through the mechanical middle phases (PRD, Issues, Triage, Build, Review) without the human invoking each one.

The mode exists to cover a short away-from-keyboard window (roughly a dinner or laundry cycle) on the user's local machine while the machine stays on and the session stays open. It is markdown-driven orchestration: there is no compiled code, no daemon, and no background process. The orchestrator runs turn-by-turn inside the single open Kiro session that invoked `/hands-off`, chaining skill invocations across turns without stopping to ask the user.

Two human-only boundaries are preserved by design: alignment is reached through the Grill phase **before** the mode is engaged, and the integration pull request is opened but **never merged**.

## Naming

The name "hands-off" is deliberately distinct from Kiro's tool-approval autonomy mode. Kiro's autonomy mode governs whether individual tool calls are auto-approved; hands-off mode governs whether the Arc workflow auto-advances between phases. The two are unrelated and can be set independently.

## The toggle

The toggle is represented by a single repo-local state file, `.arc-hands-off.json`, at the repository root.

- **On** — the file exists and contains `{"state": "on"}`.
- **Off** — the file is absent, or it contains `{"state": "off"}`.
- **Default** — absent means off, so a repo that has never seen the command defaults to off with no setup.
- **Persistence** — the file lives on disk, so the selected state survives across workflow invocations until the command changes it.

The file is machine-local session state, not shared configuration. It is gitignored and must never be committed.

## The `/hands-off` command

- `/hands-off` (no argument) → write `{"state": "on"}` to `.arc-hands-off.json`, then enter the auto-advance control loop in the same session.
- `/hands-off off` → write `{"state": "off"}` to `.arc-hands-off.json` (or delete the file), then stop and do nothing else.

## Repository_State read model

GitHub is the de-facto state machine. The orchestrator keeps no private progress counter; on each loop iteration it re-derives the current phase by reading `Repository_State` — the combination of the board `Status` column, triage labels, and pull request state — fresh from GitHub via the `gh` CLI. This section defines only the reads that assemble `Repository_State`; the state→phase decision table that consumes it is documented separately.

Resolve these canonical values at runtime before issuing any GraphQL read, so no ID or label string is ever guessed or duplicated. Read each value from its source file on every run — these files are the single source of truth, so the skill never pins copies that could drift out of sync:

- **Project node ID, `Status` field ID, and option IDs** — read from `docs/agents/project-board.md` (the `Project` and `Status field` sections). Do not hardcode these IDs in the skill; resolve them from that file each run, because they change if the board is recreated.
- **Triage label strings** — read from `docs/agents/triage-labels.md` (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `tracking`, `wontfix`).
- **`gh` CLI usage** for issues, comments, and labels follows `docs/agents/issue-tracker.md`. `gh` infers the owner and repo from the clone's `git remote`, so the reads below need no owner/repo hardcoded; where a GraphQL query names them explicitly, take them from `docs/agents/project-board.md`.

### Reads performed each iteration

1. **The PRD (`tracking`) issue.** Find the container issue for this work, or confirm its absence.

   ```bash
   gh issue list --label tracking --state open \
     --json number,title,labels \
     --jq '[.[] | {number, title, labels: [.labels[].name]}]'
   ```

   Zero results means no PRD issue exists yet; one result is the PRD issue whose number (`<prd>`) feeds the reads below.

2. **The PRD issue's sub-issues and each one's triage label.** Used to tell Issues from Triage from Build.

   ```bash
   gh api graphql -f query='
     query($owner:String!, $repo:String!, $n:Int!) {
       repository(owner:$owner, name:$repo) {
         issue(number:$n) {
           subIssues(first:50) {
             nodes {
               number
               title
               labels(first:10) { nodes { name } }
             }
           }
         }
       }
     }' -F owner="$(gh repo view --json owner --jq .owner.login)" \
        -F repo="$(gh repo view --json name --jq .name)" -F n=<prd>
   ```

   For each sub-issue, read its triage label against the canonical strings above: a slice is triaged once it carries `ready-for-agent` (an `AFK_Slice`) or `ready-for-human` (a `HITL_Slice`); a slice still carrying `needs-triage`/`needs-info` or no triage label is untriaged.

3. **The open integration PR.** The single consolidated PR whose body closes the PRD issue.

   ```bash
   gh pr list --state open \
     --search "Closes #<prd> in:body" \
     --json number,title,body,reviewDecision \
     --jq '[.[] | {number, title, reviewDecision}]'
   ```

   Its presence means Build has shipped; `reviewDecision` (for example `APPROVED`) indicates whether Review has completed.

4. **The board `Status` of the PRD issue.** Read the issue's project item Status, filtering to the configured project node ID, and map the returned option ID against the option IDs above.

   ```bash
   gh api graphql -f query='
     query($owner:String!, $repo:String!, $n:Int!) {
       repository(owner:$owner, name:$repo) {
         issue(number:$n) {
           projectItems(first:20) {
             nodes {
               project { id }
               fieldValueByName(name:"Status") {
                 ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
               }
             }
           }
         }
       }
     }' -F owner="$(gh repo view --json owner --jq .owner.login)" \
        -F repo="$(gh repo view --json name --jq .name)" -F n=<prd>
   ```

   Keep only the item whose `project.id` equals the project node ID read from `docs/agents/project-board.md`; if no item matches, treat the board Status as unknown and rely on the label and PR reads. The board sync is best-effort per `docs/agents/project-board.md`, so labels and PR state remain the primary signals.

5. **The grill-complete proxy.** Whether alignment has been reached is inferred from a local file, not a `gh` read: the presence of a non-trivial `CONTEXT.md` at the repository root (or, equivalently, an existing PRD `tracking` issue). A missing or trivially empty `CONTEXT.md` with no PRD issue means grill is not done. This proxy is conservative — when in doubt it should read as "grill not done" so the run stops rather than automate alignment.

### Treating a read failure as ambiguous

These reads are the orchestrator's only window into "where are we." If any `gh` or `gh api graphql` read fails — network error, authentication failure, or an API error — the orchestrator cannot reliably determine the phase. It MUST NOT guess or proceed on a partial read. A read failure is treated as an **ambiguous state**: the orchestrator stops auto-advancement and parks a `phase-detection` item with the read failure as the one-line reason. The decision-table row for the ambiguous state and the park-and-stop behavior are defined with the control loop.

### Conceptual Repository_State shape

The reads above are assembled into a single conceptual record consumed by the decision table. It is never stored — it is re-derived every iteration.

```json
{
  "grillProxyPresent": true,
  "prdIssue": { "number": 120, "labels": ["tracking"] },
  "subIssues": [
    { "number": 121, "label": "ready-for-agent" },
    { "number": 142, "label": "ready-for-human" }
  ],
  "integrationPr": { "number": 130, "state": "open", "reviewed": false }
}
```

- `grillProxyPresent` — whether a non-trivial `CONTEXT.md` or an existing PRD issue indicates grill is done.
- `prdIssue` — the `tracking`-labelled PRD issue, or `null` if none exists.
- `subIssues` — each slice and its triage label, used to decide Issues vs Triage vs Build.
- `integrationPr` — the open integration PR and whether it has been reviewed, used to decide Build vs Review vs stop.

## State to phase decision table

Each loop iteration, the orchestrator classifies the freshly-read `Repository_State` against the table below and takes the single matching next action. The reads that assemble `Repository_State` are defined in the previous section; this table is the consumer that turns those reads into a decision.

| Observed Repository_State | Current phase | Next action |
| --- | --- | --- |
| No `CONTEXT.md` (or trivially empty) **and** no PRD issue | Grill not done | **Stop** — park `grill` as "requires the human" (Requirement 3.2) |
| Grill proxy present, no PRD issue exists | Ready to start | Invoke `to-prd` — begin at PRD (Requirement 3.3) |
| PRD issue exists, has no sub-issues | PRD done | Invoke `to-issues` |
| Sub-issues exist, one or more still untriaged (carry `needs-triage`/`needs-info` or no triage label) | Issues done | Invoke `triage` |
| Every sub-issue triaged (`ready-for-agent` or `ready-for-human`), no open integration PR | Triage done | Invoke `tdd-parallel` (Build) |
| Open integration PR exists, not yet reviewed | Build done | Invoke `code-review` (Review) |
| Integration PR reviewed clean (Review completed) | Review done | **Stop** auto-advancement (Requirement 2.4) |
| State matches no row, or matches more than one row in a contradictory way | Ambiguous | **Stop** — park `phase-detection` as "ambiguous state" |

The orchestrator always advances in the fixed order PRD → Issues → Triage → Build → Review (Requirement 2.3). It never skips forward past an incomplete phase or jumps backward to redo a completed one within a single decision; it takes exactly the one next action the matching row prescribes.

### Re-derived every iteration: idempotent and self-correcting

The next action is re-derived from `Repository_State` on every loop iteration, never from a remembered position. Because the table keys off what actually exists in GitHub rather than a private progress counter, a phase that has already completed is simply skipped — its work is already reflected in the state, so detection lands on a later row.

For example, if an integration PR already exists when the loop starts, detection lands on the "Build done" row and `tdd-parallel` is never re-run; the orchestrator advances straight to `code-review`. Likewise, sub-issues that already exist move detection past the "PRD done" row without re-invoking `to-prd`. This makes auto-advancement idempotent (re-reading the same state yields the same decision) and self-correcting (work the human did between turns, or an externally-opened PR, is picked up on the next read with no special handling).

When the state genuinely matches no single row — a read failed (see the previous section), or the signals contradict each other (for example, sub-issues that still need triage alongside an open integration PR whose `Closes` set does not match them) — the orchestrator does not guess. It treats the situation as the ambiguous row: it stops auto-advancement and parks a `phase-detection` item rather than risk taking a wrong action while the human is away.

## Grill-first precondition gate

Alignment is a human-only boundary: the Grill phase is **excluded from auto-advancement** and is never invoked by the orchestrator (Requirement 3.1). To enforce this, the orchestrator runs a single grill-first precondition gate **once, before the control loop** — not inside it. The gate can only do one of two things: stop the run, or let auto-advancement begin. It never runs grill.

This gate is the first thing `/hands-off` (no argument) does after writing `{"state": "on"}`. It runs before any `Repository_State` decision-table iteration.

### The gate check

The gate consults the grill-complete proxy defined in the Repository_State read model (read 5): a non-trivial `CONTEXT.md` at the repository root, or an existing PRD `tracking` issue, indicates grill has reached shared understanding. A missing or trivially empty `CONTEXT.md` with no PRD issue means grill is not done. The proxy is conservative: when in doubt it reads as "grill not done" so the run stops rather than automate alignment.

### When the proxy is absent: park-and-wait, report, return

If the grill proxy is absent, alignment has not been reached, so the orchestrator MUST stop before the loop and record that the Grill phase requires the human (Requirement 3.2). It:

1. Parks a phase-level item for grill with the `park-and-wait` disposition — `kind` `phase-failure`, `ref` `grill`, and the one-line reason "Grill has not reached shared understanding; alignment needs the human". (The `Parked_Item` shape and the two dispositions are defined with the park semantics.)
2. Produces a single `Hands_Off_Report` whose run-stopped reason is the grill gate, so the human sees why nothing auto-advanced.
3. Returns. It does **not** enter the control loop, and it never invokes grill — alignment stays a human-only step.

```text
# Grill-first precondition gate (Req 3.1, 3.2) — runs once, before the loop
if not grill_complete_proxy():
    park(kind="phase-failure", ref="grill",
         reason="Grill has not reached shared understanding; alignment needs the human",
         disposition="park-and-wait")
    report()
    return    # never enter the loop, never invoke grill
```

### When the proxy is present: begin at PRD

If the grill proxy is present, alignment exists and the gate passes. The orchestrator begins auto-advancement at the PRD phase (Requirement 3.3): it falls through into the in-session auto-advance control loop, whose first decision-table iteration lands on the "Ready to start" row and invokes `to-prd`. The grill gate itself takes no phase action beyond letting the loop start.

The in-session control loop that runs after this gate passes — reading `Repository_State`, advancing through PRD → Issues → Triage → Build → Review, and stopping on completion, failure, or an ambiguous state — is documented separately.

## The auto-advance control loop

Once the grill-first precondition gate passes, `/hands-off` (no argument) falls through into this loop. It is the heart of hands-off mode: read state, detect phase, take the one next action, re-read, and repeat until a stop condition fires. The loop owns no domain logic — it reads `Repository_State`, picks the next phase from the decision table, and delegates the actual work to the existing phase skills, exactly as a human would between phases.

### Where the loop runs: one open local session

The loop runs entirely within the single, uninterrupted Kiro session in which the user invoked `/hands-off` on their local machine (Requirement 4.1). It advances turn-by-turn inside that session; "hands-off" means the orchestrator chains skill invocations across turns without stopping to ask, not that anything runs in the background.

There is no daemon, no cron, no headless runner, and no resume-after-close:

- The loop runs **only** because the user started it in an open, interactive local session (Requirement 4.3). It never starts itself.
- When that session ends — the user closes it, the machine sleeps, or the turn budget runs out — the loop ends with it (Requirement 4.2). Nothing continues in the background.
- There is no saved loop position to resume. A later `/hands-off` simply re-derives the phase from `Repository_State` (see the decision table) and continues from wherever the work actually is, because GitHub, not the loop, holds the progress.

### Each iteration

On every pass the orchestrator performs the same four steps, in order:

1. **Read state.** Re-derive `Repository_State` fresh from GitHub via the `gh` reads in the Repository_State read model. Never reuse a remembered position; a read failure is treated as ambiguous (below).
2. **Detect phase.** Classify the freshly-read state against the state-to-phase decision table to get exactly one next action.
3. **Check the stop conditions.** If detection is the Review-complete row, stop auto-advancement (Requirement 2.4). If detection is the ambiguous row, park a `phase-detection` item and stop (see below). Otherwise continue to step 4.
4. **Invoke the next phase skill in-session.** Invoke the single skill the matching row prescribes — `to-prd`, `to-issues`, `triage`, `tdd-parallel`, or `code-review` — directly in this session, with no human prompt and no waiting for a human to pull the trigger (Requirement 2.2). When it returns, loop back to step 1.

Because the next action is re-derived from state every iteration, the orchestrator always advances in the fixed order PRD → Issues → Triage → Build → Review (Requirement 2.3), and an already-completed phase is naturally skipped — its work is already reflected in the state, so detection lands on a later row.

### The loop never blocks on a question

While the human is away the orchestrator's posture is **stop safely and park, never guess and never thrash.** It never blocks on a question and never makes a decision that needs the absent human's judgment. Any such decision becomes a `Parked_Item` that the orchestrator records and then declines to make (Requirement 5.4); it does not pause mid-loop to ask. Two things can stop the loop:

- **Review complete** — the clean exit. Detection lands on the Review-done row and the loop breaks (Requirement 2.4).
- **Ambiguous state** — the safe exit. Detection matches no single row, or a `gh` read failed, so the orchestrator parks a `phase-detection` item (`park-and-wait`) and breaks rather than risk a wrong action while the human is away.

Park-and-continue for skipped HITL slices and park-and-wait for a genuine phase failure are also collected as the loop runs; the `Parked_Item` shape and the two dispositions are defined with the park semantics, and the `park(...)` calls below are placeholders for them.

### Loop pseudocode

This mirrors the gate-then-loop structure: the grill gate (documented above) runs once and can only stop or fall through; the loop below runs only after it falls through.

```text
# Runs only after the grill-first gate passes — in the one open local session (Req 4.1, 4.3)
parked = []                                 # in-session source of truth for the report

loop:
    state = read_repository_state()         # gh + gh api graphql      (Req 2.1)
    phase = detect_phase(state)             # decision table           (Req 2.3)

    if phase == REVIEW_COMPLETE:            # clean exit               (Req 2.4)
        break
    if phase == AMBIGUOUS:                  # safe exit (read failed / contradictory)
        parked += park(kind="phase-failure", ref="phase-detection",
                       reason="Repository_State did not match a single known phase",
                       disposition="park-and-wait")
        break

    result = invoke_skill(next_skill(phase))    # in-session, no human prompt (Req 2.2)

    parked += result.parked_items           # park-and-continue: skipped HITL slices

    if result.failed:                       # park-and-wait: a phase genuinely failed
        parked += park(kind="phase-failure", ref=phase,
                       reason=result.failure_reason,
                       disposition="park-and-wait")
        break                               # never retry this phase this session

report(parked)                              # single Hands_Off_Report when the loop stops
```

When the session ends before the loop reaches a stop condition, the loop simply stops where it is (Requirement 4.2); no report is forced and no background work continues. The `Hands_Off_Report` assembly that runs when the loop stops on its own — Review complete, ambiguous state, or a parked phase failure — is documented separately.

## Park semantics

While the human is away the orchestrator never blocks and never thrashes: rather than stopping to ask or retrying a failing phase, it records the exception as a `Parked_Item` and then either keeps going or stops, depending on the kind of exception. This section defines the `Parked_Item` shape and the two dispositions that the grill-first gate and the control loop referenced above as placeholders.

### The Parked_Item shape

Every parked exception — a skipped HITL slice, an incomplete AFK slice, a failed phase, a review blocker, or a deferred decision — is recorded as a single in-memory `Parked_Item` with exactly four fields:

```json
{
  "kind": "hitl-slice",
  "ref": "#142",
  "reason": "Requires manual OAuth app registration before implementation",
  "disposition": "park-and-continue"
}
```

- `kind` — one of `hitl-slice`, `afk-incomplete`, `phase-failure`, `review-blocker`, `decision-deferred`. These are the only kinds; do not invent new ones.
- `ref` — an issue reference (`#N`) for slice-level items, or a phase name (`grill`, `build`, `review`, `phase-detection`) for phase-level items.
- `reason` — a single-line explanation, suitable for one bullet in the report (Requirements 5.3, 6.2, 6.3).
- `disposition` — either `park-and-continue` or `park-and-wait`. The disposition decides whether the loop keeps going or stops.

### The two dispositions

The orchestrator distinguishes exactly two dispositions, and every `Parked_Item` carries one of them.

#### Park-and-continue — HITL slices

`park-and-continue` is used for human-only slices encountered during Build. A slice carrying the `ready-for-human` label is a `HITL_Slice`: it needs a human to implement it, so the orchestrator must never attempt it while the human is away. `tdd-parallel` already filters `[HITL]` / `ready-for-human` slices out of its fan-out and builds only the `ready-for-agent` AFK slices, so the orchestrator records what Build skipped rather than skipping slices itself.

For each skipped HITL slice the orchestrator:

1. Records a `Parked_Item` with `kind` `hitl-slice`, `ref` the slice issue (`#N`), a one-line reason for why it needs a human, and `disposition` `park-and-continue` (Requirements 5.1, 5.3).
2. Keeps building the remaining AFK slices — parking a HITL slice never stops the run, so automatable work still gets done while the human is gone (Requirement 5.2).

A decision that genuinely needs the absent human's judgment is handled the same way: the orchestrator records a `Parked_Item` with `kind` `decision-deferred` and declines to make the decision rather than guessing, again without stopping the run (Requirement 5.4).

#### Park-and-wait — genuine phase failure

`park-and-wait` is used for a genuine phase failure, where the current phase cannot proceed. Three situations trigger it:

- A middle phase errored outright — recorded with `kind` `phase-failure` and `ref` the phase name (Requirement 6.1).
- The Build phase could not bring an AFK slice to a passing state — recorded with `kind` `afk-incomplete`, `ref` the slice issue (`#N`), and a one-line reason (Requirement 6.2).
- The Review phase flagged a blocking issue — recorded with `kind` `review-blocker`, `ref` `review`, and a one-line reason (Requirement 6.3).

On any of these the orchestrator records the `Parked_Item` with `disposition` `park-and-wait`, then **stops auto-advancement** at that phase (Requirement 6.1). It MUST NOT retry the failed phase during the same session (Requirement 6.4): the loop breaks and the run ends with a report. The safe default holds — when a phase cannot proceed, stopping beats guessing while the human is away.

### Where parked items are recorded

- **In-memory during the session is authoritative.** The in-session `parked` list — the one the grill-first gate and the control loop append to — is the single source of truth for the `Hands_Off_Report`. It is the only record guaranteed correct regardless of network state, so the report is always rendered from it.
- **GitHub mirrors are durable but secondary.** A HITL slice already carries the `ready-for-human` label as its natural park marker; the orchestrator invents **no** new label and adds none. Every parked item is also written into the `PARKED` section of the `Hands_Off_Report`, which survives the session ending. These mirrors exist for the returning human; the in-memory list is what the report is built from.
## Merge-stop preservation

The merge stays the human's decision, in both modes. Hands-off mode adds **no** merge or push capability of its own: the orchestrator never calls `git merge`, never pushes to the `Default_Branch`, and never merges a pull request. Shipping is delegated entirely to the Build phase, which follows the merge-stop convention in `docs/agents/ship-style.md` — open the integration PR with `Closes #<prd>` in the body, then stop and leave the merge to the human.

### Shipping is delegated to tdd-parallel

When Build completes its automatable AFK slices, `tdd-parallel` does the shipping exactly as it does in a manual run: it pushes the integration branch and opens the single integration PR with `Closes #<prd>` in the body, then stops per `docs/agents/ship-style.md` (Requirement 7.1). The orchestrator invokes `tdd-parallel` like any other phase skill (see the control loop) and adds nothing to this path — no extra push, no second PR, no merge step.

### The orchestrator only reads PR state

After Build ships, the orchestrator's only interaction with the integration PR is to **read** it: it reads the open PR (and its `reviewDecision`) as part of `Repository_State` to decide whether to advance to Review, exactly as the decision table prescribes. It leaves the integration PR **unmerged** (Requirement 7.2) and never pushes to the `Default_Branch` (Requirement 7.3). Nothing the orchestrator does moves code onto the default branch; the merge-stop is a hard boundary it reads up to but never crosses.

### Identical whether the mode is on or off

Because the orchestrator reuses the same `tdd-parallel` → `ship-style` path that a manual run uses, the merge-stop applies identically whether hands-off mode is on or off (Requirement 7.4). The only difference between the two modes is who pulls the trigger to start Build — the human when off, the orchestrator when on — and that difference ends at the integration PR. From the opened PR onward the behavior is the same in both modes: the PR is left for the human to review and merge, and the `Hands_Off_Report`'s READ & MERGE section points there so the merge remains a deliberate human action.

## The Hands_Off_Report

When auto-advancement stops, the orchestrator produces exactly one `Hands_Off_Report` — the single come-back artifact the returning human reads to see what happened (Requirement 8.1). This section resolves the `report()` placeholder referenced by the grill-first gate, the control loop, and the park semantics above.

### Produced whenever auto-advancement stops

The report is produced for **every** way the run can stop — there is no exit path that does not end in a report:

- **Review complete** — the clean exit. The loop's decision table landed on the Review-done row and broke (Requirement 2.4).
- **Phase failure** — a middle phase errored, Build could not bring an AFK slice to passing, or Review flagged a blocker, so a `park-and-wait` item was recorded and the loop broke (Requirement 6).
- **Grill gate** — the grill-first precondition gate found no alignment, parked `grill`, and returned before the loop ever started (Requirement 3.2).
- **Ambiguous state** — a `gh` read failed or the signals contradicted each other, so a `phase-detection` item was parked and the loop broke.

The one exception is the session ending mid-loop (Requirement 4.2): if the user closes the session or the machine sleeps before a stop condition fires, the loop simply stops where it is and no report is forced — there is no background process to assemble one. A report is produced only when the run reaches one of the stop conditions above while the session is still open.

### What the report is built from

The report is assembled from two sources, both already gathered during the run:

- The **run's results** — the completed AFK slices and the integration PR — read back from the merged slice list and the PR body.
- The **in-memory `parked` list** — the authoritative source of truth the grill gate and control loop appended to (see the park semantics). The report is always rendered from this list, never re-derived from GitHub, so it is correct regardless of network state.

### The three sections

Every report has exactly three sections, in this order:

1. **DID** — the completed AFK slices and the contents of the integration PR (Requirement 8.2). The integration PR line shows the PR URL, or `none opened` when the run stopped before Build shipped (for example, the grill gate). The slices are listed from the merged slice list, one bullet per slice.
2. **PARKED** — every parked item from the in-memory list: each skipped HITL slice (`park-and-continue`) and each failed phase (`park-and-wait`), each rendered as one bullet with its one-line reason (Requirement 8.3).
3. **READ & MERGE** — the link to the integration PR so the human can review and merge from their phone (Requirement 8.4), plus the reminder that nothing reached the default branch.

If a section has no entries, it states `None` rather than being omitted, so the human can tell the difference between "nothing was done / parked" and "the report was truncated." A grill-gate stop, for example, renders DID as `None` (nothing ran) and PARKED with the single grill item.

### Report markdown template

The orchestrator renders the report from this exact template, filling the placeholders from the run's results and the parked list:

```markdown
## Hands-Off Report

Run stopped: <reason — Review complete | phase failure | grill gate | ambiguous state>
Stopped at: <ISO-8601 timestamp>

### DID

Integration PR: <url or "none opened">

Completed AFK slices (merged into the integration branch):

- #<n> — <slice title>
- #<n> — <slice title>

### PARKED

- [HITL] #<n> — <slice title> — <one-line reason>
- [FAILED: <phase>] — <one-line reason>

### READ & MERGE

- Review and merge: <integration PR url>
- Nothing reached the default branch; the merge is yours.
```

When a section has no entries, replace its body with the single line `None`. For example, a run with no parked items renders the PARKED section as just `None`, and a grill-gate stop renders the DID slice list as `None` and `Integration PR: none opened`.

### Where the report is posted

The report is posted to GitHub so it survives the session ending and the human can read it from their phone. The **PRD issue is the primary target**: it is stable across the whole run and exists even when no PR was opened (for example, when the grill gate stops the run before Build). Post the report as a comment on the PRD issue, following `docs/agents/issue-tracker.md`:

```bash
gh issue comment <prd> --body-file hands-off-report.md
```

Use `--body-file` (writing the rendered markdown to a temporary file first) rather than `--body` so the multi-line report, code spans, and bullet lists survive shell quoting intact.

#### Fallback to the integration PR body

If the PRD issue cannot be resolved — no `tracking` issue was found, or the comment post fails — fall back to writing the report into the integration PR body instead (Requirement 8.5):

```bash
gh pr edit <integration-pr> --body-file hands-off-report.md
```

The fallback only applies when an integration PR exists. If neither the PRD issue nor an integration PR can be resolved (for example, a grill-gate stop with no PRD issue), the orchestrator surfaces the report in-session as its final message so the run is never left without a come-back artifact.
