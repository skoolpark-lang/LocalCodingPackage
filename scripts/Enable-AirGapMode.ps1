[CmdletBinding()]
param(
    [switch]$ConfigureFirewall
)

$ErrorActionPreference = "Stop"

function Merge-SettingsFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [hashtable]$Settings
    )

    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $data = @{}
        }
        else {
            $data = $raw | ConvertFrom-Json -AsHashtable
        }
    }
    else {
        $data = @{}
    }

    foreach ($key in $Settings.Keys) {
        $data[$key] = $Settings[$key]
    }

    $data | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $Path
}

$airGapSettings = @{
    "telemetry.telemetryLevel" = "off"
    "update.mode" = "none"
    "extensions.autoUpdate" = $false
    "extensions.autoCheckUpdates" = $false
    "extensions.ignoreRecommendations" = $true
    "workbench.enableExperiments" = $false
    "workbench.settings.enableNaturalLanguageSearch" = $false
    "npm.fetchOnlinePackageInfo" = $false
}

$settingFiles = @(
    Join-Path $env:APPDATA "Code\User\settings.json",
    Join-Path $env:APPDATA "VSCodium\User\settings.json"
)

foreach ($settingsFile in $settingFiles) {
    Merge-SettingsFile -Path $settingsFile -Settings $airGapSettings
    Write-Host "Air-gap editor settings applied: $settingsFile"
}

if ($ConfigureFirewall) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Firewall configuration requires an elevated PowerShell session."
    }

    $candidateExecutables = @(
        (Get-Command "codium" -ErrorAction SilentlyContinue).Source,
        (Get-Command "code" -ErrorAction SilentlyContinue).Source
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($exe in $candidateExecutables) {
        $ruleName = "LocalCodingPackage Block Outbound - " + (Split-Path -Leaf $exe)
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Action Block -Program $exe -Profile Any | Out-Null
            Write-Host "Outbound firewall block added: $exe"
        }
    }
}

Write-Host "Air-gap mode configured. Model traffic should use http://127.0.0.1:8080/v1 only."

