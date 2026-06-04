# Property-based preservation sweep (Task 5, optional/comprehensive) for the
# setup-arc-skill-availability bugfix. Broadens the deterministic checks in
# Tasks 1, 3.5 and 3.6 across an input space rather than a single concrete case.
#
#   Sweep A (Property 1, Fix Checking): generate arbitrary non-arc-workflow
#     workspace names; after the refresh, assert setup-arc resolves for EVERY one.
#     Global skills resolve independent of workspace, so the global presence must
#     hold for the whole simulated set.
#
#   Sweep B (Property 2, Preservation): for the Arc skill set + setup-zsl-superpowers,
#     assert resolution outcome is identical before (simulated stale global) and
#     after (real fixed global) the fix, for EVERY name EXCEPT setup-arc -- the one
#     name the bug condition C broke (unresolved -> resolved).
#
#   Sweep C (Idempotency): run the documented refresh N times and assert
#     ~/.kiro/skills/setup-arc/ content (relative file list + SHA256 hashes) is
#     identical regardless of N -- no duplication, no corruption.
#
# Run from the arc-workflow repo root (cwd = c:\Dev\arc-workflow).
# Compatible with both Windows PowerShell 5.1 and pwsh 7 (no ternary / ?? operators,
# 2-arg Join-Path only). Self-cleans every temp working directory it creates.

$ErrorActionPreference = 'Stop'
$fail = 0

function Assert-True($label, $cond) {
    if ($cond) {
        Write-Output "PASS  $label"
    } else {
        Write-Output "FAIL  $label"
        $script:fail++
    }
}

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

$globalSkillsRoot = Join-Path $HOME '.kiro/skills'

# resolveSkillReference(name, workspace): mirrors the steering pre-flight order --
# workspace .kiro/skills/<name> first, then ~/.kiro/skills/<name>.
function Resolve-Skill($name, $workspace) {
    $local  = Test-Path (Join-Path (Join-Path $workspace '.kiro/skills') $name)
    $global = Test-Path (Join-Path $globalSkillsRoot $name)
    return ($local -or $global)
}

# Manifest of a directory: sorted "<relpath>|<sha256>" lines. Stable across runs
# when content is byte-identical; line count == file count (duplication probe).
function Get-DirManifest($root) {
    if (-not (Test-Path $root)) { return '<MISSING>' }
    $rootFull = (Resolve-Path $root).Path
    $files = Get-ChildItem -Path $rootFull -Recurse -File | Sort-Object FullName
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/')
        $h = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
        [void]$sb.AppendLine("$rel|$h")
    }
    return $sb.ToString()
}

Write-Output '===== Sweep A: Property 1 (Fix Checking) across arbitrary workspaces ====='
# Arbitrary non-arc-workflow workspace names: crafted edge cases + random GUIDs.
$wsNames = @(
    'my-project',
    'Some Project With Spaces',
    'proj.with.dots',
    'UPPER_CASE_REPO',
    'cafe-unicode-app',
    'a',
    'nested-mono-repo'
)
for ($i = 0; $i -lt 5; $i++) { $wsNames += ('rand-' + [guid]::NewGuid().ToString('N')) }

