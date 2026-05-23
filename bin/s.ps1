param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

function Quote-ForBash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $replacement = "'" + '"' + "'" + '"' + "'"
    return "'" + $Value.Replace("'", $replacement) + "'"
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wsl) {
    throw "wsl.exe was not found. Install WSL first."
}

$distros = & $wsl.Source -l -q 2>$null
if ($LASTEXITCODE -ne 0 -or -not $distros) {
    throw "No WSL distribution is available. Run 'wsl --install -d Ubuntu' and complete first-time setup."
}

$sRootWindows = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$normalized = $sRootWindows -replace '\\', '/'
if ($normalized -notmatch '^([A-Za-z]):/(.*)$') {
    throw "Unable to convert S_ROOT to a WSL path: $sRootWindows"
}

$sRootWsl = "/$($matches[1].ToLower())/$($matches[2])"
$quotedArgs = @()
foreach ($arg in $Args) {
    $quotedArgs += (Quote-ForBash $arg)
}

$command = "export S_ROOT=$(Quote-ForBash $sRootWsl); exec `"`$S_ROOT/bin/s`""
if ($quotedArgs.Count -gt 0) {
    $command = "$command $([string]::Join(' ', $quotedArgs))"
}

& $wsl.Source bash -lc $command
exit $LASTEXITCODE
