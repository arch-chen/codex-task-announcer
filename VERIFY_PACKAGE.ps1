[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifestPath = Join-Path $root 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'SHA256SUMS.txt is missing.' }
$checked = 0
$failures = @()
foreach ($line in Get-Content -LiteralPath $manifestPath -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2) { $failures += "Invalid line: $line"; continue }
    $path = Join-Path $root $parts[1]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $failures += "Missing: $($parts[1])"; continue }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $parts[0].ToUpperInvariant()) {
        $failures += "Hash mismatch: $($parts[1])"
    }
    $checked++
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }
if (-not $Quiet) { Write-Output "Package verification passed: $checked files" }