$wsRoots = @()
try {
    foreach ($n in $wsNames) {
        Assert-True "A workspace name is not the arc-workflow repo: '$n'" ($n -ne 'arc-workflow')
        $ws = Join-Path $env:TEMP ('arc-sweepA-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $ws -Force | Out-Null
        $wsRoots += $ws
        # Empty workspace: no local .kiro/skills, so resolution must come from global.
        $resolves = Resolve-Skill 'setup-arc' $ws
        Assert-Equal "A setup-arc resolves from non-arc workspace '$n'" $resolves $true
    }
}
finally {
    foreach ($ws in $wsRoots) { try { [System.IO.Directory]::Delete($ws, $true) } catch { } }
}

Write-Output ''
Write-Output '===== Sweep B: Property 2 (Preservation) across the skill-name space ====='
# Input space: local Arc skill set + setup-zsl-superpowers.
$arcSkills = Get-ChildItem -Path .kiro/skills -Directory | Select-Object -ExpandProperty Name
$inputNames = @($arcSkills) + 'setup-zsl-superpowers' | Select-Object -Unique
Write-Output ("B input space ({0} names): {1}" -f $inputNames.Count, ($inputNames -join ', '))

# Simulate the UNFIXED (stale) global skill set = current global minus setup-arc.
# Resolution depends only on directory presence, so empty marker dirs faithfully
# reproduce which names resolved before the fix.
$staleRoot = Join-Path $env:TEMP ('arc-stale-' + [guid]::NewGuid().ToString('N'))
try {
    $curGlobalNames = Get-ChildItem -Path $globalSkillsRoot -Directory | Select-Object -ExpandProperty Name
    foreach ($n in $curGlobalNames) {
        if ($n -ne 'setup-arc') {
            New-Item -ItemType Directory -Path (Join-Path $staleRoot $n) -Force | Out-Null
        }
    }

    foreach ($name in $inputNames) {
        $orig  = Test-Path (Join-Path $staleRoot $name)          # original/stale outcome
        $fixed = Test-Path (Join-Path $globalSkillsRoot $name)   # fixed outcome
        if ($name -eq 'setup-arc') {
            # The ONLY name whose outcome changed: unresolved (C) -> resolved.
            Assert-Equal "B 'setup-arc' original UNRESOLVED (bug condition C)" $orig $false
            Assert-Equal "B 'setup-arc' fixed RESOLVED" $fixed $true
        } else {
            # Every other name: outcome identical before and after the fix.
            Assert-Equal "B '$name' outcome identical before/after (orig=$orig fixed=$fixed)" $orig $fixed
        }
    }
}
finally {
    try { [System.IO.Directory]::Delete($staleRoot, $true) } catch { }
}

# Req 3.3: the zsl .claude-plugin manifests MUST stay byte-for-byte untouched
# (this fix never edits them). Baselines recorded on the UNFIXED state in Task 2
# (same values as preservation-checks.ps1).
$BASE_PLUGIN_JSON_SHA256 = 'A7432CE125B2BE0A29E4A2377914C3E079662C747DCBFFC90BCED3E710610B6B'
$BASE_MARKETPLACE_SHA256 = '598CE2A3C92928BFE9EDD1D011F5F7ECC096448B0E7819B191CED2BCFB144CD2'
$pluginPath = 'c:\Dev\zsl-skills\.claude-plugin\plugin.json'
$marketPath = 'c:\Dev\zsl-skills\.claude-plugin\marketplace.json'
Assert-True 'B zsl plugin.json exists' (Test-Path $pluginPath)
Assert-True 'B zsl marketplace.json exists' (Test-Path $marketPath)
Assert-Equal 'B zsl plugin.json untouched (SHA256)' (Get-FileHash $pluginPath -Algorithm SHA256).Hash $BASE_PLUGIN_JSON_SHA256
Assert-Equal 'B zsl marketplace.json untouched (SHA256)' (Get-FileHash $marketPath -Algorithm SHA256).Hash $BASE_MARKETPLACE_SHA256

Write-Output ''
Write-Output '===== Sweep C: Idempotent refresh (N repeated runs) ====='
$N = 3
$globalSetupArc = Join-Path $globalSkillsRoot 'setup-arc'
$manifests = @()
$counts = @()
for ($i = 1; $i -le $N; $i++) {
    # The documented, idempotent refresh (same command as the manual + auto hooks).
    Copy-Item -Recurse -Force .kiro/skills/* $globalSkillsRoot
    Copy-Item -Force .kiro/steering/arc-workflow.md (Join-Path $HOME '.kiro/steering/arc-workflow.md')
    $m = Get-DirManifest $globalSetupArc
    $manifests += $m
    $lineCount = (($m -split "`n") | Where-Object { $_.Trim() -ne '' }).Count
    $counts += $lineCount
    Write-Output ("C run #{0}: {1} files under setup-arc/" -f $i, $lineCount)
}

$allSame = $true
for ($i = 1; $i -lt $N; $i++) {
    if ($manifests[$i] -ne $manifests[0]) { $allSame = $false }
}
Assert-True "C ~/.kiro/skills/setup-arc/ manifest identical across $N runs (no corruption)" $allSame
$countSame = (($counts | Select-Object -Unique).Count -eq 1)
Assert-True ("C file count constant across $N runs (no duplication): " + ($counts -join ',')) $countSame

Write-Output ''
if ($fail -eq 0) {
    Write-Output 'RESULT: ALL PROPERTY-BASED SWEEPS PASS (A fix-checking, B preservation, C idempotency)'
} else {
    Write-Output "RESULT: $fail SWEEP ASSERTION(S) FAILED"
}
