# WoW client patch updater.
# Reads version.txt from GitHub, compares SHA-256 against the local patch,
# downloads only if it differs, verifies what it downloaded, and clears the
# WDB cache so item and spell tooltips are not stale.
#
# Exit codes: 0 ok (game may launch) | 1 config | 2 network | 3 verify failed

$ErrorActionPreference = 'Stop'

# ---- EDIT THESE TWO LINES ----------------------------------------------
$VersionUrl = 'https://raw.githubusercontent.com/Zepheer/wow-client-patch/main/version.txt'
$PatchUrl   = 'https://github.com/Zepheer/wow-client-patch/releases/latest/download/patch-4.MPQ'
# ------------------------------------------------------------------------

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir  = Join-Path $Root 'Data'
$CacheDir = Join-Path $Root 'Cache'

function Say([string]$m) { Write-Host "  $m" }

# Old Windows defaults to TLS 1.0, which GitHub refuses.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

Write-Host ''
Write-Host '  Checking for client updates...'
Write-Host ''

if (-not (Test-Path $DataDir)) { Say "ERROR: no Data folder here. Is this the WoW folder?"; exit 1 }

# --- fetch the manifest -------------------------------------------------
try {
    $raw = (Invoke-WebRequest -Uri $VersionUrl -UseBasicParsing -TimeoutSec 20).Content
} catch {
    Say "Could not reach the update server. Starting the game with your current files."
    Say "($($_.Exception.Message))"
    exit 0                      # never block play just because the host is down
}

$cfg = @{}
foreach ($line in $raw -split "`n") {
    $line = $line.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $kv = $line -split '=', 2
    if ($kv.Count -eq 2) { $cfg[$kv[0].Trim()] = $kv[1].Trim() }
}
foreach ($k in 'file','sha256') {
    if (-not $cfg.ContainsKey($k)) { Say "ERROR: version.txt has no '$k' entry."; exit 1 }
}

$PatchName = $cfg['file']
$Expected  = $cfg['sha256'].ToLower()
$Local     = Join-Path $DataDir $PatchName

# --- compare ------------------------------------------------------------
$current = ''
if (Test-Path $Local) { $current = (Get-FileHash -Path $Local -Algorithm SHA256).Hash.ToLower() }

if ($current -eq $Expected) {
    Say "Your client patch is up to date."
    Write-Host ''
    exit 0
}

if ($current -eq '') { Say "$PatchName is missing - downloading it." }
else                 { Say "A new client patch is available - downloading." }
if ($cfg.ContainsKey('notes') -and $cfg['notes']) { Say "  $($cfg['notes'])" }

# --- download to a temp file, verify, then swap in ----------------------
$tmp = Join-Path $env:TEMP ("$PatchName." + [guid]::NewGuid().ToString('N') + '.part')
try {
    Invoke-WebRequest -Uri $PatchUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 600
} catch {
    Say "Download failed: $($_.Exception.Message)"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    exit 2
}

$got = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
if ($got -ne $Expected) {
    Say "ERROR: the downloaded file did not match its checksum. Nothing was changed."
    Say "expected $Expected"
    Say "got      $got"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    exit 3
}

# Never delete the old patch before the new one is verified and in place.
try {
    Move-Item -Path $tmp -Destination $Local -Force
} catch {
    Say "ERROR: could not write $Local"
    Say "Close World of Warcraft and try again."
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    exit 3
}
Say "Patch updated."

# --- clear the WDB cache ------------------------------------------------
# Without this the client keeps showing OLD item and spell tooltips after a
# data change - the exact symptom that wastes the most time.
if (Test-Path $CacheDir) {
    $wdb = Join-Path $CacheDir 'WDB'
    if (Test-Path $wdb) {
        try { Remove-Item -Path $wdb -Recurse -Force; Say "Cleared the client cache." }
        catch { Say "Note: could not clear Cache\WDB - close WoW and rerun if tooltips look wrong." }
    }
}

Write-Host ''
exit 0
