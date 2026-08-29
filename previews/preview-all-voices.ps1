$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PreviewMciAudio {
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr callback);
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern bool mciGetErrorString(int code, StringBuilder text, int size);
}
'@

function Invoke-Mci([string]$Command) {
    $buffer = New-Object Text.StringBuilder 512
    $code = [PreviewMciAudio]::mciSendString($Command, $buffer, $buffer.Capacity, [IntPtr]::Zero)
    if ($code -ne 0) {
        $errorText = New-Object Text.StringBuilder 512
        [void][PreviewMciAudio]::mciGetErrorString($code, $errorText, $errorText.Capacity)
        throw "MCI ${code}: $errorText"
    }
}

$files = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.mp3' -File | Sort-Object Name
foreach ($file in $files) {
    Write-Host "Playing: $($file.BaseName)"
    try {
        Invoke-Mci ('open "{0}" type mpegvideo alias previewvoice' -f $file.FullName)
        Invoke-Mci 'play previewvoice wait'
    }
    finally {
        try { Invoke-Mci 'close previewvoice' } catch {}
    }
    Start-Sleep -Milliseconds 500
}
Write-Host 'All voice previews completed.'
