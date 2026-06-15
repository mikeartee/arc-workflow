# Requirements Document

## Introduction

Hands-off mode is a persistent on/off toggle for the arc-workflow engineering pipeline, engaged via the `/hands-off` command. When off, the workflow behaves as it does today: the human invokes each of the seven phases manually, acting as the scheduler between phases. When on, the orchestrator reads repository and board state to determine the current phase and automatically advances through the mechanical middle phases (PRD, Issues, Triage, Build, Review) without the human invoking each one.

The mode exists to cover a short away-from-keyboard window (roughly a dinner or laundry cycle) on the user's local machine while the machine stays on and the session stays open. It deliberately preserves two human-only boundaries: alignment is reached through the Grill phase before the mode is engaged, and the integration pull request is opened but never merged. Because the human is absent while the mode runs, the orchestrator never blocks on questions and never makes decisions requiring human judgment; instead it parks exceptions and keeps going where it safely can, then reports back through a come-back artifact stored in GitHub.

## Glossary

- **Hands_Off_Mode**: The persistent on/off toggle named "hands-off" that controls whether the workflow auto-advances, toggled via the `/hands-off` command. The name is deliberately distinct from Kiro's tool-approval autonomy mode.
- **Hands_Off_Command**: The `/hands-off` slash command used to toggle Hands_Off_Mode. Invoking `/hands-off` with no argument turns the mode on; invoking `/hands-off off` turns the mode off.
- **Orchestrator**: The arc-workflow component that, while Hands_Off_Mode is on, detects the current phase from repository state and invokes the next phase's skill automatically.
- **Middle_Phases**: The five mechanical phases the Orchestrator may auto-advance through, in order: PRD (to-prd), Issues (to-issues), Triage (triage), Build (tdd-parallel), Review (code-review).
- **Grill_Phase**: Phase 1 (grill-with-docs), the alignment phase that requires the human and is never automated.
- **Repository_State**: The combination of the GitHub Projects v2 board Status column, triage labels, and pull request state that the Orchestrator reads to determine the current phase.
- **AFK_Slice**: A slice issue carrying the `ready-for-agent` triage label, eligible for autonomous TDD execution.
- **HITL_Slice**: A slice issue carrying the `ready-for-human` triage label, requiring human implementation.
- **Parked_Item**: An AFK_Slice that could not be completed, a HITL_Slice that was skipped, or a phase that failed, each recorded for the human to action on return.
- **Park_And_Continue**: Recording an item as parked and proceeding with remaining automatable work.
- **Park_And_Wait**: Recording an item as parked and stopping further auto-advancement.
- **Merge_Stop**: The ship-style rule by which the workflow opens the integration pull request and stops, leaving the merge to the human.
- **Integration_PR**: The single consolidated pull request that tdd-parallel opens for the completed AFK_Slices.
- **Hands_Off_Report**: The come-back artifact summarizing what was done, what was parked, and where to read and merge.
- **Default_Branch**: The repository's main branch (for example `main` or `master`).

## Requirements

### Requirement 1: Persistent mode toggle

**User Story:** As a developer, I want a persistent hands-off toggle, so that I can choose between driving the workflow manually and letting it auto-advance while I am away.

#### Acceptance Criteria

1. THE Hands_Off_Mode SHALL expose a toggle named "hands-off" with exactly two states: on and off.
2. THE Hands_Off_Mode SHALL persist the selected state across workflow invocations until the state is changed.
3. WHILE Hands_Off_Mode is off, THE Orchestrator SHALL require the human to invoke each phase manually.
4. WHEN the workflow starts and no state has been set, THE Hands_Off_Mode SHALL default to off.
5. WHEN the Hands_Off_Command is invoked with no argument, THE Hands_Off_Mode SHALL set its state to on.
6. WHEN the Hands_Off_Command is invoked with the argument "off", THE Hands_Off_Mode SHALL set its state to off.

### Requirement 2: State-based phase detection and auto-advancement

**User Story:** As a developer, I want the workflow to figure out where it is and move itself forward, so that the middle phases run without me invoking each one.

#### Acceptance Criteria

1. WHILE Hands_Off_Mode is on, THE Orchestrator SHALL determine the current phase by reading Repository_State.
2. WHILE Hands_Off_Mode is on AND the current phase is a Middle_Phase that has completed, THE Orchestrator SHALL invoke the next Middle_Phase skill without human invocation.
3. WHILE Hands_Off_Mode is on, THE Orchestrator SHALL advance through the Middle_Phases in the order PRD, Issues, Triage, Build, Review.
4. WHEN the Review phase completes, THE Orchestrator SHALL stop auto-advancement.

