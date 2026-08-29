[CmdletBinding()]
param(
    [string]$Voice,
    [string]$ProjectPath,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $pluginRoot 'project-names.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$voices = @($settings.onlineTts.voices)

if ($List -or [string]::IsNullOrWhiteSpace($Voice)) {
    $voices | Select-Object alias, displayName, gender, id | Format-Table -AutoSize
    if ([string]::IsNullOrWhiteSpace($Voice)) {
        exit 0
    }
}

$selected = $voices | Where-Object {
    [string]$_.alias -ieq $Voice -or
    [string]$_.id -ieq $Voice -or
    [string]$_.displayName -ieq $Voice
} | Select-Object -First 1
if (-not $selected) {
    throw "Unknown voice: $Voice. Run with -List to see available voices."
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $settings.onlineTts.voice = [string]$selected.id
    $scope = 'global default'
}
else {
    $normalizedTarget = [IO.Path]::GetFullPath($ProjectPath).TrimEnd([char[]]@('\', '/'))
    $project = @($settings.projects) | Where-Object {
        [IO.Path]::GetFullPath([string]$_.path).TrimEnd([char[]]@('\', '/')) -ieq $normalizedTarget
    } | Select-Object -First 1
    if (-not $project) {
        throw "Project path is not configured: $ProjectPath"
    }
    $project | Add-Member -NotePropertyName voice -NotePropertyValue ([string]$selected.id) -Force
    $scope = "project $normalizedTarget"
}

$json = $settings | ConvertTo-Json -Depth 10
$temporaryPath = "$settingsPath.tmp"
[IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temporaryPath -Destination $settingsPath -Force
Write-Output "Voice updated for $scope`: $($selected.displayName) [$($selected.id)]"
