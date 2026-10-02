[CmdletBinding()]
param(
    [string]$ModelPath,
    [int]$ContextSize = 32768,
    [int]$Port = 8080,
    [string]$HostAddress = "127.0.0.1",
    [int]$GpuLayers = 0,
    [int]$Threads = 0,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $ModelPath) {
    $model = Get-ChildItem -Path (Join-Path $Root "models") -Filter "*.gguf" -File | Sort-Object Length -Descending | Select-Object -First 1
    if (-not $model) {
        throw "No GGUF model found. Copy a Qwen GGUF file into the models folder or pass -ModelPath."
    }
    $ModelPath = $model.FullName
}

if (-not (Test-Path -LiteralPath $ModelPath)) {
    throw "Model file not found: $ModelPath"
}

$server = Get-ChildItem -Path (Join-Path $Root "vendor\llama.cpp") -Recurse -Filter "llama-server.exe" -File | Select-Object -First 1
if (-not $server) {
    throw "llama-server.exe was not found under vendor\llama.cpp. Run Build-OfflineBundle.ps1 on an online PC first."
}

$args = @(
    "-m", $ModelPath,
    "-c", $ContextSize,
    "--host", $HostAddress,
    "--port", $Port,
    "--jinja",
    "--temp", "1.0",
    "--top-p", "0.95",
    "--top-k", "40"
)

if ($GpuLayers -gt 0) {
    $args += @("-ngl", $GpuLayers)
}

if ($Threads -gt 0) {
    $args += @("-t", $Threads)
}

Write-Host "Starting llama.cpp server"
Write-Host "Model: $ModelPath"
Write-Host "API: http://$HostAddress`:$Port/v1"

if (-not $NoBrowser) {
    Write-Host "Configure Roo Code as OpenAI Compatible:"
    Write-Host "  Base URL: http://$HostAddress`:$Port/v1"
    Write-Host "  API Key: none"
    Write-Host "  Model: local-qwen-coder"
}

& $server.FullName @args

