[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$EventJson,
    [switch]$RoutingOnly
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $pluginRoot 'project-names.json'
$logDirectory = Join-Path $env:LOCALAPPDATA 'CodexTaskAnnouncer'
$logPath = Join-Path $logDirectory 'announcer.log'

function Write-AnnouncerLog {
    param([string]$Message)

    try {
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
    catch {
        # Notification failures must never affect the Codex turn.
    }
}

function Get-EventValue {
    param(
        [object]$Event,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Event.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }
    return ''
}

function Get-TomlStringValue {
    param(
        [string]$Content,
        [string]$Key
    )

    $pattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*["''](?<value>[^"'']*)["'']\s*(?:#.*)?$'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Groups['value'].Value
    }
    return ''
}

function Get-CodexHomes {
    $pluginUserHome = Split-Path -Parent (Split-Path -Parent $pluginRoot)
    $profileHome = [Environment]::GetFolderPath('UserProfile')
    $candidates = @(
        (Join-Path $pluginUserHome '.codex'),
        [string]$env:CODEX_HOME,
        (Join-Path $env:USERPROFILE '.codex'),
        (Join-Path $profileHome '.codex')
    )

    $resolved = @()
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $resolved -notcontains $candidate) {
            $resolved += $candidate
        }
    }
    return @($resolved)
}

function Get-EventIdentifiers {
    param([object]$Event)

    $names = @(
        'thread-id', 'thread_id', 'threadId',
        'turn-id', 'turn_id', 'turnId',
        'conversation-id', 'conversation_id', 'conversationId',
        'task-id', 'task_id', 'taskId'
    )
    $identifiers = @()
    foreach ($name in $names) {
        $value = Get-EventValue -Event $Event -Names @($name)
        if (-not [string]::IsNullOrWhiteSpace($value) -and $identifiers -notcontains $value) {
            $identifiers += $value
        }
    }
    return @($identifiers)
}

function Test-FileTailContainsIdentifier {
    param(
        [string]$Path,
        [string[]]$Identifiers
    )

    $stream = New-Object IO.FileStream(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        $maximumBytes = 8MB
        $start = [Math]::Max(0, $stream.Length - $maximumBytes)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false)), $true, 4096, $true)
        try {
            $tail = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    foreach ($identifier in $Identifiers) {
        if ($tail.Contains($identifier)) {
            return $true
        }
    }
    return $false
}

function Get-AutomationSessionMatch {
    param(
        [string[]]$Identifiers,
        [string]$CodexHome
    )

    if ($Identifiers.Count -eq 0) {
        return $null
    }

    $sessionsRoot = Join-Path $CodexHome 'sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container)) {
        return $null
    }

    try {
        $recentThreshold = (Get-Date).AddMinutes(-15)
        $sessionFiles = @(Get-ChildItem -LiteralPath $sessionsRoot -Filter '*.jsonl' -File -Recurse -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -ge $recentThreshold } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20)
    }
    catch {
        Write-AnnouncerLog "Session metadata scan failed; announcement remains enabled: $($_.Exception.Message)"
        return $null
    }

    foreach ($sessionFile in $sessionFiles) {
        try {
            $firstLine = Get-Content -LiteralPath $sessionFile.FullName -TotalCount 1 -Encoding UTF8 -ErrorAction Stop
            $meta = ($firstLine | ConvertFrom-Json).payload
            if ([string]$meta.thread_source -ine 'automation') {
                continue
            }

            $sessionId = [string]$meta.id
            $identifierMatched = $Identifiers -contains $sessionId
            if (-not $identifierMatched) {
                $identifierMatched = Test-FileTailContainsIdentifier -Path $sessionFile.FullName -Identifiers $Identifiers
            }
            if ($identifierMatched) {
                if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = $sessionFile.BaseName }
                return [PSCustomObject]@{
                    Id = $sessionId
                    Kind = 'automation-session'
                    ThreadId = [string]$Identifiers[0]
                }
            }
        }
        catch {
            Write-AnnouncerLog "Ignored unreadable session metadata: $($sessionFile.FullName)"
        }
    }

    return $null
}

