[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$announcer = Join-Path $root 'plugin\scripts\announce.ps1'
$temporaryCodexHome = Join-Path ([IO.Path]::GetTempPath()) ('codex-task-announcer-tests-' + [guid]::NewGuid().ToString('N'))
$previousCodexHome = $env:CODEX_HOME

function Assert-RoutingResult {
    param(
        [string]$Name,
        [hashtable]$Event,
        [string]$Expected
    )

    $eventJson = $Event | ConvertTo-Json -Compress
    $eventBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($eventJson))
    $escapedAnnouncer = $announcer.Replace("'", "''")
    $testCommand = @"
`$eventJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$eventBase64'))
`$ProgressPreference = 'SilentlyContinue'
& '$escapedAnnouncer' -EventJson `$eventJson -RoutingOnly
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($testCommand))
    $actual = @(& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand)
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
    $actualText = ($actual -join "`n").Trim()
    if ($actualText -ne $Expected) {
        throw "$Name expected '$Expected' but received '$actualText'."
    }
    Write-Output "PASS: $Name"
}

try {
    $env:CODEX_HOME = $temporaryCodexHome
    $automationDirectory = Join-Path $temporaryCodexHome 'automations\heartbeat-test'
    New-Item -ItemType Directory -Path $automationDirectory -Force | Out-Null
    $automationToml = @'
version = 1
id = "heartbeat-test"
kind = "heartbeat"
status = "ACTIVE"
target_thread_id = "thread-automation"
'@
    [IO.File]::WriteAllText(
        (Join-Path $automationDirectory 'automation.toml'),
        $automationToml,
        (New-Object Text.UTF8Encoding($false))
    )

    $sessionDirectory = Join-Path $temporaryCodexHome 'sessions\2026\08\31'
    New-Item -ItemType Directory -Path $sessionDirectory -Force | Out-Null
    $automationSessionLines = @(
        ([ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            type = 'session_meta'
            payload = [ordered]@{
                id = 'session-automation'
                thread_source = 'automation'
                cwd = 'C:\Projects\Shared'
            }
        } | ConvertTo-Json -Compress),
        ([ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            type = 'response_item'
            payload = [ordered]@{
                type = 'message'
                internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'turn-automation' }
            }
        } | ConvertTo-Json -Compress)
    )
    [IO.File]::WriteAllLines(
        (Join-Path $sessionDirectory 'rollout-session-automation.jsonl'),
        $automationSessionLines,
        (New-Object Text.UTF8Encoding($false))
    )

    $manualSessionLines = @(
        ([ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            type = 'session_meta'
            payload = [ordered]@{
                id = 'session-manual'
                thread_source = 'cli'
                cwd = 'C:\Projects\Shared'
            }
        } | ConvertTo-Json -Compress),
        ([ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            type = 'response_item'
            payload = [ordered]@{
                type = 'message'
                internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'turn-manual-session' }
            }
        } | ConvertTo-Json -Compress)
    )
    [IO.File]::WriteAllLines(
        (Join-Path $sessionDirectory 'rollout-session-manual.jsonl'),
        $manualSessionLines,
        (New-Object Text.UTF8Encoding($false))
    )

    Assert-RoutingResult -Name 'configured automation thread is silent' -Expected 'skip:automation' -Event @{
        type = 'agent-turn-complete'
        'thread-id' = 'thread-automation'
        cwd = 'C:\Projects\Shared'
    }
    Assert-RoutingResult -Name 'explicit automation metadata is silent' -Expected 'skip:automation' -Event @{
        type = 'agent-turn-complete'
        thread_id = 'thread-not-configured'
        thread_source = 'automation'
        cwd = 'C:\Projects\Shared'
    }
    Assert-RoutingResult -Name 'automation session turn identifier is silent' -Expected 'skip:automation' -Event @{
        type = 'agent-turn-complete'
        'thread-id' = 'turn-automation'
        cwd = 'C:\Projects\Shared'
    }
    Assert-RoutingResult -Name 'manual session turn identifier still announces' -Expected 'announce' -Event @{
        type = 'agent-turn-complete'
        'thread-id' = 'turn-manual-session'
        cwd = 'C:\Projects\Shared'
    }
    Assert-RoutingResult -Name 'manual thread in same project still announces' -Expected 'announce' -Event @{
        type = 'agent-turn-complete'
        threadId = 'thread-manual'
        cwd = 'C:\Projects\Shared'
    }
    Assert-RoutingResult -Name 'other notification type is ignored' -Expected 'ignore:event-type' -Event @{
        type = 'other-event'
        'thread-id' = 'thread-manual'
        cwd = 'C:\Projects\Shared'
    }
}
finally {
    $env:CODEX_HOME = $previousCodexHome
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
