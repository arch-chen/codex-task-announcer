[CmdletBinding()]
param(
    [ValidateSet('xiaoxiao', 'xiaoyi', 'yunxi', 'yunyang', 'yunjian', 'yunxia')]
    [string]$Voice = 'xiaoxiao',
    [string]$ProjectPath = '',
    [string]$ProjectName = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$sourcePlugin = Join-Path $packageRoot 'plugin'
$hashManifest = Join-Path $packageRoot 'SHA256SUMS.txt'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)
    [IO.File]::WriteAllText($Path, $Value, (New-Object Text.UTF8Encoding($false)))
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    Write-Utf8NoBom -Path $Path -Value ($Value | ConvertTo-Json -Depth 12)
}

function Test-PackageIntegrity {
    if (-not (Test-Path -LiteralPath $hashManifest -PathType Leaf)) {
        throw 'SHA256SUMS.txt is missing.'
    }
    $failures = @()
    foreach ($line in Get-Content -LiteralPath $hashManifest -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) {
            $failures += "Invalid manifest line: $line"
            continue
        }
        $expected = $parts[0].Trim().ToUpperInvariant()
        $relative = $parts[1]
        $path = Join-Path $packageRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures += "Missing: $relative"
            continue
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
            $failures += "Hash mismatch: $relative"
        }
    }
    if ($failures.Count -gt 0) {
        throw ($failures -join [Environment]::NewLine)
    }
}

function Resolve-NodeExecutable {
    param([string]$UserHome)
    $candidates = @(
        (Join-Path $UserHome '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
    )
    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
    if (Test-Path -LiteralPath $runtimeRoot) {
        $runtimeNode = Get-ChildItem -LiteralPath $runtimeRoot -Filter node.exe -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($runtimeNode) { $candidates += $runtimeNode.FullName }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    $command = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw 'Node.js was not found. Install/open Codex Desktop fully, then retry.'
}

function ConvertTo-TomlStringArray {
    param([string[]]$Values)
    $items = foreach ($value in $Values) { ConvertTo-Json -InputObject ([string]$value) -Compress }
    return '[ ' + ($items -join ', ') + ' ]'
}

function Add-OrReplaceProject {
    param([object]$Settings, [string]$Path, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = [IO.Path]::GetFileName($fullPath) }
    $projects = @($Settings.projects | Where-Object { $_ })
    $replacement = [PSCustomObject]@{ path = $fullPath; name = $Name; speechText = '' }
    $replaced = $false
    for ($index = 0; $index -lt $projects.Count; $index++) {
        $existingPath = [IO.Path]::GetFullPath([string]$projects[$index].path).TrimEnd([char[]]@('\', '/'))
        if ($existingPath -ieq $fullPath) {
            $projects[$index] = $replacement
            $replaced = $true
            break
        }
    }
    if (-not $replaced) { $projects += $replacement }
    $Settings.projects = @($projects)
}

foreach ($required in @(
    '.codex-plugin\plugin.json',
    'project-names.json',
    'scripts\announce.ps1',
    'scripts\generate-speech.js',
    'scripts\set-voice.ps1',
    'vendor\node_modules\node-edge-tts\dist\edge-tts.js'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourcePlugin $required) -PathType Leaf)) {
        throw "Required package file is missing: plugin\$required"
    }
}

Test-PackageIntegrity
$packageManifest = Get-Content -LiteralPath (Join-Path $packageRoot 'package-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $sourcePlugin '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$templateSettings = Get-Content -LiteralPath (Join-Path $sourcePlugin 'project-names.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$userHome = [Environment]::GetFolderPath('UserProfile')
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $userHome '.codex' }
$node = Resolve-NodeExecutable -UserHome $userHome
$codexCommand = Get-Command codex.exe, codex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $codexCommand) { throw 'Codex CLI was not found in PATH.' }

if ($ValidateOnly) {
    [PSCustomObject]@{
        Package = '{0}-{1}' -f [string]$packageManifest.packageName, [string]$packageManifest.packageVersion
        PluginVersion = $manifest.version
        VoiceCount = @($templateSettings.onlineTts.voices).Count
        Node = $node
        Codex = $codexCommand.Source
        Integrity = 'PASS'
    } | Format-List
    exit 0
}

$configPath = Join-Path $codexHome 'config.toml'
$marketplacePath = Join-Path $userHome '.agents\plugins\marketplace.json'
$targetPlugin = Join-Path $userHome 'plugins\codex-task-announcer'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $codexHome "backups\codex-task-announcer\$timestamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$configText = ''
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $backupRoot 'config.toml')
    $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
}
else {
    Write-Utf8NoBom -Path (Join-Path $backupRoot 'config-missing.marker') -Value ''
}
if (Test-Path -LiteralPath $marketplacePath -PathType Leaf) {
    Copy-Item -LiteralPath $marketplacePath -Destination (Join-Path $backupRoot 'marketplace.json')
}
else {
    Write-Utf8NoBom -Path (Join-Path $backupRoot 'marketplace-missing.marker') -Value ''
}