function Get-AutomationMatch {
    param([object]$Event)

    $identifiers = @(Get-EventIdentifiers -Event $Event)
    $threadId = Get-EventValue -Event $Event -Names @('thread-id', 'thread_id', 'threadId')
    $threadSource = Get-EventValue -Event $Event -Names @('thread-source', 'thread_source', 'threadSource')
    if ($threadSource -ieq 'automation') {
        $automationId = Get-EventValue -Event $Event -Names @('automation-id', 'automation_id', 'automationId')
        $kind = Get-EventValue -Event $Event -Names @('automation-kind', 'automation_kind', 'automationKind')
        if ([string]::IsNullOrWhiteSpace($automationId)) { $automationId = 'event-metadata' }
        if ([string]::IsNullOrWhiteSpace($kind)) { $kind = 'automation' }
        return [PSCustomObject]@{
            Id = $automationId
            Kind = $kind
            ThreadId = $threadId
        }
    }

    $codexHomes = @(Get-CodexHomes)
    if (-not [string]::IsNullOrWhiteSpace($threadId)) {
        foreach ($codexHome in $codexHomes) {
            $automationsRoot = Join-Path $codexHome 'automations'
            if (Test-Path -LiteralPath $automationsRoot -PathType Container) {
                try {
                    $automationFiles = @(Get-ChildItem -LiteralPath $automationsRoot -Filter 'automation.toml' -File -Recurse -ErrorAction Stop)
                }
                catch {
                    Write-AnnouncerLog "Automation metadata scan failed for ${codexHome}; checking other sources: $($_.Exception.Message)"
                    $automationFiles = @()
                }

                foreach ($automationFile in $automationFiles) {
                    try {
                        $content = Get-Content -LiteralPath $automationFile.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                        $targetThreadId = Get-TomlStringValue -Content $content -Key 'target_thread_id'
                        if ($targetThreadId -ne $threadId) {
                            continue
                        }

                        $automationId = Get-TomlStringValue -Content $content -Key 'id'
                        $kind = Get-TomlStringValue -Content $content -Key 'kind'
                        if ([string]::IsNullOrWhiteSpace($automationId)) { $automationId = $automationFile.Directory.Name }
                        if ([string]::IsNullOrWhiteSpace($kind)) { $kind = 'automation' }
                        return [PSCustomObject]@{
                            Id = $automationId
                            Kind = $kind
                            ThreadId = $threadId
                        }
                    }
                    catch {
                        Write-AnnouncerLog "Ignored unreadable automation metadata: $($automationFile.FullName)"
                    }
                }
            }
        }
    }

    foreach ($codexHome in $codexHomes) {
        $sessionMatch = Get-AutomationSessionMatch -Identifiers $identifiers -CodexHome $codexHome
        if ($sessionMatch) {
            return $sessionMatch
        }
    }
    return $null
}

function Resolve-ForwardExecutable {
    param([string]$ConfiguredPath)

    if ($ConfiguredPath -and (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf)) {
        return $ConfiguredPath
    }

    if ([IO.Path]::GetFileName($ConfiguredPath) -ne 'codex-computer-use.exe') {
        return $ConfiguredPath
    }

    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
    $candidate = Get-ChildItem -LiteralPath $runtimeRoot -Filter 'codex-computer-use.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    return $ConfiguredPath
}

function Invoke-ForwardNotifier {
    param(
        [object]$Settings,
        [string]$Payload
    )

    $forward = @($Settings.forwardCommand)
    if ($forward.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$forward[0])) {
        return
    }

    $executable = Resolve-ForwardExecutable -ConfiguredPath ([string]$forward[0])
    if (-not $executable -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        Write-AnnouncerLog "Forward notifier was not found: $executable"
        return
    }

    $arguments = @()
    if ($forward.Count -gt 1) {
        $arguments = @($forward[1..($forward.Count - 1)])
    }

    try {
        & $executable @arguments $Payload | Out-Null
    }
    catch {
        Write-AnnouncerLog "Forward notifier failed: $($_.Exception.Message)"
    }
}

function ConvertTo-NormalizedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
    }
    catch {
        $fullPath = $Path
    }

    return $fullPath.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
}

