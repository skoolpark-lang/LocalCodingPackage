[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ProjectPath,
    [switch]$InitGitIfMissing
)

$ErrorActionPreference = "Stop"
$Project = Resolve-Path $ProjectPath

function Ensure-Directory {
    param([Parameter(Mandatory)] [string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Add-Task {
    param(
        [System.Collections.ArrayList]$Tasks,
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [string]$Command,
        [string]$Group = "build"
    )

    [void]$Tasks.Add([ordered]@{
        label = $Label
        type = "shell"
        command = $Command
        group = $Group
        problemMatcher = @()
        presentation = [ordered]@{
            reveal = "always"
            panel = "shared"
            clear = $true
        }
    })
}

Push-Location $Project
try {
    $insideGit = $false
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) { $insideGit = $true }

    if (-not $insideGit -and $InitGitIfMissing) {
        git init
        $insideGit = $true
    }

    if (-not $insideGit) {
        Write-Warning "Project is not a Git repository. The agent pack works best with Git. Rerun with -InitGitIfMissing to initialize."
    }

    $tasks = [System.Collections.ArrayList]::new()
    $profiles = [System.Collections.ArrayList]::new()

    $solutions = Get-ChildItem -Path $Project -Filter "*.sln" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue
    $csprojs = Get-ChildItem -Path $Project -Filter "*.csproj" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue
    $cmakeLists = Get-ChildItem -Path $Project -Filter "CMakeLists.txt" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue
    $cmakePresets = Get-ChildItem -Path $Project -Filter "CMakePresets.json" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue

    if ($solutions.Count -gt 0) {
        $sln = Resolve-Path -Relative $solutions[0].FullName
        Add-Task -Tasks $tasks -Label "Agent: dotnet build solution Debug" -Command "dotnet build `"$sln`" -c Debug"
        Add-Task -Tasks $tasks -Label "Agent: dotnet test solution" -Command "dotnet test `"$sln`" --no-restore" -Group "test"
        [void]$profiles.Add([ordered]@{ name = "dotnet-build-debug"; type = "dotnet"; command = "dotnet build `"$sln`" -c Debug"; autoDetected = $true; runAfterAgentEdit = $true })
        [void]$profiles.Add([ordered]@{ name = "dotnet-test"; type = "dotnet"; command = "dotnet test `"$sln`" --no-restore"; autoDetected = $true; runAfterAgentEdit = $false })
    } elseif ($csprojs.Count -gt 0) {
        $proj = Resolve-Path -Relative $csprojs[0].FullName
        Add-Task -Tasks $tasks -Label "Agent: dotnet build project Debug" -Command "dotnet build `"$proj`" -c Debug"
        Add-Task -Tasks $tasks -Label "Agent: dotnet test project" -Command "dotnet test `"$proj`" --no-restore" -Group "test"
        [void]$profiles.Add([ordered]@{ name = "dotnet-build-debug"; type = "dotnet"; command = "dotnet build `"$proj`" -c Debug"; autoDetected = $true; runAfterAgentEdit = $true })
    }

    if ($cmakePresets.Count -gt 0) {
        Add-Task -Tasks $tasks -Label "Agent: cmake configure preset" -Command "cmake --preset default"
        Add-Task -Tasks $tasks -Label "Agent: cmake build preset" -Command "cmake --build --preset default"
        [void]$profiles.Add([ordered]@{ name = "cmake-build-preset"; type = "cmake"; command = "cmake --build --preset default"; autoDetected = $true; runAfterAgentEdit = $true })
    } elseif ($cmakeLists.Count -gt 0) {
        Add-Task -Tasks $tasks -Label "Agent: cmake configure Debug" -Command "cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug"
        Add-Task -Tasks $tasks -Label "Agent: cmake build Debug" -Command "cmake --build build --config Debug"
        [void]$profiles.Add([ordered]@{ name = "cmake-build-debug"; type = "cmake"; command = "cmake --build build --config Debug"; autoDetected = $true; runAfterAgentEdit = $true })
    }

    Add-Task -Tasks $tasks -Label "Agent: git status" -Command "git status --short" -Group "none"
    Add-Task -Tasks $tasks -Label "Agent: git diff" -Command "git diff -- ." -Group "none"

    Ensure-Directory (Join-Path $Project ".vscode")
    $tasksPath = Join-Path $Project ".vscode\tasks.json"
    if (Test-Path $tasksPath) {
        $backup = "$tasksPath.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
        Copy-Item -LiteralPath $tasksPath -Destination $backup
        Write-Host "Existing tasks.json backed up to $backup"
    }

    [ordered]@{
        version = "2.0.0"
        tasks = $tasks
    } | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $tasksPath

    $settingsPath = Join-Path $Project ".vscode\settings.json"
    $workspaceSettings = [ordered]@{
        "telemetry.telemetryLevel" = "off"
        "update.mode" = "none"
        "extensions.autoUpdate" = $false
        "extensions.autoCheckUpdates" = $false
        "extensions.ignoreRecommendations" = $true
        "workbench.enableExperiments" = $false
        "workbench.settings.enableNaturalLanguageSearch" = $false
    }
    $workspaceSettings | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $settingsPath

    $profilePath = Join-Path $Project "local-agent.build-profiles.json"
    [ordered]@{
        agent = [ordered]@{
            autoApplyChanges = $true
            maxBuildRepairAttempts = 2
            requireGitRepository = $true
        }
        buildProfiles = $profiles
    } | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $profilePath

    Ensure-Directory (Join-Path $Project ".roo\rules")
    Ensure-Directory (Join-Path $Project ".clinerules")
    Copy-Item -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "rules\roo\10-local-coding-agent.md") -Destination (Join-Path $Project ".roo\rules\10-local-coding-agent.md") -Force
    Copy-Item -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "rules\cline\10-local-coding-agent.md") -Destination (Join-Path $Project ".clinerules\10-local-coding-agent.md") -Force

    $rooIgnore = Join-Path $Project ".rooignore"
    if (-not (Test-Path $rooIgnore)) {
        @(
            "bin/",
            "obj/",
            "build/",
            ".git/",
            ".vs/",
            "*.user",
            "*.suo",
            "packages/",
            "node_modules/"
        ) | Set-Content -Encoding UTF8 -Path $rooIgnore
    }

    Write-Host "Workspace configured: $Project"
    Write-Host "Generated tasks: $tasksPath"
    Write-Host "Generated build profiles: $profilePath"
}
finally {
    Pop-Location
}
