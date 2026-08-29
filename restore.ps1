[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'
$backup = [IO.Path]::GetFullPath($BackupPath)
if (-not (Test-Path -LiteralPath $backup -PathType Container)) { throw "Backup folder not found: $backup" }
$userHome = [Environment]::GetFolderPath('UserProfile')
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $userHome '.codex' }
$configPath = Join-Path $codexHome 'config.toml'
$marketplacePath = Join-Path $userHome '.agents\plugins\marketplace.json'
$targetPlugin = Join-Path $userHome 'plugins\codex-task-announcer'

if (Test-Path -LiteralPath (Join-Path $backup 'config.toml')) {
    Copy-Item -LiteralPath (Join-Path $backup 'config.toml') -Destination $configPath -Force
}
elseif (Test-Path -LiteralPath (Join-Path $backup 'config-missing.marker')) {
    Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath (Join-Path $backup 'marketplace.json')) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $marketplacePath) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $backup 'marketplace.json') -Destination $marketplacePath -Force
}
elseif (Test-Path -LiteralPath (Join-Path $backup 'marketplace-missing.marker')) {
    Remove-Item -LiteralPath $marketplacePath -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $targetPlugin) { Remove-Item -LiteralPath $targetPlugin -Recurse -Force }
if (Test-Path -LiteralPath (Join-Path $backup 'plugin-previous')) {
    Move-Item -LiteralPath (Join-Path $backup 'plugin-previous') -Destination $targetPlugin
}

Write-Output 'Restore completed. Fully restart Codex.'