function Test-PathContains {
    param(
        [string]$Candidate,
        [string]$Root
    )

    if ($Candidate -eq $Root) {
        return $true
    }
    return $Candidate.StartsWith($Root + '\') -or $Candidate.StartsWith($Root + '/')
}

function Get-ProjectAnnouncement {
    param(
        [object]$Settings,
        [string]$WorkingDirectory
    )

    $normalizedCwd = ConvertTo-NormalizedPath -Path $WorkingDirectory
    $bestProject = $null
    $bestLength = -1

    foreach ($project in @($Settings.projects)) {
        $projectPath = ConvertTo-NormalizedPath -Path ([string]$project.path)
        if ($projectPath -and (Test-PathContains -Candidate $normalizedCwd -Root $projectPath)) {
            if ($projectPath.Length -gt $bestLength -and -not [string]::IsNullOrWhiteSpace([string]$project.name)) {
                $bestProject = $project
                $bestLength = $projectPath.Length
            }
        }
    }

    if ($bestProject) {
        return [PSCustomObject]@{
            Name = [string]$bestProject.name
            SpeechText = [string]$bestProject.speechText
            Voice = [string]$bestProject.voice
        }
    }

    if ($Settings.fallbackToDirectoryName -eq $false -or [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        return $null
    }

    $trimmed = $WorkingDirectory.TrimEnd([char[]]@('\', '/'))
    return [PSCustomObject]@{
        Name = [IO.Path]::GetFileName($trimmed)
        SpeechText = ''
        Voice = ''
    }
}

function Resolve-NodeExecutable {
    param([object]$Settings)

    $candidates = @(
        [string]$Settings.onlineTts.nodePath,
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    $command = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    throw 'Node.js was not found for neural speech generation.'
}

function Get-StringSha256 {
    param([string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-NeuralAudioFile {
    param(
        [object]$Settings,
        [string]$Message,
        [string]$Voice
    )

    $online = $Settings.onlineTts
    $rate = [string]$online.rate
    $pitch = [string]$online.pitch
    $volume = [string]$online.volume
    $language = [string]$online.language
    if ([string]::IsNullOrWhiteSpace($rate)) { $rate = 'default' }
    if ([string]::IsNullOrWhiteSpace($pitch)) { $pitch = 'default' }
    if ([string]::IsNullOrWhiteSpace($volume)) { $volume = 'default' }
    if ([string]::IsNullOrWhiteSpace($language)) { $language = 'zh-CN' }

    $cacheDirectory = Join-Path $logDirectory 'audio-cache'
    if (-not (Test-Path -LiteralPath $cacheDirectory)) {
        New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    }

    $cacheKey = @($Voice, $language, $rate, $pitch, $volume, $Message) -join "`n"
    $hash = Get-StringSha256 -Value $cacheKey
    $audioPath = Join-Path $cacheDirectory "$hash.mp3"
    if ((Test-Path -LiteralPath $audioPath -PathType Leaf) -and (Get-Item -LiteralPath $audioPath).Length -gt 512) {
        return $audioPath
    }

    $requestPath = Join-Path $cacheDirectory "$hash.request.json"
    $partialPath = Join-Path $cacheDirectory "$hash.partial.mp3"
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue

    $request = [ordered]@{
        text = $Message
        voice = $Voice
        language = $language
        outputFormat = 'audio-24khz-48kbitrate-mono-mp3'
        rate = $rate
        pitch = $pitch
        volume = $volume
        timeoutMs = [int]$online.timeoutMs
    }
    $requestJson = $request | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($requestPath, $requestJson, (New-Object Text.UTF8Encoding($false)))

    $node = Resolve-NodeExecutable -Settings $Settings
    $generator = Join-Path $PSScriptRoot 'generate-speech.js'
    try {
        $generatorOutput = @(& $node $generator $requestPath $partialPath 2>&1)
        $generatorExitCode = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    }

    if ($generatorExitCode -ne 0) {
        Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
        throw "Neural speech generation failed: $($generatorOutput -join ' ')"
    }
    if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf) -or (Get-Item -LiteralPath $partialPath).Length -le 512) {
        Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
        throw 'Neural speech generation returned an empty audio file.'
    }

    Move-Item -LiteralPath $partialPath -Destination $audioPath -Force
    return $audioPath
}

function Initialize-MciAudioType {
    if ('CodexMciAudio' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CodexMciAudio {
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr callback);

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern bool mciGetErrorString(int errorCode, StringBuilder errorText, int errorTextSize);
}
'@
}

function Invoke-MciCommand {
    param([string]$Command)

    $buffer = New-Object Text.StringBuilder 512
    $code = [CodexMciAudio]::mciSendString($Command, $buffer, $buffer.Capacity, [IntPtr]::Zero)
    if ($code -ne 0) {
        $errorText = New-Object Text.StringBuilder 512
        [void][CodexMciAudio]::mciGetErrorString($code, $errorText, $errorText.Capacity)
        throw "MCI ${code}: $errorText"
    }
    return $buffer.ToString()
}

function Invoke-Mp3Playback {
    param([string]$Path)

    Initialize-MciAudioType
    $alias = 'codexspeech'
    try {
        Invoke-MciCommand -Command ('open "{0}" type mpegvideo alias {1}' -f $Path, $alias) | Out-Null
        Invoke-MciCommand -Command "play $alias wait" | Out-Null
    }
    finally {
        try {
            Invoke-MciCommand -Command "close $alias" | Out-Null
        }
        catch {
        }
    }
}

function Invoke-ProjectSpeech {
    param(
        [string]$Message,
        [string]$FallbackSpeechText
    )

    $speaker = New-Object -ComObject SAPI.SpVoice
    try {
        $voices = $speaker.GetVoices()
        $chineseVoice = $null
        $englishVoice = $null
        for ($index = 0; $index -lt $voices.Count; $index++) {
            $voice = $voices.Item($index)
            $language = [string]$voice.GetAttribute('Language')
            if (-not $chineseVoice -and $language -match '(^|;)804($|;)') {
                $chineseVoice = $voice
            }
            if (-not $englishVoice -and $language -match '(^|;)409($|;)') {
                $englishVoice = $voice
            }
        }

        if ($chineseVoice) {
            try {
                $speaker.Voice = $chineseVoice
                $speaker.Volume = 100
                $speaker.Rate = 0
                [void]$speaker.Speak($Message)
                return $Message
            }
            catch {
                Write-AnnouncerLog "Chinese voice failed, using fallback: $($_.Exception.Message)"
            }
        }

        if ([string]::IsNullOrWhiteSpace($FallbackSpeechText)) {
            if ($Message -match '^[\x00-\x7F]+$') {
                $FallbackSpeechText = $Message
            }
            else {
                $FallbackSpeechText = 'Codex task complete'
            }
        }

        if (-not $englishVoice) {
            throw 'No usable Windows speech voice is installed.'
        }

        $speaker.Voice = $englishVoice
        $speaker.Volume = 100
        $speaker.Rate = 0
        [void]$speaker.Speak($FallbackSpeechText)
        return $FallbackSpeechText
    }
    finally {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($speaker)
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($EventJson)) {
        Write-AnnouncerLog 'No event payload was received.'
        exit 0
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $RoutingOnly) {
        Invoke-ForwardNotifier -Settings $settings -Payload $EventJson
    }

    if ($settings.enabled -eq $false) {
        if ($RoutingOnly) { Write-Output 'ignore:disabled' }
        exit 0
    }

    $event = $EventJson | ConvertFrom-Json
    if ([string]$event.type -ne 'agent-turn-complete') {
        if ($RoutingOnly) { Write-Output 'ignore:event-type' }
        exit 0
    }

    if ($settings.suppressAutomationAnnouncements -ne $false) {
        $automation = Get-AutomationMatch -Event $event
        if ($automation) {
            Write-AnnouncerLog "Skipped automation announcement: $($automation.Kind) $($automation.Id) thread $($automation.ThreadId)"
            if ($RoutingOnly) { Write-Output 'skip:automation' }
            exit 0
        }
    }

    if ($RoutingOnly) {
        Write-Output 'announce'
        exit 0
    }

    $announcement = Get-ProjectAnnouncement -Settings $settings -WorkingDirectory ([string]$event.cwd)
    if (-not $announcement -or [string]::IsNullOrWhiteSpace([string]$announcement.Name)) {
        exit 0
    }

    $message = '{0}{1}' -f [string]$announcement.Name, [string]$settings.suffix
    $mutex = New-Object Threading.Mutex($false, 'Local\CodexTaskCompletionAnnouncer')
    $ownsMutex = $false
    try {
        $ownsMutex = $mutex.WaitOne(15000)
        if (-not $ownsMutex) {
            Write-AnnouncerLog 'Skipped an overlapping announcement.'
            exit 0
        }

        [System.Media.SystemSounds]::Asterisk.Play()
        $neuralVoice = [string]$announcement.Voice
        if ([string]::IsNullOrWhiteSpace($neuralVoice)) {
            $neuralVoice = [string]$settings.onlineTts.voice
        }

        $neuralSucceeded = $false
        if ($settings.onlineTts.enabled -ne $false -and -not [string]::IsNullOrWhiteSpace($neuralVoice)) {
            try {
                $audioPath = Get-NeuralAudioFile -Settings $settings -Message $message -Voice $neuralVoice
                Invoke-Mp3Playback -Path $audioPath
                Write-AnnouncerLog "Announced: $message (neural voice: $neuralVoice)"
                $neuralSucceeded = $true
            }
            catch {
                Write-AnnouncerLog "Neural voice failed, using offline fallback: $($_.Exception.Message)"
            }
        }

        if (-not $neuralSucceeded) {
            $spokenText = Invoke-ProjectSpeech -Message $message -FallbackSpeechText ([string]$announcement.SpeechText)
            Write-AnnouncerLog "Announced: $message (offline spoken: $spokenText)"
        }
    }
    finally {
        if ($ownsMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}
catch {
    Write-AnnouncerLog "Announcement failed: $($_.Exception.Message)"
}

exit 0
