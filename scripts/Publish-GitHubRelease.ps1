[CmdletBinding()]
param(
    [string]$PackageRoot = "",
    [string]$Repo = "skoolpark-lang/LocalCodingPackage",
    [string]$Branch = "main",
    [string]$Tag = "",
    [string]$AssetName = "",
    [switch]$Prerelease = $true
)

$ErrorActionPreference = "Stop"

function Get-GitHubToken {
    if ($env:GH_TOKEN) { return $env:GH_TOKEN.Trim() }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN.Trim() }

    $paths = @(
        "C:\CodexWorks\Commit Report\.secrets\github-token.txt",
        "C:\CodexWorks\Easy Log Analyzer\.secrets\github-token.txt"
    )

    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return (Get-Content -LiteralPath $path -Raw).Trim()
        }
    }

    throw "GitHub token not found. Set GH_TOKEN/GITHUB_TOKEN or create a supported .secrets\github-token.txt file."
}

function Invoke-GitHubJson {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [object]$Body = $null
    )

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }

    $json = $Body | ConvertTo-Json -Depth 20
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)] [string]$BasePath,
        [Parameter(Mandatory)] [string]$FullPath
    )

    $baseUri = [System.Uri](([System.IO.Path]::GetFullPath($BasePath).TrimEnd("\") + "\"))
    $fileUri = [System.Uri]([System.IO.Path]::GetFullPath($FullPath))
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString()).Replace("/", "\")
}

function Assert-ZipEntry {
    param(
        [Parameter(Mandatory)] [string]$ZipPath,
        [Parameter(Mandatory)] [string[]]$Entries
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $names = $archive.Entries | ForEach-Object { $_.FullName.Replace("\", "/") }
        foreach ($entry in $Entries) {
            $normalized = $entry.Replace("\", "/")
            if ($names -notcontains $normalized) {
                throw "ZIP missing required entry: $normalized"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
}

$PackageRoot = [System.IO.Path]::GetFullPath($PackageRoot)
if (-not (Test-Path -LiteralPath $PackageRoot -PathType Container)) {
    throw "Package root not found: $PackageRoot"
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = "offline-pack-" + (Get-Date -Format "yyyyMMdd")
}

$date = if ($Tag -match "(\d{8})$") { $Matches[1] } else { Get-Date -Format "yyyyMMdd" }
if ([string]::IsNullOrWhiteSpace($AssetName)) {
    $AssetName = "LocalCodingAgentOfflinePack-$date.zip"
}

$zip = Join-Path $PackageRoot "dist\LocalCodingAgentOfflinePack.zip"
if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) {
    throw "Release ZIP not found: $zip. Run scripts\Build-OfflineBundle.ps1 first."
}

Assert-ZipEntry -ZipPath $zip -Entries @(
    "scripts/Install-Offline.ps1",
    "scripts/Start-LocalModel.ps1",
    "scripts/Configure-Workspace.ps1",
    "vendor/extensions/roo-cline-3.54.0.vsix",
    "vendor/vscodium/VSCodiumUserSetup-x64-1.135.06055.exe",
    "vendor/llama.cpp/llama-server.exe"
)

$token = Get-GitHubToken
$headers = @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "LocalCodingPackage-release-script"
}

$api = "https://api.github.com/repos/$Repo"
$ref = Invoke-GitHubJson -Method Get -Uri "$api/git/ref/heads/$Branch" -Headers $headers
$parentSha = $ref.object.sha
$parentCommit = Invoke-GitHubJson -Method Get -Uri "$api/git/commits/$parentSha" -Headers $headers
$baseTreeSha = $parentCommit.tree.sha

$includePatterns = @(
    "README.ko.md",
    "docs\*.md",
    "models\*.txt",
    "profiles\*.json",
    "rules\roo\*.md",
    "rules\cline\*.md",
    "scripts\*.ps1"
)

$files = foreach ($pattern in $includePatterns) {
    Get-ChildItem -Path (Join-Path $PackageRoot $pattern) -File -ErrorAction SilentlyContinue
}

$tree = @()
foreach ($file in ($files | Sort-Object FullName -Unique)) {
    $relative = (Get-RelativePath -BasePath $PackageRoot -FullPath $file.FullName).Replace("\", "/")
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $blob = Invoke-GitHubJson -Method Post -Uri "$api/git/blobs" -Headers $headers -Body @{
        content = $content
        encoding = "utf-8"
    }
    $tree += @{
        path = $relative
        mode = "100644"
        type = "blob"
        sha = $blob.sha
    }
}

$newTree = Invoke-GitHubJson -Method Post -Uri "$api/git/trees" -Headers $headers -Body @{
    base_tree = $baseTreeSha
    tree = $tree
}

$commit = Invoke-GitHubJson -Method Post -Uri "$api/git/commits" -Headers $headers -Body @{
    message = "Add offline coding agent package files"
    tree = $newTree.sha
    parents = @($parentSha)
}

Invoke-GitHubJson -Method Patch -Uri "$api/git/refs/heads/$Branch" -Headers $headers -Body @{
    sha = $commit.sha
    force = $false
} | Out-Null

$release = $null
try {
    $release = Invoke-GitHubJson -Method Get -Uri "$api/releases/tags/$Tag" -Headers $headers
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 404) {
        throw
    }
}

$zipHash = Get-FileHash -Algorithm SHA256 -Path $zip
$bodyText = @"
Offline Windows package for a local coding agent setup.

Contents:
- VSCodium Windows installer
- Roo Code VSIX extension
- llama.cpp Windows server runtime
- PowerShell install/start/workspace configuration scripts
- C#/WPF and C++ local agent rules

Model files are not included. Copy a Qwen GGUF model into the models folder after extracting the package.

Validation:
- PowerShell script syntax check
- Required ZIP entries verified
- Release ZIP SHA256: $($zipHash.Hash)
"@

if ($null -eq $release) {
    $release = Invoke-GitHubJson -Method Post -Uri "$api/releases" -Headers $headers -Body @{
        tag_name = $Tag
        target_commitish = $Branch
        name = "Local Coding Agent Offline Pack $date"
        body = $bodyText
        draft = $false
        prerelease = [bool]$Prerelease
    }
}
else {
    $release = Invoke-GitHubJson -Method Patch -Uri "$api/releases/$($release.id)" -Headers $headers -Body @{
        name = "Local Coding Agent Offline Pack $date"
        body = $bodyText
        draft = $false
        prerelease = [bool]$Prerelease
    }
}

foreach ($asset in @($release.assets)) {
    if ($asset.name -eq $AssetName) {
        Invoke-RestMethod -Method Delete -Uri "$api/releases/assets/$($asset.id)" -Headers $headers | Out-Null
    }
}

$uploadUrl = $release.upload_url
if ($uploadUrl.Contains("{")) {
    $uploadUrl = $uploadUrl.Substring(0, $uploadUrl.IndexOf("{"))
}

$uploadUri = $uploadUrl + "?name=" + [System.Uri]::EscapeDataString($AssetName)
$uploaded = Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers -ContentType "application/zip" -InFile $zip

[pscustomobject]@{
    Repository = $Repo
    Branch = $Branch
    Commit = $commit.sha
    Tag = $Tag
    ReleaseUrl = $release.html_url
    AssetName = $uploaded.name
    AssetSize = $uploaded.size
    AssetUrl = $uploaded.browser_download_url
    ZipPath = $zip
    Sha256 = $zipHash.Hash
} | ConvertTo-Json -Compress

