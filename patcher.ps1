param(
    # Set when this script re-launches itself after updating. Stops an update
    # loop if a hash ever fails to settle.
    [switch]$NoSelfUpdate
)

# WoW client patch updater.
# Reads version.txt from GitHub and keeps three things current:
#   0. itself                (patcher.ps1 - so players never re-download by hand)
#   1. the client patch MPQ  (Data\patch-4.MPQ)
#   2. the server addons     (Interface\AddOns\...)
# Each is downloaded only when its SHA-256 differs, and verified before it is
# put in place. The WDB cache is cleared only when the MPQ actually changed.
#
# Exit codes:
#   0  up to date, nothing done   (launch straight away)
#  10  something was updated      (worth showing the player before launching)
#   1  config problem | 2 network | 3 verification failed
#
# DESIGN RULE: the addon step must never stop someone playing. Every failure in
# that phase warns and carries on. Only the MPQ phase can return a hard error.

$ErrorActionPreference = 'Stop'

# ---- EDIT THESE TWO LINES ----------------------------------------------
$VersionUrl = 'https://raw.githubusercontent.com/Zepheer/wow-client-patch/main/version.txt'
$BaseUrl    = 'https://github.com/Zepheer/wow-client-patch/releases/latest/download'
# ------------------------------------------------------------------------

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir   = Join-Path $Root 'Data'
$CacheDir  = Join-Path $Root 'Cache'
$AddOnsDir = Join-Path $Root 'Interface\AddOns'
$Marker    = Join-Path $AddOnsDir '.patcher-addons.sha'

$changed = $false

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

# =======================================================================
#  PHASE 0 - update THIS SCRIPT
#  Without this, every change to the patcher needs every player to
#  re-download it by hand, and the old copy keeps working just well enough
#  that nobody notices they are missing things.
#  Like the addon phase, any failure here warns and carries on.
# =======================================================================
if (-not $NoSelfUpdate -and $cfg.ContainsKey('patcher_sha256') -and $cfg['patcher_sha256']) {
    try {
        $me       = $PSCommandPath
        $wantSelf = $cfg['patcher_sha256'].ToLower()
        $haveSelf = ''
        if ($me -and (Test-Path $me)) { $haveSelf = (Get-FileHash -Path $me -Algorithm SHA256).Hash.ToLower() }

        if ($me -and $haveSelf -and $wantSelf -ne $haveSelf) {
            Say "Updating the patcher itself..."
            # Stage NEXT TO the script, not in %TEMP%. If TEMP sits on another
            # volume, Move-Item degrades from an atomic rename into copy+delete,
            # and an interruption there would leave a truncated patcher.ps1 -
            # breaking the very thing that repairs everything else. Same volume
            # means the swap is a rename and cannot half-happen.
            $stmp = Join-Path (Split-Path -Parent $me) ("patcher.new." + [guid]::NewGuid().ToString('N') + '.tmp')
            Invoke-WebRequest -Uri "$BaseUrl/patcher.ps1" -OutFile $stmp -UseBasicParsing -TimeoutSec 120

            $gotSelf = (Get-FileHash -Path $stmp -Algorithm SHA256).Hash.ToLower()
            if ($gotSelf -ne $wantSelf) {
                Say "The new patcher did not match its checksum - keeping the current one."
                Remove-Item $stmp -Force -ErrorAction SilentlyContinue
            } else {
                # Only replace after the checksum passed, so a truncated or wrong
                # download can never overwrite a working patcher.
                Move-Item -Path $stmp -Destination $me -Force
                Say "Patcher updated - re-running the new version."
                Write-Host ''

                # Run the replacement in a fresh process. Re-executing in-process
                # is subtle because this script is already loaded; a new process
                # is unambiguous.
                $proc = Start-Process -FilePath 'powershell' -PassThru -Wait -NoNewWindow -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$me,'-NoSelfUpdate'
                exit $proc.ExitCode
            }
        }
    } catch {
        Say "Could not update the patcher - continuing with the current one."
        Say "($($_.Exception.Message))"
        if ($stmp -and (Test-Path $stmp)) { Remove-Item $stmp -Force -ErrorAction SilentlyContinue }
    }
}

# =======================================================================
#  PHASE 1 - the client patch MPQ
# =======================================================================
$PatchName = $cfg['file']
$Expected  = $cfg['sha256'].ToLower()
$Local     = Join-Path $DataDir $PatchName
$PatchUrl  = "$BaseUrl/$PatchName"

$current = ''
if (Test-Path $Local) { $current = (Get-FileHash -Path $Local -Algorithm SHA256).Hash.ToLower() }

