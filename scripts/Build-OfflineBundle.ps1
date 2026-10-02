[CmdletBinding()]
param(
    [string]$OutputName = "LocalCodingAgentOfflinePack.zip",
    [switch]$SkipVSCodium,
    [switch]$SkipRooCode,
    [switch]$SkipLlamaCpp
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Vendor = Join-Path $Root "vendor"
$ArchiveDir = Join-Path $Vendor "archives"
$ManifestPath = Join-Path $Root "THIRD_PARTY_MANIFEST.json"
$DistDir = Join-Path $Root "dist"

New-Item -ItemType Directory -Force -Path $ArchiveDir, $DistDir, (Join-Path $Vendor "extensions"), (Join-Path $Vendor "vscodium"), (Join-Path $Vendor "llama.cpp") | Out-Null

function Get-LatestRelease {
    param([Parameter(Mandatory)] [string]$Repo)
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
}

function Get-Releases {
    param([Parameter(Mandatory)] [string]$Repo)
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=30"
}

function Download-Asset {
    param(
        [Parameter(Mandatory)] [object]$Asset,
        [Parameter(Mandatory)] [string]$DestinationDirectory
    )

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $outFile = Join-Path $DestinationDirectory $Asset.name
    Write-Host "Downloading $($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $outFile
    $hash = Get-FileHash -Algorithm SHA256 -Path $outFile

    [pscustomobject]@{
        name = $Asset.name
        source = $Asset.browser_download_url
        path = (Resolve-Path $outFile).Path
        sha256 = $hash.Hash
        size = (Get-Item $outFile).Length
    }
}

$items = @()

if (-not $SkipRooCode) {
    $roo = Get-LatestRelease -Repo "RooCodeInc/Roo-Code"
    $vsix = $roo.assets | Where-Object { $_.name -match "\.vsix$" } | Select-Object -First 1
    if (-not $vsix) { throw "Roo Code VSIX asset was not found." }
    $items += Download-Asset -Asset $vsix -DestinationDirectory (Join-Path $Vendor "extensions")
}

if (-not $SkipVSCodium) {
    $codium = Get-LatestRelease -Repo "VSCodium/vscodium"
    $setup = $codium.assets | Where-Object { $_.name -match "^VSCodiumUserSetup-x64-.*\.exe$" } | Select-Object -First 1
    if (-not $setup) { throw "VSCodium x64 user setup asset was not found." }
    $items += Download-Asset -Asset $setup -DestinationDirectory (Join-Path $Vendor "vscodium")
}

if (-not $SkipLlamaCpp) {
    $llamaAsset = $null
    $llamaTag = $null
    foreach ($release in (Get-Releases -Repo "ggml-org/llama.cpp")) {
        $candidate = $release.assets | Where-Object { $_.name -match "^llama-.*-bin-win-cpu-x64\.zip$" } | Select-Object -First 1
        if ($candidate) {
            $llamaAsset = $candidate
            $llamaTag = $release.tag_name
            break
        }
    }

    if (-not $llamaAsset) { throw "llama.cpp Windows CPU x64 zip asset was not found in recent releases." }
    $download = Download-Asset -Asset $llamaAsset -DestinationDirectory $ArchiveDir
    $items += $download

    $llamaDir = Join-Path $Vendor "llama.cpp"
    Get-ChildItem -Path $llamaDir -Force | Remove-Item -Recurse -Force
    Expand-Archive -Path $download.path -DestinationPath $llamaDir -Force
    $server = Get-ChildItem -Path $llamaDir -Recurse -Filter "llama-server.exe" | Select-Object -First 1
    if (-not $server) { throw "llama-server.exe was not found after extracting $($llamaAsset.name)." }

    $items += [pscustomobject]@{
        name = "llama.cpp extracted"
        source = "ggml-org/llama.cpp $llamaTag"
        path = (Resolve-Path $llamaDir).Path
        sha256 = $null
        size = $null
    }
}

$manifest = [pscustomobject]@{
    generatedAt = (Get-Date).ToString("o")
    package = "Offline Coding Agent Pack"
    thirdParty = $items
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $ManifestPath

$zipPath = Join-Path $DistDir $OutputName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

$tempRoot = Join-Path $env:TEMP ("local-coding-agent-pack-" + [guid]::NewGuid().ToString("N"))
$staging = Join-Path $tempRoot "LocalCodingAgentOfflinePack"
New-Item -ItemType Directory -Force -Path $staging | Out-Null

$exclude = @("dist")
Get-ChildItem -Path $Root -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $staging -Recurse -Force
}

$onlineOnlyScripts = @(
    "scripts\Build-OfflineBundle.ps1",
    "scripts\Publish-GitHubRelease.ps1"
)

foreach ($relative in $onlineOnlyScripts) {
    $onlineScript = Join-Path $staging $relative
    if (Test-Path -LiteralPath $onlineScript -PathType Leaf) {
        Remove-Item -LiteralPath $onlineScript -Force
    }
}

Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $tempRoot -Recurse -Force

Write-Host "Offline bundle created: $zipPath"