$previousForward = @()
$notifyPattern = '(?m)^[\t ]*notify[\t ]*=[\t ]*(\[[^\r\n]*\])[\t ]*$'
$notifyMatch = [regex]::Match($configText, $notifyPattern)
$hasAnyNotify = [regex]::IsMatch($configText, '(?m)^[\t ]*notify[\t ]*=')
if ($hasAnyNotify -and -not $notifyMatch.Success) {
    throw "The existing notify setting is multi-line or unsupported. Backup: $backupRoot"
}

$existingSettingsPath = Join-Path $targetPlugin 'project-names.json'
$existingSettings = $null
if (Test-Path -LiteralPath $existingSettingsPath -PathType Leaf) {
    $existingSettings = Get-Content -LiteralPath $existingSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
if ($notifyMatch.Success) {
    if ($notifyMatch.Value -match 'codex-task-announcer[\\/]scripts[\\/]announce\.ps1' -and $existingSettings) {
        $previousForward = @($existingSettings.forwardCommand)
    }
    else {
        try { $previousForward = @($notifyMatch.Groups[1].Value | ConvertFrom-Json) }
        catch { throw "Unable to preserve the existing notify command. Backup: $backupRoot" }
    }
}

$targetParent = Split-Path -Parent $targetPlugin
New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
$stagingPlugin = Join-Path $targetParent ".codex-task-announcer-install-$timestamp"
Copy-Item -LiteralPath $sourcePlugin -Destination $stagingPlugin -Recurse -Force
$settingsPath = Join-Path $stagingPlugin 'project-names.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$selectedVoice = @($settings.onlineTts.voices) | Where-Object { [string]$_.alias -ieq $Voice } | Select-Object -First 1
if (-not $selectedVoice) { throw "Voice alias is not available: $Voice" }
$settings.onlineTts.voice = [string]$selectedVoice.id
$settings.onlineTts.nodePath = $node
$settings.forwardCommand = @($previousForward)
if ($existingSettings) {
    $settings.projects = @($existingSettings.projects | Where-Object { $_ })
    if ($existingSettings.PSObject.Properties.Name -contains 'suppressAutomationAnnouncements') {
        $settings.suppressAutomationAnnouncements = [bool]$existingSettings.suppressAutomationAnnouncements
    }
}
Add-OrReplaceProject -Settings $settings -Path $ProjectPath -Name $ProjectName
Write-JsonFile -Path $settingsPath -Value $settings

if (Test-Path -LiteralPath $targetPlugin) {
    Move-Item -LiteralPath $targetPlugin -Destination (Join-Path $backupRoot 'plugin-previous')
}
else {
    Write-Utf8NoBom -Path (Join-Path $backupRoot 'plugin-missing.marker') -Value ''
}
Move-Item -LiteralPath $stagingPlugin -Destination $targetPlugin

if (Test-Path -LiteralPath $marketplacePath -PathType Leaf) {
    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$marketplace.name)) { throw 'Existing marketplace.json has no name.' }
}
else {
    $marketplace = [PSCustomObject]@{
        name = 'personal'
        interface = [PSCustomObject]@{ displayName = 'Personal' }
        plugins = @()
    }
}
$entry = [PSCustomObject]@{
    name = 'codex-task-announcer'
    source = [PSCustomObject]@{ source = 'local'; path = './plugins/codex-task-announcer' }
    policy = [PSCustomObject]@{ installation = 'AVAILABLE'; authentication = 'ON_INSTALL' }
    category = 'Productivity'
}
$entries = @($marketplace.plugins | Where-Object { $_ -and [string]$_.name -ne 'codex-task-announcer' })
$entries += $entry
$marketplace.plugins = @($entries)
New-Item -ItemType Directory -Path (Split-Path -Parent $marketplacePath) -Force | Out-Null
Write-JsonFile -Path $marketplacePath -Value $marketplace

$notifyValues = @(
    (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
    (Join-Path $targetPlugin 'scripts\announce.ps1')
)
$notifyLine = 'notify = ' + (ConvertTo-TomlStringArray -Values $notifyValues)
if ($notifyMatch.Success) {
    $configText = [regex]::Replace($configText, $notifyPattern, $notifyLine, 1)
}
else {
    $configText = $notifyLine + [Environment]::NewLine + $configText
}
New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
Write-Utf8NoBom -Path $configPath -Value $configText

& $codexCommand.Source plugin add "codex-task-announcer@$($marketplace.name)"
if ($LASTEXITCODE -ne 0) { throw "codex plugin add failed. Backup: $backupRoot" }

$result = [ordered]@{
    installedAt = (Get-Date).ToString('o')
    pluginVersion = $manifest.version
    pluginPath = $targetPlugin
    marketplacePath = $marketplacePath
    marketplaceName = [string]$marketplace.name
    configPath = $configPath
    backupPath = $backupRoot
    voiceAlias = $Voice
    voiceId = [string]$selectedVoice.id
    projectPath = $ProjectPath
    projectName = $ProjectName
    nodePath = $node
    restartRequired = $true
}
$resultPath = Join-Path $codexHome 'codex-task-announcer-install-result.json'
Write-JsonFile -Path $resultPath -Value $result
$result | Format-List
Write-Output 'Installation completed. Fully restart Codex, then test in a new task.'
