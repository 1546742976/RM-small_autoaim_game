param(
    [Parameter(Mandatory = $true)][string]$GodotPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$enginePath = (Resolve-Path -LiteralPath $GodotPath).Path
$projectPath = Join-Path $repoRoot '射击游戏'
$artifactPath = Join-Path $repoRoot 'artifacts'
$releasePath = Join-Path $repoRoot 'builds\windows'
$templatePath = Join-Path $PSScriptRoot 'cache\4.7.2-stable\windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw 'Missing Windows template. Run: python tools/fetch_windows_template.py'
}

New-Item -ItemType Directory -Force -Path $artifactPath, $releasePath | Out-Null
$oldEnvironment = @{}
try {
    # Keep build/editor caches and temporary files inside this workspace.
    foreach ($key in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')) {
        $oldEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        $directory = Join-Path $artifactPath "runtime\$($key.ToLower())"
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        [Environment]::SetEnvironmentVariable($key, $directory, 'Process')
    }
    function Invoke-Engine([string[]]$EngineArgs) {
        & $enginePath @EngineArgs 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Godot failed: $LASTEXITCODE" }
        $logArgument = [Array]::IndexOf($EngineArgs, '--log-file')
        if ($logArgument -ge 0 -and (Select-String -LiteralPath $EngineArgs[$logArgument + 1] -Pattern 'SCRIPT ERROR:|^ERROR:|SMOKE FAIL|^FAIL' -Quiet)) {
            throw "Inspect $($EngineArgs[$logArgument + 1]) before shipping."
        }
    }
    Invoke-Engine @('--headless', '--path', $projectPath, '--editor', '--import', '--quit', '--log-file', "$artifactPath/import.log")
    Invoke-Engine @('--headless', '--path', $projectPath, '--script', 'res://tests/test_rules.gd', '--log-file', "$artifactPath/rules.log")
    Invoke-Engine @('--headless', '--path', $projectPath, '--log-file', "$artifactPath/game-smoke-headless.log", '--', '--smoke-test')
    Invoke-Engine @('--headless', '--path', $projectPath, '--export-release', 'Windows Desktop', '--log-file', "$artifactPath/export.log")
    Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md'), (Join-Path $repoRoot 'ASSET_MANIFEST.md'), (Join-Path $repoRoot 'VALIDATION.md'), (Join-Path $repoRoot 'UI_DESIGN.md'), (Join-Path $repoRoot 'CONTROL_API.md'), (Join-Path $repoRoot 'LICENSE') -Destination $releasePath -Force
    $sdkPath = Join-Path $releasePath 'sdk'
    New-Item -ItemType Directory -Force -Path $sdkPath | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'sdk\cpp') -Destination $sdkPath -Recurse -Force
    $licensesPath = Join-Path $releasePath 'licenses'
    New-Item -ItemType Directory -Force -Path $licensesPath | Out-Null
    Copy-Item -LiteralPath "$projectPath/assets/fonts/OFL.txt", "$projectPath/assets/fonts/NOTICE.txt" -Destination $licensesPath -Force
    if (Test-Path -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination $licensesPath -Force
    }
    Copy-Item -Path "$projectPath/assets/licenses/*" -Destination $licensesPath -Force
    Write-Host "Windows game: $releasePath\RMPrecisionLab.exe"
} finally {
    foreach ($key in $oldEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $oldEnvironment[$key], 'Process')
    }
}
