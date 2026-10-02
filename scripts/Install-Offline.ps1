[CmdletBinding()]
param(
    [string]$ProjectPath,
    [switch]$SkipEditorInstall
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Find-EditorCommand {
    $commands = @("codium", "code")
    foreach ($cmd in $commands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    return $null
}

$editor = Find-EditorCommand

if (-not $editor -and -not $SkipEditorInstall) {
    $installer = Get-ChildItem -Path (Join-Path $Root "vendor\vscodium") -Filter "VSCodiumUserSetup-x64-*.exe" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($installer) {
        Write-Host "Installing VSCodium from $($installer.Name)"
        Start-Process -FilePath $installer.FullName -ArgumentList "/VERYSILENT", "/NORESTART" -Wait
        $editor = Find-EditorCommand
    }
}

if (-not $editor) {
    throw "VS Code or VSCodium command was not found. Install one manually, then rerun this script."
}

$vsix = Get-ChildItem -Path (Join-Path $Root "vendor\extensions") -Filter "*.vsix" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $vsix) { throw "Roo Code VSIX was not found in vendor\extensions." }

Write-Host "Installing Roo Code extension: $($vsix.Name)"
& $editor --install-extension $vsix.FullName --force
if ($LASTEXITCODE -ne 0) { throw "Extension installation failed with exit code $LASTEXITCODE." }

$server = Get-ChildItem -Path (Join-Path $Root "vendor\llama.cpp") -Recurse -Filter "llama-server.exe" -File | Select-Object -First 1
if ($server) {
    Write-Host "llama.cpp server found: $($server.FullName)"
} else {
    Write-Warning "llama-server.exe was not found. Rebuild the bundle with llama.cpp assets or place llama-server.exe under vendor\llama.cpp."
}

if ($ProjectPath) {
    & (Join-Path $PSScriptRoot "Configure-Workspace.ps1") -ProjectPath $ProjectPath
}

Write-Host "Offline coding agent installation completed."
Write-Host "Put a Qwen GGUF model under models\, then run scripts\Start-LocalModel.ps1."

