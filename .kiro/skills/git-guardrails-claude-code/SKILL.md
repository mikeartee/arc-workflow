---
name: git-guardrails-claude-code
description: Set up Kiro hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Kiro.
---

# Setup Git Guardrails

Sets up a `preToolUse` hook in Kiro that intercepts and blocks dangerous git commands before the agent executes them.

## What Gets Blocked

- `git push` (all variants including `--force`)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

When blocked, the agent sees a message telling it that it does not have authority to run these commands.

## Steps

### 1. Ask scope

Ask the user: install for **this project only** (`.kiro/hooks/`) or **all projects** (`~/.kiro/hooks/`)?

### 2. Create the hook file

Create a JSON hook file at the appropriate location:

- **Project**: `.kiro/hooks/block-dangerous-git.json`
- **Global**: `~/.kiro/hooks/block-dangerous-git.json`

Hook file contents:

```json
{
  "name": "Block Dangerous Git Commands",
  "version": "1.0.0",
  "description": "Blocks destructive git operations before the agent executes them",
  "when": {
    "type": "preToolUse",
    "toolTypes": ["shell"]
  },
  "then": {
    "type": "askAgent",
    "prompt": "Check the shell command about to be run. If it matches any of these dangerous git patterns, STOP and tell the user you do not have authority to run it:\n- git push (any variant, including --force)\n- git reset --hard\n- git clean -f or -fd\n- git branch -D\n- git checkout . or git restore .\n\nIf the command does NOT match any of these patterns, proceed normally without comment."
  }
}
```

### 3. Ask about customization

Ask if the user wants to add or remove any patterns from the blocked list. Update the `prompt` field in the hook accordingly.

### 4. Verify

In Kiro, open the Agent Hooks panel (Explorer → Agent Hooks) and confirm the hook appears. You can also trigger it by asking the agent to run `git push` — it should refuse.

## Notes

- Kiro hooks use JSON files in `.kiro/hooks/` (workspace) or `~/.kiro/hooks/` (global)
- The `preToolUse` event fires before any shell tool execution
- The `askAgent` action sends a prompt to the agent to evaluate the command before proceeding
- Hook changes take effect immediately — no restart needed