### Requirement 3: Grill-first precondition

**User Story:** As a developer, I want alignment reached before automation begins, so that the mode only automates mechanical work after shared understanding exists.

#### Acceptance Criteria

1. THE Orchestrator SHALL exclude the Grill_Phase from auto-advancement.
2. IF Hands_Off_Mode is turned on before the Grill_Phase has reached shared understanding, THEN THE Orchestrator SHALL stop and record that the Grill_Phase requires the human.
3. WHILE Hands_Off_Mode is on AND the Grill_Phase has reached shared understanding, THE Orchestrator SHALL begin auto-advancement at the PRD phase.

### Requirement 4: Single-session local execution

**User Story:** As a developer, I want the mode to run as one local session while my machine is on, so that the work happens with the same blast radius as my manual runs.

#### Acceptance Criteria

1. THE Orchestrator SHALL run auto-advancement within a single uninterrupted session on the user's local machine.
2. WHEN the session ends, THE Orchestrator SHALL stop auto-advancement.
3. THE Orchestrator SHALL run auto-advancement only when invoked by the user within an open local session.

### Requirement 5: Non-blocking exception handling for HITL slices

**User Story:** As a developer who is away from the keyboard, I want human-only slices skipped rather than blocking the run, so that automatable work still gets done while I am gone.

#### Acceptance Criteria

1. WHILE Hands_Off_Mode is on AND a slice carries the HITL_Slice label, THE Orchestrator SHALL skip that slice and apply Park_And_Continue.
2. WHILE Hands_Off_Mode is on, THE Orchestrator SHALL continue building remaining AFK_Slices after parking a HITL_Slice.
3. WHILE Hands_Off_Mode is on, THE Orchestrator SHALL record each skipped HITL_Slice as a Parked_Item with a one-line reason.
4. IF a decision requires the absent human's judgment, THEN THE Orchestrator SHALL record a Parked_Item and refrain from making that decision.

### Requirement 6: Park-and-wait on phase failure

**User Story:** As a developer who is away, I want a genuinely failing phase to stop and be parked, so that the workflow does not thrash or retry indefinitely.

#### Acceptance Criteria

1. IF a Middle_Phase fails, THEN THE Orchestrator SHALL stop auto-advancement at that phase and apply Park_And_Wait.
2. IF the Build phase cannot bring an AFK_Slice to a passing state, THEN THE Orchestrator SHALL record that slice as a Parked_Item with a one-line reason.
3. IF the Review phase flags a blocking issue, THEN THE Orchestrator SHALL stop auto-advancement and record the issue as a Parked_Item with a one-line reason.
4. WHEN a phase failure is parked, THE Orchestrator SHALL refrain from retrying the failed phase during the same session.

### Requirement 7: Preservation of the merge stop

**User Story:** As a developer, I want the merge to remain my decision, so that nothing reaches the default branch without my review.

#### Acceptance Criteria

1. WHEN the Build phase completes its automatable AFK_Slices, THE Orchestrator SHALL open the Integration_PR and apply the Merge_Stop.
2. THE Orchestrator SHALL leave the Integration_PR unmerged.
3. THE Orchestrator SHALL refrain from pushing to the Default_Branch.
4. THE Orchestrator SHALL apply the Merge_Stop identically whether Hands_Off_Mode is on or off.

### Requirement 8: Hands-off report

**User Story:** As a developer returning to my machine, I want a single report of what happened, so that I can see what was done, what was parked, and where to merge from my phone.

#### Acceptance Criteria

1. WHEN auto-advancement stops, THE Orchestrator SHALL produce a Hands_Off_Report.
2. THE Hands_Off_Report SHALL contain a "DID" section listing the completed AFK_Slices and the contents of the Integration_PR.
3. THE Hands_Off_Report SHALL contain a "PARKED" section listing each skipped HITL_Slice and each failed phase, each with a one-line reason.
4. THE Hands_Off_Report SHALL contain a "READ & MERGE" section with the link to the Integration_PR.
5. THE Orchestrator SHALL store the Hands_Off_Report as a comment on the PRD issue or in the Integration_PR body.
