<#
.SYNOPSIS
    Ashen Hollow installer and updater for Windows.

.DESCRIPTION
    Fetches the latest GitHub Release of the game, verifies the download against
    the release's checksum file, and swaps it into place atomically. Installs
    per-user under %LOCALAPPDATA%, so it never asks for administrator rights and
    never touches anything outside your profile.

    A copy of this script is installed alongside the game, and the shortcuts it
    creates run it with -Launch — which is what makes the game self-updating:
    every start checks for a new release, and a failed check never stands
    between you and the version you already have.

.PARAMETER Launch
    Update if possible, then start the game.

.PARAMETER Check
    Report whether an update is available and change nothing. Exits 10 when
    there is one.

.PARAMETER Uninstall
    Remove the game. Saves and settings are kept.

.PARAMETER Force
    Reinstall even when already up to date.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Check
    .\install.ps1 -Launch
#>
[CmdletBinding()]
param(
    [switch]$Launch,
    [switch]$Check,
    [switch]$Uninstall,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# TLS 1.2 for Windows PowerShell 5.1, which does not negotiate it by default
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Name = 'Ashen Hollow'
$Repo = if ($env:AH_REPO) { $env:AH_REPO } else { 'fettglatze/2d-soulslike' }
$Api  = if ($env:AH_API)  { $env:AH_API }  else { 'https://api.github.com' }
$Prefix = if ($env:AH_PREFIX) { $env:AH_PREFIX }
          elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\AshenHollow' }
          else { Join-Path ([System.IO.Path]::GetTempPath()) 'AshenHollow' }
$VersionFile = Join-Path $Prefix 'version.txt'
$AssetMatch = 'windows'

function Say  { param([string]$m) Write-Host $m }
function Warn { param([string]$m) Write-Warning $m }

function Get-InstalledVersion {
    if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw).Trim() } else { '' }
}

