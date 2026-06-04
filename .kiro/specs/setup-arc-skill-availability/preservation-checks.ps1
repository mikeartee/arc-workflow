# Preservation checks for the setup-arc-skill-availability bugfix (Property 2).
# Observation-first baselines recorded on the UNFIXED state in Task 2.
# Re-run from the arc-workflow repo root (cwd = c:\Dev\arc-workflow) in Task 3.6.
#
# ALL checks must PASS on the unfixed state and STILL PASS after the fix, EXCEPT
# the whole-file SKILL.md hash (3.6-info) which legitimately changes when the H1
# is corrected. The BODY_BELOW_H1 / ALL_EXCEPT_H1 / FRONTMATTER hashes prove the
# file is otherwise byte-for-byte unchanged.
#
# Encoding note: line-based hashes are computed from a .NET UTF-8 read
# ([System.IO.File]::ReadAllText) normalized to LF, so results are identical
# under both Windows PowerShell 5.1 and pwsh 7 (verified in Task 2). Get-Content
# is NOT used for hashing because its default encoding differs between hosts and
# corrupts the em-dash (U+2014) in the description/body.

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

$sha = [System.Security.Cryptography.SHA256]::Create()
function HashOf($s) {
    ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) -join ''
}

# --- Recorded baselines (UNFIXED state, Task 2) ---
$BASE_MANUAL_HOOK_SHA256   = '64B986906F9E711E9DB591CC634629C715FE4D68D6BD81564B99FEE7C45F7D84'
$BASE_PLUGIN_JSON_SHA256   = 'A7432CE125B2BE0A29E4A2377914C3E079662C747DCBFFC90BCED3E710610B6B'
$BASE_MARKETPLACE_SHA256   = '598CE2A3C92928BFE9EDD1D011F5F7ECC096448B0E7819B191CED2BCFB144CD2'
$BASE_SKILL_WHOLE_SHA256   = '36346C07B260547489220DB1914C7B7A57E245ED82AD36774827A44C62B5561C'
$BASE_FRONTMATTER_SHA256   = '97d987474a4eabad0f7c505bea379eec6b29fc7b3583442dfcc255e7218d34b7'
$BASE_BODY_BELOW_H1_SHA256 = '5c851d54923dece3228521b981b60690500e7e8ef5b895cd9c4e4de1aa9d445c'
$BASE_ALL_EXCEPT_H1_SHA256 = 'c653303e49fc9b3e43aa4b2cc9a2420b65a005de75131a1c1b94d782eed19920'
$BASE_NAME_LINE            = 'name: setup-arc'
$BASE_H1_LINE             = '# Setup ZSL Superpowers'  # UNFIXED H1; becomes '# Setup Arc' after Task 3.1

# --- Req 3.1: local resolution inside arc-workflow ---
Assert-Equal '3.1 local .kiro/skills/setup-arc/SKILL.md exists' (Test-Path .kiro/skills/setup-arc/SKILL.md) $true

# --- Req 3.2: manual hook byte-for-byte unchanged ---
$manualHash = (Get-FileHash .kiro/hooks/sync-skills-to-global.json -Algorithm SHA256).Hash
Assert-Equal '3.2 manual sync hook SHA256' $manualHash $BASE_MANUAL_HOOK_SHA256

# --- Req 3.3: zsl plugin manifests untouched ---
Assert-Equal '3.3 plugin.json exists' (Test-Path 'c:\Dev\zsl-skills\.claude-plugin\plugin.json') $true
Assert-Equal '3.3 marketplace.json exists' (Test-Path 'c:\Dev\zsl-skills\.claude-plugin\marketplace.json') $true
$pluginHash = (Get-FileHash 'c:\Dev\zsl-skills\.claude-plugin\plugin.json' -Algorithm SHA256).Hash
$marketHash = (Get-FileHash 'c:\Dev\zsl-skills\.claude-plugin\marketplace.json' -Algorithm SHA256).Hash
Assert-Equal '3.3 plugin.json SHA256' $pluginHash $BASE_PLUGIN_JSON_SHA256
Assert-Equal '3.3 marketplace.json SHA256' $marketHash $BASE_MARKETPLACE_SHA256

# --- Req 3.4: other global Arc skills resolve ---
Assert-Equal '3.4 global tdd resolves' (Test-Path $HOME/.kiro/skills/tdd) $true
Assert-Equal '3.4 global triage resolves' (Test-Path $HOME/.kiro/skills/triage) $true
Assert-Equal '3.4 global diagnose resolves' (Test-Path $HOME/.kiro/skills/diagnose) $true

# --- Host-independent UTF-8 read of SKILL.md (lines 1-6 = frontmatter, line 7 = H1) ---
$p = (Resolve-Path .kiro/skills/setup-arc/SKILL.md).Path
$text = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
$lines = $text -split "`r?`n"

# --- Req 3.5: frontmatter name + description identical ---
# Line 0 is the opening '---'; line 1 is the name line (deterministic frontmatter layout).
$nameLine = [string]$lines[1]
Assert-Equal '3.5 frontmatter name line' $nameLine $BASE_NAME_LINE
$frontmatter = ($lines[0..5] -join "`n")
Assert-Equal '3.5 frontmatter block (lines 1-6) SHA256' (HashOf $frontmatter) $BASE_FRONTMATTER_SHA256

# --- Req 3.6: body unchanged apart from the H1 ---
$bodyBelowH1 = ($lines[7..($lines.Count-1)] -join "`n")
Assert-Equal '3.6 body-below-H1 SHA256' (HashOf $bodyBelowH1) $BASE_BODY_BELOW_H1_SHA256
$exceptH1 = (($lines[0..5] + $lines[7..($lines.Count-1)]) -join "`n")
Assert-Equal '3.6 all-except-H1 SHA256' (HashOf $exceptH1) $BASE_ALL_EXCEPT_H1_SHA256

# Informational: H1 line + whole-file hash (both expected to change after Task 3.1 H1 fix).
Write-Output "INFO  3.6 current H1 line 7: '$($lines[6])' (baseline UNFIXED: '$BASE_H1_LINE')"
$wholeHash = (Get-FileHash .kiro/skills/setup-arc/SKILL.md -Algorithm SHA256).Hash
if ($wholeHash -eq $BASE_SKILL_WHOLE_SHA256) {
    Write-Output 'INFO  3.6 whole-file SKILL.md hash matches baseline (UNFIXED state)'
} else {
    Write-Output 'INFO  3.6 whole-file SKILL.md hash changed (expected after H1 fix)'
}

Write-Output ''
if ($fail -eq 0) {
    Write-Output 'RESULT: ALL PRESERVATION CHECKS PASS'
} else {
    Write-Output "RESULT: $fail PRESERVATION CHECK(S) FAILED"
}