if ($current -eq $Expected) {
    Say "Your client patch is up to date."
} else {
    if ($current -eq '') { Say "$PatchName is missing - downloading it." }
    else                 { Say "A new client patch is available - downloading." }
    if ($cfg.ContainsKey('notes') -and $cfg['notes']) { Say "  $($cfg['notes'])" }

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
    $changed = $true

    # --- clear the WDB cache --------------------------------------------
    # Only after a real MPQ change. Without this the client keeps showing OLD
    # item and spell tooltips - the exact symptom that wastes the most time.
    # Addon updates do NOT need it, so this deliberately sits inside this block.
    if (Test-Path $CacheDir) {
        $wdb = Join-Path $CacheDir 'WDB'
        if (Test-Path $wdb) {
            try { Remove-Item -Path $wdb -Recurse -Force; Say "Cleared the client cache." }
            catch { Say "Note: could not clear Cache\WDB - close WoW and rerun if tooltips look wrong." }
        }
    }
}

# =======================================================================
#  PHASE 2 - the addons
#  Everything below warns and continues. It must never block the launch.
# =======================================================================
if ($cfg.ContainsKey('addons_file') -and $cfg['addons_file'] -and $cfg.ContainsKey('addons_sha256')) {
    try {
        $AddOnsZip  = $cfg['addons_file']
        $AddExpect  = $cfg['addons_sha256'].ToLower()
        $AddUrl     = "$BaseUrl/$AddOnsZip"

        # We cannot hash an extracted folder tree reliably, so we record what we
        # installed in a marker file and compare against that.
        $installed = ''
        if (Test-Path $Marker) { $installed = (Get-Content $Marker -ErrorAction SilentlyContinue | Select-Object -First 1) }
        if ($installed) { $installed = $installed.Trim().ToLower() }

        if ($installed -eq $AddExpect) {
            Say "Your addons are up to date."
        } else {
            Say "Updating server addons..."

            $atmp = Join-Path $env:TEMP ("addons." + [guid]::NewGuid().ToString('N') + '.zip')
            Invoke-WebRequest -Uri $AddUrl -OutFile $atmp -UseBasicParsing -TimeoutSec 600

            $agot = (Get-FileHash -Path $atmp -Algorithm SHA256).Hash.ToLower()
            if ($agot -ne $AddExpect) {
                Say "Addon download did not match its checksum - skipping. Your addons were not changed."
                Remove-Item $atmp -Force -ErrorAction SilentlyContinue
            } else {
                $stage = Join-Path $env:TEMP ("addons." + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $stage -Force | Out-Null

                # .NET first (works on PS4 / .NET 4.5). Expand-Archive needs PS5.
                $unpacked = $false
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($atmp, $stage)
                    $unpacked = $true
                } catch {
                    try {
                        Expand-Archive -Path $atmp -DestinationPath $stage -Force
                        $unpacked = $true
                    } catch {
                        Say "Could not unpack the addon archive - skipping. ($($_.Exception.Message))"
                    }
                }

                if ($unpacked) {
                    if (-not (Test-Path $AddOnsDir)) { New-Item -ItemType Directory -Path $AddOnsDir -Force | Out-Null }

                    # Only ever touch folders that came out of OUR archive, and only
                    # if they are plain names. This is what stops a bad manifest
                    # writing anywhere outside Interface\AddOns.
                    $ok = 0
                    foreach ($src in (Get-ChildItem -Path $stage -Directory)) {
                        $name = $src.Name
                        if ($name -match '[\\/:]' -or $name -eq '.' -or $name -eq '..') {
                            Say "Skipping suspicious entry '$name'."
                            continue
                        }
                        $dest = Join-Path $AddOnsDir $name
                        try {
                            if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force }
                            Copy-Item -Path $src.FullName -Destination $dest -Recurse -Force
                            $ok++
                        } catch {
                            Say "Could not update addon '$name' - is WoW still running?"
                        }
                    }

                    if ($ok -gt 0) {
                        Set-Content -Path $Marker -Value $AddExpect -Encoding ASCII
                        $names = $cfg['addons_list']
                        if ($names) { Say "Addons updated: $names" } else { Say "Addons updated ($ok)." }
                        $changed = $true
                    } else {
                        Say "No addons could be updated. Your existing ones were left alone."
                    }
                }

                Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $atmp -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # Anything unexpected in the addon phase is a warning, never a blocker.
        Say "Addon update skipped: $($_.Exception.Message)"
    }
}

Write-Host ''
if ($changed) { exit 10 }
exit 0