function Get-LatestRelease {
    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'AshenHollow-Installer' }
    if ($env:AH_TOKEN) { $headers['Authorization'] = "Bearer $env:AH_TOKEN" }
    try {
        Invoke-RestMethod -Uri "$Api/repos/$Repo/releases/latest" -Headers $headers `
            -UseBasicParsing -TimeoutSec 30
    } catch {
        $null
    }
}

# Strict mode makes a missing property an error rather than $null, so every
# field that comes off the network is checked before it is read.
function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function Get-AssetUrl {
    param($Release, [string]$Match)
    $assets = Get-Prop $Release 'assets'
    if (-not $assets) { return $null }
    foreach ($a in $assets) {
        if ($a.name -like "*$Match*") { return $a.browser_download_url }
    }
    return $null
}

function Save-Url {
    param([string]$Url, [string]$Dest)
    $headers = @{ 'User-Agent' = 'AshenHollow-Installer' }
    if ($env:AH_TOKEN) { $headers['Authorization'] = "Bearer $env:AH_TOKEN" }
    Invoke-WebRequest -Uri $Url -OutFile $Dest -Headers $headers -UseBasicParsing -TimeoutSec 600
}

# --- shortcuts ---------------------------------------------------------------
# Guarded: the COM object only exists on Windows, and the installer is also run
# on Linux by its own test suite.
function New-Shortcut {
    param([string]$LinkPath, [string]$Target, [string]$Arguments, [string]$Icon)
    try {
        $shell = New-Object -ComObject WScript.Shell
    } catch {
        return $false
    }
    $dir = Split-Path -Parent $LinkPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $sc = $shell.CreateShortcut($LinkPath)
    $sc.TargetPath = $Target
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $Prefix
    if ($Icon -and (Test-Path $Icon)) { $sc.IconLocation = $Icon }
    $sc.Description = 'A 2D souls-like in dark retro pixel art'
    $sc.Save()
    return $true
}

function Test-Windows {
    # $IsWindows only exists in PowerShell 6+, and reading it under
    # Set-StrictMode on Windows PowerShell 5.1 is an error rather than $false.
    return ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
}

function Install-Shortcuts {
    if (-not (Test-Windows)) {
        Say 'Shortcuts skipped (not running on Windows).'
        return
    }
    $ps = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path $ps)) { $ps = 'powershell.exe' }
    $script = Join-Path $Prefix 'install.ps1'
    $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Launch"
    $icon = Join-Path $Prefix 'icon.ico'
    if (-not (Test-Path $icon)) { $icon = Get-GameBinary }

    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Ashen Hollow.lnk'
    $desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Ashen Hollow.lnk'
    foreach ($link in @($startMenu, $desktop)) {
        if (-not (New-Shortcut $link $ps $args $icon)) {
            Say 'Shortcuts skipped (not running on Windows).'
            return
        }
    }
}

function Get-GameBinary {
    if (-not (Test-Path $Prefix)) { return $null }
    $exe = Get-ChildItem -Path $Prefix -Filter 'AshenHollow*.exe' -File -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}

# --- install -----------------------------------------------------------------
function Install-Game {
    param([bool]$ForceInstall, [bool]$Quiet)

    $release = Get-LatestRelease
    if (-not $release) {
        Warn "Could not reach GitHub ($Api/repos/$Repo)."
        Warn 'If this repository is private, set AH_TOKEN to a personal access token.'
        return 2
    }
    $tag = Get-Prop $release 'tag_name'
    if (-not $tag) {
        Warn 'The release has no tag_name; nothing to install.'
        return 2
    }
    $current = Get-InstalledVersion
    if ($tag -eq $current -and -not $ForceInstall) {
        if (-not $Quiet) { Say "$Name $tag is already up to date." }
        return 0
    }

    $url = Get-AssetUrl $release $AssetMatch
    if (-not $url) {
        Warn "Release $tag has no $AssetMatch build attached."
        return 2
    }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("ashen-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $zip = Join-Path $work 'package.zip'
        Say "Downloading $Name $tag..."
        try { Save-Url $url $zip } catch { Warn "Download failed: $_"; return 2 }

        # Checksums are optional so an older release without them still installs,
        # but when they are published a mismatch stops the install dead.
        $sumsUrl = Get-AssetUrl $release 'SHA256SUMS'
        if ($sumsUrl) {
            $sums = Join-Path $work 'SHA256SUMS'
            try { Save-Url $sumsUrl $sums } catch { $sums = $null }
            if ($sums -and (Test-Path $sums)) {
                $file = Split-Path -Leaf ([uri]$url).AbsolutePath
                $want = $null
                foreach ($line in Get-Content $sums) {
                    if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $file) {
                        $want = $Matches[1].ToLower()
                    }
                }
                if (-not $want) {
                    # The release publishes checksums but not for this file.
                    # That is not "unverified", it is wrong - refuse rather
                    # than shrug.
                    Warn "Checksum mismatch: $file is not listed in SHA256SUMS."
                    return 2
                }
                $got = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
                if ($want -ne $got) {
                    Warn "Checksum mismatch for $file."
                    Warn "  expected $want"
                    Warn "  got      $got"
                    return 2
                }
                Say 'Checksum verified.' 
            }
        }

        Say "Installing to $Prefix"
        $unpacked = Join-Path $work 'unpacked'
        try {
            Expand-Archive -Path $zip -DestinationPath $unpacked -Force
        } catch {
            Warn 'The archive is corrupt.'
            return 2
        }

        # Swap atomically: the old install is only removed once the new one is
        # in place, so a failure here never leaves a half-installed game behind.
        $parent = Split-Path -Parent $Prefix
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        foreach ($stale in @("$Prefix.new", "$Prefix.old")) {
            if (Test-Path $stale) { Remove-Item -Recurse -Force $stale }
        }
        Move-Item $unpacked "$Prefix.new"
        Set-Content -Path (Join-Path "$Prefix.new" 'version.txt') -Value $tag -NoNewline
        Copy-Item $PSCommandPath (Join-Path "$Prefix.new" 'install.ps1') -Force -ErrorAction SilentlyContinue
        if (Test-Path $Prefix) { Move-Item $Prefix "$Prefix.old" }
        Move-Item "$Prefix.new" $Prefix
        if (Test-Path "$Prefix.old") { Remove-Item -Recurse -Force "$Prefix.old" }

        Install-Shortcuts
        Say "$Name $tag installed."
        return 0
    } finally {
        if (Test-Path $work) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
    }
}

function Start-Game {
    # The update is best-effort on purpose: GitHub being unreachable, or a
    # release being broken, must never stand between a player and the copy of
    # the game they already have.
    $rc = Install-Game $false $true
    if ($rc -ne 0) { Warn 'Continuing with the installed version.' }
    $exe = Get-GameBinary
    if (-not $exe) {
        Warn "No game found in $Prefix. Run install.ps1 first."
        return 1
    }
    if ($env:AH_DRY_RUN -eq '1') {
        Say "would launch: $exe"
        return 0
    }
    Start-Process -FilePath $exe -WorkingDirectory $Prefix
    return 0
}

function Test-Update {
    $current = Get-InstalledVersion
    if ($current) { Say "installed: $current" } else { Say 'installed: (nothing)' }
    $release = Get-LatestRelease
    if (-not $release) {
        Say "latest:    (could not reach $Api)"
        return 1
    }
    $tag = Get-Prop $release 'tag_name'
    if ($tag) { Say "latest:    $tag" } else { Say 'latest:    (none published)' }
    if ($tag -and $tag -ne $current) {
        Say 'An update is available. Run this script with no arguments to install it.'
        return 10
    }
    Say 'Up to date.'
    return 0
}

function Uninstall-Game {
    foreach ($p in @($Prefix, "$Prefix.new", "$Prefix.old")) {
        if (Test-Path $p) { Remove-Item -Recurse -Force $p }
    }
    if (Test-Windows) {
        $links = @(
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Ashen Hollow.lnk')
        )
        try { $links += (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Ashen Hollow.lnk') } catch {}
        foreach ($l in $links) { if ($l -and (Test-Path $l)) { Remove-Item -Force $l } }
    }
    Say "$Name removed. Save files and settings were left alone."
    Say 'They live in %APPDATA%\Godot\app_userdata\Ashen Hollow'
    return 0
}

$code = 0
if     ($Uninstall) { $code = Uninstall-Game }
elseif ($Check)     { $code = Test-Update }
elseif ($Launch)    { $code = Start-Game }
else                { $code = Install-Game $Force.IsPresent $false }
exit $code
