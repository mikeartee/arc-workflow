# Fix-check for the setup-arc-skill-availability bugfix (Property 1: Expected Behavior).
# Re-runs the SAME probes Task 1 used (the bug-condition exploration check), but now
# asserts the FIXED outcome: setup-arc resolves from a non-arc-workflow workspace.
#
# On the UNFIXED state these probes FAILED (proving the bug). After Task 3.1 (H1 fix)
# and Task 3.4 (one-time sync into ~/.kiro/skills), they MUST now PASS.
#
# Re-run from the arc-workflow repo root (cwd = c:\Dev\arc-workflow).

$ErrorActionPreference = 'Stop'
$fail = 0

function Assert-Equal($label, $actual, $expected) {
    if ($actual -eq $expected) {
        Write-Output "PASS  $label"
    } else {
        Write-Output "FAIL  $label"
        Write-Output "        expected: $expected"
        Write-Output "        actual:   $actual"
        $script:fail++
    }
}

$globalSkill = Join-Path $HOME '.kiro/skills/setup-arc/SKILL.md'

# --- Probe 1: setup-arc present in the global skill set (was False on unfixed state) ---
$globalSetupArc = Test-Path $globalSkill
Assert-Equal 'P1.1 global ~/.kiro/skills/setup-arc/SKILL.md exists' $globalSetupArc $true

# --- Probe 2: corrected H1 in the global copy; old branding gone ---
# Select-String -Quiet returns a real [bool] ($true/$false), so use it directly.
$hasNewH1 = [bool](Select-String -Path $globalSkill -Pattern '^# Setup Arc$' -Quiet)
Assert-Equal 'P1.2a global SKILL.md has corrected H1 "# Setup Arc"' $hasNewH1 $true
$hasOldH1 = [bool](Select-String -Path $globalSkill -Pattern '# Setup ZSL Superpowers' -Quiet)
Assert-Equal 'P1.2b global SKILL.md no longer contains "# Setup ZSL Superpowers"' $hasOldH1 $false

# --- Probe 3: from a NON-arc-workflow workspace, resolution now succeeds with no pre-flight warning ---
# Resolution order mirrors the steering pre-flight: check workspace .kiro/skills/ then ~/.kiro/skills/.
$probeWs = Join-Path $env:TEMP ('arc-fixcheck-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $probeWs -Force | Out-Null
try {
    $localHit  = Test-Path (Join-Path $probeWs '.kiro/skills/setup-arc')
    $globalHit = Test-Path (Join-Path $HOME '.kiro/skills/setup-arc')
    $resolves  = $localHit -or $globalHit
    Assert-Equal 'P1.3a setup-arc resolves from a non-arc workspace' $resolves $true
    # No warning is emitted exactly when the reference resolves.
    $preflightWarnsSetupArc = -not $resolves
    Assert-Equal 'P1.3b pre-flight emits NO warning for setup-arc' $preflightWarnsSetupArc $false
}
finally {
    try { [System.IO.Directory]::Delete($probeWs, $true) } catch { }
}

# --- Probe 4: the Task 1 asymmetry is gone — other Arc skills STILL resolve globally too ---
Assert-Equal 'P1.4 global tdd resolves' (Test-Path (Join-Path $HOME '.kiro/skills/tdd')) $true
Assert-Equal 'P1.4 global triage resolves' (Test-Path (Join-Path $HOME '.kiro/skills/triage')) $true
Assert-Equal 'P1.4 global diagnose resolves' (Test-Path (Join-Path $HOME '.kiro/skills/diagnose')) $true

Write-Output ''
if ($fail -eq 0) {
    Write-Output 'RESULT: FIX-CHECK PASSES - setup-arc resolves; bug is fixed'
} else {
    Write-Output "RESULT: $fail FIX-CHECK ASSERTION(S) FAILED"
}
